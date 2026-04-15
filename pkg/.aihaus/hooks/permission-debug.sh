#!/bin/bash
set -euo pipefail

# permission-debug.sh — observability-only PermissionRequest hook
# Ships disabled. Enable for triage: export AIHAUS_DEBUG_PERMISSIONS=1
#
# CRITICAL INVARIANT: emit NOTHING on stdout. No {"behavior": ...} JSON.
# Other PermissionRequest hooks (auto-approve-bash.sh, auto-approve-writes.sh)
# remain authoritative. This hook writes one JSONL record per event to
# .aihaus/audit/permission-log.jsonl and exits 0.
# See ADR-009 and architecture.md §7 for the full contract.

# Gate: silent no-op unless explicitly enabled
if [[ "${AIHAUS_DEBUG_PERMISSIONS:-0}" != "1" ]]; then
  exit 0
fi

INPUT=$(cat)

# Extract fields — jq preferred, grep/sed fallback (mirrors audit-log.sh pattern)
if command -v jq >/dev/null 2>&1; then
  TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
  DETAIL=$(echo "$INPUT" | jq -r '.tool_input.command // .tool_input.file_path // empty' 2>/dev/null || echo "")
  SESSION=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
  MATCHER=$(echo "$INPUT" | jq -r '.matcher // .hook_event_name // empty' 2>/dev/null || echo "")
else
  TOOL=$(echo "$INPUT" | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"tool_name"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' || echo "")
  DETAIL=$(echo "$INPUT" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"command"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' || echo "")
  if [[ -z "$DETAIL" ]]; then
    DETAIL=$(echo "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"file_path"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' || echo "")
  fi
  SESSION=$(echo "$INPUT" | grep -oE '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"session_id"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' || echo "")
  MATCHER=""
fi

# Ensure audit directory
AUDIT_DIR="${CLAUDE_PROJECT_DIR:-.}/.aihaus/audit"
mkdir -p "$AUDIT_DIR" 2>/dev/null || true

# Minimal JSON escape (backslash + double-quote), strip newlines
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'; }

TS=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S%z)

printf '{"ts":"%s","event":"PermissionRequest","tool":"%s","matcher":"%s","detail":"%s","session_id":"%s"}\n' \
  "$TS" \
  "$(esc "${TOOL:-}")" \
  "$(esc "${MATCHER:-}")" \
  "$(esc "${DETAIL:-}")" \
  "$(esc "${SESSION:-}")" \
  >> "$AUDIT_DIR/permission-log.jsonl" 2>/dev/null || true

# CRITICAL: emit NOTHING on stdout — no {behavior: ...} JSON.
# Other PermissionRequest hooks (auto-approve-bash, auto-approve-writes) stay authoritative.
exit 0
