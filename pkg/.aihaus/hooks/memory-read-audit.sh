#!/usr/bin/env bash
# memory-read-audit.sh — SubagentStop hook (M050/S08, ADR-260611-F)
#
# Joins transcript evidence against the injection receipts written by
# context-inject.sh (.claude/audit/memory-read.jsonl — receipts are the
# delivery ground truth, sole writer context-inject.sh per BR-P5) and emits
# one verdict row per SubagentStop to ITS OWN JSONL:
#   .claude/audit/memory-read-verdicts.jsonl   (sole writer: THIS hook)
#
# Join semantics (ADR-260611-F):
#   - a receipt row exists => the artifact was injected; inline artifacts
#     (harness / memory_packet / warnings / tier_c_excerpt) are read BY
#     CONSTRUCTION (they live inside additionalContext);
#   - the path_list receipt is advisory — read evidence comes from the
#     transcript (Read calls on HIGH-tier paths);
#   - NO receipts for the agent => verdict "indeterminate", NOT "unread"
#     (worktree spawns suppress receipts by design — ADR-260611-G §Negative).
#
# Verdict enum: read | partial | unread | indeterminate  (architecture §4.3).
# Observe-only this cycle (BR-P8/U3, ADR-260611-D): exit 0 on EVERY path,
# never blocks, all writes `|| true`.
#
# Opt-out: AIHAUS_MEMORY_READ_AUDIT=0 — emits an AUDITED bypass row first
# (BR-P4 never-silent; tdd-guard.sh:30-39 shape), then exit 0.
#
# Env overrides:
#   AIHAUS_MEMORY_READ_LOG           receipts path (default .claude/audit/memory-read.jsonl)
#   AIHAUS_MEMORY_READ_VERDICTS_LOG  verdicts path (default .claude/audit/memory-read-verdicts.jsonl)
#
# ADR refs: ADR-260611-F (receipts + read-audit), ADR-260611-D (observe→enforce),
#           ADR-004 lineage (one writer per file; aggregators read-only).
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/path-helpers.sh
. "${HOOK_DIR}/lib/path-helpers.sh"

ts_iso() { date -u +%FT%TZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z"; }

PROJECT_ROOT="$(aihaus_project_root)"

# ---------------------------------------------------------------------------
# 0. Worktree / submodule write-suppression (BR-P5 single-writer; ADR-260611-G).
#    The verdicts JSONL must only ever be written from the orchestrator
#    process. Inside a linked worktree or submodule checkout: exit silently.
# ---------------------------------------------------------------------------
_pr_norm="${PROJECT_ROOT//\\//}"
case "$_pr_norm" in
  */.claude/worktrees/*) exit 0 ;;
esac
if command -v git >/dev/null 2>&1; then
  SUPER="$(git rev-parse --show-superproject-working-tree 2>/dev/null || true)"
  if [ -n "$SUPER" ]; then
    exit 0
  fi
fi

RECEIPTS_LOG="$(aihaus_project_path "${AIHAUS_MEMORY_READ_LOG:-.claude/audit/memory-read.jsonl}")"
VERDICTS_LOG="$(aihaus_project_path "${AIHAUS_MEMORY_READ_VERDICTS_LOG:-.claude/audit/memory-read-verdicts.jsonl}")"

# ---------------------------------------------------------------------------
# 1. Verdict-row writer (rotation: 10 MB OR 10 000 lines → .old; ADR-M011-A)
# ---------------------------------------------------------------------------
_rotate_verdicts_if_needed() {
  [ -f "$VERDICTS_LOG" ] || return 0
  local bytes lines
  bytes="$(stat -c%s "$VERDICTS_LOG" 2>/dev/null || stat -f%z "$VERDICTS_LOG" 2>/dev/null || echo 0)"
  if [ "$bytes" -ge 10485760 ]; then
    mv -f "$VERDICTS_LOG" "${VERDICTS_LOG}.old" 2>/dev/null || true
    return 0
  fi
  lines="$(wc -l < "$VERDICTS_LOG" 2>/dev/null | tr -d ' ')"
  if [ -n "$lines" ] && [ "$lines" -ge 10000 ]; then
    mv -f "$VERDICTS_LOG" "${VERDICTS_LOG}.old" 2>/dev/null || true
  fi
}

_jesc() { local s="${2-}"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; printf -v "$1" '%s' "$s"; }

# _write_verdict <agent> <receipts_seen> <reads_evidenced> <verdict> <decision> <opt_out> <session>
_write_verdict() {
  local agent="${1:-}" seen="${2:-0}" evidenced="${3:-0}" verdict="${4:-indeterminate}" \
        decision="${5:-observe}" opt_out="${6:-false}" session="${7:-}"
  mkdir -p "$(dirname "$VERDICTS_LOG")" 2>/dev/null || return 0
  _rotate_verdicts_if_needed
  local e_ag e_se
  _jesc e_ag "$agent"; _jesc e_se "$session"
  printf '{"ts":"%s","event":"memory-read-audit","agent":"%s","receipts_seen":%s,"reads_evidenced":%s,"verdict":"%s","decision":"%s","opt_out":%s,"session":"%s"}\n' \
    "$(ts_iso)" "$e_ag" "$seen" "$evidenced" "$verdict" "$decision" "$opt_out" "$e_se" \
    >> "$VERDICTS_LOG" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# 2. Audited bypass (BR-P4 — never silent; tdd-guard.sh:30-39 shape)
# ---------------------------------------------------------------------------
if [ "${AIHAUS_MEMORY_READ_AUDIT:-1}" = "0" ]; then
  cat >/dev/null 2>&1 || true   # drain stdin (avoid broken-pipe to the caller)
  _write_verdict "" 0 0 "indeterminate" "bypass" "true" ""
  exit 0
fi

# ---------------------------------------------------------------------------
# 3. Parse SubagentStop payload (learning-advisor.sh field fallbacks)
# ---------------------------------------------------------------------------
INPUT="$(cat 2>/dev/null || true)"
AGENT_NAME=""
SESSION_ID=""
TRANSCRIPT_PATH=""

if command -v jq >/dev/null 2>&1; then
  AGENT_NAME="$(printf '%s' "$INPUT" | jq -r '.agent_name // .subagent_name // .name // empty' 2>/dev/null || true)"
  SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // .hook_input.session_id // empty' 2>/dev/null || true)"
  TRANSCRIPT_PATH="$(printf '%s' "$INPUT" | jq -r '.transcript_path // .hook_input.transcript_path // empty' 2>/dev/null || true)"
fi
[ -z "$AGENT_NAME" ] && AGENT_NAME="$(printf '%s' "$INPUT" | grep -o '"agent_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"\(.*\)"/\1/' 2>/dev/null || true)"
[ -z "$SESSION_ID" ] && SESSION_ID="$(printf '%s' "$INPUT" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"\(.*\)"/\1/' 2>/dev/null || true)"
[ -z "$TRANSCRIPT_PATH" ] && TRANSCRIPT_PATH="$(printf '%s' "$INPUT" | grep -o '"transcript_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"\(.*\)"/\1/' 2>/dev/null || true)"

# ---------------------------------------------------------------------------
# 4. Receipts join — gather the LAST spawn group for this agent.
#    context-inject.sh writes one shared ts per spawn (_RECEIPT_TS), so the
#    most recent ts for the agent identifies the spawn this Stop closes.
# ---------------------------------------------------------------------------
RECEIPTS_SEEN=0
READS_EVIDENCED=0
VERDICT="indeterminate"
_spawn_rows=""
_agent_rows=""

if [ -f "$RECEIPTS_LOG" ] && [ -n "$AGENT_NAME" ]; then
  if command -v jq >/dev/null 2>&1; then
    _agent_rows="$(jq -c --arg ag "$AGENT_NAME" 'select(.event == "inject-receipt" and .agent == $ag)' "$RECEIPTS_LOG" 2>/dev/null || true)"
    if [ -n "$_agent_rows" ]; then
      _last_ts="$(printf '%s\n' "$_agent_rows" | jq -r '.ts' 2>/dev/null | sort | tail -1 || true)"
      _spawn_rows="$(printf '%s\n' "$_agent_rows" | jq -c --arg ts "$_last_ts" 'select(.ts == $ts)' 2>/dev/null || true)"
    fi
  else
    # jq-less fallback (K-002 defensive pattern): receipt rows are written by
    # context-inject.sh _write_receipt with a STABLE key order and no embedded
    # spaces around separators, so fixed-string grep + sed parsing is reliable.
    _agent_rows="$(grep -F '"event":"inject-receipt"' "$RECEIPTS_LOG" 2>/dev/null | grep -F "\"agent\":\"${AGENT_NAME}\"" || true)"
    if [ -n "$_agent_rows" ]; then
      _last_ts="$(printf '%s\n' "$_agent_rows" | sed -n 's/.*"ts":"\([^"]*\)".*/\1/p' | sort | tail -1 || true)"
      _spawn_rows="$(printf '%s\n' "$_agent_rows" | grep -F "\"ts\":\"${_last_ts}\"" || true)"
    fi
  fi
  if [ -n "$_spawn_rows" ]; then
    RECEIPTS_SEEN="$(printf '%s\n' "$_spawn_rows" | grep -c '^{' 2>/dev/null)" || true
    RECEIPTS_SEEN="$(printf '%s' "$RECEIPTS_SEEN" | tr -d '[:space:]')"
    case "$RECEIPTS_SEEN" in (''|*[!0-9]*) RECEIPTS_SEEN=0 ;; esac
  fi
fi

if [ "$RECEIPTS_SEEN" -gt 0 ]; then
  # Inline artifacts = injected-by-construction = read. (Stable writer format
  # makes the grep correct on both the jq and jq-less branches.)
  _inline_count="$(printf '%s\n' "$_spawn_rows" | grep -cE '"artifact":"(harness|memory_packet|warnings|tier_c_excerpt)"' 2>/dev/null)" || true
  _inline_count="$(printf '%s' "$_inline_count" | tr -d '[:space:]')"
  case "$_inline_count" in (''|*[!0-9]*) _inline_count=0 ;; esac
  _advisory_count=$(( RECEIPTS_SEEN - _inline_count ))

  # Advisory receipts (path_list): transcript Read evidence on HIGH-tier paths.
  # Canonical HIGH-tier set (role-defaults.json HIGH rows + fallback minimum).
  _transcript_available=0
  _advisory_evidenced=0
  if [ "$_advisory_count" -gt 0 ] && [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    _transcript_available=1
    if grep -Eq '\.aihaus/(project\.md|protocols/(default|routing|harness)\.md|memory/workflows/(business-rules|environment|user-preferences)\.md|decisions\.md|knowledge\.md|memory/MEMORY\.md)' \
        "$TRANSCRIPT_PATH" 2>/dev/null; then
      _advisory_evidenced="$_advisory_count"
    fi
  fi

  READS_EVIDENCED=$(( _inline_count + _advisory_evidenced ))
  if [ "$READS_EVIDENCED" -ge "$RECEIPTS_SEEN" ]; then
    VERDICT="read"
  elif [ "$_transcript_available" = "0" ] && [ "$_advisory_count" -gt 0 ]; then
    # Cannot inspect the transcript — heuristic evidence absent, not negative.
    VERDICT="indeterminate"
  elif [ "$READS_EVIDENCED" -eq 0 ]; then
    VERDICT="unread"
  else
    VERDICT="partial"
  fi
else
  # No receipts: worktree spawn (suppressed by design) or pre-S05 install.
  VERDICT="indeterminate"
fi

_write_verdict "$AGENT_NAME" "$RECEIPTS_SEEN" "$READS_EVIDENCED" "$VERDICT" "observe" "false" "$SESSION_ID"

# Fail-safe: observe-only — never block the agent (BR-P4/P8).
exit 0
