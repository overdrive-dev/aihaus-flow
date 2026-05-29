# Workflow Agents

Workflow agents govern process, gates, memory, and environment movement. They do
not replace specialist code agents. They decide when to spawn or request
specialists at their stages. The interactive sub-flows (planning, bugfix, feature)
are the **routable entries** a request lands on; the workflow agents are the gate
executors those sub-flows (and native `/goal` runs) spawn as work moves through
the stages.

Claude-callable agent files may still live under `.aihaus/agents/` because the
Claude agent loader expects that shape. Workflow-specific rules and durable
profile data live here.

## Agent Roles

| Role | Stage Ownership | Responsibility |
|---|---|---|
| workflow-intake | backlog | Keep backlog items meaningful enough to revisit later. |
| workflow-planning-gate | planejamento | Record task-specific business-rule gaps, identify missing business rules, and block unclear tasks. |
| workflow-tdd-gate | tdd | Ensure acceptance criteria become failing tests or explicit verification contracts. |
| workflow-execution-review | review-execucao | Review implementation readiness before broad tests and deployment. |
| workflow-test-gate | testes | Run or coordinate automated tests, identify breakage, and require a Playwright dev-review plan for UI/flow work. |
| workflow-cicd | testes, homolog, prod | Prepare repeatable CI/CD commands, deployment checks, and environment evidence. |
| workflow-dev-reviewer | homolog | Validate the published homolog result; Playwright/headless browser is mandatory for UI and flow work. |
| workflow-human-review | human-review | Summarize evidence for the human and reject handoff when required Playwright evidence is missing. |
| workflow-designer | any | Create or adjust repo workflow profiles and workflow-agent rules when the project changes. |

## Memory Contract

Before acting, workflow agents read:

1. `.aihaus/workflows/default.md` + `.aihaus/workflows/artifacts.md`
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
Task-specific `BLOCKED-TO-PLANNING` results should not stop a larger
run; they create one source-facing business-rule gap for the affected task and
allow other ready tasks to continue.

For UI or user-flow work, `homolog` cannot pass without Playwright/headless
browser evidence. Backend-only skips must say why there is no frontend,
console, or environment-visible behavior to validate.

`homolog` must dispatch `workflow-dev-reviewer` immediately when a task
enters the stage. A `workflow-test-gate` Playwright plan is only input for that
agent, not a substitute for running dev review.

## Sub-flow invocation

The interactive sub-flows are the **routable entries** (and can also be invoked
via the Skill tool from a native `/goal` run). Per task, the active flow decides
whether a stage needs interactive scoping or runs fully autonomously:

- **planejamento.** A *fresh requester brief* (a single request, no pre-planned
  source) routes to the interactive planning sub-flow `Skill(aih-plan)`: it reaches
  `entendimento` (100% understanding, BR-1), clarifies business rules with the
  requester, and surfaces the plan via **native plan mode** (`ExitPlanMode` → GUI
  Plan panel). That approval **is** the `planejamento → tdd` gate. A *source-backed*
  backlog (Linear, file) instead runs the autonomous planning sweep
  (`workflow-planning-gate`); gaps become per-task `BLOCKED-TO-PLANNING` rows, never
  an interactive prompt.
- **desenvolvimento (tdd / review-execucao).** When a ready task needs dev-level
  scoping, route to `Skill(aih-feature)` (feature) or `Skill(aih-bugfix)` (defect)
  for the interactive scoping, then drive the autonomous gates. Pre-scoped tasks go
  straight to the specialist agents.

**Interactive-vs-autonomous rule.** Interactive scoping is a *scoping-first window*
at the entry of a task — it may ask the requester. Once the plan-mode approval lands
(or the autonomous sweep passes), the run drives every downstream gate with **no
mid-run input** until the target stage or a true blocker. The online stages (`homolog`,
`prod`) are never interactive and never sub-flowed; they stay devops-gated CI/CD
(`role-guard.sh`).
