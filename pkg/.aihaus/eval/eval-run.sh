#!/usr/bin/env bash
# eval-run.sh — deterministic eval over an aihaus goal run (3.0 / S6 Eval & Drift Control).
#
# OpenAI-harness pattern: turn gate_events + audit traces into repeatable pass/fail
# checks. This covers the DETERMINISTIC subset (outcome verdicts, write-then-reference,
# planning-gate, policy traces). The BUSINESS-RULE-COVERAGE rubric (did the build
# satisfy the confirmed business rules?) needs a judgment/LLM pass and is deliberately
# OUT of scope here — see the "Rubric" note at the end.
#
# Usage: bash eval-run.sh [--db <kanban.db>] [--project <root>]
# Exit: 0 = all deterministic checks pass · 1 = >=1 failed · 2 = cannot run.
# Emits one JSONL row per check to stdout.
set -uo pipefail

DB=""
PROJECT="$(pwd)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --db) DB="$2"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    -h|--help) echo "Usage: eval-run.sh [--db <kanban.db>] [--project <root>]"; exit 0 ;;
    *) echo "warn: unknown arg ignored: $1" >&2; shift ;;
  esac
done
[[ -z "$DB" ]] && DB="${PROJECT}/.aihaus/state/kanban.db"

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "EVAL-SKIP: sqlite3 unavailable" >&2; exit 2
fi
if [[ ! -f "$DB" ]]; then
  echo "EVAL-SKIP: no goal DB at ${DB}" >&2; exit 2
fi

_q() { sqlite3 "$DB" "$1" 2>/dev/null | tr -d '\r' || true; }
_num() { case "${1:-}" in (''|*[!0-9]*) echo 0 ;; (*) echo "$1" ;; esac; }
_report() { printf '{"check":"%s","result":"%s","detail":"%s"}\n' "$1" "$2" "$3"; }

fails=0

# 1 — Outcome: every gate_events verdict is one of the four legal verdicts.
bad="$(_num "$(_q "SELECT count(*) FROM gate_events WHERE verdict NOT LIKE 'PASS%' AND verdict NOT LIKE 'SKIPPED%' AND verdict NOT LIKE 'BLOCKED-TO-PLANNING%' AND verdict NOT LIKE 'BLOCKED%';")")"
if [[ "$bad" -gt 0 ]]; then _report verdict-validity FAIL "${bad} gate_events with non-canonical verdict"; fails=$((fails+1)); else _report verdict-validity PASS ""; fi

# 2 — Process (write-then-reference): every recorded evidence_path must exist on disk.
missing=0
while IFS= read -r ep; do
  [[ -z "$ep" ]] && continue
  case "$ep" in (/*) p="$ep" ;; (*) p="${PROJECT}/${ep}" ;; esac
  [[ -e "$p" ]] || missing=$((missing+1))
done < <(_q "SELECT evidence_path FROM gate_events WHERE evidence_path IS NOT NULL AND evidence_path != '';")
if [[ "$missing" -gt 0 ]]; then _report evidence-exists FAIL "${missing} gate_events point to missing evidence files"; fails=$((fails+1)); else _report evidence-exists PASS ""; fi

# 3 — Process (planning gate): no task past planejamento with an open planning question.
openq="$(_num "$(_q "SELECT count(*) FROM tasks t JOIN planning_questions pq ON pq.task_id = t.id WHERE pq.status='open' AND t.stage NOT IN ('backlog','entendimento','planejamento');")")"
if [[ "$openq" -gt 0 ]]; then _report planning-gate FAIL "${openq} task(s) advanced past planejamento with open business-rule questions"; fails=$((fails+1)); else _report planning-gate PASS ""; fi

# 4 — Efficiency/churn: a task should not have more gate_events than evaluated stages * 3.
churn="$(_num "$(_q "SELECT count(*) FROM (SELECT task_id, count(*) c FROM gate_events GROUP BY task_id HAVING c > 30);")")"
if [[ "$churn" -gt 0 ]]; then _report no-gate-churn FAIL "${churn} task(s) with >30 gate_events (possible re-eval loop)"; fails=$((fails+1)); else _report no-gate-churn PASS ""; fi

# 5 — Policy trace (informational): online-action blocks recorded by role-guard.
RG="${PROJECT}/.claude/audit/role-guard.jsonl"
if [[ -f "$RG" ]]; then
  blocks="$(_num "$(grep -c '"decision":"block-online"' "$RG" 2>/dev/null || echo 0)")"
  _report role-guard-online-blocks INFO "${blocks} online-action block(s) recorded"
fi

# 6 — Learning loop (planning-answer promotion, M050/S07 — feeds the ADR-260611-D
#     flip evidence): every answered planning question must have a BR-ledger entry
#     carrying its byte-stable join token `Source: pq-<id>` in
#     .aihaus/memory/workflows/business-rules.md (route: protocols/kanban/
#     memory-promotion.md). Waiver: answers recorded as `no-rule:<reason>` are
#     explicit no-promotion rows and are exempt.
LEDGER="${PROJECT}/.aihaus/memory/workflows/business-rules.md"
unpromoted=0
while IFS= read -r row; do
  [[ -z "$row" ]] && continue
  qid="${row%%|*}"
  ans="${row#*|}"
  case "$ans" in no-rule:*) continue ;; esac
  grep -qF "Source: ${qid}" "$LEDGER" 2>/dev/null || unpromoted=$((unpromoted+1))
done < <(_q "SELECT question_id || '|' || replace(replace(answer, char(10), ' '), char(13), ' ') FROM planning_answers;")
if [[ "$unpromoted" -gt 0 ]]; then _report planning-answer-promotion FAIL "${unpromoted} answered planning question(s) without a ledger entry carrying 'Source: pq-<id>' (waive explicitly with a no-rule:<reason> answer)"; fails=$((fails+1)); else _report planning-answer-promotion PASS ""; fi

# 7 — Citation coverage (REPORT-ONLY — never a gate; the ADR-260611-D flip
#     evidence stream): reads .claude/audit/rule-cite.jsonl (sole writer: the
#     `aihaus kanban` wrapper, ADR-260611-C) and reports the
#     autonomous-decisions-per-human-answer metric.
RC="${PROJECT}/.claude/audit/rule-cite.jsonl"
if [[ -f "$RC" ]]; then
  gate_rows="$(_num "$(grep -c '"event":"kanban-gate"' "$RC" 2>/dev/null || echo 0)")"
  cited_rows="$(_num "$(grep -c '"event":"kanban-gate".*"validation":"ok".*"decision":"allow"' "$RC" 2>/dev/null || echo 0)")"
  answers="$(_num "$(_q "SELECT count(*) FROM planning_answers;")")"
  coverage="n/a"; per_answer="n/a"
  [[ "$gate_rows" -gt 0 ]] && coverage="$(awk -v c="$cited_rows" -v t="$gate_rows" 'BEGIN { printf "%.0f%%", (c/t)*100 }')"
  [[ "$answers" -gt 0 ]] && per_answer="$(awk -v c="$cited_rows" -v a="$answers" 'BEGIN { printf "%.1f", c/a }')"
  _report citation-coverage INFO "${cited_rows}/${gate_rows} gate write(s) cited (coverage ${coverage}); ${answers} human answer(s); ${per_answer} autonomous decision(s) per human answer"
else
  _report citation-coverage INFO "no rule-cite.jsonl yet — 0 gate writes via the wrapper (aihaus kanban gate)"
fi

# Rubric (NON-deterministic, out of scope here): business-rule coverage — whether the
# delivered work satisfies the confirmed BUSINESS-RULES for each task — requires a
# judgment/LLM pass over BUSINESS-RULES + the evidence package. Run it separately.

echo "EVAL: ${fails} deterministic check(s) failed."
[[ "$fails" -eq 0 ]]
