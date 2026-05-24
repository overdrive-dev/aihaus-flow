# M049 - aih-goal workflow runner

## Goal

Add a goal-level command that can import many source-backed tasks, evaluate
workflow gates, and execute ready work without requiring the user to manually
run one command per task.

## User Contract

`/aih-goal` invocation is approval to work autonomously until the target stage
or true blockers.

Default target:

```text
human-review
```

Default usage:

```text
/aih-goal --until human-review
```

The command discovers the planned kanban/backlog from explicit flags, existing
local goal DB state, workflow memory, project/workflow source hints, and
connected systems such as Linear or Notion. Source flags remain overrides.

## Scope

- Add `/aih-goal` skill.
- Store operational goal state in `.aihaus/state/aih-goal.db`.
- Store readable evidence packages in `.aihaus/workflows/runs/`.
- Treat Linear and other kanban systems as source/sync targets, with local
  aihaus artifacts as the recoverable execution record.
- Add workflow agents for TDD, execution review, tests, human-review packaging,
  and workflow design.
- Make gates mandatory to evaluate, not mandatory to run when not applicable.
- Treat the DB as a cache + append-only journal, not as a competing task source
  of truth.
- Register every task that enters `planejamento` in the local kanban.
- Store planning questions, planning answers, and related-task links as
  structured contracts. Planning question rows are task-specific business-rule
  gaps, not TUI prompts or mixed batch questionnaires.

## Gate Contract

Every gate returns one of:

- `PASS`
- `SKIPPED: <reason>`
- `BLOCKED-TO-PLANNING: <task-specific business-rule gap>`
- `BLOCKED: <true blocker>`

Task-specific planning blockers do not stop the goal run; they create one
source-facing business-rule gap per affected task and allow other ready tasks
to continue.

## Local Kanban Contract

When no external kanban is connected, `.aihaus/state/aih-goal.db` is the local
kanban for aihaus. When an external kanban is connected, the DB is still the
local workflow mirror and journal.

Every task entering `planejamento` must exist in the local kanban. Every missing
business rule or expectation becomes a planning question row scoped to that
task. Every accepted answer becomes a planning answer row for that task's
question. Agents must search the local kanban for related tasks before creating
or importing a new planning task, but related tasks are linked, not merged into
one planning question.

## Validation

Package smoke tests must reflect:

- 15 skills
- 57 agents
- 57 cohort memberships
- `aih-graph` package indexing counts for 57 agents and 15 skills
