#!/bin/bash
set -euo pipefail

INPUT=$(cat)

# jq-optional: extract .tool_input.command with bash fallback.
if command -v jq >/dev/null 2>&1; then
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
else
  # Fallback: grep for "command": "value" within tool_input. Handles flat JSON.
  COMMAND=$(echo "$INPUT" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"command"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' || echo "")
fi

# Hard-block catastrophic commands
if echo "$COMMAND" | grep -qiE \
  'rm\s+-rf\s+(/|~|\$HOME|C:\\)' \
  '|git\s+push\s+--force\s+(origin\s+)?(main|master|staging|production)' \
  '|drop\s+(table|database)\s' \
  '|truncate\s+' \
  '|git\s+clean\s+-fd' \
  '|mkfs\.' \
  '|dd\s+if='; then
  echo "BLOCKED: Catastrophic command. Requires explicit user approval." >&2
  exit 2
fi

exit 0
