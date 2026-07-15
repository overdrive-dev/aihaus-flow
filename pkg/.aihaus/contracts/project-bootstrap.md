# Contract: project bootstrap

## Boundary

Project bootstrap is repository-local, provider-neutral, offline, and
two-phase. The deterministic command discovers evidence and writes rebuildable
state. The active coding agent synthesizes reviewed Markdown. Neither phase
depends on Claude slash commands, global aihaus installation, user-level hooks
or settings, Bash, symlinks, a hosted service, or aih-graph.

## Deterministic discovery

Run node .aihaus/tools/init.mjs --repo . --json only from the Git repository
root. The command may write .aihaus/state/bootstrap/discovery.json and nothing
else. Dry-run and status modes are read-only.

Discovery must:

- resolve and verify the Git root through real paths;
- stay inside that root and reject escaping links;
- use local Git and filesystem evidence only;
- exclude secret-bearing paths before reading content;
- retain source path, content hash, tracked/worktree state, and reviewed commit;
- distinguish safe facts from conflicts and memory candidates;
- report whether authoritative evidence is sufficient for semantic synthesis;
- exclude aihaus-managed routers and host skills from project evidence;
- leave .aih-graph-consent, global settings, hooks, and user files untouched.

The packet is disposable. Canonical project memory remains the Markdown under
.aihaus/memory/project/.

If `readyForSynthesis` is false, synthesis is blocked. Preserve the templates
and report `no-authoritative-project-sources`. Generated aihaus adapters,
installation metadata, the repository name alone, and transient host-tool
versions do not make an empty repository ready.

## Evidence authority

Classify synthesis inputs instead of flattening them:

1. user requests and repository instruction files;
2. explicit accepted rules, decisions, architecture, and operational docs;
3. manifests, CI, container, migration, and test configuration;
4. source layout and code behavior as verified facts or inferred candidates.

Code shape, file names, README marketing, and test names are not automatically
accepted business rules. Conflicting sources remain unresolved until an owner
or higher-authority artifact resolves them.

## Memory synthesis

Use the mapping and target statuses in the packet, then follow .aihaus/INIT.md.
Fill untouched templates with source-backed statements. Patch non-template
files minimally and preserve manual edits. Never replace existing memory
wholesale.

Every durable automatic statement must cite a repository-relative source and
the reviewed commit where practical. Mark dirty tracked sources as worktree and
new sources as untracked. Record only explicit accepted rules and decisions;
keep inferred candidates and gaps visibly unaccepted.

Do not copy secret values. Environment and deployment memory may describe
topology, credential locations, approval boundaries, smoke checks, and
rollback expectations without storing credentials or executing operations.

## Idempotency and completion

Unchanged repository inputs produce byte-identical discovery state and no
writes on a second run. Completion requires sufficient authoritative evidence,
a fresh packet, reviewed canonical Markdown, preserved existing content,
explicit conflicts and gaps, and status reporting initialized true,
memoryReadiness ready, and stale false.
