#!/bin/bash
set -euo pipefail

cd "$CLAUDE_PROJECT_DIR"

# Stash uncommitted work as safety net
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  git stash push -m "auto-backup-$(date +%Y%m%d-%H%M%S)" --include-untracked 2>/dev/null || true
  git stash pop 2>/dev/null || true
fi

LOG_DIR="$CLAUDE_PROJECT_DIR/.claude/audit"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).jsonl"
mkdir -p "$LOG_DIR"

jq -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{ts: $ts, event: "session_end"}' >> "$LOG_FILE"

exit 0
