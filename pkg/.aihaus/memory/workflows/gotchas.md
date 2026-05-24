# Workflow Gotchas

Use this file for recurring workflow failures that future `/aih-goal` runs
should avoid.

Good entries include:

- stale source-status assumptions,
- missing per-stage sync that caused final-only kanban updates,
- environment or CI delays that make evidence misleading,
- repeated ambiguity in business planning questions,
- local artifact drift between Markdown projections and external kanban state.

Each entry should explain the symptom, cause, and the next-run behavior that
avoids repeating it.
