# M048 - aihaus-flow 2.0 Native Repository Memory

**Status:** Ready for release validation
**Date:** 2026-05-21
**Milestone:** `M048-aihaus-flow-2-native-repo-memory`

## Project Description

M048 turns aihaus-flow into an integrated system of agents plus native repository memory. The milestone preserves the current aihaus agent/skill/hook workflow, but adds a complete repository brain that indexes real code, project memory, execution history, and agent memory. Agents should no longer operate from flat prompt context alone; they should receive relevant codebase context, impact analysis, historical decisions, gotchas, and milestone links before planning, editing, reviewing, or verifying work.

This is a single milestone for aihaus-flow 2.0. It is allowed to contain many internal stories and gates, but it should ship as one coherent behavioral change: aihaus agents operating over a native, queryable, continuously refreshed memory of the repository.

## Why This Milestone

aihaus-flow currently has strong workflow mechanics: specialist agents, skills, hooks, run manifests, decisions, knowledge files, and completion protocols. What it lacks is a native repository brain. The existing memory surfaces are mostly markdown and aihaus-specific structured artifacts. They help with process continuity, but they do not fully answer codebase questions such as:

- What does this function do?
- Where is it called?
- What files or tests does it impact?
- Which milestone, decision, commit, or gotcha is connected to it?
- What should an implementer or reviewer know before touching it?

The user wants aihaus-flow itself to be the integration point: agents plus complete memory. Ollama is desired as the local semantic layer so embeddings can run privately and efficiently without relying on external providers. Agent memory should remain markdown-based and human-readable, with hooks ensuring it is read, written, and re-indexed.

## User-Visible Outcome

When M048 ships, a human operating Codex or Claude with aihaus-flow can ask repository-aware questions and receive grounded answers from aihaus memory:

- `aihaus memory context <file|symbol|topic>` explains the relevant code, related docs, decisions, gotchas, and current index freshness.
- `aihaus memory callers <function-or-symbol>` lists where a function or symbol is called.
- `aihaus memory impact <file|symbol>` reports likely affected files, tests, agents, hooks, milestones, and risk areas.
- `aihaus memory milestone <file|symbol|commit>` links code to milestones, stories, commits, and decisions when evidence exists.
- `aihaus memory gotchas <topic>` surfaces reusable lessons from project and agent memory.
- aihaus agents automatically consult this memory before doing high-impact work.
- memory refresh happens after relevant events such as commits, task completion, milestone completion, gotcha append, and agent memory updates.

The milestone is complete only when the integrated system is dogfooded on aihaus-flow itself: planner, implementer, reviewer, and verifier must use the native memory layer on the milestone's own code changes.

## Completion Class

Operational integration milestone.

This is not just a library addition. Completion requires end-to-end proof that:

- code is indexed,
- semantic retrieval works locally through Ollama when configured,
- structural queries work without Ollama,
- agents consume the memory layer,
- hooks keep the index fresh or clearly mark it stale,
- markdown memory remains the source of truth for human-curated agent/project knowledge,
- verification can prove the new behavior on the aihaus-flow repository.

## Final Integrated Acceptance

The milestone is accepted when all of these scenarios pass in the real repository:

1. A user runs a build or refresh command and aihaus creates or updates a local repository memory index.
2. The index includes real code entities, not only aihaus markdown artifacts.
3. A user can query a file, function, hook, skill, or topic and receive relevant code, memory, and decision context.
4. A user can ask where a known function or symbol is called and receive call-site evidence where static extraction supports it.
5. A user can ask what changing a file or symbol may impact and receive affected files, tests, runtime hooks, skills, decisions, and gotchas where evidence exists.
6. Ollama embeddings work as a local semantic backend when Ollama is available.
7. BM25 or another deterministic local fallback works when Ollama is unavailable.
8. Agent memory remains markdown-backed and is indexed into the repository brain.
9. At least planner, implementer, code-reviewer, and verifier protocols require memory consultation at the appropriate points.
10. Hooks refresh or mark memory stale after commits, task completion, milestone completion, gotcha append, and agent memory updates.
11. The milestone dogfoods itself: the final review and verification use the new memory commands against the M048 diff.

## Architectural Decisions

### One Milestone, Many Internal Stories

M048 is a single aihaus-flow 2.0 milestone. It should not be split into multiple milestones or release tracks. To keep it executable, it uses internal stories, gates, and explicit verification criteria.

Alternatives considered:
- Split 2.0 into several milestones. Rejected by user preference; the user wants one milestone for the integrated transformation.
- Implement as a small `pkg` patch. Rejected because the change is architectural and crosses agents, hooks, memory, indexing, storage, and verification.

### aihaus-flow Owns the Integration

The memory layer is not a sidecar tool that agents may optionally use. aihaus-flow owns the integration contract between agents and repository memory.

Agents must be shaped to:

- request relevant memory before planning or editing,
- declare target files or symbols when possible,
- run impact checks before risky edits,
- write reusable learnings back to markdown memory,
- trigger or rely on hooks that refresh the derived index.

Alternatives considered:
- Keep memory as an optional CLI only. Rejected because it would not change agent behavior reliably.
- Replace the aihaus agent system with an external code intelligence tool. Rejected because the existing agent workflow remains valuable and should be preserved.

### Markdown Memory Remains Source of Truth

Agent memory, decisions, knowledge, gotchas, reviews, and milestone summaries remain human-readable markdown. The database and vector index are derived caches.

Rationale:
- Markdown is auditable, editable, versionable, and compatible with the current aihaus philosophy.
- Hooks can enforce refresh and consistency without hiding knowledge inside a database.
- Future agents can recover from DB loss by rebuilding from source files.

Alternatives considered:
- Move all memory into SQLite only. Rejected because it would weaken auditability and make manual correction harder.
- Store all memory only in markdown and use grep. Rejected because it cannot answer semantic and impact questions well enough.

### Deterministic Graph First, Semantic Layer Second

The repository brain must combine deterministic structure with semantic retrieval. Embeddings alone are not sufficient.

Deterministic graph data should include files, chunks, symbols, imports, calls, tests, commits, milestones, decisions, gotchas, and agent memory. Ollama embeddings provide semantic recall over this indexed content, but impact analysis must lean on graph edges wherever possible.

Alternatives considered:
- Vector-only RAG. Rejected because it cannot reliably answer call-site and impact questions.
- Full GitNexus clone. Rejected for M048; GitNexus is inspiration, not the implementation target.

### Ollama Is the Local Semantic Backend

M048 should use Ollama with `nomic-embed-text` as the only semantic embedding backend, using BM25 or equivalent local lexical search as fallback.

Rationale:
- The user wants local intelligence without external embedding APIs.
- Ollama's embedding API is simple enough to integrate without exposing provider selection to users or agents.
- Local embeddings preserve privacy and reduce recurring cost.

Alternatives considered:
- Voyage or cloud embeddings as default. Rejected because the user wants local-first.
- Local ONNX as first implementation. Rejected for the first cut unless it proves simpler than Ollama in this repo.

### CLI First, MCP Later Unless Needed for Agent Ergonomics

The first integration surface should be a robust CLI because both humans and agents can call it. MCP can be added once the commands and data model are stable, or sooner only if Claude/Codex ergonomics require it.

Alternatives considered:
- MCP first. Rejected because it risks designing the protocol before the underlying memory commands are proven.
- No MCP ever. Kept open; MCP may become important after the CLI stabilizes.

## Error Handling Strategy

Memory must fail soft for ordinary agent workflows and fail hard only when a command explicitly asks for memory correctness.

Expected behavior:

- If Ollama is unavailable, commands fall back to lexical/structural search and report that semantic vector recall is disabled.
- If the index is stale, context and impact commands include a staleness warning and recommend refresh.
- If parsing a file fails, the indexer records a parser warning and continues with file/chunk-level indexing.
- If a hook refresh fails, the hook should mark the memory stale and emit an audit row rather than blocking unrelated work.
- If a command is used as a required verification gate, stale or missing memory should fail that gate with a clear remediation command.
- If agent memory markdown is malformed, the source file is preserved and the indexer records a recoverable warning.
- `purge` removes derived memory state without deleting markdown source-of-truth files.

## Risks and Unknowns

- Static call graph quality may vary by language and dynamic patterns.
- Tree-sitter or parser dependency choices may affect Windows setup and install friction.
- The fixed `nomic-embed-text` model affects embedding quality, latency, and dimensionality.
- Incremental indexing can become complicated if it tries to be perfect too early.
- Automatic agent memory consultation can become noisy if every agent receives too much context.
- Some "belongs to milestone" answers may be inferential unless commit, manifest, or decision evidence exists.
- The current repository has conflicting archival signals around `pkg`; M048 must clarify what is active and what is historical.

## Open TODOs From Target-Repository Dogfood

### T01 - Bootstrap, Doctor, and Runtime Layout for Client Repositories

- [ ] Make `aih-init` target-repository-aware: scan the full repository first, classify current aihaus/Claude/Codex artifacts, then install or repair only what aihaus-flow needs.
- [ ] Add a user-facing `aihaus doctor` / `aihaus init --repair` path that verifies OS, shell, Git, Ollama reachability, `nomic-embed-text`, package/runtime versions, hooks, settings, and memory index health.
- [ ] Keep `aih-graph` source code out of client repository roots. The package source remains in aihaus-flow; target repositories receive only runtime artifacts.
- [ ] Define the target runtime layout: repo-local binaries under `.aihaus/bin/`, derived graph state under `.aihaus/state/`, runtime metadata under `.aihaus/runtime/`, and conflict archives under `.aihaus/backups/bootstrap-<timestamp>/`.
- [ ] Support a global binary fallback under `~/.aihaus/bin/` while keeping repository-specific databases and stale markers in the target repo's `.aihaus/state/`.
- [ ] Ensure `.claude/hooks`, `.claude/agents`, and `.claude/skills` can link to or mirror `.aihaus/hooks`, `.aihaus/agents`, and `.aihaus/skills` without duplicating ownership or leaving missing hook references.
- [ ] Archive old or conflicting aihaus-flow artifacts instead of deleting them, and produce a clear report of what was ignored, kept, replaced, or backed up.
- [ ] Update memory extraction to understand target repository layouts such as `.aihaus/decisions.md`, `.aihaus/knowledge.md`, `.aihaus/memory/**`, and `.claude/agent-memory/**`, not only package-local `pkg/.aihaus/**` paths.
- [ ] Make initialization refresh repository memory automatically after install and leave the repo usable in lexical fallback mode even when Ollama is missing or the model has not been pulled yet.
- [ ] Dogfood this flow against `domus-nora-app` before release because it has old aihaus artifacts, rich markdown memory, missing hook references, and real package history.

### T02 - Workflow and Agent Spawn Audit

- [ ] Map every `/aih-*` workflow command to the agents it calls or spawns, the required memory it should read, and the memory files or audit events it must write.
- [ ] Decide which workflow steps should inject memory through hooks, which should call `aihaus memory context/query` directly, and which should only mark the memory index stale.
- [ ] Preserve existing aihaus agent behavior while making memory read/write automatic for humans operating Codex or Claude.

## Existing Codebase / Prior Art

- `pkg` contains the existing aihaus agent, skill, hook, template, install, update, and runtime distribution machinery.
- `pkg/.aihaus/agents` contains the specialist agent definitions whose protocols will need memory integration.
- `pkg/.aihaus/skills` contains user-facing aihaus commands and orchestration protocols.
- `pkg/.aihaus/hooks` contains lifecycle hooks, audit hooks, task hooks, context injection, manifest mutation, and refresh seams.
- `aih-graph` is the closest existing memory engine. It already has SQLite storage, typed aihaus nodes, BM25/FTS5 search, a local embedding client, and query modes.
- Existing markdown memory includes decisions, knowledge templates, global gotchas, review memory, and per-agent memory conventions.
- GitNexus is external inspiration for code graph, impact, MCP, and agent-facing repository intelligence, but M048 should build aihaus-native behavior rather than clone GitNexus wholesale.

## Relevant Requirements

R1. aihaus-flow must integrate agents and repository memory as one system.

R2. Memory must answer codebase questions about functions, files, calls, impact, tests, milestones, commits, decisions, gotchas, and agent memory.

R3. The system must index real code, not only aihaus markdown artifacts.

R4. Ollama with `nomic-embed-text` must be supported as the local semantic embedding backend.

R5. Agent memory must remain in markdown files, with hooks ensuring usage and re-indexing.

R6. The memory layer must refresh or mark itself stale after relevant repository and aihaus workflow events.

R7. Existing aihaus agent functionality must be preserved while gaining memory awareness.

R8. The system must remain usable by a human operating Codex or Claude.

## Scope

### In Scope

- A single aihaus-flow 2.0 milestone with internal stories and gates.
- Repository memory engine evolution from the existing graph/memory substrate.
- Code indexing for aihaus-flow's own primary languages and artifact types.
- File, chunk, symbol, import, call, test, commit, milestone, decision, gotcha, and agent-memory indexing.
- Ollama `nomic-embed-text` embeddings.
- Local lexical fallback.
- Query, context, callers, impact, milestone, gotchas, refresh, and status commands.
- Hook integration for refresh and stale marking.
- Agent protocol updates for planner, implementer, code-reviewer, verifier, and related memory-writing roles.
- Dogfood verification on aihaus-flow itself.

### Out of Scope

- Hosted service or cloud database.
- Visual graph UI.
- Full GitNexus feature parity.
- Mandatory multi-repo graph.
- Replacing aihaus agents with a different agent framework.
- Fine-tuning models.
- Making Ollama install or model download mandatory for all users.
- Moving human-authored memory out of markdown.

### Non-Goals

- Perfect static analysis for every language.
- Perfect impact prediction.
- Fully autonomous refactors based only on memory output.
- Blocking every agent action on memory commands.
- Rewriting all existing aihaus workflow protocols in one pass when targeted integration is enough.

## Technical Constraints

- Must run locally by default.
- Must preserve existing aihaus install and operation paths until an explicit migration path exists.
- Must preserve markdown as the source of truth for curated memory.
- Must support Windows developer workflows.
- Must be rebuildable from repository files and markdown memories.
- Must degrade gracefully when Ollama is not running.
- Must provide explicit staleness signals rather than silently serving outdated memory.
- Must keep context payloads bounded so agents do not receive excessive irrelevant memory.
- Must include tests for parser, storage, query, refresh, and agent protocol behavior.

## Integration Points

- aihaus agent definitions: add memory consultation protocols by role.
- aihaus skills: expose or call memory commands during planning, execution, review, verification, and completion.
- aihaus hooks: refresh or stale-mark memory after workflow events.
- git: commits and diffs feed temporal and impact memory.
- markdown memory: decisions, knowledge, gotchas, reviews, milestone summaries, and agent memory feed the index.
- Ollama: local embedding backend through HTTP API.
- SQLite or successor local store: derived memory graph, search index, and embeddings.
- Codex/Claude human workflows: CLI commands must be easy for agents and humans to invoke.

## Internal Stories

### S01 - Founding Architecture Contract

Create the M048 architecture contract for aihaus-flow 2.0 native repository memory. Define the source-of-truth model, derived index model, required commands, agent obligations, hook refresh strategy, and verification gates.

Acceptance:
- A binding architecture document exists.
- It explicitly defines markdown source of truth vs derived index.
- It defines how agents must consume memory.
- It defines how stale memory is detected and reported.

### S02 - Memory Core Schema and Storage

Extend or reshape the existing memory substrate to support generic repository nodes and edges in addition to aihaus-specific nodes.

Acceptance:
- The storage schema can represent files, chunks, symbols, calls, tests, commits, milestones, decisions, gotchas, and agent memory.
- Schema versioning exists.
- Rebuild and purge behavior are documented and tested.

### S03 - Repository Walker and Chunk Indexing

Implement repository walking and chunk-level indexing with ignore rules and size limits.

Acceptance:
- Code files and markdown files are indexed as files and chunks.
- Ignored/vendor/generated paths are skipped unless explicitly included.
- Indexer emits recoverable warnings for unreadable or oversized files.

### S04 - Code Symbol and Relationship Extraction

Extract real code structure for the repository's priority languages and artifact types.

Acceptance:
- Functions, scripts, hooks, skills, and relevant code symbols are extracted where supported.
- Imports or references are captured where supported.
- Basic call relationships are captured where static extraction supports them.
- Unsupported files still receive file/chunk indexing.

### S05 - Ollama Semantic Backend

Add Ollama as the local embedding backend and wire it into build and query flows.

Acceptance:
- User can configure the Ollama URL; model remains fixed to `nomic-embed-text`.
- Build can embed indexed chunks through Ollama.
- Query can embed the user query through the same Ollama backend.
- If Ollama is unavailable, commands report fallback behavior clearly.

### S06 - Hybrid Query and Context Commands

Implement the user-facing memory commands needed by humans and agents.

Acceptance:
- `query` performs hybrid retrieval across lexical, vector, and graph evidence where available.
- `context` returns a bounded explanation of a file, symbol, or topic.
- `callers` returns call-site evidence where available.
- `impact` returns likely affected code, tests, hooks, skills, decisions, and gotchas.
- `milestone` links code to commits, stories, milestones, and decisions where evidence exists.
- `gotchas` surfaces reusable lessons from markdown memory.

### S07 - Temporal and Markdown Memory Indexing

Index execution and curated memory sources.

Acceptance:
- Decisions, knowledge, gotchas, reviews, milestone summaries, and agent memory are indexed.
- Commits and changed files are indexed.
- Milestone and story artifacts are indexed when present.
- Agent memory remains markdown-backed.

### S08 - Hooks, Refresh, and Staleness

Integrate memory refresh or stale marking into aihaus lifecycle events.

Acceptance:
- Relevant hooks call refresh or mark memory stale.
- Status command reports whether memory is fresh, stale, partial, or unavailable.
- Failed refresh is non-destructive and audit-visible.
- Incremental refresh works for common changed-file cases.

### S09 - Agent Protocol Integration

Update agent and skill protocols so memory is part of normal aihaus operation.

Acceptance:
- Planner consults memory before creating plans.
- Implementer consults context and impact before risky edits.
- Code-reviewer uses memory impact on diffs.
- Verifier uses memory to check goal-to-code integration.
- Knowledge and reviewer roles write reusable learnings to markdown memory.
- Protocols specify when memory is required, optional, or advisory.

### S10 - Verification, Dogfood, and Release Readiness

Use M048's memory system to review and verify M048 itself.

Acceptance:
- Tests cover storage, parser, Ollama embedding behavior, query behavior, refresh behavior, and key command output.
- Dogfood evidence shows memory commands used against the M048 diff.
- Final verification demonstrates planner, implementer, reviewer, and verifier integration.
- Documentation explains setup, fallback behavior, and operational usage.

## Gates

### Gate 1 - Architecture Accepted

No implementation starts until the integrated memory architecture is written and accepted.

### Gate 2 - Core CLI Works

The memory CLI can build, refresh, report status, and run basic query/context commands.

### Gate 3 - Real Code Is Indexed

The index contains code files, chunks, symbols, and at least basic structural relationships. Markdown-only indexing does not satisfy this gate.

### Gate 4 - Ollama Works and Fallback Works

Ollama embeddings work when configured. A deterministic fallback works when Ollama is unavailable.

### Gate 5 - Impact Exists

The system can answer impact questions using graph evidence, semantic evidence, and temporal memory where available.

### Gate 6 - Agents Consume Memory

At least planner, implementer, code-reviewer, and verifier use memory commands in their protocols and in dogfood execution.

### Gate 7 - Refresh Is Integrated

Hooks refresh or stale-mark memory after relevant events.

### Gate 8 - Dogfood Verification Passes

The milestone is reviewed and verified using its own repository memory layer.

## Testing Requirements

- Unit tests for parser/extractor behavior by language or artifact type.
- Unit tests for storage schema migration and node/edge upsert behavior.
- Unit tests for Ollama request/response handling using a fake Ollama server.
- Unit tests for query ranking and bounded output behavior.
- Integration tests for build, refresh, status, query, context, callers, impact, milestone, and gotchas commands.
- Hook tests for stale marking and refresh behavior.
- Protocol tests or smoke checks proving agent definitions include the required memory consultation rules.
- Dogfood test against aihaus-flow itself.

## Acceptance Criteria

- A single M048 plan governs the aihaus-flow 2.0 memory transformation.
- Existing agent functionality remains intact.
- Repository code is indexed as first-class memory.
- Ollama local embeddings are supported.
- Markdown agent memory remains the source of truth and is indexed.
- Memory commands answer context, callers, impact, milestone, and gotcha questions.
- Lifecycle hooks keep the index current or mark it stale.
- Core agents consume memory as part of normal operation.
- Final verification uses the new memory layer on the milestone's own changes.

## Current Implementation Progress

Implemented in this branch:

- S03: repository walker and chunk indexing now persist `File` and `Chunk` nodes, with skip rules for generated/vendor/runtime directories and binary/oversized files.
- S04: code symbol extraction now persists `Symbol` and `Call` nodes for Go functions/methods plus shell and PowerShell functions; Go call sites include file/line evidence and resolved symbol edges where static resolution is unique.
- S05: local semantic embeddings are wired through Ollama's `/api/embed` endpoint with fixed `nomic-embed-text`; `AIH_GRAPH_OLLAMA_URL` and `OLLAMA_HOST` may point at a non-default endpoint.
- S06: `query`, `context`, `callers`, `impact`, `gotchas`, and `milestone` commands expose repository-brain queries over exact graph nodes and BM25 fallback; `query`, `context`, `callers`, `impact`, `gotchas`, `milestone`, `status`, and `refresh` also expose stable `--json` payloads for agent consumption.
- S07: markdown memory sections now persist as `Memory` nodes, tests persist as `Test` nodes, and the latest 200 git commits persist as `Commit` nodes with `touches` edges to indexed files.
- S08/S09 first slice: `status` and `mark-stale` commands plus hooks mark memory stale after writes/git history changes and refresh after startup, task completion, and session end; both settings templates carry the memory lifecycle hooks, and all packaged agents now require JSON-backed memory consultation when available.
- S09 automation hardening: `context-inject.sh` auto-loads a bounded native repository memory packet into every subagent start, so ordinary users do not have to call memory commands manually; agents use targeted `aihaus memory ... --json` commands only when they need deeper context.
- S05 automation hardening: `aih-graph-refresh.sh` opportunistically starts local Ollama when installed; `aih-graph` always refreshes BM25 and enriches with `nomic-embed-text` embeddings when Ollama is available.
- CLI ergonomics: `aihaus memory <subcommand>` delegates to the current source `aih-graph` engine, including `refresh`, with Windows `.cmd` preferring Git Bash over the WSL stub.

Dogfood evidence from aihaus-flow:

- `aih-graph build --db C:\tmp\aih-graph-m048-memory-tests.db --accept-all-repos ..` indexed 328 files, 495 chunks, 395 symbols, 1413 calls, 15 tests, 41 memory sections, and 200 commits.
- `aih-graph callers ParseRepositoryText` returned call-site evidence from `aih-graph/cmd/aih-graph/main.go` and `aih-graph/internal/extract/repository_test.go`.
- `aih-graph context aih-graph/internal/extract/repository.go:ParseRepositoryText --depth 1` returned exact symbol context plus called helper symbols and call sites.
- `aih-graph impact aih-graph/internal/extract/repository.go:ParseRepositoryText --type Symbol --depth 1` surfaced `TestParseRepositoryTextIndexesTextFilesAndChunks` as a related test.
- `aih-graph gotchas git checkout` returned gotcha memory from `pkg/.aihaus/memory/global/gotchas.md`.
- `aih-graph milestone Ollama` returned M048 docs, Ollama code chunks, the M048 commit, and ADR-260521-A.
- `aih-graph status --json` returned a machine-readable fresh index state with node counts, BM25/embedding row counts, and embedding model counts.
- `aih-graph query --json Ollama` defaults to hybrid BM25 and returned a structured query payload with match nodes and neighbor context; `--semantic --json` also returned structured BM25-backed query results.
- Real local Ollama validation with `nomic-embed-text` embedded 3400 nodes with 0 errors after capping embedding input text, and `query --semantic --json "Ollama embedding backend"` returned `semantic_vector` results.
- `aih-graph context --json --type Symbol --depth 1 aih-graph/internal/extract/repository.go:ParseRepositoryText` returned exact symbol context as JSON, including related helper symbols, call nodes, and test evidence.
- `aih-graph impact --json --type File --depth 1 --limit 80 aih-graph/cmd/aih-graph/main.go` returned bounded JSON impact context with `freshness`, `neighborhood_total`, `neighborhood_returned`, `neighborhood_truncated`, and truncated long string properties.
- `aih-graph callers --json ParseRepositoryText` returned call-site evidence as structured JSON.
- `aih-graph gotchas --json git checkout` and `aih-graph milestone --json Ollama` returned BM25 match payloads with node summaries and neighbor context.
- `aih-graph refresh --json --repo .. --db C:\tmp\aih-graph-m048-refresh-json.db --accept-all-repos` returned a machine-readable refresh payload with nested `status`, node counts, BM25 rows, and embedding model counts.
- `aih-graph query --json "refresh json output"` returned commit `3eb7b1b` plus the changed code, test, and M048 doc files; `context --json --type Symbol aih-graph/cmd/aih-graph/main.go:runRefresh` showed `collectStatusJSON`, `runBuild`, `runWithStdoutDiscard`, and `writeJSON` as first-hop context; `impact --json --type File aih-graph/cmd/aih-graph/main.go` surfaced the recent memory commits touching the CLI.
- `aihaus memory version` and `aihaus memory status --repo . --db ...` work through the PowerShell wrapper.
- `aihaus memory refresh --repo . --db C:\tmp\aih-graph-m048-memory-alias-refresh.db --accept-all-repos` works through the Windows `.cmd` wrapper and preserves the caller repository path.
- `aihaus memory refresh --repo . --db C:\tmp\aih-graph-m048-wrapper-refresh-json.db --accept-all-repos --json` works through the PowerShell wrapper and returns the same structured refresh payload.
- `aih-graph-refresh.sh` now delegates to `aih-graph refresh --repo ...`, opportunistically starts local Ollama, and reports the real non-zero refresh exit code on failure; hook validation produced a fresh BM25 index through the refresh hook.
- `aih-graph-stale.sh --from-hook bash` ignores `aihaus memory refresh ... --json` and does not recreate `.aihaus/state/aih-graph.stale` after a refresh command.
- `tools/smoke-test.sh` now includes an M048 contract check for memory lifecycle hooks in both settings templates, automatic memory injection in `context-inject.sh`, Ollama auto-start selection in `aih-graph-refresh.sh`, and integrated `aihaus memory ... --json` commands in all packaged agents; targeted `rg`, JSON parsing, and `bash -n` validations passed under Git Bash.
- The all-agent memory contract now asserts that packaged agents use `aihaus memory` as the integration surface and do not bypass it with direct role-level `aih-graph` calls.
- A targeted `rg` for direct role-level `aih-graph` memory commands, legacy M039 query-mode examples, and the old M039 memory-lookup heading returns no matches after the all-agent prompt migration.
- `CLAUDE.md`, `INSTALL-VIA-LLM.md`, `aih-graph/README.md`, `aih-graph/PRD.md`, and `impact` fallback guidance now point agents and humans at `query --json` rather than the legacy M039 prompt examples.
- Windows Git Bash smoke portability now uses workspace-local `tmp/` scratch directories, manifest-local temp files, and per-check `GOTMPDIR`/`GOCACHE`, avoiding sandbox-blocked `/tmp`, `C:\tmp`, and `%LOCALAPPDATA%\Temp` paths.
- `go test ./...` passes inside `aih-graph`.
- Full `tools/smoke-test.sh` under Windows Git Bash passes: `aihaus package smoke test PASSED [OK] (87/87)`.
- Target-repo runtime layout slice:
  - `aihaus memory` wrappers and hooks now default to repo-local `.aihaus/state/aih-graph.db`.
  - install/update seed `.aihaus/bin`, `.aihaus/state`, `.aihaus/runtime`, `.aihaus/backups`, `.aihaus/workflows`, and `.aihaus/memory/workflows`.
  - `aih-graph` extraction now understands installed target layouts such as `.aihaus/agents`, `.aihaus/skills`, `.aihaus/hooks`, `.aihaus/knowledge.md`, `.aihaus/decisions.md`, `.aihaus/memory/**`, and `.claude/agent-memory/**`.
  - The target repo does not need a root `aih-graph/` source directory; source remains in the aihaus-flow package repo.
- Workflow-agent slice:
  - Added repo-local workflow profile defaults under `.aihaus/workflows/`.
  - Added workflow memory seed under `.aihaus/memory/workflows/`.
  - Added initial workflow agents for backlog intake, planning gate, CI/CD, and dev review.
  - Agent/cohort contracts now account for 52 packaged agents.

## Resolved M048 Implementation Decisions

- Keep `aih-graph` as the engine name and expose `aihaus memory <subcommand>` as the human/agent alias.
- Use Go-native extraction for the first implementation; defer Tree-sitter until a language need justifies the install and maintenance cost.
- Support aihaus-flow's current practical language set first: Markdown, Go, Bash, and PowerShell, with file/chunk fallback for everything else.
- Defer MCP for M048; the CLI JSON contract is sufficient for Codex and Claude operation and easier to dogfood.
- Require JSON memory consultation for all packaged agents when the integrated `aihaus memory` command is available, while keeping absence of that command non-blocking.
- Treat milestone ownership as evidence-derived: prefer explicit milestone docs, decisions, commits, and touched files; report uncertainty instead of inventing ownership when those signals are missing.
