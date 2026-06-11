# aihaus Harness

One law, three memory tiers, one gate grammar (ADR-260611-A/B). If this
condensation disagrees with `.aihaus/protocols/business-rules.md`,
that file is canonical.

## Autonomy law — decide from `.aihaus/memory/workflows/business-rules.md`

- **covered** — a rule covers the decision: decide alone; cite the BR-id
  when behavior is affected. Never ask.
- **gap** — business-visible behavior with no rule: the only TRUE blocker.
  You ask once; the answer becomes a rule.
- **conflict** — two rules disagree: surface it, ask which wins, record
  the resolution as a rule.
- **mechanics** — no business-visible behavior: decide alone; no rule,
  no citation.

Autonomy = contract coverage. No option menus for covered decisions.

## Memory tiers

- **A — code/concept graph** (rebuildable index): `aihaus memory
  query|context|callers|impact --json`; `rule <BR-id>` and `why <ref>`
  arrive in v0.42.
- **B — project memory** (source of truth): business-rules ledger (apex)
  + `decisions.md`, `knowledge.md`, `project.md`, `.aihaus/memory/**`,
  kanban DB.
- **C — global user preferences**: `~/.aihaus/memory/user/preferences.md`,
  written only via `aihaus prefs add`.

Precedence: repo overrides global — tier-B project rules beat tier-C user
preferences on conflict. Tier A never decides; it only retrieves.

## Gates

Each stage gate (entendimento, planejamento, tdd, review-execucao, testes,
homolog, human-review, prod) records one verdict:
`PASS|SKIPPED|BLOCKED-TO-PLANNING|BLOCKED`, plus warn-only `rules_cited` —
comma-separated `BR-F?[0-9]+ | GAP:pq-<id> | MECHANICS`.

<!-- MAIN-SESSION-ONLY -->
Routing: treat each fresh top-level intent as a routing event — spawn
`workflow-orchestrator` first and follow its decision, unless already inside
an active workflow, the user opts out, or the ask is trivial.
<!-- /MAIN-SESSION-ONLY -->
