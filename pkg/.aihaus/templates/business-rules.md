# Business Rules

This is your project's **living business-rules ledger** — the premises agents decide
from autonomously. It is incremental: every request that resolves a genuine open
premise adds or updates a rule here. The contract, schema, and gates are documented in
`.aihaus/workflows/business-rules.md`.

> **How an agent uses this file:** decide every contract-*covered* question from these
> rules (citing the rule ID when it affects behavior); return to a human only on a
> genuine *gap* or *conflict* — and the answer becomes a new rule below.

Each rule follows the schema (full spec in the contract):

```
### BR-<id> — <short title>
- **domain:** software | design | infra | security | data | compliance
- **statement:** <WHAT must hold, in business language — never HOW>
- **scenarios:**
  - Given <context>, When <action>, Then <expected outcome>
- **status:** proposed | accepted | deprecated
- **source:** <who defined this premise + when>
- **rationale:** <why this rule exists>
- **links:** implements:[<symbol|file|test>] · relates:[BR-…] · decided-by:[ADR-…]
- **last-reviewed:** <commit SHA>
```

`/aih-init` seeds an initial set from the codebase; rules accrete one answered premise
at a time. Keep rules in business language — implementation detail belongs in code,
ADRs, or `knowledge.md`, not here.

---

## Software

_Behavioral rules of the application: what it must do, validate, allow, or reject._

<!-- Example — delete once you add real rules:
### EXAMPLE — Orders require a positive total
- **domain:** software
- **statement:** An order cannot be submitted with a total of zero or less.
- **scenarios:**
  - Given a cart whose total is 0, When the user submits, Then submission is rejected with a "minimum order" message.
- **status:** accepted
- **source:** product owner, 2026-05-31
- **rationale:** Zero-value orders are always data-entry errors downstream.
- **links:** implements:[] · relates:[] · decided-by:[]
- **last-reviewed:** -
-->

## Design

_Rules for UX, layout, interaction, accessibility, and brand._

## Infrastructure

_Rules for deployment, environments, networking, scaling, and operations._

## Security

_Rules for authn/authz, secrets, threat surface, and safe defaults._

## Data

_Rules for retention, integrity, privacy, residency, and lifecycle._

## Compliance

_Rules for legal, regulatory, audit, and contractual obligations._
