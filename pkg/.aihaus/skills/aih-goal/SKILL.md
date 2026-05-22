---
name: aih-goal
description: Execute a planned kanban goal autonomously through aihaus workflow gates until a target stage such as human-review.
allowed-tools: Read Write Edit Grep Glob Bash Agent TaskCreate TaskUpdate Skill
argument-hint: "[goal description] [--until human-review] [--source <selector>] [--from-linear <selector>] [--from-file <path>]"
---

## Task

Run a goal as an autonomous workflow over a planned kanban/backlog. Discover or
resume the work source, import tasks into the local operational goal DB,
register planning contracts, evaluate every workflow gate, execute ready work,
attach evidence, and continue without user input until the target stage is
reached or every remaining task has a true blocker.

$ARGUMENTS

## Inputs

- `--source <selector>` - preferred kanban/source selector. Optional; default is
  discovery from repo workflow memory, configured connectors, existing goal DB
  state, and source links in project/workflow files.
- `--from-linear <selector>` - override discovery and import candidate tasks
  from Linear.
- `--from-file <path>` - override discovery and import tasks from a local
  markdown/json/text file.
- `--until <stage>` - target workflow stage. Default: `human-review`.
- `--max-active <n>` - maximum implementation tasks in flight. Default: 1.

Allowed stages: `planejamento`, `tdd`, `review-execucao`, `testes`,
`subida-dev`, `review-dev`, `human-review`, `box-dev`.

## Autonomy Contract

The `/aih-goal` invocation is approval to work without mid-run user input until
`--until` is reached.

Do not ask the user to choose between normal execution paths. Evaluate the gate,
pick the safest applicable path, write the reason to the run artifacts, and
continue.

If one task lacks business information, do not stop the whole goal. Mark that
task `blocked-to-planejamento`, write the missing question in business language,
sync/comment it to the source when available, and continue other ready tasks.

Stop the whole goal only on true blockers:

- no external source, local goal DB, or local task source can be discovered,
- unsafe git state that cannot be stashed or isolated safely,
- missing credentials or dev environment required for all remaining tasks,
- destructive or irreversible action requiring explicit human approval.

### Mandatory Reads

Before acting, read:

1. `.aihaus/workflows/default.md`
2. `.aihaus/workflows/agents.md`
3. `.aihaus/project.md`
4. `.aihaus/memory/workflows/README.md`
5. relevant `.aihaus/memory/workflows/*.md` files when present

Use auto-injected native repository memory first. If it is missing or
insufficient and `aihaus memory` is available, run:

- `aihaus memory status --repo . --json`
- `aihaus memory query --repo . --json "<goal, issue ids, or affected area>"`

## Phase 1: Resolve Source

Default behavior is source discovery. Do not require `--from-linear`,
`--from-notion`, or similar flags for normal operation. `/aih-goal` assumes the
repo already has a planned kanban/backlog and should find it.

Discovery order:

1. explicit override flags: `--from-linear`, `--from-file`, or `--source`,
2. existing `.aihaus/state/aih-goal.db` tasks not yet at `--until`,
3. source hints in `.aihaus/memory/workflows/*.md`,
4. source hints in `.aihaus/workflows/default.md` and `.aihaus/project.md`,
5. available connected kanban systems such as Linear, Notion, Jira, Trello, or
   GitHub Issues,
6. a local task list under `.aihaus/workflows/` if present,
7. `$ARGUMENTS` as a single goal brief only when no planned source exists.

See `annexes/source-discovery.md`. If an external system is unavailable but
`aih-goal.db` already has imported tasks, continue locally and record sync debt.
Stop before code changes only when no recoverable task source exists.

## Phase 2: Create Goal Run

Create `.aihaus/workflows/runs/[YYMMDD]-[slug]/`.

Use `.aihaus/state/aih-goal.db` as the local operational cache + append-only
journal. It does not replace Linear/Notion/Jira/Trello/GitHub as the human
kanban source of truth when an external kanban exists; when no external kanban
exists, it is the local kanban source for aihaus workflow state. Use
`annexes/goal-db.md` for the schema contract, `annexes/local-kanban.md` for
local task and planning contracts, and `annexes/run-state.md` for readable file
shapes. At minimum write:

- `GOAL.md`
- `TASKS.md`
- `RUN-MANIFEST.md`
- `tasks/<task-id>.md`
- `evidence/`

TaskCreate only the current coordination rows: import source, evaluate planning,
execute ready tasks, package human review. Keep the full task list in `TASKS.md`
so the UI does not become noisy for large Linear backlogs.

Save raw source snapshots in the DB before summarizing. Never overwrite source
descriptions, priorities, or external status fields unless explicitly requested.
Every task that enters `planejamento` must have a local kanban row before the
planning gate runs.

## Phase 3: Planning Sweep

For every imported task:

1. Search the local kanban for related tasks and record `task_links` when found.
2. Spawn `workflow-intake` when the source item is raw or underspecified.
3. Spawn `workflow-planning-gate`.
4. Record verdict: `READY-FOR-TDD`, `BLOCKED`, or `SKIPPED` with reason.

The planning gate must use source content first. If Linear already contains the
answers, record them as `planning_answers` and do not ask again. If something is
missing, create a `planning_questions` row, write the exact business question
back to the source when possible, and keep the task in `planejamento`. A task
must not move to `tdd` while it has open planning questions unless the question
is explicitly waived.

## Phase 4: Execute Ready Tasks

For each `READY-FOR-TDD` task, run stages in order until `--until`:

1. `workflow-tdd-gate`
2. implementation specialist agents (`implementer`, `frontend-dev`, `executor`,
   `test-writer`, or narrower existing agents as appropriate)
3. `workflow-execution-review`
4. `workflow-test-gate`
5. `workflow-cicd` for `subida-dev` and environment evidence
6. `workflow-dev-reviewer`
7. `workflow-human-review`

Implementation tasks default to sequential execution. Use `--max-active` only
when owned files and deploy/test environments are independent. Never run two
tasks that may edit the same files in parallel.

Every stage must produce one of:

- `PASS`
- `SKIPPED: <why not applicable>`
- `BLOCKED-TO-PLANNING: <business question>`
- `BLOCKED: <true blocker>`

## Phase 5: Sync Evidence

For every task that reaches `human-review`, write:

- business summary,
- commits/branch/PR if available,
- test/build commands and results,
- dev URL/environment,
- Playwright screenshots/traces when browser validation applied,
- why any gate was skipped.

Sync evidence back to the task source as comments or equivalent append-only
updates. If sync is unavailable, write it under the task artifact, add an
unsynced event to `aih-goal.db`, and continue local execution.

## Phase 6: Finish

The goal is complete when every task is either:

- at or beyond `--until`,
- `blocked-to-planejamento` with a business-facing question synced or recorded,
- `blocked` by a true blocker with evidence.

Update `RUN-MANIFEST.md`, summarize counts by final state, and point to
`.aihaus/workflows/runs/[slug]/`.

## Annexes

- `annexes/run-state.md` - run artifact format and task status vocabulary.
- `annexes/source-discovery.md` - default source discovery and connector order.
- `annexes/goal-db.md` - SQLite cache/journal schema and sync safety rules.
- `annexes/local-kanban.md` - local task, related-task, and planning Q/A
  contract.
- `annexes/linear-intake.md` - Linear import/sync behavior.

## Autonomy

See `_shared/autonomy-protocol.md`. `/aih-goal` is a post-approval execution
command: no option menus, no delegated typing, no mid-run approval prompts
unless a true blocker affects all remaining work.
