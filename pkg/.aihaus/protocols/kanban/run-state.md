# Run state

The workflow stores readable run artifacts under:

```text
.aihaus/runtime/runs/[YYMMDD]-[slug]/
```

The operational task cache and journal live in `.aihaus/state/kanban.db`.
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

### Browser Gate
Required: yes/no
Result: pass/skipped/blocked/pending
Reason: [Playwright evidence, backend-only skip, or blocker]
Evidence: [screenshot, trace, command, URL, or none]

### Business Rule Gaps
| ID | Business Rule Gap | Status | Answer Source | Answer |
|---|---|---|---|---|
| pq-001 | [Task-specific missing rule synced back to source, if blocked.] | open | | |

### Related Tasks
| Task | Relation | Reason |
|---|---|---|
| [id] | related | [why this matters] |

### Human Review Package
[Summary written after homolog passes.]
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

### Memory Promotion
- status: pending
- targets: none yet
```

### Projection rules

After every gate or stage transition, rewrite the readable projection from the
DB:

- The native CLI task list (TaskCreate/TaskUpdate) is a projection of the DB too:
  one CLI task per active coordination row, status synced from gate verdicts. The
  durable run artifacts + `kanban.db` are the source; the written plan and the
  CLI task list stay **one synced view** — no drift between document and CLI (S10).
- The interactive planning sub-flow ALSO surfaces the plan via **native plan mode**
  (`ExitPlanMode` → GUI Plan panel + approve/reject gate). Plan panel, task list,
  and plan file are all projections of the same durable plan.
- `TASKS.md` stage/planning/open-question counts match `tasks`,
  `planning_questions`, and `gate_events`.
- `tasks/<id>.md` `Stage:` matches `tasks.stage`.
- `tasks/<id>.md` `Gate Log` has one row for every evaluated stage, including
  `SKIPPED: <reason>`.
- UI or user-flow tasks must have `Browser Gate` result `pass` before leaving
  `homolog`; backend-only skips must include a reason. `pending` browser
  gates cannot move to `human-review`.
- Batch gates such as full-suite test, deploy, or dev-review may reuse a shared
  evidence file, but every affected task still gets its own gate row.
- Batch planning sweeps may reuse the same source evidence, but every missing
  business rule gets a task-specific `planning_questions` row and source
  comment. Do not store a mixed TUI-style question for multiple tasks.
- For external kanban tasks, projection is incomplete until there is a matching
  outbound `sync_events` row for the same task/stage/verdict. If the external
  update failed or was deferred, show the sync debt in `TASKS.md` and the task
  file before continuing to the next stage.
- Before finish or long pause, `RUN-MANIFEST.md` has a `### Memory Promotion`
  section with `promoted`, `no-signal`, or `deferred`; matching
  `memory_events` rows exist for promoted or deferred items.

### Status vocabulary

- `pending`
- `entendimento`
- `planejamento`
- `ready-for-tdd`
- `tdd`
- `review-execucao`
- `testes`
- `homolog`
- `human-review`
- `prod`
- `box-dev`
- `blocked-to-planejamento`
- `blocked`
- `completed`

### Gate verdicts

Every stage writes exactly one of:

- `PASS`
- `SKIPPED: <reason>`
- `BLOCKED-TO-PLANNING: <task-specific business-rule gap>`
- `BLOCKED: <true blocker>`

Skipping a gate is allowed only after evaluation. The reason must say why the
gate does not apply to that task.
