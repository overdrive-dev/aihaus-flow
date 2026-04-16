#!/bin/bash
set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
BACKUP_DIR="$CLAUDE_PROJECT_DIR/.claude/backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

mkdir -p "$BACKUP_DIR"

if [ -f "$FILE_PATH" ]; then
  REL_PATH="${FILE_PATH#$CLAUDE_PROJECT_DIR/}"
  BACKUP_FILE="$BACKUP_DIR/${TIMESTAMP}_${REL_PATH//\//__}"
  cp "$FILE_PATH" "$BACKUP_FILE" 2>/dev/null || true
  # Keep last 200 backups
  ls -t "$BACKUP_DIR"/* 2>/dev/null | tail -n +201 | xargs rm -f 2>/dev/null || true
fi

exit 0
