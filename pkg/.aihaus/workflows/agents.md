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
| workflow-planning-gate | planejamento | Run Socratic clarification, identify missing business rules, and block unclear tasks. |
| workflow-tdd-gate | tdd | Ensure acceptance criteria become failing tests or explicit verification contracts. |
| workflow-execution-review | review-execucao | Review implementation readiness before broad tests and deployment. |
| workflow-test-gate | testes | Run or coordinate automated tests, identify breakage, and propose test improvements. |
| workflow-cicd | testes, subida-dev | Prepare repeatable CI/CD commands, deployment checks, and environment evidence. |
| workflow-dev-review | review-dev | Validate the published dev result; use Playwright/headless browser for UI and flow work. |
| workflow-human-review | human-review | Summarize evidence for the human and route accepted/rejected decisions. |
| workflow-designer | any | Create or adjust repo workflow profiles and workflow-agent rules when the project changes. |

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
