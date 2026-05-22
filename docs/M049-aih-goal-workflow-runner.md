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

Expected Linear-backed usage:

```text
/aih-goal --from-linear "Nora sprint atual" --until human-review
```

## Scope

- Add `/aih-goal` skill.
- Store goal state in `.aihaus/workflows/runs/`.
- Treat Linear as a source/sync target, with local aihaus artifacts as the
  recoverable source of truth.
- Add workflow agents for TDD, execution review, tests, human-review packaging,
  and workflow design.
- Make gates mandatory to evaluate, not mandatory to run when not applicable.

## Gate Contract

Every gate returns one of:

- `PASS`
- `SKIPPED: <reason>`
- `BLOCKED-TO-PLANNING: <business question>`
- `BLOCKED: <true blocker>`

Task-specific planning blockers do not stop the goal run; they create source
questions and allow other ready tasks to continue.

## Validation

Package smoke tests must reflect:

- 15 skills
- 57 agents
- 57 cohort memberships
- `aih-graph` package indexing counts for 57 agents and 15 skills
