# aih-graph

`aih-graph` is aihaus's optional, local code and concept retrieval engine. It
builds a disposable SQLite graph from a consented repository. Project source
and `.aihaus/memory/` Markdown remain authoritative.

## Retrieval

- Structural relationships use graph traversal.
- Lexical search uses SQLite FTS5/BM25 and works without embeddings.
- Semantic search can use configurable local Ollama embeddings.
- Hybrid search expands lexical or vector seeds through graph relationships.

There is no hosted store, telemetry service, mandatory model API, ANN index, or
cloud account.

## Indexed concepts

The portable aihaus surface is indexed as Map, Convention, Role, Room,
Contract, and Tool nodes. Durable pages become Decision, Rule, and Memory
nodes. Repository extraction adds File, Chunk, Symbol, Call, Test, and Commit
nodes where supported.

Current parser fidelity:

| Input | Text | Symbols | Calls |
|---|---:|---:|---:|
| Go | yes | Go AST | Go AST |
| Bash | yes | function regex | no |
| PowerShell | yes | function regex | no |
| Markdown/config/JS/TS | yes | no | no |
| Python | no | no | no |

Text indexing is not AST extraction. See [PRD.md](PRD.md) for the complete
capability and release contract.

## Refresh and embeddings

Repository text discovery uses
`git ls-files --cached --others --exclude-standard`, including nested
`.gitignore` rules and negations. A separate safety boundary always excludes
Git internals, aihaus runtime state, database files, and graph artifacts.

Refresh upserts current nodes, removes only nodes that disappeared, and reuses
an embedding when both its content SHA and model match. Ollama requests use
native batches of up to 64 texts and retry transient failures. The default
model is `nomic-embed-text`; set `AIH_GRAPH_OLLAMA_MODEL=bge-m3` (or another
installed Ollama embedding model) to change it.

## Install and use

Released binaries are installed separately from the portable instruction core.
The repository README shows the Bash and PowerShell installer commands.

Indexing requires explicit repository consent. Create `.aih-graph-consent` at
the repository root or pass `--accept-all-repos` for one build. The aihaus
wrapper pins repository-local state:

```bash
node .aihaus/tools/graph.mjs refresh --json
node .aihaus/tools/graph.mjs status --json
node .aihaus/tools/graph.mjs query --json "decision boundary"
node .aihaus/tools/graph.mjs context --json path/to/file
node .aihaus/tools/graph.mjs callers --json SymbolName
node .aihaus/tools/graph.mjs impact --json path/to/file
node .aihaus/tools/graph.mjs rule --json BR-001
node .aihaus/tools/graph.mjs why --json path/to/file
```

Generated state lives at `.aihaus/state/aih-graph.db` when invoked through the
wrapper. Raw binary calls use the privacy package's per-repository OS state
location unless `--db` is supplied.

## Development

The module requires the Go version declared in `go.mod` and has no CGO
dependency.

```bash
go mod verify
go vet ./...
go test ./...
go build ./cmd/aih-graph
```

CI also cross-compiles Linux amd64, macOS amd64/arm64, and Windows amd64.

## Privacy and deletion

Repository and user-scope indexes use separate consent and storage. `uninstall`
purges generated databases and sidecars within the configured state root; it
must not remove source, Markdown memory, or unrelated files.

## License

MIT. See the repository `LICENSE`.
