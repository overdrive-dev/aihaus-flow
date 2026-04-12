#!/bin/bash
set -euo pipefail

INPUT=$(cat)

# jq-optional: extract .tool_input.file_path with bash fallback.
if command -v jq >/dev/null 2>&1; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")
else
  FILE_PATH=$(echo "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"file_path"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' || echo "")
fi

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
