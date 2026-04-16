#!/bin/bash
set -euo pipefail

INPUT=$(cat)
LOG_DIR="$CLAUDE_PROJECT_DIR/.claude/audit"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).jsonl"
mkdir -p "$LOG_DIR"

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if command -v jq >/dev/null 2>&1; then
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // "unknown"' 2>/dev/null)
  SESSION=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
  jq -n \
    --arg ts "$TS" \
    --arg cmd "$COMMAND" \
    --arg sid "$SESSION" \
    '{ts: $ts, event: "bash", cmd: $cmd, session: $sid}' \
    >> "$LOG_FILE"
else
  # Pure-bash fallback: extract fields via grep, emit JSON manually with escaping.
  COMMAND=$(echo "$INPUT" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"command"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' || echo "unknown")
  SESSION=$(echo "$INPUT" | grep -oE '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"session_id"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' || echo "unknown")
  # Minimal JSON escape: backslash and double-quote only.
  esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'; }
  printf '{"ts":"%s","event":"bash","cmd":"%s","session":"%s"}\n' \
    "$TS" "$(esc "${COMMAND:-unknown}")" "$(esc "${SESSION:-unknown}")" \
    >> "$LOG_FILE"
fi

exit 0
