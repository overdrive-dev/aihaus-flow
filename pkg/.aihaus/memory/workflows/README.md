# Workflow Memory

This folder stores durable workflow knowledge for this repository.

Use it for:

- repository-specific rules of work,
- user preferences for how work moves,
- CI/CD and environment notes,
- recurring workflow gotchas,
- business-language reasons a task returned to planning.
- source-system preferences, such as how external cards encode planning answers.
- kanban source hints, such as the default project, board, view, or database
  used by the workflow.
- conventions for planning question/answer contracts and related-task links in
  the local kanban.

Starter files:

- `environment.md` - environment, CI/CD, deployment, and source-system defaults.
- `user-preferences.md` - durable user preferences for workflow movement.
- `rules.md` - repository-specific workflow rules that agents must follow.
- `gotchas.md` - recurring workflow mistakes and how future runs avoid them.

Do not use it for:

- transient run logs,
- generated state,
- database files,
- one-off command output.

Generated state belongs in `.aihaus/state/`. The workflow profile belongs in
`.aihaus/workflows/`.

Agents should not write this directory directly during a run. They should return
candidate workflow-memory findings in their report, or emit per-agent memory to
`.aihaus/memory/agents/<agent-name>.md`; the memory-promotion phase promotes
durable workflow facts.
