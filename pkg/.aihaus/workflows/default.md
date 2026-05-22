# aihaus Workflow Profile

This file is the repository-local workflow contract. It defines how work moves
through this repo. aihaus skills and workflow agents must read this file before
moving tasks between stages.

## Source of Truth

- Workflow state starts local-first in `.aihaus/workflows/`.
- External tools such as Linear, Jira, Trello, Notion, or GitHub Issues are sync
  targets, not required storage for the first implementation.
- Durable learned behavior belongs in `.aihaus/memory/workflows/`, not in this
  file.
- Runtime evidence and generated state belong in `.aihaus/state/`.

## Default Stages

| Stage | Purpose | Exit Gate |
|---|---|---|
| backlog | Capture tasks that make sense to pick up later, even without detail. | Task has a clear enough title and short intent. |
| planejamento | Clarify scope, business rules, user expectations, risks, and acceptance criteria. | Socratic questions are answered or explicitly waived; acceptance criteria are testable. |
| tdd | Turn acceptance criteria into failing tests or equivalent verification contracts. | Tests/contracts fail for the expected reason or the repo records why strict TDD does not apply. |
| review-execucao | Review implementation before broader test and deploy work. | Code changes satisfy the TDD contract and obvious quality issues are resolved. |
| testes | Capture breakage, regression risk, and test improvements before environment promotion. | Relevant automated checks pass or failures are documented as blockers. |
| subida-dev | Promote to the development environment for stronger validation. | Dev environment has the task published or the deploy blocker is documented. |
| review-dev | Validate the published dev result, usually with Playwright/headless browser when there is UI or user-flow impact. | Visual/flow evidence passes, or backend-only work is explicitly marked not browser-validatable. |
| human-review | Human validates after dev review has passed and the work is already available in dev. | Human accepts or sends back with business-language feedback. |
| box-dev | Holding box for accepted dev work before the next downstream process. | Project-specific. |

## Planning Gate

`planejamento` is blocking. A task must not move to `tdd` while business rules,
expected behavior, acceptance criteria, data assumptions, or user-facing outcomes
are unclear.

The planning gate must ask Socratic questions when needed. Good questions are
about business meaning and expected behavior, not implementation trivia.

If a task came from an external source such as Linear, the planning gate must
read the issue description, comments, links, and attached context before asking
anything. Do not ask the human to repeat answers already present in the source.

Every task that enters `planejamento` must be registered in the local kanban
under `.aihaus/state/aih-goal.db`. Planning questions and answers are workflow
contracts: record the question before asking it, record the answer before using
it, and keep the task in `planejamento` while any planning question is open.

## Gate Evaluation Contract

Every workflow gate is mandatory to evaluate, but not every gate is mandatory to
run. A gate may pass, skip, or block:

- `PASS` means the stage evidence is sufficient.
- `SKIPPED` means the agent evaluated the gate and found it not applicable; the
  skip reason must name why.
- `BLOCKED-TO-PLANNING` means a business expectation, rule, criterion, or
  validation method is missing or failed.
- `BLOCKED` means a true operational blocker prevents progress.

Task-specific blockers should not stop a larger goal run. Mark that task and
continue with other ready tasks.

## Dev Review Gate

`review-dev` uses Playwright/headless browser validation whenever the task has
visual, navigation, form, interaction, console, or user-flow impact.

Backend-only tasks may skip browser validation only when there is no direct
front-end, console, or environment-visible behavior to check. The reviewer must
say why the browser gate was not applicable.

If `review-dev` finds a blocker, the task returns to `planejamento` with:

- the business expectation that failed,
- the observed behavior,
- the question or decision needed from the human,
- links to evidence when available.

Avoid technical implementation language in the workflow handoff unless it is
needed for traceability.

## CI/CD Agents

CI/CD workflow agents may act in `testes`, `subida-dev`, `review-dev`, and later
environment stages. Their job is to optimize repeatable checks, deployments,
rollback notes, smoke tests, and environment evidence while preserving the gates
above.

## Goal Runs

`/aih-goal` may import many tasks from Linear or a local source and run them
autonomously until a target stage such as `human-review`.

The goal runner must:

- discover a planned kanban/backlog by default, without requiring source flags,
- use `.aihaus/state/aih-goal.db` as the local operational cache and journal,
- register every discovered or imported task in the local kanban before
  planning,
- search the local kanban for related tasks before creating new local tasks,
- create readable evidence packages under `.aihaus/workflows/runs/`,
- evaluate planning before TDD for every task,
- persist planning questions and answers as structured contracts,
- continue ready tasks when other tasks are blocked,
- attach evidence before moving work to `human-review`,
- sync questions and evidence back to the external source when available.

The external kanban remains the source of truth for user-owned task fields.
When no external kanban is connected, the local kanban owns task title,
description, priority, status, planning contracts, and related-task links.
`aih-goal.db` stores workflow state, snapshots, planning contracts, gate events,
task links, and sync debt.

## Customization

Projects may replace the stage list or gate rules, but every workflow profile
must declare:

- stages in order,
- entry and exit gates,
- who or what may move work forward,
- when memory must be read,
- what evidence must be written,
- where blockers return.
