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
