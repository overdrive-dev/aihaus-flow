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
- Artifact storage + consumption rules (IDs, pointers, scope, worktree paths): see `artifacts.md`.
- Routing — natural-language requests auto-route to sub-flows (no `/aih-*` typing required): see `routing.md`.
- Native fan-out workflows (autonomous only; qa/devops, runtime-authored): see `fan-out.md`.
- Parallel agents without conflicts (worktree isolation, Owned-Files sharding, single-writer): see `parallelism.md`.
- Business rules — the decision-autonomy contract agents decide from (schema, domains, gates): see `business-rules.md`.

## Composition

The **actions are the spine.** A natural-language request auto-routes to the
interactive sub-flow that fits it — planning (`aih-plan`), feature (`aih-feature`),
or bugfix (`aih-bugfix`) — which then drives the gated stages below, reading this
contract. The **kanban DB (`.aihaus/state/kanban.db`) is the default operational
substrate**: every action registers its task + gate events there, under
**single-writer** discipline (one writer per transition — ADR-004; safe when
parallel worktree agents each own disjoint files and merge back sequentially).
Native **`/goal`** supplies the autonomous loop for hands-off multi-turn
execution; the gates here plus the hooks (`role-guard`, `autonomy-guard`,
`tdd-guard`) enforce regardless of how a run is launched. **Native dynamic
workflows are reserved for autonomous fan-out only** (qa sweeps, devops deploy).
Rule: interactive scoping → sub-flow skill (can ask the requester); fully
autonomous fan-out → native JS workflow (no mid-run input).

## Default Stages

| Stage | Purpose | Exit Gate |
|---|---|---|
| backlog | Capture tasks that make sense to pick up later, even without detail. | Task has a clear enough title and short intent. |
| entendimento | Reach 100% understanding of the problem/feature before specifying. | No open question remains about what is being asked; ambiguity resolved with the requester. |
| planejamento | Clarify scope, business rules, user expectations, risks, and acceptance criteria. | Task-specific business-rule gaps are answered or explicitly waived; acceptance criteria are testable. |
| tdd | (dev 4.0–4.1) Map technical impact, then turn acceptance criteria into failing tests/contracts. | Impact surface mapped with no NEEDS-REVIEW rule pending; tests/contracts fail for the expected reason or strict-TDD-N/A recorded. |
| review-execucao | (dev 4.2–4.5) Implement in a local worktree, run local Playwright smoke for UI/flow, verify integration wiring, review readiness. | Code satisfies the contract; UI/flow has local Playwright evidence; connections wired; quality issues resolved. All offline/Docker. |
| testes | Run the full test pipeline in local Docker; capture breakage and regression risk. | Relevant automated checks pass in Docker-local; UI/flow records the homolog Playwright plan or blocks. |
| homolog | Promote to the staging/homologation environment and validate published behavior (full Playwright for UI/flow). | Published in homolog with passing Playwright/E2E evidence, or backend-only skip justified. **Online — devops only.** |
| human-review | Human validates the homolog result in business language and approves promotion. | Human accepts (approval to promote) or sends back with business-language feedback. |
| prod | After human approval, promote to production. | Production promotion executed, or the blocker is documented. **Online — devops only.** |
| box-dev | Holding box for accepted work before the next downstream process. | Project-specific. |

## Understanding Gate

`entendimento` precedes `planejamento`: reach 100% understanding of the
problem/feature before planning. No open question about *what* is being
asked may remain; resolve ambiguity with the requester.

## Development Sub-stages (4.0–4.5)

`tdd` and `review-execucao` carry the development detail, all **offline/Docker**:
4.0 technical impact and rule-conflict check · 4.1 failing
tests/contracts · 4.2 implementation in a local worktree · 4.3 local Playwright
**smoke** for UI/flow · 4.4 integration wiring · 4.5 readiness review. Full
Playwright E2E runs later at `homolog`.

## Online Boundary

`homolog` and `prod` are the **online** stages and may be driven only by a
profile holding the `devops` role (see `.aihaus/workflows/roles.md`);
`role-guard.sh` enforces it. Everything up to and including `testes` is
offline-local (Docker).

## Planning Gate

`planejamento` is blocking. A task must not move to `tdd` while business rules,
expected behavior, acceptance criteria, data assumptions, or user-facing outcomes
are unclear.

The planning gate must record task-specific business-rule gaps when needed.
Good blockers describe missing business meaning and expected behavior, not
implementation trivia or TUI option prompts.

If a task came from an external source such as Linear, the planning gate must
read the issue description, comments, links, and attached context before asking
anything. Do not ask the human to repeat answers already present in the source.

Every task that enters `planejamento` must be registered in the local kanban
under `.aihaus/state/kanban.db`. Planning questions and answers are workflow
contracts: record the task-specific business-rule gap before syncing it, record
the answer before using it, and keep the task in `planejamento` while any
planning question is open.

Do not merge blockers from several tasks into one planning question, Linear
comment, memory event, or kanban note. When a batch run discovers related gaps,
write one blocker per task and link related tasks explicitly.

## Gate Evaluation Contract

Every workflow gate is mandatory to evaluate, but not every gate is mandatory to
run. A gate may pass, skip, or block:

- `PASS` means the stage evidence is sufficient.
- `SKIPPED` means the agent evaluated the gate and found it not applicable; the
  skip reason must name why.
- `BLOCKED-TO-PLANNING` means a task-specific business expectation, rule,
  criterion, or validation method is missing or failed.
- `BLOCKED` means a true operational blocker prevents progress.

Task-specific blockers should not stop a larger run. Mark that task and
continue with other ready tasks.

## Homolog Review Gate

`homolog` uses Playwright/headless browser validation whenever the task has
visual, navigation, form, interaction, console, or user-flow impact.

Entering `homolog` is a dispatch edge. The workflow must immediately spawn
`workflow-dev-reviewer`; a Playwright plan written in `testes` or the local
smoke run in `review-execucao` does not replace full homolog validation.

Backend-only tasks may skip browser validation only when there is no direct
front-end, console, or environment-visible behavior to check. The reviewer must
say why the browser gate was not applicable.

`homolog` is not a parking state. A task that needs browser validation must run
Playwright immediately after the homolog environment is available. It must not
move to `human-review`, and should not remain sitting in `homolog`, without
one of:

- Playwright command/result plus screenshot, trace, or URL evidence,
- explicit backend-only skip reason,
- blocker stating why the browser gate cannot run.

If `homolog` finds a blocker, the task returns to `planejamento` with:

- the business expectation that failed,
- the observed behavior,
- the task-specific business-rule gap or decision needed from the human,
- links to evidence when available.

Avoid technical implementation language in the workflow handoff unless it is
needed for traceability.

## CI/CD Agents

CI/CD workflow agents may act in `testes`, `homolog`, and `prod` (the online
stages — devops only). Their job is to optimize repeatable checks, deployments,
rollback notes, smoke tests, and environment evidence while preserving the gates
above.

## Kanban Runs

A run — any sub-flow, or native `/goal` for hands-off multi-turn execution — may
import many tasks from Linear or a local source and advance them autonomously
until a target stage such as `human-review`.

The runner must:

- discover a planned kanban/backlog by default, without requiring source flags,
- use `.aihaus/state/kanban.db` as the local operational cache and journal,
- register every discovered or imported task in the local kanban before
  planning,
- search the local kanban for related tasks before creating new local tasks,
- create readable evidence packages under `.aihaus/workflows/runs/`,
- evaluate planning before TDD for every task,
- persist task-specific planning questions and answers as structured contracts,
- continue ready tasks when other tasks are blocked,
- spawn `workflow-dev-reviewer` immediately when a task enters `homolog`,
- attach evidence before moving work to `human-review`,
- require Playwright evidence before `human-review` for UI or user-flow work,
- sync questions and evidence back to the external source when available.

The external kanban remains the source of truth for user-owned task fields.
When no external kanban is connected, the local kanban owns task title,
description, priority, status, planning contracts, and related-task links.
`kanban.db` stores workflow state, snapshots, planning contracts, gate events,
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
