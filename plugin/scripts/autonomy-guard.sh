#!/usr/bin/env bash
# autonomy-guard.sh — detect + block autonomy-protocol violations in the
# final assistant turn. Wired to the Stop event in settings.local.json.
#
# Exit 0 with no output = no violation (or no execution-phase context).
# Exit 0 with block JSON = forbidden pattern detected during execution phase.
#
# Enforcement targets (per _shared/autonomy-protocol.md):
#   - §No option menus (L32-50)
#   - §No honest checkpoints (L52-63)
#   - §No delegated typing (L65-72)
#
# Execution-phase detection:
#   - $AIHAUS_EXEC_PHASE=1 set by parent skill (primary signal); OR
#   - $MANIFEST_PATH points to a RUN-MANIFEST.md with non-empty Invoke stack.
#
# Outside execution phase: violations LOGGED but NOT blocked — plan
# documents (Alternatives tables) reference option-menu prose legitimately.
#
# Story 7 of plan 260414-exec-auto-approve.
set -uo pipefail

AUDIT_LOG="${AIHAUS_AUDIT_LOG:-.claude/audit/autonomy-violations.jsonl}"

INPUT="$(cat)"

# Extract the assistant's final message from Stop hook payload.
MSG=""
if command -v jq >/dev/null 2>&1; then
  MSG=$(echo "$INPUT" | jq -r '
    .message.content //
    .assistant_message //
    .transcript //
    .content //
    empty
  ' 2>/dev/null || echo "")
fi
[ -z "$MSG" ] && MSG="$INPUT"

# Forbidden patterns. Each line below is: REGEX<TAB>SECTION
# Patterns use ERE syntax (grep -E). Quotes are plain single-quoted strings
# to avoid shell-escape hell.
PATTERNS=$(cat <<'PATTERNS_EOF'
[Cc]heckpoint honesto	L52-63:no-honest-checkpoints
[Hh]onest checkpoint	L52-63:no-honest-checkpoints
[Oo]pção sua	L32-50:no-option-menus
Qual (prefere|escolhe)\??	L32-50:no-option-menus
[Rr]ealista:.*([4-9]|1[0-9])h\+?	L52-63:no-reality-renegotiation
[Pp]ausing (to|here|for)	L52-63:no-honest-checkpoints
[Ss]hould I (continue|proceed|pause)	L32-50:no-option-menus
[Tt]hree realistic forks	L52-63:no-honest-checkpoints
[Ww]ave [0-9]+ complet[ao].*([Ss]top|[Pp]ause|[Aa]linha)	L52-63:no-honest-checkpoints
retoma depois com /aih-	L65-72:no-delegated-typing
[Tt]ype the command.*/aih-	L65-72:no-delegated-typing
PATTERNS_EOF
)

ts_iso() { date -u +%FT%TZ; }

log_violation() {
  local pattern="$1" section="$2" exec_phase="$3"
  mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || return 0
  local pattern_json section_json
  pattern_json=$(printf '%s' "$pattern" | sed 's/\\/\\\\/g; s/"/\\"/g')
  section_json=$(printf '%s' "$section" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '{"ts":"%s","violation":"%s","section":"%s","exec_phase":"%s"}\n' \
    "$(ts_iso)" "$pattern_json" "$section_json" "$exec_phase" \
    >> "$AUDIT_LOG" 2>/dev/null || true
}

emit_block() {
  local pattern="$1" section="$2"
  local reason="Autonomy violation: pattern '$pattern' matches autonomy-protocol.md $section. Pick the safer default per TRUE blocker test (L15-31) and proceed silently. Log the choice in RUN-MANIFEST progress log instead of asking the user."
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg r "$reason" '{decision:"block", reason:$r}'
  else
    local reason_json
    reason_json=$(printf '%s' "$reason" | sed 's/\\/\\\\/g; s/"/\\"/g')
    printf '{"decision":"block","reason":"%s"}\n' "$reason_json"
  fi
}

# Detect execution phase.
in_execution=0
if [ "${AIHAUS_EXEC_PHASE:-0}" = "1" ]; then
  in_execution=1
elif [ -n "${MANIFEST_PATH:-}" ] && [ -f "${MANIFEST_PATH}" ]; then
  if awk '/^## Invoke stack$/ {on=1; next} /^## / {on=0} on && /\|/ {found=1} END {exit !found}' "$MANIFEST_PATH" 2>/dev/null; then
    in_execution=1
  fi
fi

# Scan message against each pattern. First match in exec phase blocks.
while IFS=$'\t' read -r pattern section; do
  [ -z "$pattern" ] && continue
  if printf '%s' "$MSG" | grep -qE "$pattern" 2>/dev/null; then
    log_violation "$pattern" "$section" "$in_execution"
    if [ "$in_execution" = "1" ]; then
      emit_block "$pattern" "$section"
      exit 0
    fi
  fi
done <<< "$PATTERNS"

exit 0
