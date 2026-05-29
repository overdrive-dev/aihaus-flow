# aihaus Routing — single autonomous entry

The stage-workflow ([default.md](default.md)) is the single spine. The user does
**not** type `/aih-*`; a natural-language request is **auto-routed** into the
workflow. Slash commands remain as an **optional override** (escape hatch +
determinism anchor), never required.

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
  Empty descriptions force `/`-typing; populated descriptions enable routing. The
  entry carries a routing-rich description; the interactive sub-flows are invoked
  by the stage-workflow, not auto-triggered standalone.

## Catalog hygiene (prerequisite)

Reliable routing requires a **lean, non-overlapping** catalog — competing or
duplicate descriptions cause mis-routes. Keep the routable set scoped to what the
active profile uses; the stage-workflow + its sub-flows are the spine.
