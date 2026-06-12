# aihaus Business-Rules Contract

The business-rules ledger is the **decision-autonomy substrate** — the premises an
agent decides from. The client defines the premises once; agents then derive every
covered decision from the ledger instead of re-asking. **BDD (Given/When/Then) is the
lingua franca**: a rule's scenarios are at once its unambiguous statement and the
failing tests the `tdd` stage needs.

## The autonomy law

| Situation | Agent behavior |
|-----------|----------------|
| Decision **covered** by a rule | Decide alone. Cite the rule ID when it affects behavior. Never ask. |
| **Gap** — business-visible behavior, no rule | Pause (the only TRUE blocker). Ask. The answer becomes a new rule. |
| **Conflict** — two rules disagree | Surface it. Ask which wins. Record the resolution as a rule. |
| **Pure mechanics** — no business-visible behavior | Decide alone. No rule required. |

Autonomy = contract coverage. The ledger self-extends by exactly the premises that
were genuinely open. "Silence" resolves by default: business-visible → gap (ask);
mechanics → decide. Mark known-free areas with an explicit *unconstrained* rule so
silence is never ambiguous.

## Residence

- **Source of truth** — the markdown ledger at `.aihaus/memory/workflows/business-rules.md`.
  Reviewable, git-diffable, incremental, like `decisions.md`.
- **Queryable index** — the aih-graph `Rule` node: `aihaus memory rule <id> --json`
  (rule → implementing code + tests) and `aihaus memory why <symbol> --json`
  (code → the rules it serves). The markdown is authoritative; the graph is a
  rebuildable index.

## Rule record schema

```
BR-<id>
  domain:        software | design | infra | security | data | compliance   # exactly one
  statement:     <one line, business language — WHAT must hold, never HOW>
  scenarios:     <one or more Given / When / Then>          # the testable core; feeds tdd
  status:        proposed | accepted | deprecated
  source:        <who defined the premise + when>           # provenance of the premise
  rationale:     <why this rule exists>
  links:
    implements:  [<symbol | file | test>]                   # aih-graph edges (rule ↔ code)
    relates:     [BR-<id> …]                                 # rule ↔ rule
    decided-by:  [ADR-<id> …]                                # rule ↔ ADR (cites, never owns)
  last-reviewed: <commit SHA>                                # staleness anchor
```

## Domains

Six domains, one namespace: `software` · `design` · `infra` · `security` · `data` ·
`compliance`. A rule names exactly one. Further domains are each a recorded decision.

## The three-ledger boundary (no bleed)

- **Business-rules ledger** — WHAT the system must do (behavior, invariants, domain rules).
- **ADRs (`decisions.md`)** — HOW / WHY we chose a technical approach.
- **`knowledge.md`** — reusable how-to / findings.

A rule may *cite* an ADR and vice-versa (that is a link) — ownership never overlaps.
Rule = behavior; ADR = approach; knowledge = technique.

## Gates

- **rule-gate** (`planejamento → tdd`) — a task may not enter `tdd` without ≥1 linked
  rule carrying testable BDD criteria. Extends `calibrate-guard.sh`.
- **flow-guard** (promotion boundary) — a code mutation reaching an online
  stage (`homolog` / `prod`) or production code is rejected unless it arrives through
  an active flow. Offline / dev scratch is free; nothing lands in prod without the
  contract. It is the sole gate at the online boundary.

## How agents consume it

1. Retrieve the **relevant slice** (aih-graph semantic) — never the whole ledger per turn.
2. Decide every covered question from it; **cite the rule** when behavior is affected.
3. On a gap / conflict: pause, ask the one question, **write the answer as a rule**, resume.
4. Never invent a rule to satisfy a gate — a vacuous rule has no testable scenario, so
   the `tdd` stage fails it anyway. Mechanical / no-behaviour-change work is exempt.
