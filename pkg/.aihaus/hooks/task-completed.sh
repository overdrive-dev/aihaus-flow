#!/bin/bash
set -euo pipefail

INPUT=$(cat)
TASK_SUBJECT=$(echo "$INPUT" | jq -r '.task_subject // "unknown"')

LOG_DIR="$CLAUDE_PROJECT_DIR/.claude/audit"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).jsonl"
mkdir -p "$LOG_DIR"

jq -n \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg task "$TASK_SUBJECT" \
  '{ts: $ts, event: "task_completed", task: $task}' \
  >> "$LOG_FILE"

exit 0
