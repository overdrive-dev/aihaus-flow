#!/bin/bash
set -euo pipefail

INPUT=$(cat)
LOG_DIR="$CLAUDE_PROJECT_DIR/.claude/audit"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).jsonl"
mkdir -p "$LOG_DIR"

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if command -v jq >/dev/null 2>&1; then
  AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // "unknown"' 2>/dev/null)
  AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // "unknown"' 2>/dev/null)
  jq -n \
    --arg ts "$TS" \
    --arg type "$AGENT_TYPE" \
    --arg id "$AGENT_ID" \
    '{ts: $ts, event: "agent_start", type: $type, id: $id}' \
    >> "$LOG_FILE"
else
  AGENT_TYPE=$(echo "$INPUT" | grep -oE '"agent_type"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"agent_type"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' || echo "unknown")
  AGENT_ID=$(echo "$INPUT" | grep -oE '"agent_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"agent_id"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' || echo "unknown")
  esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'; }
  printf '{"ts":"%s","event":"agent_start","type":"%s","id":"%s"}\n' \
    "$TS" "$(esc "${AGENT_TYPE:-unknown}")" "$(esc "${AGENT_ID:-unknown}")" \
    >> "$LOG_FILE"
fi

exit 0
