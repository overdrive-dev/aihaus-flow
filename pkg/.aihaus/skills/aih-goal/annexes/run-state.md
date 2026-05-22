# aih-goal run state

`/aih-goal` stores readable run artifacts under:

```text
.aihaus/workflows/runs/[YYMMDD]-[slug]/
```

The operational task cache and journal live in `.aihaus/state/aih-goal.db`.
The run directory is the readable evidence package for resume, audit, and human
review. External systems such as Linear remain the human kanban source of truth.

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
| ID | Source | Title | Stage | Planning | Open Q | Evidence |
|---|---|---|---|---|---|---|
| NORACAR-123 | Linear | Fix billing filter | planejamento | pending | 1 | tasks/NORACAR-123.md |
```

### Task file

Each task gets `tasks/<id>.md`:

```markdown
# [ID] [Title]

Source: [Linear URL or local source]
Stage: [current stage from tasks.stage]
Target: human-review
Priority: [local/external priority when known]
Related: [linked task ids or none]

### Source Context
[Description, comments, acceptance criteria, copied links.]

### Gate Log
| Stage | Verdict | Reason | Evidence |
|---|---|---|---|

### Business Questions
| ID | Question | Status | Answer Source | Answer |
|---|---|---|---|---|
| pq-001 | [Question sent back to source, if blocked.] | open | | |

### Related Tasks
| Task | Relation | Reason |
|---|---|---|
| [id] | related | [why this matters] |

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

### Projection rules

After every gate or stage transition, rewrite the readable projection from the
DB:

- `TASKS.md` stage/planning/open-question counts match `tasks`,
  `planning_questions`, and `gate_events`.
- `tasks/<id>.md` `Stage:` matches `tasks.stage`.
- `tasks/<id>.md` `Gate Log` has one row for every evaluated stage, including
  `SKIPPED: <reason>`.
- Batch gates such as full-suite test, deploy, or dev-review may reuse a shared
  evidence file, but every affected task still gets its own gate row.

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
