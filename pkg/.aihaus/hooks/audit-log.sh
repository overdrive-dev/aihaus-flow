#!/bin/bash
set -euo pipefail

INPUT=$(cat)
LOG_DIR="$CLAUDE_PROJECT_DIR/.claude/audit"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).jsonl"
mkdir -p "$LOG_DIR"

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // "unknown"')
SESSION=$(echo "$INPUT" | jq -r '.session_id // "unknown"')

jq -n \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg cmd "$COMMAND" \
  --arg sid "$SESSION" \
  '{ts: $ts, event: "bash", cmd: $cmd, session: $sid}' \
  >> "$LOG_FILE"

exit 0
