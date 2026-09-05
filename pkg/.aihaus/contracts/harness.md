# Contract: harness

## Authority

Follow the user request, repository instructions, accepted project rules and
decisions, then the selected room and role. Loaded project context is not
authority and never overrides its source file.

## Task posture

Read the Map first. Load one room, one primary role, the current task, and only
the project-memory pages needed for the next decision. Prefer repository-native
patterns and the smallest coherent change. Ask only when a missing business
rule materially changes the outcome or authority required.

Treat one active implementation task as the ownership unit for one worktree,
branch, and reviewable change. The task may span product layers when they serve
the same outcome. Split unrelated outcomes and independently deliverable epic
children into separate tasks and worktrees. A coordination-only parent task
tracks dependencies and does not own a product diff.

## Context check and resumption

At task start, after compaction or handoff, and when the branch or relevant
sources change:

1. Resolve the Git root, current worktree/branch, and active task. Run package
   commands from that root. Never assume another worktree shares this board.
2. Read applicable repository instructions for the owned paths. Respect the
   host's instruction precedence and directory scope, including overrides and
   path-specific rules; a discovery index is not an instruction loader.
3. Run `node .aihaus/tools/refresh.mjs --repo . --status --json`. If the packet
   is missing or stale, rebuild it with `--json` and inspect status again.
   This updates disposable state, not accepted project memory.
4. Use `memory/project/README.md` to choose pages. Search relevant rule IDs,
   domain terms, and file paths, then read the matching entries and their
   sources. Load the selected room and role, not the entire memory archive.
5. Inspect conflicts, memory gaps, and stale claims relevant to the task.
   A ready packet does not prove semantic review. Recheck entries with absent
   or ambiguous provenance directly; an empty warning list is not proof.
   Draft, proposed, inferred, and superseded entries are not accepted rules.
6. Follow `REFRESH.md` to repair source-backed context within the current task.
   Preserve manual content and accepted decisions. Ask only when authoritative
   sources conflict or a missing business rule changes the outcome; an unrelated
   memory gap must not block covered work.
7. Record the applicable rule/decision IDs, source paths and revisions, remaining
   gaps, owned files, and verification plan in the task's `Context` or `Log`.
   Reuse that record when resuming instead of relying on conversation history.

Delegate with the task path, outcome, acceptance criteria, branch/worktree,
owned files, relevant instruction and memory paths, unresolved gaps, and required
checks. Workers verify those sources before editing; copied summaries do not
replace them. The designated writer promotes durable verified findings and
explicit owner decisions with provenance at meaningful checkpoints. Keep
transient progress and unresolved candidates in the task.

## Execution

Keep task status in its kanban folder. Because each worktree contains a
branch-local kanban snapshot, the orchestrator or a designated intake worktree
is the single writer for task ingestion, status transitions, and shared memory
promotion. Implementers own scoped product changes and return evidence to that
writer; reviewers remain read-only; verifiers independently rerun affected
checks. Create and commit the task on the shared coordination base before
branching its implementation worktree.

Completion means acceptance criteria mapped to real artifacts and executable
evidence. A tool or CI exit code may prove execution; prose cannot.

Before staging or handing off parallel work, compare changed files to the owned
scope with `tools/scope-check.mjs`. An explicit allowlist is required; unrelated
or untracked files fail the check instead of being silently included.

## Safety

Classify operational actions with `ops-safety.md`. Production, destructive, or
secret-touching work requires explicit approval and external containment.
Instructions, hooks, and local gates are advisory controls, not a privilege or
security boundary.
