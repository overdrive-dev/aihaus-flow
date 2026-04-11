#!/bin/bash
set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if echo "$FILE_PATH" | grep -qiE \
  '\.env(\.|$)' \
  '|credentials' \
  '|\.git/(config|hooks)' \
  '|id_rsa' \
  '|\.pem$' \
  '|secret' \
  '|\.key$'; then
  echo "BLOCKED: Sensitive file. Requires explicit user approval." >&2
  exit 2
fi

exit 0
