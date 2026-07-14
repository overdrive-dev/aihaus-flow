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

Move tasks atomically and let one writer own a transition. Relationships and
queries may be accelerated by a generated index, but the task files remain
authoritative.

Portable commands:

```bash
node .aihaus/tools/task.mjs create --title "Outcome" --room feature --json
node .aihaus/tools/task.mjs question <task-id> --text "Business question" --json
node .aihaus/tools/task.mjs answer <task-id> --question Q-xxxxxx --text "Answer" --draft-rule "Candidate rule" --json
node .aihaus/tools/task.mjs move <task-id> doing --json
node .aihaus/tools/task.mjs list --json
```

Answers create a draft rule inside the task. They never promote themselves to
`memory/project/business-rules.md`; deliberate review and promotion are still
required.
