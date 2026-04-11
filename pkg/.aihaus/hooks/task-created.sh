#!/bin/bash
set -euo pipefail

INPUT=$(cat)
LOG_DIR="$CLAUDE_PROJECT_DIR/.claude/audit"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).jsonl"
mkdir -p "$LOG_DIR"

TASK_SUBJECT=$(echo "$INPUT" | jq -r '.task_subject // "unknown"')
TEAMMATE=$(echo "$INPUT" | jq -r '.teammate_name // "unknown"')

jq -n \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg task "$TASK_SUBJECT" \
  --arg who "$TEAMMATE" \
  '{ts: $ts, event: "task_created", task: $task, teammate: $who}' \
  >> "$LOG_FILE"

exit 0
