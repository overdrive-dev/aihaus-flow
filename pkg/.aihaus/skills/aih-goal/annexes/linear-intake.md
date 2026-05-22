# aih-goal Linear intake

Linear is a source and sync target for `/aih-goal`. Local aihaus artifacts remain
the recoverable source of truth during execution.

### Import

When `--from-linear <selector>` is present:

1. Resolve the selector to issues. Accept issue ids, URLs, project/view/team
   names, labels, or search text supported by the connected Linear capability.
2. For each issue, read title, identifier, URL, description, status, labels,
   assignee if available, comments, attachments, and linked resources.
3. Preserve raw source text in `tasks/<id>.md` before summarizing.
4. Do not create labels, projects, custom views, or statuses unless the user
   explicitly asked for Linear workspace mutation.

### Planning gate behavior

The planning gate must use Linear issue content and comments as answers. If the
business rule, acceptance criteria, or validation method is already documented in
Linear, mark the gate `READY-FOR-TDD`; do not ask the human to repeat it.

If information is missing:

1. Write the missing question in business language.
2. Comment it on the Linear issue when the integration can write comments.
3. Set only that task to `blocked-to-planejamento`.
4. Continue other ready tasks.

### Evidence sync

When a task reaches `human-review`, write a Linear comment containing:

- business summary,
- branch/commit/PR,
- commands run and results,
- dev URL/environment,
- browser evidence paths when Playwright was used,
- skipped gates with reasons,
- remaining known risks or none.

If Linear write access is unavailable, write the same package under the local
task file and add a sync blocker to the run manifest.

### Failure handling

Linear unavailable before import is a true blocker unless another source was
provided. Linear unavailable after local import is not a run blocker; continue
locally and record pending sync work.
