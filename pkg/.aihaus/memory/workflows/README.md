# Workflow Memory

This folder stores durable workflow knowledge for this repository.

Use it for:

- repository-specific rules of work,
- user preferences for how work moves,
- CI/CD and environment notes,
- recurring workflow gotchas,
- business-language reasons a task returned to planning.
- source-system preferences, such as how Linear issues encode planning answers.
- kanban source hints, such as the default Linear project/view or Notion database
  used by `/aih-goal`.

Do not use it for:

- transient run logs,
- generated state,
- database files,
- one-off command output.

Generated state belongs in `.aihaus/state/`. The workflow profile belongs in
`.aihaus/workflows/`.
