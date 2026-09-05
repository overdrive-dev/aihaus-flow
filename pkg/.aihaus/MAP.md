# aihaus Map

Read `contracts/harness.md` first. Then choose one room; do not preload every
workflow, role, or ledger.

| Intent | Load |
|---|---|
| initialize or refresh project memory | REFRESH.md, contracts/project-bootstrap.md, and the research room |
| deliver a behavior change | `rooms/feature/CONTEXT.md` |
| diagnose and fix a defect | `rooms/bugfix/CONTEXT.md` |
| gather evidence before deciding | `rooms/research/CONTEXT.md` |
| small mechanical change | feature room, use its quick path |
| deploy, release, rollback, secrets | `contracts/ops-safety.md` plus the active room |
| review or completion claim | `contracts/adversarial-review.md` and `contracts/evidence.md` |

Load `conventions.md` whenever files or durable memory may change. Select one
primary role from `roles/`: orchestrator, planner, implementer, researcher,
reviewer, or verifier. Roles describe responsibility; rooms describe the work.

Follow the harness context check before substantive work and on resumption.
`memory/project/README.md` maps questions to memory pages; retrieve only relevant
entries and verify their cited sources. The current Markdown task in
`memory/kanban/` carries scope, rule/decision references, gaps, and evidence.

If no row fits, use the smallest existing room and record the missing case in
the task. A new room requires repeated lab evidence, not a one-off request.
