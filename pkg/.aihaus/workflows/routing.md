# aihaus Routing — auto-route to sub-flows

The **sub-flows are the routable entries.** The user does **not** type `/aih-*`;
a natural-language request is **auto-routed** to the sub-flow that fits it
(planning / feature / bugfix), which then drives the gated stages in
[default.md](default.md) and writes the kanban DB. Native `/goal` wraps a run for
hands-off multi-turn execution. Slash commands remain an **optional override**
(escape hatch + determinism anchor), never required.

## Entry behavior

1. **Classify** the request (feature · bug · question · ops) and resolve the
   requester's **profile** (`.aihaus/.profile`).
2. **Route to the scoping sub-flow** — interactive: planning / bugfix / feature
   (these stay skills; see [default.md](default.md) § Composition).
3. **Drive gated execution** through the stages (`entendimento → planejamento →
   tdd → review-execucao → testes → homolog → human-review → prod`).

## Invariants

- **Entrada autônoma, progressão determinística.** The router chooses *where you
  enter*; it **never skips a gate**. High-blast actions (anything touching an
  online environment) echo the chosen route and confirm, even in autonomous mode.
- **The role scopes the menu.** A profile only routes to the sub-flows/stages its
  roles permit (see [roles.md](roles.md)); `role-guard.sh` enforces the online
  boundary. builder/dev/qa never reach the online stages.
- **Descriptions are the routing fuel.** The model auto-invokes by `description`.
  The sub-flows (`aih-plan`, `aih-feature`, `aih-bugfix`) and the `aih-quick`
  fast-path each carry a **routing-rich, non-overlapping** description so a request
  lands on the right one — feature work → `aih-feature`, a defect → `aih-bugfix`,
  "think/plan first" → `aih-plan`, a trivial well-understood change → `aih-quick`.
  Each sub-flow then drives the gated stages and writes the kanban DB. Keep the
  descriptions **distinct** (no two competing for the same intent) so routing
  stays reliable.

## Catalog hygiene (prerequisite)

Reliable routing requires a **lean, non-overlapping** catalog — competing or
duplicate descriptions cause mis-routes. Keep the routable set scoped to what the
active profile uses; the stage-workflow + its sub-flows are the spine.

## Native surfaces (plan mode + task list)

The written plan must feed **native Claude Code surfaces** so it shows in the GUI,
not only in files:

- **Native plan mode (`ExitPlanMode`)** — the interactive planning sub-flow
  (`planejamento`, main thread) surfaces its plan via plan mode → the GUI **Plan**
  panel + the native approve/reject gate. That approval IS the
  `planejamento → desenvolvimento` gate. The autonomous runner cannot call it
  (no mid-run input); only the interactive sub-flow does.
- **Native task list (`TaskCreate`/`TaskUpdate`)** — the runner projects one task
  per active coordination row, status synced from gate verdicts.

Both are **projections** of the durable plan / `kanban.db` (the source) — one
synced view across the plan file, the GUI Plan panel, and the task list (S10).
