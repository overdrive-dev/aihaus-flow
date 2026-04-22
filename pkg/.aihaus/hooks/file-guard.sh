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

# Path-scope check: reject writes that escape $CLAUDE_PROJECT_DIR
# (including ../ traversal and absolute paths outside the project root).
# Path-scope check added M014/S02 (PermissionRequest layer deleted in S04).
# Fail-closed: if CLAUDE_PROJECT_DIR is unset, deny to prevent escapes.
if [[ -z "${CLAUDE_PROJECT_DIR:-}" ]]; then
  echo "BLOCKED: write outside project dir (CLAUDE_PROJECT_DIR is unset)" >&2
  exit 2
fi

if [[ -n "$FILE_PATH" ]]; then
  # Resolve symlinks for both the target and project root so that worktrees
  # symlinked inside the project dir don't produce false positives.
  # Use shell fallback if realpath is unavailable.
  if command -v realpath >/dev/null 2>&1; then
    # realpath -m: resolve without requiring path to exist (file may be new)
    resolved_file=$(realpath -m "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")
    resolved_project=$(realpath "$CLAUDE_PROJECT_DIR" 2>/dev/null || echo "$CLAUDE_PROJECT_DIR")
  else
    # Fallback: use Python (required per README) or cd-based expansion.
    if command -v python3 >/dev/null 2>&1; then
      resolved_file=$(python3 -c "import os,sys; print(os.path.normpath(sys.argv[1]))" "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")
      resolved_project=$(python3 -c "import os,sys; print(os.path.normpath(sys.argv[1]))" "$CLAUDE_PROJECT_DIR" 2>/dev/null || echo "$CLAUDE_PROJECT_DIR")
    elif command -v python >/dev/null 2>&1; then
      resolved_file=$(python -c "import os,sys; print(os.path.normpath(sys.argv[1]))" "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")
      resolved_project=$(python -c "import os,sys; print(os.path.normpath(sys.argv[1]))" "$CLAUDE_PROJECT_DIR" 2>/dev/null || echo "$CLAUDE_PROJECT_DIR")
    else
      resolved_file="$FILE_PATH"
      resolved_project="$CLAUDE_PROJECT_DIR"
    fi
  fi

  # Ensure resolved_project has a trailing slash for prefix matching so that
  # "/project-foo" doesn't match "/project-foobar".
  case "$resolved_file" in
    "${resolved_project}/"*|"${resolved_project}")
      # Inside project dir — allow
      ;;
    *)
      echo "BLOCKED: write outside project dir (path: ${FILE_PATH})" >&2
      exit 2
      ;;
  esac
fi

exit 0
