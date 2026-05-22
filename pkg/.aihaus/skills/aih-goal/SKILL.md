---
name: aih-goal
description: Execute a multi-task goal autonomously through aihaus workflow gates, optionally importing tasks from Linear, until a target stage such as human-review.
allowed-tools: Read Write Edit Grep Glob Bash Agent TaskCreate TaskUpdate Skill
argument-hint: "[goal description] [--from-linear <selector>] [--from-file <path>] [--until human-review]"
---

## Task

Run a goal as an autonomous workflow. Import tasks, evaluate every workflow gate,
execute ready work, attach evidence, and continue without user input until the
target stage is reached or every remaining task has a true blocker.

$ARGUMENTS

## Inputs

- `--from-linear <selector>` - import candidate tasks from Linear. The selector
  can be an issue id, project/view/team/search phrase, or copied Linear URL.
- `--from-file <path>` - import tasks from a local markdown/json/text file.
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

- source system unavailable and no task source was imported,
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

If `--from-linear` is present, use the connected Linear capability when
available. Read issue title, id, URL, description, comments, labels/status,
attachments/links, and acceptance criteria. Do not create Linear labels, views,
or workflow states unless explicitly requested by the user.

If Linear is unavailable, this is a source blocker only when no local task list
was also provided. Report the missing integration and stop before making code
changes.

If `--from-file` is present, parse that file into task records. If neither flag
is present, parse `$ARGUMENTS` as the goal brief and create one task from it.

## Phase 2: Create Goal Run

Create `.aihaus/workflows/runs/[YYMMDD]-[slug]/`.

Use `annexes/run-state.md` for file shapes. At minimum write:

- `GOAL.md`
- `TASKS.md`
- `RUN-MANIFEST.md`
- `tasks/<task-id>.md`
- `evidence/`

TaskCreate only the current coordination rows: import source, evaluate planning,
execute ready tasks, package human review. Keep the full task list in `TASKS.md`
so the UI does not become noisy for large Linear backlogs.

## Phase 3: Planning Sweep

For every imported task:

1. Spawn `workflow-intake` when the source item is raw or underspecified.
2. Spawn `workflow-planning-gate`.
3. Record verdict: `READY-FOR-TDD`, `BLOCKED`, or `SKIPPED` with reason.

The planning gate must use source content first. If Linear already contains the
answers, do not ask again. If something is missing, write the exact business
question back to the source when possible and keep the task in `planejamento`.

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

Sync evidence to Linear comments when the source is Linear. If sync is
unavailable, write it under the task artifact and note the sync blocker.

## Phase 6: Finish

The goal is complete when every task is either:

- at or beyond `--until`,
- `blocked-to-planejamento` with a business-facing question synced or recorded,
- `blocked` by a true blocker with evidence.

Update `RUN-MANIFEST.md`, summarize counts by final state, and point to
`.aihaus/workflows/runs/[slug]/`.

## Annexes

- `annexes/run-state.md` - run artifact format and task status vocabulary.
- `annexes/linear-intake.md` - Linear import/sync behavior.

## Autonomy

See `_shared/autonomy-protocol.md`. `/aih-goal` is a post-approval execution
command: no option menus, no delegated typing, no mid-run approval prompts
unless a true blocker affects all remaining work.
