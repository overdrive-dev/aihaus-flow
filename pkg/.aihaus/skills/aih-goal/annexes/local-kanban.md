# aih-goal local kanban contract

The local kanban is the minimum durable task ledger needed for `/aih-goal` to
work with or without Linear, Notion, Jira, Trello, or GitHub Issues.

It is intentionally small. It is not a full clone of an external product.

### Task registration

Every task discovered, imported, created, or moved into `planejamento` must have:

- one row in `tasks`,
- one readable file in the goal run `tasks/<task-id>.md`,
- a current stage,
- a planning status,
- source identity when available.

Do not run the planning gate on an ad hoc task that is not registered locally.
When an external kanban exists, register a local mirror row before acting. When
no external kanban exists, the local row is the kanban task.

### Planning questions

Every missing business rule, acceptance criterion, validation expectation, or
scope decision must be recorded as a `planning_questions` row before the agent
asks or syncs it.

Although the table is named `planning_questions`, each row is a durable
business-rule gap for one task, not a conversational TUI prompt. The `question`
text must be written so it can live in Linear, local kanban, memory, and run
artifacts without sounding like an option menu.

Required format:

- name the affected task or source id,
- state the missing business rule, acceptance criterion, validation expectation,
  or scope decision,
- avoid implementation choices unless they change user-visible behavior,
- avoid "Should I/we..." phrasing and multi-option TUI language,
- keep one missing rule per row.

Examples:

- Bad: `Should I update the kanban now or at the end?`
- Good: `Business rule gap for NORACAR-123: define which stage change must be visible in Linear after review-dev passes, including the required evidence comment.`
- Bad: `For tasks A, B, and C, what should happen with billing filters and exports?`
- Good: `Business rule gap for NORACAR-124: define whether archived billing records appear in the doctor financial filter results.`

When a batch planning sweep finds the same missing rule in several tasks,
create one row per task. Reuse the same `reason` or `source_ref` if helpful,
and add `task_links` for related work, but do not create a shared batch
question that blocks or advances multiple tasks at once.

Question status values:

- `open` - waiting for an answer,
- `answered` - answer was recorded,
- `waived` - the human or source explicitly allowed work to proceed,
- `superseded` - replaced by a newer clearer question.

A task cannot leave `planejamento` while it has `open` planning questions.

Answering or waiving a question advances only the task referenced by that row.
If the same answer applies to related tasks, record separate `planning_answers`
rows for each task-specific question.

### Planning answers

Every answer must be recorded as a `planning_answers` row. Answers may come from:

- external issue descriptions or comments,
- local task files,
- explicit user replies,
- repo workflow memory,
- a documented waiver.

Do not overwrite an answer in place. If the answer changes, add a new answer row
and use a gate event or question status to show which answer is current.

### Related tasks

Before creating a new local task or importing a source task into planning, search
the local kanban for related work.

Search signals:

- exact source URL or issue id,
- title tokens and domain nouns,
- touched files or modules,
- shared acceptance criteria,
- matching business rules in planning answers,
- existing source snapshots.

When related work is found, write a `task_links` row with relation such as:

- `related`,
- `duplicates`,
- `blocks`,
- `blocked_by`,
- `parent`,
- `child`,
- `same_area`.

If an external system has separate issues, keep separate local rows and link
them. Do not merge external tasks without explicit user instruction.

### Local-only mode

When no external kanban is integrated, `/aih-goal` may create local tasks from a
file, existing DB rows, or `$ARGUMENTS`. In this mode the local kanban owns task
title, description, priority, visible status, planning questions, planning
answers, and related-task links.

Readable markdown artifacts are still required so humans can inspect the run
without querying SQLite.

For a pasted list or `--from-list` run, create one local task per list item. Do
not collapse the list into one task just because it arrived in a single prompt.
The user's request to work "sem checkpoints", "ininterruptamente", or
"ate terminar" changes the autonomy contract only: keep writing state
checkpoints to files, but do not stop for conversational approvals between
items.
