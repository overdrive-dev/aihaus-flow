#!/usr/bin/env bash
# aih-graph-refresh.sh — refresh the aih-graph index for the current repo.
#
# Per ADR-260515-D-amend-01 + ADR-260515-B-amend-02. Invoked manually
# (`bash .aihaus/hooks/aih-graph-refresh.sh`) or by aihaus skills that want
# the structural/semantic memory to reflect recent changes.
#
# Discovery (in order):
#   1. AIH_GRAPH_BIN env var (explicit override)
#   2. $HOME/.aihaus/bin/aih-graph[.exe]   (canonical install location)
#   3. $PWD/aih-graph/bin/aih-graph[.exe]  (in-tree dogfood build)
#   4. PATH lookup via `command -v aih-graph`
# If none resolves, emit a non-fatal warning and exit 0 — aih-graph is
# optional; missing binary should never block the aihaus session.
#
# Env vars:
#   AIH_GRAPH_BIN       Explicit binary path (skip discovery)
#   AIH_GRAPH_PROVIDER  Search/embedding provider. Default unset -> uses
#                       binary default (bm25, pure-Go offline FTS5). Pass
#                       ollama for local semantic embeddings, fake for tests,
#                       or none to skip the search index.
#   AIH_GRAPH_DB        Override .db path (default: aih-graph manages via XDG)
#   AIH_GRAPH_QUIET     If set non-empty, suppress per-line output.

set -euo pipefail

quiet="${AIH_GRAPH_QUIET:-}"
log() {
  [[ -n "$quiet" ]] && return 0
  echo "aih-graph-refresh: $*"
}
warn() {
  echo "aih-graph-refresh: warning: $*" >&2
}

# Repo root: prefer CLAUDE_PROJECT_DIR set by Claude Code; fall back to PWD.
repo_root="${CLAUDE_PROJECT_DIR:-$PWD}"

# Detect platform suffix.
ext=""
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) ext=".exe" ;;
esac

# Locate binary via discovery chain.
candidates=()
[[ -n "${AIH_GRAPH_BIN:-}" ]] && candidates+=("$AIH_GRAPH_BIN")
candidates+=("$HOME/.aihaus/bin/aih-graph${ext}")
candidates+=("$repo_root/aih-graph/bin/aih-graph${ext}")

bin=""
for c in "${candidates[@]}"; do
  if [[ -x "$c" ]]; then
    bin="$c"
    break
  fi
done
if [[ -z "$bin" ]] && command -v aih-graph >/dev/null 2>&1; then
  bin="$(command -v aih-graph)"
fi

if [[ -z "$bin" ]]; then
  warn "no aih-graph binary found; skipping refresh"
  warn "install via: bash pkg/scripts/install-aih-graph-binary.sh"
  exit 0
fi

log "binary: $bin"
log "repo:   $repo_root"

# Build invocation.
args=(build --accept-all-repos "$repo_root")
if [[ -n "${AIH_GRAPH_DB:-}" ]]; then
  args=(build --accept-all-repos --db "$AIH_GRAPH_DB" "$repo_root")
fi

provider="${AIH_GRAPH_PROVIDER:-none}"
if [[ "$provider" != "none" ]]; then
  args+=(--embed-provider "$provider")
fi

# Run. Failures are non-fatal — aih-graph is supplemental.
if ! "$bin" "${args[@]}"; then
  warn "aih-graph build failed (exit $?); continuing"
  exit 0
fi

rm -f "$repo_root/.claude/audit/aih-graph.stale" 2>/dev/null || true
log "refresh complete"
