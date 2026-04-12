#!/bin/bash
set -euo pipefail

INPUT=$(cat)
LOG_DIR="$CLAUDE_PROJECT_DIR/.claude/audit"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).jsonl"
mkdir -p "$LOG_DIR"

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if command -v jq >/dev/null 2>&1; then
  TASK_SUBJECT=$(echo "$INPUT" | jq -r '.task_subject // "unknown"' 2>/dev/null)
  TEAMMATE=$(echo "$INPUT" | jq -r '.teammate_name // "unknown"' 2>/dev/null)
  jq -n \
    --arg ts "$TS" \
    --arg task "$TASK_SUBJECT" \
    --arg who "$TEAMMATE" \
    '{ts: $ts, event: "task_created", task: $task, teammate: $who}' \
    >> "$LOG_FILE"
else
  TASK_SUBJECT=$(echo "$INPUT" | grep -oE '"task_subject"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"task_subject"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' || echo "unknown")
  TEAMMATE=$(echo "$INPUT" | grep -oE '"teammate_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"teammate_name"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' || echo "unknown")
  esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'; }
  printf '{"ts":"%s","event":"task_created","task":"%s","teammate":"%s"}\n' \
    "$TS" "$(esc "${TASK_SUBJECT:-unknown}")" "$(esc "${TEAMMATE:-unknown}")" \
    >> "$LOG_FILE"
fi

exit 0
