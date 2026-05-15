# aih-graph v0.1 PRD

**Project:** aih-graph — Go binary memory engine for aihaus
**Repo:** `aihaus-flow/aih-graph/` (monorepo; not a sibling repo)
**Spec version:** v0.1 (forever-scope per ADR-260515-E)
**Date:** 2026-05-15
**Status:** Spec frozen at M031/S06; build begins M032; v0.1.0 release in M038

## Overview

aih-graph is a Go binary that builds a queryable knowledge graph from aihaus repositories. It extracts AST nodes from 5 languages, ingests markdown (including agent memory + ADRs), stores in JSONL, and exposes a BFS query interface with token-budget enforcement. Distinguishing feature vs graphify: **first-class ontological types for aihaus concepts** (Decision, Milestone, Story, Agent, Hook, Skill).

aih-graph is **NOT a graphify replacement** — it has narrower scope (intentionally narrower forever per Q4 + ADR-260515-E). Users who need semantic LLM extract, embeddings, clustering, or 29-lang coverage should install graphify in parallel. aih-graph's value-add is what graphify cannot do: typed retrieval over aihaus's specific ontology.

## Goals (v0.1 forever-scope)

| # | Goal | Source ADR |
|---|------|-----------|
| 1 | Build CLI binary callable from aihaus skills via Bash | ADR-260515-D |
| 2 | Extract AST from 6 langs (bash, python, JS/TS, Go, Markdown, PowerShell — per ADR-260515-E-amend-01) | ADR-260515-C + -E |
| 3 | Store as JSONL with per-record `_v` schema version | ADR-260515-B |
| 4 | 6 first-class typed accessor structs in `pkg/aihgraph/` Go API | ADR-260515-B |
| 5 | BFS query with `--budget N` token cap | ADR-260515-E |
| 6 | Per-repo isolation invariant + ingestion consent gate + `--purge` uninstall + NDA opt-out | ADR-260515-A |
| 7 | XDG-compliant default storage path (Linux/macOS/Windows) | ADR-260515-A |
| 8 | `--include-gitignored <glob>` flag + `.aihignore` config | ADR-260515-E |
| 9 | Cross-compile CI for 4 platforms (linux-amd64, darwin-amd64, darwin-arm64, windows-amd64) | M037 milestone |
| 10 | M032 pre-flight verification gate before any Go code commit | ADR-260515-C |

## Non-Goals (v0.1 forever-scope; explicitly OUT)

- Embeddings / vector retrieval / semantic similarity. (v0.2+ candidate; ONNX-local; NOT committed.)
- Clustering (Leiden community detection). (v0.2+ candidate.)
- HTML visualization (graph.html). (Possibly never — CLI + JSONL is enough.)
- Cross-repo global graph. (v0.2+ candidate; gated on per-repo isolation invariant evolution.)
- LLM-semantic extract (paid API backend). (Never — graphify covers this; users install in parallel.)
- Watch mode auto-rebuild. (v0.2+ candidate.)
- Git merge driver for graph.json. (Never.)
- 24+ other tree-sitter grammars (Rust, Java, Ruby, etc.). (Never expected in v0.1.)
- Mandatory MCP server in v0.1. (Deferred to v0.2 per ADR-260515-D.)
- schemagen toolchain. (v0.2+ candidate per phase-researcher-R2 YAGNI argue-against; fixed 6 types in v0.1 don't need generator overhead.)

## 2-Column Comparison: graphify TODAY vs aih-graph v0.1 (forever-scope)

Per BRIEF.md CHALLENGES C2 surfacing — honest trade-off.

| Capability | graphify v0.7.19 (today, empirically tested on aihaus-flow) | aih-graph v0.1 (forever-scope) |
|------------|---------------------------------------------|-------------------------------|
| **Languages** | 29 (bash, python, JS/TS, Go, Rust, Java, Ruby, C/C++, Swift, Kotlin, Scala, PHP, R, Lua, Zig, PowerShell, Elixir, ObjC, Julia, Vue, Svelte, Astro, Groovy, Dart, V, SystemVerilog, SQL, Fortran, Pascal/Delphi) | 6 (bash, python, JS/TS, Go, Markdown, PowerShell — 7 grammar modules; per ADR-260515-E-amend-01) |
| **AST extraction** | Tree-sitter; mature; full-feature | Tree-sitter; same library; subset of grammars |
| **Markdown ingestion** | Yes | Yes |
| **Storage format** | graph.json (1MB on aihaus-flow) | JSONL (per-record append-friendly; smaller binary footprint) |
| **First-class aihaus types (Decision/Milestone/Story/Agent/Hook/Skill)** | No — all markdown treated as generic headers | **Yes — 6 typed accessor structs in Go API** ← aih-graph's distinguishing value |
| **Query interface** | `graphify query "..." --budget N` (BFS); sub-0.5s on 1580-node graph; ~500 tokens output | `aih-graph query "..." --budget N` (BFS); target sub-0.5s parity |
| **Output (empirical on aihaus-flow)** | 1580 nodes / 1428 edges / 162 communities | Not measurable until M035 ships; v0.1 promises in-scope-lang subset, no nodes/edges projection committed (per CHECK F2 fix) |
| **LLM-semantic extract (paid API)** | Yes — gemini/kimi/claude/openai/ollama backend; richer prose-question retrieval | **NO** (defer to user installing graphify in parallel) |
| **Clustering (community detection)** | Yes — Leiden | NO (v0.2+ candidate) |
| **Embeddings / vector retrieval** | graphrag (RAG over graph) | NO (v0.2+ ONNX-local candidate) |
| **HTML visualization** | graph.html | NO (CLI + JSONL only) |
| **Cross-repo global graph** | `graphify global add` (v0.7.x) | NO (v0.2+ candidate; gated on isolation invariant evolution) |
| **Watch mode** | `graphify watch <path>` | NO (v0.2+ candidate) |
| **Write-back / save-result** | `graphify save-result` | YES (aih-graph save-result equivalent in v0.1; structured Q&A persisted to per-repo storage) |
| **Privacy contract (per-repo isolation + consent gate + NDA opt-out)** | NO — graphify v0.7.x has no privacy contract surface | **YES — 5 binding contracts** ← aih-graph's distinguishing value |
| **Mandatory addon to aihaus** | Currently NO (user installs separately) | YES (M039 install.sh auto-builds; M040 smoke checks enforce) |
| **Bus factor** | 1 maintainer (safishamsi); 6 weeks old (created 2026-04-03); 47k stars in viral spike | aihaus's existing maintainer (Victor); monorepo means same maintenance discipline |
| **License** | MIT | MIT (aih-graph follows aihaus parent license) |
| **Install footprint** | Python 3.10+ + uv + ~50MB Python deps | Single Go binary (~30MB statically linked across 4 platforms) |
| **Token cost on agent invocation** | 6.7k tokens on full `GRAPH_REPORT.md` prepend; ~500 tokens per query | Target parity: ~500 tokens per query |
| **Custom aihaus integrations (hooks, smoke-checks, install.sh wiring)** | None | M039 ships full integration |

**Honest summary:** graphify dominates on feature breadth + 24 additional langs + semantic LLM extract + HTML viz + clustering. aih-graph dominates ONLY on 2 axes: **typed aihaus ontology** + **privacy contract**. Users who need graphify's feature breadth should install graphify in parallel — the two coexist (different output paths). aih-graph's narrowness is intentional and forever.

## Module Layout (per architecture.md §4)

```
aihaus-flow/
└── aih-graph/                          (top-level Go module — monorepo)
    ├── go.mod                          (M032 deliverable; pinned deps)
    ├── go.sum
    ├── cmd/aih-graph/main.go           (CLI entrypoint; M032)
    ├── internal/
    │   ├── parser/                     (tree-sitter integration; M033)
    │   ├── graph/                      (Node/Edge data model per ADR-260515-B; M034)
    │   ├── storage/                    (JSONL writer/reader; M034)
    │   ├── query/                      (BFS implementation + --budget N; M035)
    │   ├── types/                      (6 first-class aihaus types; M035)
    │   ├── privacy/                    (XDG path + consent gate + isolation per ADR-260515-A; M036)
    │   └── watch/                      (placeholder; v0.2+ — empty stub in v0.1 if any)
    ├── pkg/aihgraph/                   (PUBLIC Go API surface; typed accessor structs from ADR-260515-B)
    ├── .aihignore                      (default config; aihaus repo-aware defaults — node_modules/ excluded; .aihaus/memory/*.md INCLUDED)
    ├── .github/workflows/aih-graph-ci.yml  (CI cross-compile per S09 spec → M037 impl)
    ├── bin/aih-graph                   (built binary; committed under monorepo per ADR-260515-D)
    ├── PRD.md                          (THIS document)
    ├── README.md                       (user-facing; M038 deliverable)
    └── LICENSE                         (MIT; M032 deliverable)
```

## CLI Surface (v0.1)

```
aih-graph build <path>                  Build/refresh graph for repository at <path>
  --include-gitignored <glob>             Override .gitignore for matching paths (default: respects .gitignore)
  --no-cluster                            Skip clustering (always true in v0.1; v0.2 flag)
  --accept-all-repos                      Bypass ingestion consent gate (CI/automation only)
  --force                                 Overwrite existing graph

aih-graph query "<question>" [--budget N=2000]
                                        BFS over graph, return up to N tokens of matched nodes + edges
  --graph <path>                          Override graph.jsonl path (default XDG)
  --dfs                                   Use depth-first instead of breadth-first
  --type <Type>                           Filter by first-class type (e.g., --type Decision)

aih-graph save-result --question Q --answer A --type query|path_query|explain [--nodes N1 N2 ...]
                                        Persist Q&A to per-repo memory (graph-augmented retrieval feedback)

aih-graph uninstall [--purge]           Remove aih-graph state
  --purge                                 Remove ALL per-repo graphs + global state + sentinels (hard contract)

aih-graph --version                     Print version + commit SHA
aih-graph --help                        CLI help
```

## Implementation Sequence (M032-M040)

Per architecture.md §4 module-by-module + ADR-260515-E forever-scope discipline.
**Post-pivot (ADR-260515-B-amend-01 + E-amend-02 — 2026-05-15):** substrate is SQLite + sqlite-vec; vector embeddings tier-1 in v0.1.

- **M032 — foundation:** `go.mod`, `cmd/aih-graph/main.go` scaffold, LICENSE, basic README. (DONE — see m032-foundation tag.)
- **M033 — AST extraction + toolchain validation:** `internal/parser/` with 6 langs (bash, python, JS/TS, Go, Markdown, PowerShell — per ADR-260515-E-amend-01). Per-lang tree-sitter query files. **S1 pre-flight gate (per ADR-260515-C-amend-01):** validate CGO toolchain works with BOTH tree-sitter binding AND `mattn/go-sqlite3` + sqlite-vec extension load. Known blocker: w64devkit gcc 16.1.0 produces `pe-bigobj-x86-64` incompatible with Go cgo (memory: `project_m033_cgo_prereq.md`). S1 must propose alternative (TDM-GCC / MSVC / pure-Go fallback) before AST work begins.
- **M034 — SQLite schema + sqlite-vec storage:** `internal/storage/` with schema migrations (nodes + edges + vec_nodes virtual table per ADR-260515-B-amend-01); `database/sql` wrappers; sqlite-vec extension loader (per-platform .dll/.so/.dylib resolution). Idempotent `aih-graph build` writes/updates nodes + edges.
- **M035 — Query + typed accessors + embedding pipeline:** `internal/query/` (recursive CTE BFS + hybrid SQL+vec_distance) + `internal/types/` (6 typed accessor structs over SQL) + `internal/embed/` (pluggable provider: Voyage AI default + local ONNX fallback; SHA-based change detection) + `pkg/aihgraph/` public API. **Heaviest milestone** (~1 week scope per amendment estimate).
- **M036 — Privacy gates:** `internal/privacy/` (XDG resolution + per-repo .db isolation + consent gate + `--purge` = file delete + NDA opt-out via `--embed-provider local`). Composes naturally with single-file-per-repo design.
- **M037 — CI cross-compile + sqlite-vec extension bundling:** `.github/workflows/aih-graph-ci.yml` — 4-platform matrix; per-platform sqlite-vec extension download from upstream releases at build time; tree-sitter binding linked statically per Pattern A.
- **M038 — v0.1.0 ship:** README, version-tagging, binary release to GitHub Releases (per ADR-260515-D-amend-01 option [2] binary fallback path).
- **M039 — aihaus integration:** `pkg/scripts/install.sh` builds aih-graph; **Go + C-toolchain pre-flight check + interactive 3-way prompt** per ADR-260515-D-amend-01 (now also validates CGO toolchain not just Go presence); `pkg/.aihaus/hooks/aih-graph-refresh.sh` new hook; `.aihaus/.install-mode` sidecar; PowerShell parity (`install.ps1`); ~15 agent prompt addenda with `aih-graph query --semantic` examples.
- **M040 — smoke checks + release v0.35.0:** Smoke Check 84 (build smoke + DB schema + sqlite-vec extension load), 85 (privacy ADR enforcement), 86 (integration round-trip including semantic query). aihaus v0.35.0 tag includes aih-graph v0.1.0.

## Acceptance Criteria for v0.1 (cross-milestone)

Test at M038 closeout:

- [ ] `aih-graph build .` on aihaus-flow root completes in <60s (includes embedding generation for high-value nodes).
- [ ] `aih-graph build .` re-run with no source changes completes in <5s (SHA-based skip on unchanged embeddings).
- [ ] `aih-graph query "ADR-260514-B"` returns `Decision` node within token budget (structural lookup).
- [ ] `aih-graph query --type Milestone "M030"` returns Milestone node + Story edges (filtered structural).
- [ ] `aih-graph query --semantic "how does merge-settings handle hooks arrays"` returns top-K relevant Decision/Milestone/Skill nodes by cosine similarity.
- [ ] `aih-graph query "..."` (default hybrid mode) returns nodes ranked by combined SQL match + vector distance.
- [ ] `aih-graph build` on a new repo without `.aih-graph-consent` exits with code 2 + error message.
- [ ] `aih-graph build /tmp/test --accept-all-repos` works.
- [ ] `aih-graph build --embed-provider local` runs without external API calls (NDA opt-out path).
- [ ] `aih-graph uninstall --purge` removes all data (single .db file delete); verifier confirms path absent.
- [ ] CI cross-compile produces binaries for linux-amd64, darwin-amd64, darwin-arm64, windows-amd64; each bundles matching sqlite-vec extension.
- [ ] `sqlite_version()` and `vec_version()` both return at install-time smoke check.
- [ ] Smoke Check 84 (build smoke), 85 (privacy ADR enforcement), 86 (integration round-trip + semantic query) all PASS.
- [ ] M033/S1 pre-flight verification gate executed; CGO toolchain confirmed compatible with both tree-sitter AND sqlite-vec.

## Estimated v0.1 Timeline

Per ADR-260515-B-amend-01 + E-amend-02 estimates:

| Milestone | Focused effort | Calendar (1-2 sessions/week) |
|-----------|----------------|-------------------------------|
| M033 (AST + CGO toolchain swap) | 1-2 weeks | 2-3 weeks |
| M034 (SQLite + sqlite-vec) | 3-5 days | 1-2 weeks |
| M035 (query + types + embed pipeline) | ~1 week | 2-3 weeks |
| M036 (privacy) | 3-5 days | 1 week |
| M037 (CI cross-compile) | 2-3 days | 1 week |
| M038 (release) | 1-2 days | 1 week |
| M039 (aihaus integration) | 3-5 days | 1-2 weeks |
| M040 (smoke + aihaus release) | 1-2 days | 1 week |
| **Total (focused effort)** | **~7-8 weeks** | **~12-14 weeks calendar** |

**Risk multipliers:** CGO toolchain blocker (currently active), brainstorm-cascade scope shifts, adversarial review iteration (3-4 CRITICAL BLOCKERs per milestone historical baseline). Realistic ship date: **~3 months calendar.**

## References

- ADR-260515-A through -E (5 ADRs in `pkg/.aihaus/decisions.md`)
- BRIEF.md `.aihaus/brainstorm/260514-graphify-mandatory-addon/BRIEF.md` (full 16-turn brainstorm context)
- CHALLENGES.md C2 (2-column comparison surfacing requirement)
- VERIFICATIONS.md (M031/S02 — M032 pre-flight verification gate contract)
- architecture.md (M031/S03+S05 — module layout + integration model)
