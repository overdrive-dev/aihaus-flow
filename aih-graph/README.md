# aih-graph

Standalone Go binary memory engine for [aihaus](https://github.com/overdrive-dev/aihaus-flow).

**Status:** v0.1.0-dev (foundation scaffold; M032 of aihaus). Build implementation lands across M033–M038.

## What this is

aih-graph is the **memory + structural retrieval engine** aihaus uses as a mandatory addon. It builds a queryable knowledge graph of aihaus-managed repositories with **first-class ontological types** for aihaus concepts (Decision, Milestone, Story, Agent, Hook, Skill).

This is intentionally **narrower than graphify-the-tool**. v0.1 forever-scope:
- 5 langs (bash, python, JS/TS, Go, Markdown)
- AST extraction via tree-sitter
- JSONL storage
- BFS query with `--budget N` token cap
- 6 first-class typed accessor structs

Out of scope (use graphify in parallel if needed):
- Semantic LLM extraction (paid API)
- Vector embeddings / similarity retrieval (v0.2+ candidate)
- Clustering (Leiden community detection)
- 24+ additional language grammars

## Status

**M032 — foundation scaffold (current).** Module init + CLI skeleton + LICENSE + README. Zero functional implementation yet.

Subsequent milestones build the v0.1 capability:
- M033: AST extraction across 5 langs
- M034: Node/Edge data model + JSONL storage
- M035: BFS query + typed accessor structs
- M036: Privacy gates (XDG storage, isolation, consent, purge, NDA opt-out)
- M037: CI cross-compile (4 platforms)
- M038: v0.1.0 release
- M039: Aihaus integration (install.sh, hooks, agent prompts)
- M040: Smoke checks + aihaus v0.35.0 release

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
