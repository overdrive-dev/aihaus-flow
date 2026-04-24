#!/usr/bin/env bash
# telemetry-collect.sh — maintainer-only per-milestone telemetry summariser
# Reads audit JSONLs + brainstorm/reviews to produce ONE markdown table row.
# Output is written to stdout; the orchestrator (Step 6.7) appends it to
# .aihaus/memory/global/architecture.md under <!-- telemetry-summary -->.
#
# Usage: bash tools/telemetry-collect.sh <MILESTONE_ID>
#   e.g. bash tools/telemetry-collect.sh M013
#
# This script NEVER writes to the memory tree directly — orchestrator is the
# sole writer per ADR-M013-A (single-writer invariant).
#
# Exit 0 always (advisory tool — callers should not fail on telemetry errors).
#
# ADR references: ADR-M013-A (single-writer), ADR-001 (files-as-state),
#   ADR-M016-B Follow-up (rotation rationale — length-cap prose).

set -euo pipefail

MILESTONE_ID="${1:-}"
if [ -z "$MILESTONE_ID" ]; then
  printf 'Usage: bash tools/telemetry-collect.sh <MILESTONE_ID>\n' >&2
  exit 0
fi

# ---- Resolve repo root relative to this script --------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUDIT_DIR="${REPO_ROOT}/.claude/audit"
MILESTONES_DIR="${REPO_ROOT}/.aihaus/milestones"
BRAINSTORM_DIR="${REPO_ROOT}/.aihaus/brainstorm"
ARCH_FILE="${REPO_ROOT}/.aihaus/memory/global/architecture.md"

# ---- Helper: safe integer (falls back to 0) -----------------------------------
_int() { printf '%s' "${1:-0}" | grep -oE '^[0-9]+' || echo 0; }

# ---- 1. LEARNING-WARNINGS count (rows for this milestone) ---------------------
WARNINGS_LOG="${AUDIT_DIR}/LEARNING-WARNINGS.jsonl"
warning_count=0
if [ -f "$WARNINGS_LOG" ]; then
  if command -v jq >/dev/null 2>&1; then
    warning_count=$(jq -r --arg m "$MILESTONE_ID" 'select(.milestone == $m) | "1"' "$WARNINGS_LOG" 2>/dev/null | wc -l | tr -d ' ')
  else
    warning_count=$(grep -c "\"milestone\":\"${MILESTONE_ID}\"" "$WARNINGS_LOG" 2>/dev/null || echo 0)
  fi
fi
warning_count=$(_int "$warning_count")

# ---- 2. Recurrence clusters (distinct hashes; clusters with recurrence>=3) ----
RECURRENCE_LOG="${AUDIT_DIR}/warning-recurrence.jsonl"
recurrence_count=0
if [ -f "$RECURRENCE_LOG" ]; then
  if command -v jq >/dev/null 2>&1; then
    recurrence_count=$(jq -r 'select(.recurrence_count >= 3) | "1"' "$RECURRENCE_LOG" 2>/dev/null | wc -l | tr -d ' ')
  else
    recurrence_count=$(grep -c '"recurrence_count":[3-9]' "$RECURRENCE_LOG" 2>/dev/null || echo 0)
  fi
fi
recurrence_count=$(_int "$recurrence_count")

# ---- 3. Cache hit rate (context-inject.jsonl) ---------------------------------
INJECT_LOG="${AUDIT_DIR}/context-inject.jsonl"
cache_hit_pct=0
if [ -f "$INJECT_LOG" ]; then
  total_inject=$(wc -l < "$INJECT_LOG" | tr -d ' ')
  if [ "$(_int "$total_inject")" -gt 0 ]; then
    if command -v jq >/dev/null 2>&1; then
      hits=$(jq -r 'select(.cache_hit == true) | "1"' "$INJECT_LOG" 2>/dev/null | wc -l | tr -d ' ')
    else
      hits=$(grep -c '"cache_hit":true' "$INJECT_LOG" 2>/dev/null || echo 0)
    fi
    cache_hit_pct=$(awk -v h="$(_int "$hits")" -v t="$(_int "$total_inject")" \
      'BEGIN { print (t==0)?0:int(h*100/t) }')
  fi
fi

# ---- 4. Curator blocks applied (curator-apply.jsonl, minus no-signal rows) ----
CURATOR_LOG="${AUDIT_DIR}/curator-apply.jsonl"
curator_blocks=0
if [ -f "$CURATOR_LOG" ]; then
  total_curator=$(wc -l < "$CURATOR_LOG" | tr -d ' ')
  skipped=$(grep -c "no-signal-this-milestone" "$CURATOR_LOG" 2>/dev/null || echo 0)
  curator_blocks=$(( $(_int "$total_curator") - $(_int "$skipped") ))
  [ "$curator_blocks" -lt 0 ] && curator_blocks=0
fi

# ---- 5. Adversarial findings (HIGH/CRITICAL) ----------------------------------
adversarial_count=0
# 5a. brainstorm CHALLENGES.md for this milestone slug
for challenges_file in "${BRAINSTORM_DIR}"/*/"CHALLENGES.md"; do
  [ -f "$challenges_file" ] || continue
  n=$(awk '/HIGH|CRITICAL/ {count++} END {print count+0}' "$challenges_file" 2>/dev/null || echo 0)
  adversarial_count=$(( adversarial_count + $(_int "$n") ))
done
# 5b. milestone execution/reviews/*.md
MILESTONE_DIR=""
for d in "${MILESTONES_DIR}"/*/; do
  base="$(basename "$d")"
  # Match e.g. "M013-" prefix
  if printf '%s' "$base" | grep -qE "^${MILESTONE_ID}-"; then
    MILESTONE_DIR="$d"
    break
  fi
done
if [ -n "$MILESTONE_DIR" ] && [ -d "${MILESTONE_DIR}execution/reviews" ]; then
  for review_file in "${MILESTONE_DIR}execution/reviews"/*.md; do
    [ -f "$review_file" ] || continue
    n=$(awk '/HIGH|CRITICAL/ {count++} END {print count+0}' "$review_file" 2>/dev/null || echo 0)
    adversarial_count=$(( adversarial_count + $(_int "$n") ))
  done
fi

# ---- 6. Emit markdown table row -----------------------------------------------
ROW="| ${MILESTONE_ID} | warnings:${warning_count} | recurrences:${recurrence_count} | cache_hit:${cache_hit_pct}% | curator_blocks:${curator_blocks} | adversarial_findings:${adversarial_count} |"
printf '%s\n' "$ROW"

# ---- 7. Stdout-only emit (BLOCKER-2 mitigation; ADR-M013-A compliance) -------
# This script is now stdout-only. The orchestrator (completion-protocol Step 6.7)
# captures stdout and applies the row to .aihaus/memory/global/architecture.md
# via the Edit tool — preserving ADR-M013-A's single-writer invariant
# (orchestrator main thread is the SOLE writer of .aihaus/memory/**).
#
# Orchestrator pattern at Step 6.7:
#   row=$(bash tools/telemetry-collect.sh M0XX) || exit 1
#   <orchestrator parses row, opens architecture.md via Edit tool, applies row
#    inside <!-- telemetry-summary --> marker section with idempotent replace +
#    50-row FIFO rotation policy>
#
# This script's responsibility ends with row emission. Architecture.md mutation,
# marker creation, idempotency, and rotation are all orchestrator concerns.
exit 0
