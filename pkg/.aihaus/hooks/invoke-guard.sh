#!/usr/bin/env bash
# invoke-guard.sh — parse last non-empty line of agent return for <AIHAUS_INVOKE .../> marker.
# Emits one verdict line: INVOKE_OK skill|args|rationale|blocking | INVOKE_REJECT <reason> | NO_INVOKE
# ADR-003 implementation. Read-only with respect to RUN-MANIFEST.md; writes audit log.
# Exit codes: 0 (INVOKE_OK / NO_INVOKE), 2 (INVOKE_REJECT *).
set -euo pipefail

ALLOWLIST="aih-quick aih-bugfix aih-feature aih-plan aih-milestone aih-run"
MAX_LEN=200
MAX_DEPTH=3
AUDIT_LOG="${AIHAUS_AUDIT_LOG:-.claude/audit/invoke.jsonl}"

# --- helpers ---

ts_iso() { date -u +%FT%TZ; }

log_audit() {
  local verdict="$1" skill="$2" rat_len="$3" args_len="$4" depth="$5" reason="${6:-null}"
  mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || return 0
  local reason_json="null"
  [ "$reason" != "null" ] && reason_json="\"$reason\""
  printf '{"ts":"%s","verdict":"%s","skill":"%s","rationale_len":%d,"args_len":%d,"depth_observed":%d,"reject_reason":%s}\n' \
    "$(ts_iso)" "$verdict" "$skill" "$rat_len" "$args_len" "$depth" "$reason_json" \
    >> "$AUDIT_LOG" 2>/dev/null || true
}

emit_reject() {
  local reason="$1" skill="${2:-}" rat_len="${3:-0}" args_len="${4:-0}" depth="${5:-0}"
  echo "INVOKE_REJECT $reason"
  log_audit "INVOKE_REJECT" "$skill" "$rat_len" "$args_len" "$depth" "$reason"
  exit 2
}

emit_no_invoke() {
  echo "NO_INVOKE"
  log_audit "NO_INVOKE" "" 0 0 0
  exit 0
}

emit_ok() {
  local skill="$1" args="$2" rationale="$3" blocking="$4" rat_len="$5" args_len="$6" depth="$7"
  echo "INVOKE_OK ${skill}|${args}|${rationale}|${blocking}"
  log_audit "INVOKE_OK" "$skill" "$rat_len" "$args_len" "$depth"
  exit 0
}

# --- read stdin, take last non-empty line ---

INPUT="$(cat)"
LAST_LINE="$(printf '%s\n' "$INPUT" | awk '/./ { last=$0 } END { print last }')"

# --- match marker exactly on last line (anchored) ---

MARKER_RE='^[[:space:]]*<AIHAUS_INVOKE skill="([^"]+)" args="([^"]*)" rationale="([^"]*)" blocking="(true|false)"/>[[:space:]]*$'

if [[ ! "$LAST_LINE" =~ $MARKER_RE ]]; then
  emit_no_invoke
fi

SKILL="${BASH_REMATCH[1]}"
ARGS="${BASH_REMATCH[2]}"
RATIONALE="${BASH_REMATCH[3]}"
BLOCKING="${BASH_REMATCH[4]}"
ARGS_LEN=${#ARGS}
RAT_LEN=${#RATIONALE}

# --- validate allowlist ---

SKILL_OK=0
for s in $ALLOWLIST; do
  if [ "$s" = "$SKILL" ]; then SKILL_OK=1; break; fi
done
[ $SKILL_OK -eq 1 ] || emit_reject "allowlist" "$SKILL" "$RAT_LEN" "$ARGS_LEN" 0

# --- validate lengths / non-empty rationale / blocking value ---

[ "$ARGS_LEN" -le "$MAX_LEN" ] || emit_reject "args-length" "$SKILL" "$RAT_LEN" "$ARGS_LEN" 0
[ "$RAT_LEN"  -le "$MAX_LEN" ] || emit_reject "rationale-length" "$SKILL" "$RAT_LEN" "$ARGS_LEN" 0
[ "$RAT_LEN"  -gt 0 ]          || emit_reject "rationale-empty"   "$SKILL" "$RAT_LEN" "$ARGS_LEN" 0
# blocking already validated by regex group

# --- depth check + self-invocation via Invoke stack ---

DEPTH=0
TOP_SKILL=""
MANIFEST_PATH="${MANIFEST_PATH:-}"
if [ -n "$MANIFEST_PATH" ] && [ -f "$MANIFEST_PATH" ]; then
  STACK_BODY="$(awk '/^## Invoke stack$/ {on=1; next} /^## / {on=0} on && /[^[:space:]]/ { print }' "$MANIFEST_PATH")"
  if [ -n "$STACK_BODY" ]; then
    DEPTH=$(printf '%s\n' "$STACK_BODY" | grep -c '|' || true)
    TOP_SKILL=$(printf '%s\n' "$STACK_BODY" | tail -n 1 | cut -d'|' -f1)
  fi
fi

[ "$DEPTH" -lt "$MAX_DEPTH" ] || emit_reject "depth" "$SKILL" "$RAT_LEN" "$ARGS_LEN" "$DEPTH"
[ "$SKILL" != "$TOP_SKILL" ]  || emit_reject "self-invocation" "$SKILL" "$RAT_LEN" "$ARGS_LEN" "$DEPTH"

# --- all checks passed ---

emit_ok "$SKILL" "$ARGS" "$RATIONALE" "$BLOCKING" "$RAT_LEN" "$ARGS_LEN" "$DEPTH"
