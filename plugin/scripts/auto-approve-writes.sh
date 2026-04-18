#!/bin/bash
set -euo pipefail

INPUT=$(cat)

# jq-optional: extract file_path with bash fallback.
if command -v jq >/dev/null 2>&1; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")
else
  FILE_PATH=$(echo "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"file_path"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' || echo "")
fi

emit_decision() {
  local behavior="$1"
  local msg="${2:-}"
  if command -v jq >/dev/null 2>&1; then
    if [[ -n "$msg" ]]; then
      jq -n --arg m "$msg" '{ hookSpecificOutput: { hookEventName: "PermissionRequest", decision: { behavior: $ENV.BEHAVIOR }, message: $m } }' BEHAVIOR="$behavior"
    else
      jq -n --arg b "$behavior" '{ hookSpecificOutput: { hookEventName: "PermissionRequest", decision: { behavior: $b } } }'
    fi
  else
    # Manual JSON — escape quotes/backslashes in the optional message.
    local esc_msg
    esc_msg=$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r')
    if [[ -n "$msg" ]]; then
      printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"%s"},"message":"%s"}}\n' "$behavior" "$esc_msg"
    else
      printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"%s"}}}\n' "$behavior"
    fi
  fi
}

# Auto-approve writes within the project
if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]] && [[ "$FILE_PATH" == "${CLAUDE_PROJECT_DIR}"* ]]; then
  emit_decision "allow"
  exit 0
fi

# Block writes outside project
emit_decision "deny" "Write blocked: outside project directory"
exit 0
