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
2. `$HOME/.aihaus/bin/aih-graph[.exe]` (canonical install location)
3. `$CLAUDE_PROJECT_DIR/aih-graph/bin/aih-graph[.exe]` (in-tree dogfood)
4. `command -v aih-graph` (PATH lookup)

If none resolves, attempt one-shot install:
```bash
bash "$AIHAUS_HOME/pkg/scripts/install-aih-graph-binary.sh"
```
Where `$AIHAUS_HOME` is read from `~/.aihaus/.install-source`. Non-fatal
(soft-fail) on network error, platform-not-supported, or missing source
script. On failure, print one informational line and proceed to Step 16:
> `aih-graph: binary not found and download failed — memory engine
> disabled (structural BFS will still work post-install)`

## Step 14. Create consent marker

The `.aih-graph-consent` marker at repo root opts this repo into aih-graph
indexing per ADR-260515-A privacy contract. `/aih-init` implies consent by
the user running it. Create the marker if absent:
```bash
[[ -f .aih-graph-consent ]] || touch .aih-graph-consent
```

## Step 15. Run initial build

Invoke the binary against the current repo:
```bash
"$BIN" build --accept-all-repos --embed-provider bm25 .
```

Capture stdout. Print a single-line outcome on success:
> `aih-graph: indexed N nodes via BM25 (db: <path>)`

On non-zero exit, print warning and continue (non-fatal):
> `aih-graph: build failed (exit C) — memory engine partially disabled`

## Step 16. Phase 3 completion summary

Print one final summary line that combines Phase 2 + Phase 3 outcomes:
> `/aih-init complete — project.md ready + aih-graph memory engine
> indexed (or skipped per binary availability).`

No external embedding provider is suggested. BM25/FTS5 is pure-Go offline
and is the only documented surface (per ADR-260516-A). Optional external
providers remain available as opt-in via `--embed-provider <name>` flags
on the binary, but `/aih-init` does not advertise them.

## Soft-skip envelope

The entire Phase 3 is wrapped in a safety envelope. Any of these conditions
exits Phase 3 cleanly without affecting Phase 2's success:
- Binary not found AND download fails
- `aih-graph build` exits non-zero
- `aih-graph build` hangs > 60s (timeout via `timeout 60 bash -c ...`)
- Disk full / permission denied on consent marker creation

In all soft-skip paths, `/aih-init` overall exit code stays 0 — the user's
`.aihaus/project.md` is still the load-bearing deliverable.
