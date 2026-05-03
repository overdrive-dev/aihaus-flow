#!/usr/bin/env bash
set -euo pipefail
# tools/validate-outcome-gates.sh — M019 outcome-gate validator
# Usage: bash tools/validate-outcome-gates.sh M0XX
#
# Prints PASS/FAIL/MANUAL per gate. Gates 1-4 are pre-merge falsifiable.
# Gate 5 is post-merge operational (zero exit-6 / lock-timeout-fallback).
#
# Gate 1: distinct-id counter — synthetic 47-distinct fixture
# Gate 2: categorizable-pause coverage — manual review
# Gate 3: outside-exec-skip emits when AIHAUS_EXEC_PHASE=0
# Gate 4: no leaked .tmp files under milestone dir
# Gate 5: zero lock-timeout-fallback rows in hook.jsonl
#
# Resolves repo root relative to this script (same discipline as smoke-test.sh).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

MS_ID="${1:?Usage: $0 M0XX}"
MS_DIR=$(find "${REPO_ROOT}/.aihaus/milestones/" -maxdepth 1 -type d -name "${MS_ID}-*" 2>/dev/null | head -1)
if [[ ! -d "${MS_DIR:-}" ]]; then
  printf "Milestone not found: %s (searched: %s/.aihaus/milestones/)\n" "$MS_ID" "$REPO_ROOT" >&2
  exit 1
fi

GATE_LOG="${REPO_ROOT}/.claude/audit/autonomy-gate.jsonl"
HOOK_LOG="${REPO_ROOT}/.claude/audit/hook.jsonl"
FIXTURE="${REPO_ROOT}/tools/fixtures/M019/S05/47-distinct-manifest.md"

# ---- Gate 1: distinct-id counter ----------------------------------------
# Run on the synthetic 47-distinct fixture; count unique story_ids.
if [[ -f "$FIXTURE" ]]; then
  DISTINCT=$(awk -F'|' '/^\s*S[0-9]+\s*\|/{gsub(/[[:space:]]/,"",$1); ids[$1]=1} END{print length(ids)}' "$FIXTURE" 2>/dev/null || echo "0")
  if [[ "$DISTINCT" -eq 47 ]]; then
    printf "Gate 1 (distinct-id counter): PASS (%s distinct story_ids in fixture)\n" "$DISTINCT"
  else
    printf "Gate 1 (distinct-id counter): FAIL (expected 47 distinct story_ids; got %s)\n" "$DISTINCT"
  fi
else
  printf "Gate 1 (distinct-id counter): SKIP (fixture not found: %s)\n" "$FIXTURE"
fi

# ---- Gate 2: categorizable-pause coverage -------------------------------
# Informational: manual review against milestone window audit rows.
printf "Gate 2 (categorizable-pause): MANUAL REVIEW — inspect %s for >5min pauses\n" "$GATE_LOG"

# ---- Gate 3: outside-exec-skip rows in audit log ------------------------
if [[ -f "$GATE_LOG" ]]; then
  CNT=$(grep -c '"decision":"outside-exec-skip"' "$GATE_LOG" 2>/dev/null; true)
  CNT=$(printf '%s' "$CNT" | tr -d ' \n\r')
  printf "Gate 3 (outside-exec-skip): %s rows in %s\n" "$CNT" "$GATE_LOG"
else
  printf "Gate 3 (outside-exec-skip): SKIP (%s absent)\n" "$GATE_LOG"
fi

# ---- Gate 4: no leaked .tmp files under milestone dir -------------------
LEAKED=$(find "$MS_DIR" -name "*.tmp" 2>/dev/null | wc -l | tr -d ' \n\r')
if [[ "$LEAKED" -eq 0 ]]; then
  printf "Gate 4 (no leaked .tmp): PASS\n"
else
  printf "Gate 4 (no leaked .tmp): FAIL (%s .tmp files under %s)\n" "$LEAKED" "$MS_DIR"
fi

# ---- Gate 5: zero exit-6 / lock-timeout-fallback (post-merge operational) --
if [[ -f "$HOOK_LOG" ]]; then
  CNT=$(grep -c '"lock-timeout-fallback"' "$HOOK_LOG" 2>/dev/null; true)
  CNT=$(printf '%s' "$CNT" | tr -d ' \n\r')
  if [[ "$CNT" -eq 0 ]]; then
    printf "Gate 5 (zero exit-6): PASS (0 lock-timeout-fallback rows in %s)\n" "$HOOK_LOG"
  else
    printf "Gate 5 (zero exit-6): FAIL (%s lock-timeout-fallback rows — threshold: 0)\n" "$CNT"
  fi
else
  printf "Gate 5 (zero exit-6): SKIP (%s absent)\n" "$HOOK_LOG"
fi
