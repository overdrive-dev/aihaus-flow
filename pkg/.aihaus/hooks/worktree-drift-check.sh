#!/usr/bin/env bash
# worktree-drift-check.sh — orchestrator-invoked helper to verify an
# isolation:worktree agent's claimed file paths actually exist in the
# main repo worktree after merge-back. Catches "agent worked on stale
# renames" silent failures (downstream consumer audit, 2026-05-03 Lesson 2).
#
# Usage:
#   bash pkg/.aihaus/hooks/worktree-drift-check.sh <path1> [<path2> ...]
#
# Exit codes:
#   0 = all paths exist in main worktree
#   1 = at least one path missing (diagnostic to stderr)
#   2 = bad args (no paths given)
set -euo pipefail
[ "$#" -ge 1 ] || { echo "worktree-drift-check.sh: at least one path required" >&2; exit 2; }
missing=0
for p in "$@"; do
  if [ ! -e "$p" ]; then
    echo "DRIFT: $p missing in main worktree" >&2
    missing=$((missing + 1))
  fi
done
if [ "$missing" -gt 0 ]; then
  echo "worktree-drift-check.sh: $missing path(s) missing — agent's reported work may not have flowed back" >&2
  exit 1
fi
exit 0
