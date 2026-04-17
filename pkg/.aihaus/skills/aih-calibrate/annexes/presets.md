# Preset → Cohort Tuple Map

This annex is the contract that `/aih-calibrate` Phase-2 reads. Every preset
is expressed as **5** cohort tuples + a permission-mode row + an optional
`### Overrides` block listing grouped `(agents → (model, effort))` lines
for agents whose baseline deviates from the cohort default.

**Source of truth for cohort membership + defaults:** `annexes/cohorts.md`
(M010/S01 + M010.1 amendment / ADR-M010-A). The top-level matrix below
describes preset intent; the per-preset sub-sections enumerate cohort
tuples + grouped override lines.

**`balanced` reversibility contract (AC-07, v0.15.0-relative):** applying
`--preset balanced` on a clean **v0.15.0-state** install MUST produce a
zero-diff no-op commit. The override lines in the `balanced` section pin
every sonnet/haiku override + every binding planner at `(opus, xhigh)` so
no frontmatter flip occurs. **AC-07 does NOT apply to v0.14.0 state** —
the v0.15.0 cohort-default shift intentionally mutates 16 agents when
`balanced` is applied over v0.14.0 (8 `:doer` opus→sonnet, 4 `:verifier`
opus→haiku, 2 `:verifier` opus→sonnet override, 2 `:investigator`
opus→sonnet; plus 2 `:verifier` sonnet→haiku).

## Preset Distribution Matrix

| Preset | :planner | :doer | :verifier | :investigator | :adversarial | Permission mode |
|--------|----------|-------|-----------|---------------|--------------|-----------------|
| `cost-optimized` | (opus, high) | (sonnet, high) | (haiku, medium) | (sonnet, medium) | preset-immune | bypassPermissions |
| `balanced` (default post-v0.15.0) | (opus, high) | (sonnet, high) | (haiku, high) | (sonnet, high) | preset-immune | bypassPermissions |
| `quality-first` | (opus, max) | (opus, max) | (opus, xhigh) | (opus, max) | preset-immune | bypassPermissions |
| `auto-mode-safe` | (opus, high) | (sonnet, high) | (haiku, high) | (sonnet, high) | preset-immune | **auto** |

**Notes:**

1. `cost-optimized` further downgrades `:verifier` + `:investigator` to
   `medium` effort on top of the new cohort defaults — maximum cost
   reduction. `:doer` stays at cohort default `(sonnet, high)` because
   `medium` is under-powered for code-gen.
2. `balanced` = shipped default post-v0.15.0; matches cohort defaults
   byte-identically on clean v0.15.0 install. Overrides pin atypical
   members (binding planners, sonnet-overrides in `:verifier`).
3. `quality-first` is aggressive. Claude Code docs warn `max` is "prone to
   overthinking"; use only for short-duration quality-critical milestones.
   "Sonnet falls back to high" (M008 rule) — sonnet agents stay at
   `(sonnet, high)` via overrides. Haiku likewise capped at `high`.
4. `auto-mode-safe` effort + model distribution identical to `balanced`;
   only the permission surface changes. See `annexes/permission-modes.md`
   for the caveat matrix printed before the full-word `auto-mode`
   confirmation.

## Preset-Immune Agents (ADR-M010-A — 4 members)

Regardless of preset, the `:adversarial` cohort is **preset-immune**:
`plan-checker`, `contrarian`, `reviewer`, `code-reviewer` retain their
baseline `(model, effort)`. Only explicit
`/aih-calibrate --cohort :adversarial --model X --effort Y` (both axes
required + literal-word `adversarial` confirmation) or
`/aih-calibrate --agent <adversarial-member> --model X --effort Y` can
mutate them.

- `plan-checker` — baseline `(opus, max)`. Every `/aih-plan` +
  `/aih-milestone` adversarial gate depends on this agent producing
  real findings at depth.
- `contrarian` — baseline `(opus, max)`. Produces minority-view findings
  against other agents' outputs.
- `reviewer` — baseline `(opus, high)`. Post-milestone reviewer of
  completed work; produces adversarial findings of the same shape.
- `code-reviewer` — baseline `(opus, high)`. Adversarial per-file review;
  ADR-002 Adversarial Contract target.

M010 extended ADR-M008-C's 2-agent immunity list to the full 4-agent
`:adversarial` cohort. Semantics identical (preset runs skip this cohort
at write time); the enumeration grew from hardcoded name-list to
cohort-lookup against `cohorts.md`.

---

## Preset: cost-optimized

**Intent:** minimum token spend across the fleet. `:verifier` +
`:investigator` at `medium` effort; doers on sonnet; verifiers on haiku
(artifact checks don't need opus).

| Cohort | Model | Effort | Notes |
|--------|-------|--------|-------|
| `:planner` | opus | high | binding planners → overrides (opus, xhigh) |
| `:doer` | sonnet | high | 3 sonnet agents (notion-sync, pattern-mapper, test-writer) already at cohort default — no override needed |
| `:verifier` | haiku | medium | nyquist-auditor + ui-auditor → overrides (sonnet, medium) |
| `:investigator` | sonnet | medium | |
| `:adversarial` | — | — | preset-immune |

Permission mode: `bypassPermissions`.

### Overrides

- `architect, planner, product-manager, roadmapper → (opus, xhigh)` — binding planners preserved
- `advisor-researcher, assumptions-analyzer, framework-selector, research-synthesizer, ux-designer → (sonnet, high)` — 5 sonnet-planners preserved at (sonnet, high)
- `nyquist-auditor, ui-auditor → (sonnet, medium)` — verifier-cohort overrides (code-gen + vision)

(3 grouped lines / 11 agent entries.)

---

## Preset: balanced

**Intent:** default post-v0.15.0. Matches cohort defaults byte-identically
on clean v0.15.0 install (AC-07 relative to v0.15.0 state). Drops 16
opus-agents to sonnet/haiku tiers vs v0.14.0 baseline.

| Cohort | Model | Effort | Notes |
|--------|-------|--------|-------|
| `:planner` | opus | high | binding planners → overrides (opus, xhigh); 5 sonnet-planners → overrides |
| `:doer` | sonnet | high | 3 sonnet agents at cohort default |
| `:verifier` | haiku | high | nyquist-auditor + ui-auditor → overrides (sonnet, high) |
| `:investigator` | sonnet | high | |
| `:adversarial` | — | — | preset-immune |

Permission mode: `bypassPermissions`.

### Overrides

- `architect, planner, product-manager, roadmapper → (opus, xhigh)` — binding-4 planners
- `advisor-researcher, assumptions-analyzer, framework-selector, research-synthesizer, ux-designer → (sonnet, high)` — 5 sonnet-planners
- `nyquist-auditor, ui-auditor → (sonnet, high)` — verifier-cohort overrides

(3 grouped lines / 11 agent entries. Applying `balanced` on clean
v0.15.0 install = zero frontmatter diff.)

---

## Preset: quality-first

**Intent:** maximum quality, accept higher token spend. All non-adversarial
cohorts pulled toward `max`; verifiers bumped to `xhigh`. Sonnet/haiku
agents stay at `(sonnet|haiku, high)` — "sonnet/haiku falls back to high"
(M008 rule; `xhigh`/`max` on sonnet/haiku collapses to `high` at runtime).

| Cohort | Model | Effort | Notes |
|--------|-------|--------|-------|
| `:planner` | opus | max | sonnet-planners preserved at (sonnet, high) |
| `:doer` | opus | max | sonnet-doers preserved at (sonnet, high) |
| `:verifier` | opus | xhigh | sonnet/haiku-verifiers preserved at (sonnet|haiku, high) |
| `:investigator` | opus | max | sonnet-investigators preserved at (sonnet, high) |
| `:adversarial` | — | — | preset-immune |

Permission mode: `bypassPermissions`.

### Overrides

- `advisor-researcher, assumptions-analyzer, framework-selector, research-synthesizer, ux-designer → (sonnet, high)` — 5 sonnet-planners
- `notion-sync, pattern-mapper, test-writer → (sonnet, high)` — 3 sonnet-doers
- `doc-verifier, ui-checker → (haiku, high)` — 2 haiku-verifiers (keep haiku — no opus upgrade)
- `nyquist-auditor, ui-auditor → (sonnet, high)` — 2 sonnet-verifier overrides retained
- `user-profiler → (sonnet, high)` — sonnet-investigator

(5 grouped lines / 13 agent entries. Within K-007 ≤ 5-line cap.)

Adversarial members (`plan-checker`, `contrarian`, `reviewer`,
`code-reviewer`) retain baseline `(opus, max|high)` — preset-immune.

---

## Preset: auto-mode-safe

**Intent:** effort + model distribution identical to `balanced`; ONLY the
permission surface changes (D-5 — cohort shape resolves to the same
frontmatter state as `balanced`). Requires full-word `auto-mode`
confirmation and passes the plan/version pre-checks in SKILL.md Phase 3.

| Cohort | Model | Effort | Notes |
|--------|-------|--------|-------|
| `:planner` | opus | high | same as balanced |
| `:doer` | sonnet | high | same as balanced |
| `:verifier` | haiku | high | same as balanced |
| `:investigator` | sonnet | high | same as balanced |
| `:adversarial` | — | — | preset-immune |

Permission mode: `auto`.

### Overrides

Identical to `balanced`:
- `architect, planner, product-manager, roadmapper → (opus, xhigh)`
- `advisor-researcher, assumptions-analyzer, framework-selector, research-synthesizer, ux-designer → (sonnet, high)`
- `nyquist-auditor, ui-auditor → (sonnet, high)`

(3 grouped lines / 11 agent entries — identical to `balanced`.)

### Side effects (apply-time, not cohort-tuple-driven)

- Switches `.aihaus/settings.local.json` `permissions.defaultMode` from
  `bypassPermissions` to `auto`.
- Deletes `permissionMode: bypassPermissions` from worktree agents
  (`implementer`, `frontend-dev`, `code-fixer`) — the field is a no-op
  under auto mode; removing it prevents user confusion.
- Widens `pkg/.aihaus/hooks/auto-approve-bash.sh` SAFE_PATTERNS additively
  (R6 compensation from PLAN.md Rev. 3). Strictly additive — no existing
  patterns removed; smoke-test Check 22 MUST stay green.

See `annexes/permission-modes.md` for the full caveat matrix printed
before the confirmation prompt.
