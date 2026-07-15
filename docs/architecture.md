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

## Memory and state

Repository bootstrap follows the authoritative-memory boundary. The Node-only
init tool deterministically discovers safe local evidence and writes the
rebuildable .aihaus/state/bootstrap/discovery.json packet. The provider-neutral
routine in .aihaus/INIT.md guides an active coding agent through a reviewed
synthesis into canonical Markdown under .aihaus/memory/project/. Discovery
never promotes inference to an accepted rule and never replaces semantic
memory with generated state.

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
