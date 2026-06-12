# aihaus Routing

Natural-language user requests enter aihaus through an explicit orchestration
step. The user does not need to type `/aih-*`. A fresh top-level request is first
classified by `workflow-orchestrator`, which chooses the workflow entry that
matches the intent, chooses `NO_WORKFLOW`, or continues an active workflow.

Slash commands remain optional overrides for determinism and recovery. They are
not required for normal use.

## Entry Behavior

1. Detect whether the conversation is already inside an active workflow.
2. If the user is continuing or answering that workflow, do not re-route; resume
   the active workflow.
3. Otherwise classify the request intent: feature, bug, planning, review, ops,
   backlog intake, workflow design, or no workflow.
4. Route to the selected workflow entry.
5. Drive gated execution through the stages in `default.md`.

## No-Workflow Path

The orchestrator may return `NO_WORKFLOW` when a workflow would add no value:

- simple factual answer,
- explanation of existing context with no repo mutation,
- trivial command output,
- quick clarification,
- explicit user instruction to avoid workflow routing for this turn.

When `NO_WORKFLOW` is selected, the main session answers directly and does not
create run artifacts.

## Active Workflow Exception

If the user is already inside a workflow, the current workflow owns the turn.
Examples:

- the user answers a planning question,
- the user says continue, resume, next, fix that, or run the check,
- the user responds to a blocker, review finding, test failure, or plan created
  by the current workflow,
- the user narrows scope inside the same task.

Only start a new orchestration pass when the user asks for a separate objective
or clearly replaces the current task.

## Route Catalog

- `BACKLOG_INTAKE` -> `workflow-intake`
- `PLANNING` -> `Skill(aih-plan)`
- `FEATURE` -> `Skill(aih-feature)`
- `BUGFIX` -> `Skill(aih-bugfix)`
- `REVIEW` -> relevant verifier/reviewer workflow agent
- `OPS` -> workflow gates plus the flow-gated online boundary
- `WORKFLOW_DESIGN` -> `workflow-designer` or planning first
- `CONTINUE_ACTIVE_WORKFLOW` -> current workflow
- `NO_WORKFLOW` -> inline answer

## Invariants

- The router chooses where work enters. It never skips mandatory gates.
- Higher-risk routes win when intent overlaps: bugfix before feature, planning
  before implementation when business meaning is unclear, ops only when the
  request touches online environment movement.
- The online stages are flow-gated: `flow-guard.sh` blocks deploy/promotion
  commands outside an active tracked flow.
- Route descriptions must stay non-overlapping. Competing descriptions cause
  misroutes.
- Business-rule gaps return to planning in business language.

## Native Surfaces

The written plan must feed native Claude Code surfaces where applicable:

- Native plan mode (`ExitPlanMode`) projects interactive planning into the GUI
  Plan panel and approval gate.
- Native task list (`TaskCreate` / `TaskUpdate`) projects active coordination
  rows and gate verdicts.

Both are projections of the durable workflow state in `.aihaus/state/` and
`.aihaus/runtime/runs/`.
