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
#   AIH_GRAPH_DB        Override .db path (default: aih-graph manages via XDG)
#   AIH_GRAPH_QUIET     If set non-empty, suppress per-line output.
#   AIH_GRAPH_OLLAMA_URL Override Ollama base URL (or use OLLAMA_HOST).
#   AIHAUS_OLLAMA_AUTO  Default 1. Start local Ollama when installed so
#                       aih-graph can use nomic-embed-text embeddings.

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

ollama_base_url="${AIH_GRAPH_OLLAMA_URL:-${OLLAMA_HOST:-http://127.0.0.1:11434}}"
case "$ollama_base_url" in
  http://*|https://*) ;;
  *) ollama_base_url="http://${ollama_base_url}" ;;
esac
ollama_base_url="${ollama_base_url%/}"
ollama_model="nomic-embed-text"
ollama_bin="${AIHAUS_OLLAMA_BIN:-}"
if [[ -z "$ollama_bin" ]] && command -v ollama >/dev/null 2>&1; then
  ollama_bin="$(command -v ollama)"
fi

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

ollama_ready() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsS "${ollama_base_url}/api/tags" >/dev/null 2>&1
    return $?
  fi
  [[ -n "$ollama_bin" ]] && "$ollama_bin" list >/dev/null 2>&1
}

ollama_model_available() {
  [[ -z "$ollama_bin" ]] && return 0
  "$ollama_bin" list 2>/dev/null | awk -v model="$ollama_model" 'NR>1 { if ($1 == model || index($1, model ":") == 1) found=1 } END { exit found ? 0 : 1 }'
}

ensure_ollama_ready() {
  ollama_ready && return 0
  [[ "${AIHAUS_OLLAMA_AUTO:-1}" == "0" ]] && return 1
  [[ -z "$ollama_bin" ]] && return 1

  log "starting Ollama for local embeddings"
  nohup "$ollama_bin" serve >/dev/null 2>&1 &
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 0.5
    ollama_ready && return 0
  done
  return 1
}

log "binary: $bin"
log "repo:   $repo_root"

# Refresh invocation.
args=(refresh --repo "$repo_root" --accept-all-repos)
if [[ -n "${AIH_GRAPH_DB:-}" ]]; then
  args+=(--db "$AIH_GRAPH_DB")
fi

if ensure_ollama_ready; then
  if ollama_model_available; then
    log "ollama: ready (${ollama_model})"
  else
    warn "Ollama is available but model '${ollama_model}' is missing; semantic embeddings will be skipped"
    warn "install model manually with: ollama pull ${ollama_model}"
  fi
else
  log "ollama: unavailable; refreshing BM25 index only"
fi

# Run. Failures are non-fatal — aih-graph is supplemental.
if "$bin" "${args[@]}"; then
  rm -f "$repo_root/.claude/audit/aih-graph.stale" 2>/dev/null || true
  log "refresh complete"
else
  rc=$?
  warn "aih-graph refresh failed (exit $rc); continuing"
  exit 0
fi
