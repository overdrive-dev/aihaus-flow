# aih-goal Linear intake

Linear is a source and sync target for `/aih-goal`. Local aihaus artifacts remain
the recoverable execution record during autonomous work.

### Import

Linear may be selected by explicit `--from-linear`, by `--source`, by workflow
memory, or by connector discovery. A flag is not required for normal operation.

When Linear is selected:

1. Resolve the selector to issues. Accept issue ids, URLs, project/view/team
   names, labels, or search text supported by the connected Linear capability.
2. For each issue, read title, identifier, URL, description, status, labels,
   assignee if available, comments, attachments, and linked resources.
3. Preserve raw source text in `source_snapshots` and `tasks/<id>.md` before
   summarizing.
4. Do not create labels, projects, custom views, or statuses unless the user
   explicitly asked for Linear workspace mutation.

### Planning gate behavior

The planning gate must use Linear issue content and comments as answers. If the
business rule, acceptance criteria, or validation method is already documented
in Linear, record it in `planning_answers`, mark the gate `READY-FOR-TDD`, and
do not ask the human to repeat it.

If information is missing:

1. Create a `planning_questions` row.
2. Write the missing question in business language.
3. Comment it on the Linear issue when the integration can write comments.
4. Set only that task to `blocked-to-planejamento`.
5. Continue other ready tasks.

### Evidence sync

Linear is the human kanban source of truth. Do not batch all issue moves and
comments at the end of a goal run.

After every evaluated stage for a Linear-backed task:

1. Resolve the current Linear team statuses from the workspace, not from stale
   local assumptions.
2. Move the issue to the matching workflow status when a matching status exists.
   Internal stages map semantically: `planejamento`, `tdd`,
   `review-execucao`, `testes`, `subida-dev`, `review-dev`, `human-review`,
   and `box-dev`.
3. Add an append-only comment when the stage produces evidence, asks a business
   question, skips a gate, or blocks. Keep routine comments short: stage,
   verdict, evidence pointer, next stage or blocker.
   For `review-dev`, include Playwright command/result and screenshot/trace/URL
   evidence when UI or user-flow behavior is affected. If skipped, state the
   backend-only reason.
4. Record an outbound `sync_events` row with a stable id before writing, and
   mark it synced only after the Linear update succeeds. Include that id in the
   comment body to avoid duplicate comments on resume.
5. If Linear write access is unavailable, keep executing locally only after
   recording pending sync debt in `sync_events`, `TASKS.md`, and the task file.

When a task reaches `human-review`, write a final Linear comment containing:

- business summary,
- branch/commit/PR,
- commands run and results,
- dev URL/environment,
- browser evidence paths and Playwright command/result when UI or flow work was
  validated,
- backend-only browser-skip reason when Playwright was not applicable,
- skipped gates with reasons,
- remaining known risks or none.

If Linear write access is unavailable, write the same package under the local
task file and add a sync blocker to the run manifest.

### Failure handling

Linear unavailable before import is a true blocker only when no local
`aih-goal.db`, local task file, or alternate connected source can be used.
Linear unavailable after local import is not a run blocker; continue locally and
record pending sync work.
