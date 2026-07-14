# aihaus Map

Read `contracts/harness.md` first. Then choose one room; do not preload every
workflow, role, or ledger.

| Intent | Load |
|---|---|
| deliver a behavior change | `rooms/feature/CONTEXT.md` |
| diagnose and fix a defect | `rooms/bugfix/CONTEXT.md` |
| gather evidence before deciding | `rooms/research/CONTEXT.md` |
| small mechanical change | feature room, use its quick path |
| deploy, release, rollback, secrets | `contracts/ops-safety.md` plus the active room |
| review or completion claim | `contracts/adversarial-review.md` and `contracts/evidence.md` |

Load `conventions.md` whenever files or durable memory may change. Select one
primary role from `roles/`: orchestrator, planner, implementer, researcher,
reviewer, or verifier. Roles describe responsibility; rooms describe the work.

Project context is pulled on demand from `memory/project/`, the current task in
`memory/kanban/`, and the rebuildable graph. Never let an index answer override
the corresponding Markdown source.

If no row fits, use the smallest existing room and record the missing case in
the task. A new room requires repeated lab evidence, not a one-off request.
