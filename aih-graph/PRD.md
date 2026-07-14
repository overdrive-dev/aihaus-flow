# aih-graph product contract

**Status:** current capability contract. Git history preserves the superseded
v0.1 planning document.

## Purpose

`aih-graph` is aihaus's single local code/concept retrieval engine. It builds
a disposable per-repository SQLite graph and returns structural, lexical, and
optional local-embedding context with bounded output and repository citations.
It is acceleration, never durable project memory.

## Required behavior

- Build only after repository consent.
- Store repository indexes outside the repository by default.
- Keep per-repository and user-scope data isolated.
- Refresh lexical/FTS rows even when embeddings are unavailable.
- Report the active retrieval mode in machine-readable output.
- Cite paths and line spans for code/text results.
- Expose deterministic freshness and stale-state information.
- Purge one repository or all generated data without touching source memory.
- Cross-compile without CGO for Linux amd64, macOS amd64/arm64, and Windows amd64.

## Current language fidelity

| Input | Text/lexical | Symbols | Calls |
|---|---:|---:|---:|
| Go | yes | Go AST | Go AST |
| Bash | yes | regex function definitions | no |
| PowerShell | yes | regex function definitions | no |
| Markdown/config/text | yes | typed Markdown extractors where defined | no |
| JavaScript/TypeScript | yes | no | no |
| Python | no | no | no |

Do not describe text indexing as AST extraction. Broad JS/TS/Python symbols and
cross-language call graphs remain deferred until an implementation and tests
exist. The pure-Go/no-CGO release constraint takes precedence over parser
marketing claims.

## Retrieval

- Structural: graph/BFS relationships.
- Lexical: SQLite FTS5/BM25, always available.
- Semantic: optional local Ollama embeddings with pure-Go brute-force cosine.
- Hybrid: vector or BM25 seed results expanded through graph relationships.

Brute-force vector scan is acceptable at the current target scale. Do not claim
ANN or an indexed vector search until one ships.

## First-class concepts

Code/text nodes include files, chunks, symbols, calls, and tests where the
extractor supports them. Portable aihaus concepts include the Map, conventions,
roles, rooms, contracts, tools, rules, decisions, task memory, and user
preferences where implemented.

Markdown remains authoritative for rules, decisions, and knowledge. A query
result must lead back to its source rather than becoming a second truth.

## Stable command surface

`build`, `status`, `query`, `context`, `callers`, `impact`, `gotchas`,
`rule`, `rule-drift`, `why`, `mark-stale`, and `uninstall`.

Command additions require a consumer and a contract test. JSON fields should be
additive and versioned when compatibility could break.

## Deferred

- Broad parser coverage for JS/TS/Python.
- ANN/vector database dependencies.
- Mandatory embeddings or network APIs.
- Hosted storage, cross-customer graphs, or telemetry.
- HTML visualization and a mandatory MCP server.

## Release gate

`go mod verify`, `go vet ./...`, `go test ./...`, native build, and the
four-platform zero-CGO build matrix must pass using the Go version declared by
`go.mod`. Freshness, deletion/rebuild, lexical-only, and JSON-mode tests are
release requirements.
