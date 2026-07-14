# aihaus

aihaus is a downloadable, repository-local package for coding agents. It gives
a project a small routing map, task rooms, six reusable roles, durable Markdown
memory, deterministic evidence/safety checks, and an optional local code index.
It turns business intent into explicit acceptance and evidence contracts, then
routes the work through verifiable software-engineering rooms.

There is no aihaus website, hosted control plane, account, or cloud memory.
Clone the GitHub repository, install the package into a Git repository, and
delete the temporary clone.

## Install

Requires Git and Node.js 22 or newer. From the root of the repository that will
use aihaus:

```bash
git clone --depth 1 https://github.com/overdrive-dev/aihaus-flow .aihaus-download
node .aihaus-download/pkg/setup.mjs --target . --json
rm -rf .aihaus-download
```

PowerShell cleanup:

```powershell
Remove-Item -LiteralPath .aihaus-download -Recurse -Force
```

The setup command is also the update command. It replaces package-owned
instructions and tools, seeds missing memory files, and preserves existing
project memory and text outside bounded aihaus blocks in `AGENTS.md`,
`CLAUDE.md`, and `.gitignore`.

For an agent-operated installation, see [INSTALL-VIA-LLM.md](INSTALL-VIA-LLM.md).

## How it works

The portable core follows a Map -> rooms -> tools shape:

- `.aihaus/MAP.md` routes a request without loading the whole package;
- `rooms/` contains feature, bugfix, and research work contexts;
- `roles/` contains orchestrator, planner, implementer, researcher, reviewer,
  and verifier responsibilities;
- `contracts/` defines the harness, executable evidence, adversarial review,
  and operational safety;
- `memory/project/` holds durable rules, decisions, knowledge, procedures, and
  environment facts as versioned Markdown;
- `memory/kanban/` stores each task as one Markdown file whose folder is its
  status;
- `tools/` contains deterministic local checks and the optional graph wrapper.

Root instruction files remain thin routers. A task loads one room, one primary
role, and only the project memory needed for its next decision.

## Local code and semantic index

`aih-graph/` is the optional Go engine for repository relationships and search.
It stores generated state locally, supports BM25/FTS5 without embeddings, and
can add local Ollama embeddings when available. Generated index results never
override source files or Markdown memory.

Install a released binary while the temporary clone still exists:

```bash
bash .aihaus-download/pkg/scripts/install-aih-graph-binary.sh --bin .aihaus/bin/aih-graph
```

On Windows:

```powershell
& .aihaus-download/pkg/scripts/install-aih-graph-binary.ps1 -Bin .aihaus/bin/aih-graph.exe
```

Consent to indexing is explicit. Create `.aih-graph-consent` in the repository
or use the engine's one-run consent flag, then use the repository-local wrapper:

```bash
node .aihaus/tools/graph.mjs refresh --json
node .aihaus/tools/graph.mjs query --json "authentication boundary"
node .aihaus/tools/graph.mjs impact --json path/to/file
```

See [aih-graph/PRD.md](aih-graph/PRD.md) for supported extraction and retrieval
semantics. JavaScript/TypeScript extraction is lexical; Python AST extraction
and approximate-nearest-neighbor indexes are not claimed.

## Evidence and operations

Executable completion criteria require tool- or CI-produced command evidence
with exit code 0. Validate an evidence document with:

```bash
node .aihaus/tools/evidence-validate.mjs path/to/evidence.json
```

The operational gate recognizes common release, deploy, push, and production
mutation commands, but it only acts when a host adapter invokes it. Prompts,
hooks, and local scripts are not a security or privilege boundary. Use external
environment isolation and least-privilege credentials.

## Local development lab

The repository can maintain an ignored, nested consumer repository for real
install/update experiments. It is never committed or published:

```bash
node tools/aihaus-lab.mjs init --force --json
node tools/aihaus-lab.mjs verify --json
node tools/aihaus-lab.mjs reset --json
```

The controller verifies realpath containment and nested Git identity before any
destructive reset or clean operation.

## Contributor checks

```bash
node tools/run-contract-tests.mjs
```

Go contributors should also run:

```bash
go test ./...
```

CI runs the contract suite on Linux, macOS, and Windows, plus the `aih-graph`
test and release matrix using the Go version declared in `aih-graph/go.mod`.

Architecture details live in [docs/architecture.md](docs/architecture.md); the
refactor/deletion ledger is [docs/provenance.md](docs/provenance.md).

## License

MIT. See [LICENSE](LICENSE).
