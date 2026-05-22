# aih-goal run state

`/aih-goal` stores durable workflow state under:

```text
.aihaus/workflows/runs/[YYMMDD]-[slug]/
```

The run directory is the source of truth for resume, audit, and evidence. It is
local-first. External systems such as Linear are sync targets.

### Required files

```text
GOAL.md
TASKS.md
RUN-MANIFEST.md
tasks/
evidence/
```

### GOAL.md

```markdown
# Goal: [title]

Started: [ISO timestamp]
Target stage: human-review
Source: linear | file | prompt

### Intent
[Business outcome.]

### Source Links
- [Linear issue/project/view URL]

### Operating Rules
- Work without user input until target stage or true blocker.
- Task-specific business gaps return only that task to planejamento.
```

### TASKS.md

Keep one row per source task:

```markdown
| ID | Source | Title | Stage | Planning | Evidence |
|---|---|---|---|---|---|
| NORACAR-123 | Linear | Fix billing filter | planejamento | pending | tasks/NORACAR-123.md |
```

### Task file

Each task gets `tasks/<id>.md`:

```markdown
# [ID] [Title]

Source: [Linear URL or local source]
Stage: planejamento
Target: human-review

### Source Context
[Description, comments, acceptance criteria, copied links.]

### Gate Log
| Stage | Verdict | Reason | Evidence |
|---|---|---|---|

### Business Questions
- [Question sent back to source, if blocked.]

### Human Review Package
[Summary written after review-dev passes.]
```

### RUN-MANIFEST.md

```markdown
# Goal Run Manifest

goal: [slug]
status: running
target_stage: human-review
started: [ISO timestamp]
last_updated: [ISO timestamp]

### Progress Log
- [ISO] Imported 22 tasks from Linear.
```

### Status vocabulary

- `pending`
- `planejamento`
- `ready-for-tdd`
- `tdd`
- `review-execucao`
- `testes`
- `subida-dev`
- `review-dev`
- `human-review`
- `box-dev`
- `blocked-to-planejamento`
- `blocked`
- `completed`

### Gate verdicts

Every stage writes exactly one of:

- `PASS`
- `SKIPPED: <reason>`
- `BLOCKED-TO-PLANNING: <business question>`
- `BLOCKED: <true blocker>`

Skipping a gate is allowed only after evaluation. The reason must say why the
gate does not apply to that task.
