# Workflow Agents

Workflow agents govern process, gates, memory, and environment movement. They do
not replace specialist code agents. They decide when to spawn or request
specialists.

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
| workflow-cicd | testes, subida-dev | Prepare repeatable CI/CD commands, deployment checks, and environment evidence. |
| workflow-dev-reviewer | review-dev | Validate the published dev result; Playwright/headless browser is mandatory for UI and flow work. |
| workflow-human-review | human-review | Summarize evidence for the human and reject handoff when required Playwright evidence is missing. |
| workflow-designer | any | Create or adjust repo workflow profiles and workflow-agent rules when the project changes. |
| aih-goal | any | Skill-level coordinator that imports tasks, evaluates gates, and drives work until the target stage. |

## Memory Contract

Before acting, workflow agents read:

1. `.aihaus/workflows/default.md`
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
Task-specific `BLOCKED-TO-PLANNING` results should not stop a larger `/aih-goal`
run; they create one source-facing business-rule gap for the affected task and
allow other ready tasks to continue.

For UI or user-flow work, `review-dev` cannot pass without Playwright/headless
browser evidence. Backend-only skips must say why there is no frontend,
console, or environment-visible behavior to validate.

`review-dev` must dispatch `workflow-dev-reviewer` immediately when a task
enters the stage. A `workflow-test-gate` Playwright plan is only input for that
agent, not a substitute for running dev review.
