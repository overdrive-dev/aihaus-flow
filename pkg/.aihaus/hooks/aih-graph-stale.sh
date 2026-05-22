#!/usr/bin/env bash
# aih-graph-stale.sh - mark derived repository memory stale after changes.
#
# This hook is intentionally cheap: it only writes a marker under
# .aihaus/state/. The next successful aih-graph refresh clears the marker.

set -euo pipefail

repo_root="${CLAUDE_PROJECT_DIR:-$PWD}"
reason="${AIH_GRAPH_STALE_REASON:-repository changed}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reason)
      reason="${2:-$reason}"
      shift 2
      ;;
    --from-hook)
      hook_kind="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

input="$(cat || true)"

# For Bash PostToolUse hooks, only mark stale for commands that commonly change
# repository history or generated files. Plain read/test commands stay quiet.
if [[ "${hook_kind:-}" == "bash" ]]; then
  command_text=""
  if command -v jq >/dev/null 2>&1; then
    command_text="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
  fi
  if [[ -z "$command_text" ]]; then
    command_text="$(printf '%s' "$input" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"command"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' || true)"
  fi
  case "$command_text" in
    *aih-graph-refresh.sh*|*'aih-graph build'*|*'aih-graph refresh'*|*'aihaus memory refresh'*|*'aih-graph status'*|*'aih-graph query'*|*'aih-graph context'*|*'aih-graph callers'*|*'aih-graph impact'*)
      exit 0
      ;;
    *'git commit'*|*'git merge'*|*'git cherry-pick'*|*'git rebase'*)
      reason="git history changed"
      ;;
    *)
      exit 0
      ;;
  esac
fi

marker_dir="$repo_root/.aihaus/state"
marker="$marker_dir/aih-graph.stale"
mkdir -p "$marker_dir"
{
  printf 'stale_since=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'reason=%s\n' "$reason"
} > "$marker.tmp"
mv "$marker.tmp" "$marker"

exit 0
