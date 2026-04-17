#!/usr/bin/env bash
# restore-automode.sh -- shared library sourced by update.sh (and
# install.sh --update) AFTER restore-effort.sh. Reads .aihaus/.automode
# and, if enabled=true, prints an informational stderr note pointing at
# /aih-automode --enable to replay permission-mode side effects.
#
# ADR references: ADR-M012-A (automode sidecar, record-defer discipline),
#                 ADR-M009-A ("record state, defer apply" preserved).
#
# Usage:
#   source "$(dirname "$0")/lib/restore-automode.sh"
#   restore_automode "${AIHAUS_DIR}"
#
# Contract:
#   - $1 is the .aihaus root (e.g. "$TARGET/.aihaus"). Must exist.
#   - Missing .automode sidecar = silent no-op (return 0).
#   - enabled=false = silent no-op (return 0).
#   - enabled=true = print informational 3-line stderr block pointing at
#     /aih-automode --enable. Does NOT mutate settings.local.json,
#     worktree agent frontmatter, or auto-approve-bash.sh SAFE_PATTERNS.
#     Side-effect replay requires explicit /aih-automode --enable with
#     literal-word "auto" confirmation (ADR-M009-A record-defer discipline).
#   - All state is confined to function locals -- sourcing script's globals
#     are not polluted.
#
# Dispatch order in update.sh (binding, architecture doc):
#   1. refresh loop (skills/agents/hooks/templates)
#   2. restore_effort   -- may WRITE .automode during v2->v3 migration
#   3. restore_automode -- READS .automode written in step 2 (order matters)

restore_automode() {
  local aihaus_root="$1"
  local automode_file="${aihaus_root}/.automode"

  [[ -f "$automode_file" ]] || return 0  # No sidecar -- silent no-op.

  local enabled=""
  local last_enabled_at=""
  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    value="${value%$'\r'}"
    case "$key" in
      enabled)         enabled="$value" ;;
      last_enabled_at) last_enabled_at="$value" ;;
    esac
  done < "$automode_file"

  if [[ "$enabled" == "true" ]]; then
    local ts_note=""
    [[ -n "$last_enabled_at" ]] && ts_note=" (last enabled: ${last_enabled_at})"
    echo "" >&2
    echo "  !!  .aihaus/.automode shows enabled=true${ts_note}." >&2
    echo "  !!  Permission-mode side effects are NOT auto-replayed after /aih-update." >&2
    echo "  !!  Run /aih-automode --enable to re-apply defaultMode=auto and worktree" >&2
    echo "  !!  agent frontmatter changes." >&2
    echo "" >&2
  fi

  return 0
}
