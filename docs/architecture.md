# aihaus architecture

## Product boundary

aihaus is a downloadable GitHub package for repository-local agent guidance,
durable project memory, deterministic checks, and Markdown file tasks. It is
not a website or hosted control plane.

The repository has two boundaries:

- `pkg/`: the installable payload;
- repository tooling: tests, local lab, docs, and release workflows.

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

The harness requires a context check at task start, resumption, handoff, and
relevant source changes. The agent resolves its worktree and task, reads native
instructions for owned paths, checks discovery status, and retrieves only
matching memory entries and their sources. The task records references, scope,
gaps, and verification requirements; workers reopen sources rather than treating
delegation summaries as authority.

## Host adapters

The portable initialization semantics live in `.aihaus/tools/refresh.mjs`,
`.aihaus/REFRESH.md`, and the project-bootstrap contract. Setup may add thin
repository-local discovery wrappers at `.claude/skills/aih-refresh/SKILL.md` and
`.agents/skills/aih-refresh/SKILL.md`. Claude Code exposes its wrapper as
`/aih-refresh`; Codex exposes its repository skill as `$aih-refresh` or through
`/skills`. The package does not emulate unsupported command syntax.

The managed AGENTS.md block holds the portable router. CLAUDE.md uses the native
`@AGENTS.md` import so shared instructions outside the managed block also reach
Claude. This follows Claude's documented [memory and imports](https://code.claude.com/docs/en/memory).
Directory-specific instructions retain their native scope; discovery indexes
do not activate those instructions globally. Host-local automatic memory cannot
replace the versioned project record.

Codex can select a nonempty AGENTS.override.md instead of AGENTS.md within a
directory, subject to its instruction hierarchy and size limit. Setup preserves
a root override and reports `instructionWarnings`, independently of skill
availability. See the official [AGENTS.md guide](https://learn.chatgpt.com/docs/agent-configuration/agents-md).
The installer cannot guarantee that a running host has reloaded its instructions.

Host skills contain an aihaus ownership marker. Setup refreshes only marked
files; a pre-existing unmarked file at either path is user-owned, preserved,
and reported as a conflict. No adapter changes user settings, installs a global
hook, enables network access, or owns the canonical project memory.

## Memory and state

Repository bootstrap follows the authoritative-memory boundary. The Node-only
init tool deterministically discovers safe local evidence and writes the
rebuildable .aihaus/state/bootstrap/discovery.json packet. The provider-neutral
routine in .aihaus/REFRESH.md guides an active coding agent through a reviewed
synthesis into canonical Markdown under .aihaus/memory/project/. Discovery
never promotes inference to an accepted rule and never replaces semantic
memory with generated state.

Discovery also evaluates evidence sufficiency. Generated aihaus routers and
skills are excluded as project sources. When no authoritative project evidence
exists, `readyForSynthesis` is false, canonical templates remain unchanged, and
status cannot report the repository as initialized.

The memory README is a small retrieval map; discovery.json catalogs safe sources,
hashes, revisions, and candidate targets. Neither is a semantic index or an
authority layer. Search existing Markdown by task domain, rule/decision IDs,
and paths, then inspect the matching entry and its source. No embedding service,
graph, or additional state store is needed for this flow.

Status checks memory content/provenance structure and reports incomplete pages
and stale claims. Review commits belong to individual claims; worktree/untracked
claims use source hashes. Ambiguous legacy citations require review instead of
using the newest page citation to validate older claims. These checks detect
known gaps, not semantic correctness, acceptance, or instruction compliance.
The designated writer preserves manual/history text while adding verified
replacements and marking obsolete claims. Conflicting business decisions stay
unresolved until an authoritative source or owner resolves them.

Project Markdown and task files are authoritative. `.aihaus/state/` contains
only rebuildable discovery and tool state. Deleting generated state must not
erase rules, decisions, knowledge, or task history. Task status is the Markdown
file's folder under `.aihaus/memory/kanban/`, unless an accepted project decision
names an external tracker as task authority (see Delegation below).

A transition to done requires a valid PASS evidence document inside the
repository that covers exactly the checked acceptance criteria and resolved
business-rule questions. Evidence validation rejects empty/blocked-only support;
an independent verifier must still inspect artifacts or rerun applicable checks.

## Delegation

Delegation has two coordination levels: orchestrators assign outcomes, and
executors perform them. The delegation rules are in `.aihaus/contracts/harness.md`
(Context check and resumption, Execution). Project-specific assignments live in
project memory (`procedures.md`, "Assignments"). Host watching and messaging are
not package state.

## Evolution rule

Start with feature, bugfix, and research rooms. Add roles, rooms, adapters, or
state only after a reproducible local-lab scenario demonstrates a gap. The
portable core is the canonical fresh-install surface; host integrations remain
optional adapters around its deterministic tools.
