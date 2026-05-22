#!/usr/bin/env bash
# Shared path helpers for hooks.
#
# Hooks can run with the tool command's cwd, not necessarily the repository
# root. Any default .claude/audit path must therefore be anchored explicitly.

aihaus_project_root() {
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    printf '%s\n' "${CLAUDE_PROJECT_DIR%/}"
    return 0
  fi

  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$root" ]; then
    printf '%s\n' "${root%/}"
    return 0
  fi

  pwd
}

aihaus_is_abs_path() {
  case "${1:-}" in
    /*|[A-Za-z]:/*|[A-Za-z]:\\*) return 0 ;;
    *) return 1 ;;
  esac
}

aihaus_project_path() {
  local path="${1:-}"
  if [ -z "$path" ]; then
    aihaus_project_root
    return 0
  fi
  if aihaus_is_abs_path "$path"; then
    printf '%s\n' "$path"
    return 0
  fi
  printf '%s/%s\n' "$(aihaus_project_root)" "$path"
}
