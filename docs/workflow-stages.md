# aihaus-flow Workflow Stages

This document explains the stages aihaus-flow uses to move work from an idea or
backlog item to a validated handoff. It is for someone downloading the repository
who needs to understand what each stage is for before running the workflow.

## The Short Version

aihaus-flow is a gated workflow. Each stage must either pass, skip with a clear
reason, or block with a useful question. The system should not silently drift
forward just because code changed.

The default kanban path is:

```text
backlog -> planejamento -> tdd -> review-execucao -> testes -> subida-dev -> review-dev -> human-review -> box-dev
```

External tools such as Linear can mirror these stages, but the workflow rules
are defined by aihaus-flow and the repository-local workflow profile.

## Stage Reference

| Stage | Objective | Exit Evidence |
|---|---|---|
| `backlog` | Capture work that should be revisited later. | A short title and intent are clear enough to triage. |
| `planejamento` | Clarify business rules, expected behavior, risks, and acceptance criteria. | Questions are answered or explicitly waived; validation is testable. |
| `tdd` | Convert acceptance criteria into failing tests or equivalent verification contracts. | The expected failure or explicit non-TDD reason is recorded. |
| `review-execucao` | Review implementation before broader tests and deployment. | The implementation satisfies the contract and obvious quality issues are resolved. |
| `testes` | Run automated checks and identify missing coverage before dev promotion. | Relevant checks pass; UI or flow work has a Playwright dev-review plan. |
| `subida-dev` | Publish the change to the development environment. | The dev environment contains the change or the deploy blocker is documented. |
| `review-dev` | Validate the published dev behavior. | Playwright/headless browser evidence passes for UI or flow work, or the task is explicitly backend-only. |
| `human-review` | Package the result for a human decision. | Business result, test evidence, dev evidence, and browser evidence or skip reason are present. |
| `box-dev` | Hold accepted dev work before the next downstream process. | Project-specific release or staging policy is satisfied. |

## Gate Outcomes

Every stage produces one of these outcomes:

- `PASS`: the evidence is sufficient to move forward.
- `SKIPPED`: the gate was evaluated and is not applicable; the reason is written.
- `BLOCKED-TO-PLANNING`: a task-specific business rule, expectation, or validation method is missing or failed.
- `BLOCKED`: an operational dependency prevents progress.

Task-specific blockers should not stop the whole run. The blocked task returns
to planning while other ready tasks continue.

Planning blockers synced to Linear or a local kanban should read like missing
business rules, not TUI questions. Keep one blocker per task. If a batch run
finds the same gap in several tasks, duplicate the task-specific blocker and
link related tasks instead of writing one mixed question.

## Playwright Rule

For UI, navigation, forms, interaction, console-observable behavior, or user
flows, `review-dev` must run Playwright or another headless browser check after
the change is available in the dev environment.

The task cannot move to `human-review`, and should not sit in `review-dev`, with
browser validation still pending. It needs one of:

- a Playwright command result plus screenshot, trace, video, console log, or dev
  URL evidence,
- an explicit backend-only skip reason,
- a blocker explaining why the browser gate could not run.

## Memory And Sync

Run artifacts are useful evidence, but they are not durable memory by
themselves. Reusable decisions, gotchas, workflow preferences, and agent lessons
must be promoted to repository memory before a goal closes.

When an external kanban is connected, aihaus-flow syncs stage changes and
evidence comments step by step. A final summary comment is still useful, but it
does not replace per-stage sync.

## What To Read Next

- Start with `/aih-help` after installation to see available commands.
- Run `/aih-init` in a target repository to create project context.
- Use `/aih-goal` for planned kanban work that should move through the staged
  workflow autonomously.
