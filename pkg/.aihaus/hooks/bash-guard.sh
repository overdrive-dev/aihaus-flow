#!/bin/bash
set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

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
