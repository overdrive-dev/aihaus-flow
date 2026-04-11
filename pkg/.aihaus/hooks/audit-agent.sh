#!/bin/bash
set -euo pipefail

INPUT=$(cat)
LOG_DIR="$CLAUDE_PROJECT_DIR/.claude/audit"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).jsonl"
mkdir -p "$LOG_DIR"

AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // "unknown"')
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // "unknown"')

jq -n \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg type "$AGENT_TYPE" \
  --arg id "$AGENT_ID" \
  '{ts: $ts, event: "agent_start", type: $type, id: $id}' \
  >> "$LOG_FILE"

exit 0
