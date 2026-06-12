# Workflow Agents

Workflow agents govern routing, process, gates, memory, and environment
movement. They do not replace specialist code agents. They decide when to spawn
or request specialists at their stages.

Claude-callable agent files may still live under `.aihaus/agents/` because the
Claude agent loader expects that shape. Workflow-specific rules and durable
profile data live under `.aihaus/protocols/` and `.aihaus/memory/workflows/`.

## Agent Roles

| Role | Stage Ownership | Responsibility |
|---|---|---|
| workflow-orchestrator | top-level intake | Classify a fresh user intent, detect active workflow continuation, and choose the workflow entry or no-workflow path. |
| workflow-intake | backlog | Keep backlog items meaningful enough to revisit later. |
| workflow-planning-gate | planejamento | Record task-specific business-rule gaps, identify missing business rules, and block unclear tasks. |
| workflow-tdd-gate | tdd | Ensure acceptance criteria become failing tests or explicit verification contracts. |
| workflow-execution-review | review-execucao | Review implementation readiness before broad tests and deployment. |
| workflow-test-gate | testes | Run or coordinate automated tests, identify breakage, and require a Playwright dev-review plan for UI/flow work. |
| workflow-cicd | testes, homolog, prod | Prepare repeatable CI/CD commands, deployment checks, and environment evidence. |
| workflow-dev-reviewer | homolog | Validate the published homolog result; Playwright/headless browser is mandatory for UI and flow work. |
| workflow-human-review | human-review | Summarize evidence for the human and reject handoff when required Playwright evidence is missing. |
| workflow-designer | any | Create or adjust repo workflow profiles and workflow-agent rules when the project changes how work should move. |

## Memory Contract

Before acting, workflow agents read:

1. `.aihaus/protocols/default.md` + `.aihaus/protocols/routing.md` + `.aihaus/protocols/artifacts.md`
2. `.aihaus/project.md`
3. `.aihaus/memory/workflows/README.md`
4. `.aihaus/memory/workflows/*.md`
5. native repository memory through `aihaus memory ... --json` when available

After acting, workflow agents write durable lessons only when they are reusable:

- `.aihaus/memory/workflows/rules.md`
- `.aihaus/memory/workflows/user-preferences.md`
- `.aihaus/memory/workflows/environment.md`
- `.aihaus/memory/workflows/gotchas.md`

Workflow agents should write blockers in business language first. Technical
details may be included as evidence, not as the main explanation.

## Gate Evaluation Contract

Every workflow gate must produce `PASS`, `SKIPPED`, `BLOCKED-TO-PLANNING`, or
`BLOCKED`. Skips are allowed only after evaluation and must include a reason.
Task-specific `BLOCKED-TO-PLANNING` results should not stop a larger run; they
create one source-facing business-rule gap for the affected task and allow other
ready tasks to continue.

For UI or user-flow work, `homolog` cannot pass without Playwright/headless
browser evidence. Backend-only skips must say why there is no frontend,
console, or environment-visible behavior to validate.

`homolog` must dispatch `workflow-dev-reviewer` immediately when a task enters
the stage. A `workflow-test-gate` Playwright plan is only input for that agent,
not a substitute for running dev review.

## Sub-flow Invocation

The top-level request lands on `workflow-orchestrator` unless the conversation
is already inside an active workflow or the request is clearly no-workflow. The
orchestrator returns the workflow entry. The main session then invokes the
chosen entry and preserves the stage gates.

Per task, the active flow decides whether a stage needs interactive scoping or
runs fully autonomously:

- `planejamento`: a fresh requester brief routes to interactive planning
  (`Skill(aih-plan)`) so the requester can clarify business rules and approve
  the plan through native plan mode. Source-backed backlog sweeps run through
  `workflow-planning-gate`; gaps become per-task `BLOCKED-TO-PLANNING` rows.
- `desenvolvimento` (`tdd` / `review-execucao`): ready feature work routes to
  `Skill(aih-feature)` and defects route to `Skill(aih-bugfix)` when dev-level
  scoping is needed. Pre-scoped tasks go straight to specialist agents.
- `homolog` and `prod`: never interactive sub-flows. They stay flow-gated
  CI/CD stages enforced by `flow-guard.sh`.

Interactive scoping is a scoping-first window at the entry of a task. Once
plan-mode approval lands or the autonomous sweep passes, the run drives
downstream gates without mid-run input until the target stage or a true blocker.
