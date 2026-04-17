# Cohort Taxonomy — 43 Agents → 4 Role Cohorts

This annex is the single source of truth for cohort membership consumed by
`/aih-calibrate` (Phase-2 preset filter, Phase-4 sidecar write) and by the
restore path in `pkg/scripts/lib/restore-calibration.sh` + `install.ps1`.
Membership lives ONLY here — no `cohort:` frontmatter field per agent
(Q-1 resolution — keeps the sync surface minimal and avoids 43 smoke-test
assertions). See ADR-M010-A for the formal cohort semantics, and
ADR-M008-C for the preset-immunity contract the `:adversarial` cohort
formalizes.

A **cohort** is a joint `(model, effort)` tier aligned to role. The 4
cohorts below cover all 43 agents. Calibration presets express the
intended role-tier as cohort tuples; preset apply iterates cohorts and
mutates both `model:` and `effort:` per member atomically.

## Cohorts

### `:planner` (17 agents)

Upstream-of-decision research + structured planning. Produce BRIEFs, PRDs,
architectures, plans, research synthesis — artifacts that feed later
cohorts. The 4 binding planners (`architect`, `planner`, `product-manager`,
`roadmapper`) carry `(opus, xhigh)` by default because their outputs gate
every downstream story; the rest default to `(opus, high)` or
`(sonnet, high)`. `assumptions-analyzer` is placed here (not `:doer`) per
evidence — its frontmatter says "spawned before planning to ensure
decisions are grounded in what the code actually reveals".
`advisor-researcher` + `brainstorm-synthesizer` are placed here because
both produce upstream-of-plan artifacts (research comparisons, synthesis
briefs).

### `:doer` (11 agents)

Forward-edit implementation — writes code, tests, docs; performs network
actions (e.g. `notion-sync`). These are the agents whose default hit the
Opus 4.7 `xhigh` tier pre-M010; the cost trade most users want is "run my
`:doer` cohort on sonnet" in one flag. 3 members ship at `(sonnet, high)`
on the v0.13.0 baseline (`notion-sync`, `pattern-mapper`, `test-writer`);
the other 8 at `(opus, high)`.

### `:verifier` (11 agents)

Read-only assessments over existing artifacts — evidence + confidence
levels, no code mutation. `user-profiler` is placed here (not `:doer`) per
evidence — "scored profile with confidence levels and evidence. Read-only
analysis". 3 sonnet members (`doc-verifier`, `ui-checker`,
`user-profiler`); 8 opus members. Default effort `high`; presets may
downgrade joint to `(sonnet, medium)` for maximum cost savings.

### `:adversarial` (4 agents) — preset-immune

Binding review gate — members produce findings that are binding on
downstream merge/release decisions. **No `--preset <name>` invocation
mutates any member of this cohort.** Members: `plan-checker`, `contrarian`,
`reviewer`, `code-reviewer`. `plan-checker` + `contrarian` at
`(opus, max)`; `reviewer` + `code-reviewer` at `(opus, high)`. The cohort
is non-uniform by design (2 tiers shipping) — this is expected, not drift,
and the v1→v2 sidecar migration path exempts `:adversarial` from the
loud `!!` warning on non-uniformity.

**M010 extends preset-immunity from 2 agents (`plan-checker`,
`contrarian` per ADR-M008-C) to 4 agents (the full `:adversarial` cohort)
via ADR-M010-A** — `reviewer` + `code-reviewer` produce adversarial
findings of the same shape as `plan-checker` + `contrarian`. Only an
explicit `--cohort :adversarial --model X --effort Y` (both axes required
+ literal-word `adversarial` confirmation) or `--agent <adversarial-member>`
invocation is allowed to mutate a member.

## Membership (43 agents)

| # | Agent | Cohort | Model | Effort |
|---|-------|--------|-------|--------|
| 1  | advisor-researcher       | :planner      | sonnet | high  |
| 2  | ai-researcher            | :planner      | opus   | high  |
| 3  | analyst                  | :planner      | opus   | high  |
| 4  | architect                | :planner      | opus   | xhigh |
| 5  | assumptions-analyzer     | :planner      | sonnet | high  |
| 6  | brainstorm-synthesizer   | :planner      | opus   | high  |
| 7  | code-fixer               | :doer         | opus   | high  |
| 8  | code-reviewer            | :adversarial  | opus   | high  |
| 9  | codebase-mapper          | :doer         | opus   | high  |
| 10 | contrarian               | :adversarial  | opus   | max   |
| 11 | debug-session-manager    | :verifier     | opus   | high  |
| 12 | debugger                 | :verifier     | opus   | high  |
| 13 | doc-verifier             | :verifier     | sonnet | high  |
| 14 | doc-writer               | :doer         | opus   | high  |
| 15 | domain-researcher        | :planner      | opus   | high  |
| 16 | eval-auditor             | :verifier     | opus   | high  |
| 17 | eval-planner             | :planner      | opus   | high  |
| 18 | executor                 | :doer         | opus   | high  |
| 19 | framework-selector       | :planner      | sonnet | high  |
| 20 | frontend-dev             | :doer         | opus   | high  |
| 21 | implementer              | :doer         | opus   | high  |
| 22 | integration-checker      | :verifier     | opus   | high  |
| 23 | intel-updater            | :doer         | opus   | high  |
| 24 | notion-sync              | :doer         | sonnet | high  |
| 25 | nyquist-auditor          | :verifier     | opus   | high  |
| 26 | pattern-mapper           | :doer         | sonnet | high  |
| 27 | phase-researcher         | :planner      | opus   | high  |
| 28 | plan-checker             | :adversarial  | opus   | max   |
| 29 | planner                  | :planner      | opus   | xhigh |
| 30 | product-manager          | :planner      | opus   | xhigh |
| 31 | project-analyst          | :doer         | opus   | high  |
| 32 | project-researcher       | :planner      | opus   | high  |
| 33 | research-synthesizer     | :planner      | sonnet | high  |
| 34 | reviewer                 | :adversarial  | opus   | high  |
| 35 | roadmapper               | :planner      | opus   | xhigh |
| 36 | security-auditor         | :verifier     | opus   | high  |
| 37 | test-writer              | :doer         | sonnet | high  |
| 38 | ui-auditor               | :verifier     | opus   | high  |
| 39 | ui-checker               | :verifier     | sonnet | high  |
| 40 | ui-researcher            | :planner      | opus   | high  |
| 41 | user-profiler            | :verifier     | sonnet | high  |
| 42 | ux-designer              | :planner      | sonnet | high  |
| 43 | verifier                 | :verifier     | opus   | high  |

**Totals:** :planner = 17 · :doer = 11 · :verifier = 11 · :adversarial = 4 · Sum = 43 ✓

## Edge-case placements (D-1 resolution)

Four agents diverge from the seed-context sketch; evidence from their
frontmatter descriptions locks the placement:

- **`advisor-researcher` → `:planner`** — "Researches a single gray-area
  decision and returns a structured comparison table. Spawned by
  discussion workflows when trade-off analysis is needed before locking a
  decision." Read-only + `WebSearch`/`WebFetch` reinforces
  research-upstream-of-plan role.
- **`user-profiler` → `:verifier`** — "Analyzes developer behavior across
  8 dimensions... Produces a scored profile with confidence levels and
  evidence. Read-only analysis." Assessments-with-evidence is
  verifier-shaped.
- **`assumptions-analyzer` → `:planner`** (moved from seed-context sketch
  which placed it in `:doer`) — "Spawned before planning to ensure
  decisions are grounded in what the code actually reveals." Upstream of
  plan, not a doer.
- **`brainstorm-synthesizer` → `:planner`** — "Fan-in synthesizer for
  `/aih-brainstorm`. Produces BRIEF.md with synthesized findings...
  and a suggested next command." Produces upstream-of-plan input.

Flag annotations (`*` for deviation, `!` for adversarial immunity) are
analyst-brief-only — they do NOT appear in the Cohort column above.
Parsers (bash awk, PowerShell regex) consume the clean 5-column layout
and defensively strip trailing non-cohort characters for forward
compatibility.
