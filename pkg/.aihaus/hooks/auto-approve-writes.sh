#!/bin/bash
set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Auto-approve writes within the project
if [[ "$FILE_PATH" == "$CLAUDE_PROJECT_DIR"* ]]; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PermissionRequest",
      decision: { behavior: "allow" }
    }
  }'
  exit 0
fi

# Block writes outside project
jq -n '{
  hookSpecificOutput: {
    hookEventName: "PermissionRequest",
    decision: { behavior: "deny" },
    message: "Write blocked: outside project directory"
  }
}'
exit 0
