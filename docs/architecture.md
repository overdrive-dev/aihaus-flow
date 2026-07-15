# aihaus architecture

## Product boundary

aihaus is a downloadable GitHub package for repository-local agent guidance,
durable project memory, deterministic checks, and a rebuildable code/concept
index. It is not a website or hosted control plane.

The repository has two boundaries:

- `pkg/`: the installable payload;
- repository tooling: tests, local lab, docs, release workflows, and source for
  the `aih-graph` binary.

## Portable core

The portable core is instructions and data: a thin Map, task rooms, six general
roles, contracts, project-memory Markdown, and file-based tasks. It does not
promise that every host can enforce every contract.

Deterministic local tools validate evidence, path ownership, and recognized
online actions. A host adapter may call these tools from lifecycle hooks. When
a host cannot enforce them, the package must report that the gate is advisory.
Prompts and hooks are never a security sandbox.

## Information loading

`MAP.md` selects one room and the minimum contracts for a task. Roles describe
responsibility; rooms describe work. Specialist heuristics such as security,
migration, integration, complexity, and goal-backward verification are loaded
as review lenses instead of permanent agent identities.

## Host adapters

The portable initialization semantics live in `.aihaus/tools/init.mjs`,
`.aihaus/INIT.md`, and the project-bootstrap contract. Setup may add thin
repository-local discovery wrappers at `.claude/skills/aih-init/SKILL.md` and
`.agents/skills/aih-init/SKILL.md`. Claude Code exposes its wrapper as
`/aih-init`; Codex exposes its repository skill as `$aih-init` or through
`/skills`. The package does not emulate unsupported command syntax.

Host skills contain an aihaus ownership marker. Setup refreshes only marked
files; a pre-existing unmarked file at either path is user-owned, preserved,
and reported as a conflict. No adapter changes user settings, installs a global
hook, enables network access, or owns the canonical project memory.

## Memory and state

Repository bootstrap follows the authoritative-memory boundary. The Node-only
init tool deterministically discovers safe local evidence and writes the
rebuildable .aihaus/state/bootstrap/discovery.json packet. The provider-neutral
routine in .aihaus/INIT.md guides an active coding agent through a reviewed
synthesis into canonical Markdown under .aihaus/memory/project/. Discovery
never promotes inference to an accepted rule and never replaces semantic
memory with generated state.

Discovery also evaluates evidence sufficiency. Generated aihaus routers and
skills are excluded as project sources. When no authoritative project evidence
exists, `readyForSynthesis` is false, canonical templates remain unchanged, and
status cannot report the repository as initialized.

Project Markdown and task files are authoritative. `.aihaus/state/` contains
rebuildable indexes and caches. Deleting generated state may reduce speed but
must not erase rules, decisions, knowledge, or task history.

`aih-graph` is the only semantic/relationship engine. Lexical/BM25 and graph
retrieval must work without embeddings. Results disclose their retrieval mode
and cite repository locations.

## Evolution rule

Start with feature, bugfix, and research rooms. Add roles, rooms, adapters, or
state only after a reproducible local-lab scenario demonstrates a gap. The
portable core is the canonical fresh-install surface; host integrations remain
optional adapters around its deterministic tools.
