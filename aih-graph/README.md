# aih-graph

Standalone Go binary memory engine for [aihaus](https://github.com/overdrive-dev/aihaus-flow).

**Status:** v0.1.4 shipped baseline plus M048 in-progress native repository memory (files, chunks, symbols, calls, tests, markdown memory, commits, local Ollama embeddings, context/callers/impact/gotchas/milestone commands).

## What this is

aih-graph is the **memory + structural retrieval engine** aihaus uses as a mandatory addon. It builds a queryable knowledge graph of aihaus-managed repositories with **first-class ontological types** for aihaus concepts (Decision, Milestone, Story, Agent, Hook, Skill) and M048 repository-memory types (File, Chunk, Symbol, Call).

M048 adds a local repository-brain slice:
- `File` and `Chunk` nodes for real repository text
- `Symbol` and `Call` nodes for Go functions/methods plus shell and PowerShell functions
- `Test` nodes for Go tests and common script/spec test files
- `Memory` nodes from markdown memory and `Commit` nodes from recent git history
- `context`, `callers`, `impact`, `gotchas`, `milestone`, `status`, and `mark-stale` commands
- `refresh` as the agent-facing rebuild command (`build` remains the lower-level primitive)
- `--embed-provider ollama` for local semantic embeddings through Ollama `/api/embed`

The installed `aihaus` shim exposes these as `aihaus memory <subcommand> ...`.

## Agent-readable output

The human text output remains the default. Agents should prefer `--json` for stable payloads:

```bash
aihaus memory query --semantic --json "Ollama embedding provider"
aihaus memory status --json
aihaus memory context --type Symbol --depth 1 --json aih-graph/internal/extract/repository.go:ParseRepositoryText
aihaus memory impact --type File --depth 1 --limit 40 --json aih-graph/cmd/aih-graph/main.go
aihaus memory callers --json ParseRepositoryText
aihaus memory gotchas --json git checkout
aihaus memory milestone --json Ollama
```

`query`, `context`, `impact`, `callers`, `gotchas`, `milestone`, and `status` support `--json`. Exact graph lookups include node `type`, `identifier`, derived `title`, and stored `properties`. Long string properties are capped in JSON output and marked with `<field>_truncated` plus `<field>_original_bytes`; the SQLite index keeps the complete value. `query`, `context`, and `impact` include `freshness`; `context` and `impact` also include `neighborhood_total`, `neighborhood_returned`, and `neighborhood_truncated`; use `--limit N` to bound agent payloads, or `--limit 0` for a full neighborhood. Pass `--repo PATH` when the command runs from outside the indexed repository.

This is intentionally **narrower than graphify-the-tool**. v0.1 forever-scope:
- **Markdown-only extraction** for 6 aihaus typed nodes (Decision/Milestone/Story/Agent/Hook/Skill) — per ADR-260515-C-amend-02
- **modernc.org/sqlite storage** (pure-Go, no CGO) — per ADR-260515-B-amend-02
- **Lexical search via BM25/FTS5** (pure-Go offline, zero API keys, zero model downloads) — default per ADR-260515-B-amend-02 + ADR-260516-A. Optional vector providers include local Ollama (`--embed-provider ollama`) and test-only fake embeddings.
- **Three query modes:** structural BFS, vector similarity (`--semantic`), hybrid
- **Pure-Go single binary** — zero CGO requirement, works on any platform Go supports

Out of scope for v0.1 baseline (M048 is now adding a first native slice):
- Broad AST extraction for every language (Python/JS/TS/etc.) remains deferred; current M048 extraction is intentionally focused on aihaus-flow's Go, shell, PowerShell, and markdown needs
- Semantic LLM extraction (paid LLM-driven node/edge extraction — distinct from embeddings)
- Clustering (Leiden community detection)
- HNSW/IVF vector indexes (brute-force only; sufficient for target repos up to ~500k nodes)
- LLM re-ranking (`--rerank` deferred to v0.2+)
- Local-ONNX embedding provider — deferred indefinitely (would re-introduce CGO; pure-Go transformer inference not production-grade today)

## Status

**v0.1.1 — shipped.** Markdown extraction across 6 aihaus types + modernc/sqlite storage + 3 query modes + BM25/FTS5 lexical search + 4-platform binary release.

Shipped milestone chain:
- M033: Markdown extraction (6 type parsers)
- M034: modernc/sqlite storage
- M035: Query (BFS/semantic/hybrid) + typed accessors + embedding pipeline
- M036: Privacy gates (XDG storage, isolation, consent, purge, NDA opt-out)
- M037: CI cross-compile (4 platforms)
- M038: v0.1.0 release
- M039: aihaus integration (install.sh, hooks, agent prompts)
- M040: Smoke checks + aihaus v0.35.0 release
- M041: BM25/FTS5 lexical search default; one-shot install; tag v0.1.1
- M041 dogfood: query --db default + hybrid BM25 routing + var-version ldflag fix; tag v0.1.2
- M042: Voyage demotion from advertised surfaces; CLI/PRD/README reconciliation; tag v0.1.3
- M046: Agent memory indexing — `.claude/agent-memory/<name>/MEMORY.md` excerpts (200 lines / 25KB cap matching native CC) injected into Agent node properties; tag v0.1.4

## Verifying the memory engine

After `/aih-init` has built the index for at least one project, you can verify the binary, the DB file, and the query pipeline in three steps.

**1. Binary present and reports version:**
```
aih-graph version
```
Should print `v0.1.3` (or higher). If the binary is absent: `bash pkg/scripts/install-aih-graph-binary.sh` re-downloads it from GitHub Releases.

**2. DB file exists on disk** (per-repo isolated, XDG-scoped):

| Platform | Path |
|----------|------|
| Linux | `$XDG_STATE_HOME/aih-graph/<sha256-hex-16>/graph.db` (default: `~/.local/state/aih-graph/...`) |
| macOS | `~/Library/Application Support/aih-graph/<sha256-hex-16>/graph.db` |
| Windows | `%LOCALAPPDATA%\aih-graph\<sha256-hex-16>\graph.db` |

The 16-hex subfolder is the SHA-256 prefix of the absolute repo path — one subfolder per repo. Override the location with the `AIH_GRAPH_HOME` env var.

**3. Query returns scored results:**
```
aih-graph query --hybrid "decision"
```
A healthy index returns at least one `[s=N.NN]` line, for example:
```
[s=5.42] Decision   ADR-260515-E-amend-02   v0.1 forever-scope: vector promoted...
[s=4.72] Hook       aih-graph-refresh.sh    aih-graph-refresh.sh — refresh...
```

Use `--semantic` (vector-only, when an embedding provider is configured) or `--bfs <exact-identifier>` (structural lookup) instead of `--hybrid` for narrower queries.

### Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `no node matches identifier "..."` | Used the default mode (identifier exact-match) on free-text input | Pass `--hybrid` or `--semantic` |
| `consent gate: missing .aih-graph-consent` | Repo not opted-in to indexing | `aih-graph build --accept-all-repos .` or run `/aih-init` |
| `database is locked` | Another process writing to the DB | Wait a few seconds and retry |
| Build prints `0 nodes` | `pkg/.aihaus/decisions.md` empty or repo has no aihaus typed nodes | Verify the repo is an aihaus-managed project (has `pkg/.aihaus/` or `.aihaus/`) |
| `aih-graph: command not found` | Binary not on PATH and discovery chain failed | Re-run install: `bash pkg/scripts/install-aih-graph-binary.sh` |

## Specs

Authoritative design package in `pkg/.aihaus/decisions.md`:
- ADR-260515-A — privacy contract
- ADR-260515-B — Node/Edge data model (hybrid generic+typed)
- ADR-260515-C — tree-sitter binding (provisional + M033 pre-flight gate; amended by C-amend-01)
- ADR-260515-D — integration model (tight, monorepo)
- ADR-260515-E — v0.1 forever-scope

Full PRD at `aih-graph/PRD.md`.

## License

MIT — see `LICENSE`.
