# Preset → Cohort Tuple Map

This annex is the contract that `/aih-effort` Phase-2 reads. Every preset is
expressed as **6** cohort tuples. The Distribution Matrix below is the
authoritative reference; per-preset sub-sections enumerate cohort tuples plus
any override lines.

**Source of truth for cohort membership + defaults:** `annexes/cohorts.md`
(M012 / ADR-M012-A). The matrix describes preset intent; per-preset sections
enumerate cohort tuples + grouped override lines.

**`balanced` reversibility contract:** applying `--preset balanced` on a clean
**v0.16.0-state** install MUST produce a zero-diff no-op commit. The override
lines in the `balanced` section pin every agent at its installed default so no
frontmatter flip occurs.

## Preset Distribution Matrix

| Cohort | `cost` | `balanced` | `high` |
|---|---|---|---|
| `:planner-binding` | (opus, high) | (opus, xhigh) | (opus, max) |
| `:planner` | (opus, high) | (opus, high) | (opus, max) |
| `:doer` | (sonnet, high) | (sonnet, high) | (opus, high) |
| `:verifier` | (haiku, medium) | (haiku, high) | (haiku, high) |
| `:adversarial-scout` | preset-immune | preset-immune | preset-immune |
| `:adversarial-review` | preset-immune | preset-immune | preset-immune |

**Footnotes:**

1. `:doer` is the only model-swap cohort: `cost`/`balanced` use `(sonnet, high)`;
   `high` escalates to `(opus, high)`. All other non-immune cohorts hold their
   fixed model across all 3 presets.
2. `sonnet`/`haiku` agents silently clip to `effort: high` when a preset would
   request `xhigh` or `max` — these effort levels are only meaningful on Opus
   (ADR-M012-A §4, M008 rule).
3. `:adversarial-scout` and `:adversarial-review` are preset-immune. Preset
   writes skip both cohorts via `is_preset_immune(cohort)` in
   `pkg/scripts/lib/restore-effort.sh`. Only explicit
   `/aih-effort --cohort :adversarial-* --model X --effort Y` (literal-word
   `adversarial` confirmation) or `--agent <member>` can mutate them.

---

## Preset: cost

**Intent:** minimum token spend. `:verifier` at `(haiku, medium)` effort; `:doer`
on sonnet; `:planner-binding` at `(opus, high)` — not escalated to `xhigh` in
this preset to reduce cost further.

| Cohort | Model | Effort |
|--------|-------|--------|
| `:planner-binding` | opus | high |
| `:planner` | opus | high |
| `:doer` | sonnet | high |
| `:verifier` | haiku | medium |
| `:adversarial-scout` | — | preset-immune |
| `:adversarial-review` | — | preset-immune |

---

## Preset: balanced

**Intent:** default post-v0.16.0. Matches cohort defaults byte-identically on
clean v0.16.0 install. `:planner-binding` escalated to `(opus, xhigh)` to keep
architect/planner/product-manager/roadmapper at maximum planning quality.

| Cohort | Model | Effort |
|--------|-------|--------|
| `:planner-binding` | opus | xhigh |
| `:planner` | opus | high |
| `:doer` | sonnet | high |
| `:verifier` | haiku | high |
| `:adversarial-scout` | — | preset-immune |
| `:adversarial-review` | — | preset-immune |

Applying `balanced` on a clean v0.16.0 install = zero frontmatter diff.

---

## Preset: high

**Intent:** maximum quality, accept higher token spend. `:doer` model swaps from
sonnet to opus. All planner cohorts escalate to `max`. `:verifier` stays on
haiku at `high` — artifact checks don't benefit from opus-level reasoning.

| Cohort | Model | Effort |
|--------|-------|--------|
| `:planner-binding` | opus | max |
| `:planner` | opus | max |
| `:doer` | opus | high |
| `:verifier` | haiku | high |
| `:adversarial-scout` | — | preset-immune |
| `:adversarial-review` | — | preset-immune |

**Note:** sonnet/haiku per-agent overrides within `:doer` or `:planner` clip to
`effort: high` regardless of preset request (clip is silent).
