# aih-graph

Standalone Go binary memory engine for [aihaus](https://github.com/overdrive-dev/aihaus-flow).

**Status:** v0.1.1 (shipped M033–M041; markdown extraction + modernc/sqlite storage + 3 query modes + BM25/FTS5 lexical search + 4-platform binary release).

## What this is

aih-graph is the **memory + structural retrieval engine** aihaus uses as a mandatory addon. It builds a queryable knowledge graph of aihaus-managed repositories with **first-class ontological types** for aihaus concepts (Decision, Milestone, Story, Agent, Hook, Skill).

This is intentionally **narrower than graphify-the-tool**. v0.1 forever-scope:
- **Markdown-only extraction** for 6 aihaus typed nodes (Decision/Milestone/Story/Agent/Hook/Skill) — per ADR-260515-C-amend-02
- **modernc.org/sqlite storage** (pure-Go, no CGO) — per ADR-260515-B-amend-02
- **Lexical search via BM25/FTS5** (pure-Go offline, zero API keys, zero model downloads) — default per ADR-260515-B-amend-02 + ADR-260516-A. Optional external embedding providers are wired but **not advertised** by aihaus skills.
- **Three query modes:** structural BFS, vector similarity (`--semantic`), hybrid
- **Pure-Go single binary** — zero CGO requirement, works on any platform Go supports

Out of scope for v0.1 (use graphify in parallel if needed):
- AST extraction for code files (Python/JS/Go/bash/PowerShell) — deferred to v0.2+ when CGO ecosystem matures or pure-Go tree-sitter port emerges
- Symbol/File generic node types for code — paired with above
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
- M042: Voyage demotion from advertised surfaces; CLI/PRD/README reconciliation

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
