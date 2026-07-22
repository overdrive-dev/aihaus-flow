# File kanban

A task is one Markdown file under exactly one status folder:
`backlog`, `todo`, `doing`, `review`, or `done`. Folder location is the sole
status source; do not duplicate it in frontmatter.

Filename: `T-yyMMdd-rand6-short-title.md`.

Minimum body:

```text
# Goal
## Acceptance
## Context
## Owned files
## Log
## Evidence
```

Move tasks atomically and let one writer own a transition. The task files and
their status folders are authoritative.

## Worktree ownership

One active implementation task maps to one worktree, branch, and reviewable
change. Keep product layers together when they deliver the same outcome. Give
unrelated outcomes and independently deliverable epic children separate tasks
and worktrees. A coordination-only parent may track dependencies, but it does
not own product files.

The board in a worktree is the snapshot carried by that branch, not a globally
synchronized queue. A designated orchestrator or intake worktree owns task
creation, status moves, and shared-memory promotion. Implementers return logs
and executable evidence to that writer instead of independently moving shared
task state.

## Ingestion

1. Reconcile the incoming item against its external identifier, current code,
   existing task files, and the external tracker when one exists.
2. Create the task once on the shared coordination base. Supply
   `--external-id` for an external ticket; duplicate identifiers are rejected
   case-insensitively across every status folder.
3. Fill acceptance criteria and owned files, then commit the task before
   creating its implementation worktree.
4. Move it to `doing` through the designated writer when execution starts.
   Record the branch/worktree in `Context` or `Log`.
5. Reconcile implementation evidence and integration before moving the task
   through `review` and `done`. Promote durable memory separately.

Forward transitions are rejected when required task sections still contain the
new-task placeholder or are empty. Existing tasks are not rewritten.

Portable commands:

```bash
node .aihaus/tools/task.mjs create --title "Outcome" --room feature --external-id EXT-123 --json
node .aihaus/tools/task.mjs question <task-id> --text "Business question" --json
node .aihaus/tools/task.mjs answer <task-id> --question Q-xxxxxx --text "Answer" --draft-rule "Candidate rule" --json
node .aihaus/tools/task.mjs move <task-id> doing --json
node .aihaus/tools/task.mjs list --json
```

Answers create a draft rule inside the task. They never promote themselves to
`memory/project/business-rules.md`; deliberate review and promotion are still
required.
