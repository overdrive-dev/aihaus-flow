# Cohort Taxonomy — 43 Agents → 5 Role Cohorts

This annex is the single source of truth for cohort membership consumed by
`/aih-calibrate` (Phase-2 preset filter, Phase-4 sidecar write) and by the
restore path in `pkg/scripts/lib/restore-calibration.sh` + `install.ps1`.
Membership lives ONLY here — no `cohort:` frontmatter field per agent
(Q-1 resolution — keeps the sync surface minimal and avoids 43 smoke-test
assertions). See ADR-M010-A (+ M010.1 amendment) for the formal cohort
semantics, and ADR-M008-C for the preset-immunity contract the
`:adversarial` cohort formalizes.

A **cohort** is a joint `(model, effort)` tier aligned to role. Every
cohort declares a **default model** (the tier most members should run on
given each model's documented strengths per Anthropic's models overview);
individual members may carry an override set in their frontmatter +
recorded as an override line in `annexes/presets.md`. The 5 cohorts below
cover all 43 agents. Calibration presets express the intended role-tier
as cohort tuples; preset apply iterates cohorts and mutates both `model:`
and `effort:` per member atomically.

## Per-cohort default models

Per Anthropic's models overview (Opus 4.7 = "most capable for complex
reasoning and agentic coding"; Sonnet 4.6 = "best combination of speed
and intelligence"; Haiku 4.5 = "fastest with near-frontier intelligence"):

| Cohort | Default model | Default effort | Rationale |
|--------|--------------|----------------|-----------|
| `:planner` | opus | high (xhigh for binding-4) | Complex reasoning + agentic coding; plans gate downstream work. |
| `:doer` | sonnet | high | Daily-driver speed-intelligence balance for code/doc writes. |
| `:verifier` | haiku | high (medium in `cost-optimized`) | Near-frontier intelligence suffices for boolean artifact checks; 5× cheaper on input than opus. |
| `:investigator` | sonnet | high | Hypothesis-driven investigation of runtime/behavioral state — not pure artifact verification. |
| `:adversarial` | opus | high (max for plan-checker + contrarian) | Binding review gate; preset-immune per ADR-M008-C (extended M010 via ADR-M010-A). |

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
actions (e.g. `notion-sync`). Default tier shifted from opus → sonnet in
v0.15.0 (M010.1 amendment) — the cost trade most users want is "run my
`:doer` cohort on sonnet" in one flag. Sonnet 4.6 handles the full daily
implementation surface; escalate to opus via `--agent <name> --model opus
--effort <e>` for atypical code-gen work.

### `:verifier` (8 agents)

Read-only assessments over existing artifacts — evidence + confidence
levels, no code mutation. Default tier shifted from opus → haiku in
v0.15.0 (M010.1 amendment) per Anthropic's "near-frontier intelligence"
framing — boolean artifact checks (paths exist, frontmatter keys match,
data flows wire up) don't need opus-grade reasoning, and the cost savings
are substantial at scale. Two members override to sonnet:
**`nyquist-auditor`** (writes + iteratively debugs minimal behavioral
tests; code-gen surface needs sonnet) and **`ui-auditor`** (6-pillar
visual audit needs vision + aesthetic judgment).

### `:investigator` (3 agents) — NEW in M010.1

Hypothesis-driven investigation of runtime or behavioral state — distinct
from `:verifier` which checks static artifacts. Default tier `(sonnet, high)`:
- **`debugger`** — uses scientific method (hypothesize → test → observe →
  refine). Needs reasoning about causation, not just artifact checks.
- **`debug-session-manager`** — orchestrates multi-cycle debug checkpoint
  loops. Judgment about when to escalate, when to retry.
- **`user-profiler`** — scored analysis of developer behavior across 8
  dimensions with confidence levels. Multi-axis synthesis, not artifact
  grep.

Split from `:verifier` in v0.15.0 (ADR-M010-A M010.1 amendment) because
investigation-class agents were mismatched to haiku-default verifier tier
— their work is closer to `:planner` reasoning than artifact checking,
but their outputs feed `:doer` work (debug diagnoses inform fixes), so
sonnet-default sits between the two.

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

Model column reflects the **current shipped default** after the v0.15.0
distribution shift (10 agents moved from opus to sonnet or haiku per the
cohort defaults above; overrides retained for 2 `:verifier` members).

| # | Agent | Cohort | Model | Effort |
|---|-------|--------|-------|--------|
| 1  | advisor-researcher       | :planner      | sonnet | high  |
| 2  | ai-researcher            | :planner      | opus   | high  |
| 3  | analyst                  | :planner      | opus   | high  |
| 4  | architect                | :planner      | opus   | xhigh |
| 5  | assumptions-analyzer     | :planner      | sonnet | high  |
| 6  | brainstorm-synthesizer   | :planner      | opus   | high  |
| 7  | code-fixer               | :doer         | sonnet | high  |
| 8  | code-reviewer            | :adversarial  | opus   | high  |
| 9  | codebase-mapper          | :doer         | sonnet | high  |
| 10 | contrarian               | :adversarial  | opus   | max   |
| 11 | debug-session-manager    | :investigator | sonnet | high  |
| 12 | debugger                 | :investigator | sonnet | high  |
| 13 | doc-verifier             | :verifier     | haiku  | high  |
| 14 | doc-writer               | :doer         | sonnet | high  |
| 15 | domain-researcher        | :planner      | opus   | high  |
| 16 | eval-auditor             | :verifier     | haiku  | high  |
| 17 | eval-planner             | :planner      | opus   | high  |
| 18 | executor                 | :doer         | sonnet | high  |
| 19 | framework-selector       | :planner      | sonnet | high  |
| 20 | frontend-dev             | :doer         | sonnet | high  |
| 21 | implementer              | :doer         | sonnet | high  |
| 22 | integration-checker      | :verifier     | haiku  | high  |
| 23 | intel-updater            | :doer         | sonnet | high  |
| 24 | notion-sync              | :doer         | sonnet | high  |
| 25 | nyquist-auditor          | :verifier     | sonnet | high  |
| 26 | pattern-mapper           | :doer         | sonnet | high  |
| 27 | phase-researcher         | :planner      | opus   | high  |
| 28 | plan-checker             | :adversarial  | opus   | max   |
| 29 | planner                  | :planner      | opus   | xhigh |
| 30 | product-manager          | :planner      | opus   | xhigh |
| 31 | project-analyst          | :doer         | sonnet | high  |
| 32 | project-researcher       | :planner      | opus   | high  |
| 33 | research-synthesizer     | :planner      | sonnet | high  |
| 34 | reviewer                 | :adversarial  | opus   | high  |
| 35 | roadmapper               | :planner      | opus   | xhigh |
| 36 | security-auditor         | :verifier     | haiku  | high  |
| 37 | test-writer              | :doer         | sonnet | high  |
| 38 | ui-auditor               | :verifier     | sonnet | high  |
| 39 | ui-checker               | :verifier     | haiku  | high  |
| 40 | ui-researcher            | :planner      | opus   | high  |
| 41 | user-profiler            | :investigator | sonnet | high  |
| 42 | ux-designer              | :planner      | sonnet | high  |
| 43 | verifier                 | :verifier     | haiku  | high  |

**Totals:** :planner = 17 · :doer = 11 · :verifier = 8 · :investigator = 3 · :adversarial = 4 · Sum = 43 ✓

**Model distribution (shipped v0.15.0):** opus = 16 · sonnet = 21 · haiku = 6 · Sum = 43 ✓. Adversarial max-effort unchanged (plan-checker + contrarian at `max`). 16 agents moved from opus in v0.14.0 → sonnet/haiku in v0.15.0 per cohort defaults (8 `:doer` opus→sonnet; 4 `:verifier` opus→haiku; 2 `:verifier` opus→sonnet override; 2 `:investigator` opus→sonnet). Additionally 2 `:verifier` agents moved sonnet→haiku (`doc-verifier`, `ui-checker`).

## Edge-case placements (D-1 + M010.1 resolution)

Agents that diverge from seed-context sketches; evidence from frontmatter
descriptions locks the placement:

- **`advisor-researcher` → `:planner`** — "Researches a single gray-area
  decision and returns a structured comparison table. Spawned by
  discussion workflows when trade-off analysis is needed before locking a
  decision." Research-upstream-of-plan role.
- **`assumptions-analyzer` → `:planner`** (not `:doer`) — "Spawned before
  planning to ensure decisions are grounded in what the code actually
  reveals." Upstream of plan, not a doer.
- **`brainstorm-synthesizer` → `:planner`** — "Fan-in synthesizer for
  `/aih-brainstorm`. Produces BRIEF.md with synthesized findings... and a
  suggested next command." Produces upstream-of-plan input.
- **`user-profiler` → `:investigator`** (M010.1 — moved from `:verifier`) —
  "Analyzes developer behavior across 8 dimensions... Produces a scored
  profile with confidence levels and evidence." Multi-axis synthesis
  matches `:investigator` shape better than artifact-verification.
- **`debugger` + `debug-session-manager` → `:investigator`** (M010.1 —
  moved from `:verifier`) — hypothesis-driven investigation of runtime
  state, not static artifact checks. Default sonnet tier per cohort
  default.

Flag annotations (`*` for deviation, `!` for adversarial immunity) are
analyst-brief-only — they do NOT appear in the Cohort column above.
Parsers (bash awk, PowerShell regex) consume the clean 5-column layout
and defensively strip trailing non-cohort characters for forward
compatibility.
