#!/usr/bin/env bash
# legacy-preflight.sh - classify old harness artifacts during /aih-init.
#
# Default behavior is report-only. With --fix-safe, archives only untracked,
# known-disposable aihaus leftovers into .aihaus/backups/legacy-cleanup/<stamp>/.
# It never removes git worktrees, .gsd, .hermes, .mcp.json, or tracked files.

set -euo pipefail

FIX_SAFE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --fix-safe) FIX_SAFE=1; shift ;;
    --report-only) FIX_SAFE=0; shift ;;
    *) shift ;;
  esac
done

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

STAMP="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || date +%Y%m%dT%H%M%SZ)"
AUDIT_DIR=".aihaus/audit"
BACKUP_DIR=".aihaus/backups/legacy-cleanup/${STAMP}"
REPORT="${AUDIT_DIR}/legacy-preflight-${STAMP}.md"
mkdir -p "$AUDIT_DIR"

ARCHIVED=0
SAFE_FOUND=0
TRACKED_SKIPPED=0
MANUAL=0

has_tracked_files() {
  git ls-files -- "$1" 2>/dev/null | grep -q .
}

is_ignored() {
  git check-ignore -q -- "$1" 2>/dev/null
}

append() {
  printf '%s\n' "$1" >> "$REPORT"
}

path_kind() {
  if [ -d "$1" ]; then
    printf 'dir'
  else
    printf 'file'
  fi
}

archive_safe() {
  local rel="$1"
  local reason="$2"
  [ -e "$rel" ] || return 0
  SAFE_FOUND=$((SAFE_FOUND + 1))

  if has_tracked_files "$rel"; then
    TRACKED_SKIPPED=$((TRACKED_SKIPPED + 1))
    append "- skip tracked $(path_kind "$rel") \`$rel\` - $reason"
    return 0
  fi

  if [ "$FIX_SAFE" -ne 1 ]; then
    append "- found disposable $(path_kind "$rel") \`$rel\` - $reason"
    return 0
  fi

  local dst="${BACKUP_DIR}/${rel}"
  mkdir -p "$(dirname "$dst")"
  mv -- "$rel" "$dst"
  ARCHIVED=$((ARCHIVED + 1))
  append "- archived $(path_kind "$dst") \`$rel\` -> \`${dst}\` - $reason"
}

manual_review() {
  local rel="$1"
  local reason="$2"
  [ -e "$rel" ] || return 0
  MANUAL=$((MANUAL + 1))
  append "- review \`$rel\` - $reason"
}

{
  printf '# aihaus legacy preflight\n\n'
  printf -- '- repo: `%s`\n' "$ROOT"
  printf -- '- timestamp: `%s`\n' "$STAMP"
  if [ "$FIX_SAFE" -eq 1 ]; then
    printf -- '- mode: `fix-safe`\n\n'
  else
    printf -- '- mode: `report-only`\n\n'
  fi
  printf '## Safe Disposable Artifacts\n\n'
} > "$REPORT"

archive_safe ".aihaus/.claude" "nested audit/cache directory created by old relative hook paths"
archive_safe ".aihaus/state/.claude" "nested audit/cache directory created by old relative hook paths"
archive_safe ".aihaus/plans/.claude" "nested audit/cache directory created by old relative hook paths"
archive_safe ".aihaus/state/schema.sql" "old ad hoc /aih-goal schema now packaged with aihaus-flow"
archive_safe ".aihaus/state/import_tasks.py" "old ad hoc /aih-goal import helper now packaged with aihaus-flow"

append ""
append "## Manual Review Artifacts"
append ""
manual_review ".gsd" "legacy GSD knowledge/runtime; migrate useful markdown into .aihaus/memory before removing"
manual_review ".gsd-id" "legacy GSD project marker"
manual_review ".hermes" "legacy agent reports; migrate useful reports into .aihaus/memory or docs before removing"
manual_review ".mcp.json" "project MCP config; if it points to gsd-workflow, replace intentionally"
manual_review ".worktrees" "local worktree-like directory not owned by current aihaus cleanup hooks"
manual_review "frontend/.aihaus" "nested package install; review because monorepos may intentionally install per package"
manual_review "frontend/.claude" "nested Claude state; review because files may be tracked in older repos"

append ""
append "## Package Install Noise"
append ""
for rel in \
  ".aihaus/agents" ".aihaus/skills" ".aihaus/hooks" ".aihaus/templates" \
  ".claude/agents" ".claude/hooks" ".claude/skills" ".claude/worktrees" \
  ".claude/agent-memory" ".claude/settings.local.json" \
  ".bg-shell"; do
  if [ -e "$rel" ]; then
    if is_ignored "$rel"; then
      append "- ignored \`$rel\`"
    else
      append "- not ignored \`$rel\` - run /aih-update from aihaus >= 0.38.6 or update .gitignore"
      MANUAL=$((MANUAL + 1))
    fi
  fi
done

append ""
append "## Git Worktrees"
append ""
WT_TMP=".aihaus/runtime/legacy-preflight-worktrees.$$"
mkdir -p ".aihaus/runtime"
if git worktree list --porcelain >"$WT_TMP" 2>/dev/null; then
  total="$(awk '/^worktree /{n++} END{print (n > 0 ? n - 1 : 0)}' "$WT_TMP")"
  locked="$(awk '/^locked/{n++} END{print n + 0}' "$WT_TMP")"
  under_claude="$(awk '/^worktree / && /\.claude\/worktrees\//{n++} END{print n + 0}' "$WT_TMP")"
  append "- registered non-main worktrees: ${total}"
  append "- locked worktrees: ${locked}"
  append "- under .claude/worktrees: ${under_claude}"
  append "- cleanup is not automatic; use .aihaus/hooks/worktree-reconcile.sh or worktree-reap.sh after reviewing pending merges"
  rm -f "$WT_TMP"
else
  append "- git worktree list failed or unavailable"
  rm -f "$WT_TMP"
fi

append ""
append "## Summary"
append ""
append "- disposable found: ${SAFE_FOUND}"
append "- archived: ${ARCHIVED}"
append "- tracked skipped: ${TRACKED_SKIPPED}"
append "- manual review items: ${MANUAL}"

printf 'aih-init legacy preflight: report=%s archived=%s manual=%s\n' "$REPORT" "$ARCHIVED" "$MANUAL"
