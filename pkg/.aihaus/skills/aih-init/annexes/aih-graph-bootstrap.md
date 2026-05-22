# aih-init Phase 3 — aih-graph memory bootstrap (M041)

Invoked from `/aih-init` SKILL.md Phase 3 after `.aihaus/project.md` is
written. Initializes the aih-graph structural + semantic memory index for
the current repo. Default provider is BM25/FTS5 — pure-Go offline, no API
key, no model file download (per ADR-260515-B-amend-02 + amend-04).

This phase is **non-fatal**. Any failure degrades silently to "no memory
engine; agents fall back to markdown reads". `/aih-init` exits 0 either way.

## Step 13. Locate aih-graph binary

Discovery chain (in order):

1. `$AIH_GRAPH_BIN` env var (explicit override)
2. `.aihaus/bin/aih-graph[.exe]` in the target repository
3. `$HOME/.aihaus/bin/aih-graph[.exe]` (global fallback)
4. `$CLAUDE_PROJECT_DIR/aih-graph/bin/aih-graph[.exe]` (contributor dogfood only)
5. `command -v aih-graph` (PATH lookup)

If none resolves, attempt one-shot install:
```bash
bash "$AIHAUS_HOME/pkg/scripts/install-aih-graph-binary.sh" --bin ".aihaus/bin/aih-graph"
```
Where `$AIHAUS_HOME` is read from `~/.aihaus/.install-source`. Non-fatal
(soft-fail) on network error, platform-not-supported, or missing source
script. On failure, print one informational line and proceed to Step 16:
> `aih-graph: binary not found and download failed — memory engine
> disabled (structural BFS will still work post-install)`

## Step 14. Prepare repo-local state

Create repo-local runtime/state directories:
```bash
mkdir -p .aihaus/bin .aihaus/state .aihaus/runtime .aihaus/backups
```

`/aih-init` implies consent for this run. Do not create repo-root
`.aih-graph-consent`; use `--accept-all-repos` on the refresh/build command
instead so target repositories are not cluttered.

## Step 15. Run initial refresh

Invoke the binary against the current repo:
```bash
"$BIN" refresh --repo . --db .aihaus/state/aih-graph.db --accept-all-repos --json
```

Capture stdout. Print a single-line outcome on success:
> `aih-graph: indexed repository memory (db: .aihaus/state/aih-graph.db)`

On non-zero exit, print warning and continue (non-fatal):
> `aih-graph: build failed (exit C) — memory engine partially disabled`

## Step 16. Phase 3 completion summary

Print one final summary line that combines Phase 2 + Phase 3 outcomes:
> `/aih-init complete — project.md ready + aih-graph memory engine
> indexed (or skipped per binary availability).`

No external embedding provider is suggested. BM25/FTS5 is pure-Go offline.
When local Ollama is available, `nomic-embed-text` semantic embeddings are
added opportunistically by the memory engine.

## Soft-skip envelope

The entire Phase 3 is wrapped in a safety envelope. Any of these conditions
exits Phase 3 cleanly without affecting Phase 2's success:
- Binary not found AND download fails
- `aih-graph build` exits non-zero
- `aih-graph build` hangs > 60s (timeout via `timeout 60 bash -c ...`)
- Disk full / permission denied on consent marker creation

In all soft-skip paths, `/aih-init` overall exit code stays 0 — the user's
`.aihaus/project.md` is still the load-bearing deliverable.
