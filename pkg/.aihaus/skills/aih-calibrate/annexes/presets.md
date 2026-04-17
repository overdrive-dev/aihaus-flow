# Preset → Cohort Tuple Map

This annex is the contract that `/aih-calibrate` Phase-2 reads. Every preset
is expressed as 4 cohort tuples + a permission-mode row + an optional
`### Overrides` block listing grouped `(agents → (model, effort))` lines
for agents whose baseline deviates from the cohort default.

**Source of truth for cohort membership:** `annexes/cohorts.md` (M010 / S01
/ ADR-M010-A). The top-level matrix below describes preset intent; the
per-preset sub-sections enumerate cohort tuples + grouped override lines.

**`balanced` reversibility contract (AC-07):** applying `--preset balanced`
on a clean v0.13.0-state install MUST produce a zero-diff no-op commit.
The override lines in the `balanced` section pin every sonnet agent at
`(sonnet, high)` and every binding planner at `(opus, xhigh)` so no
frontmatter flip occurs.

## Preset Distribution Matrix

| Preset | :planner | :doer | :verifier | :adversarial | Permission mode |
|--------|----------|-------|-----------|--------------|-----------------|
| `cost-optimized` | (opus, high) | (sonnet, high) | (sonnet, medium) | preset-immune | bypassPermissions |
| `balanced` (default post-v0.14.0) | (opus, high) | (opus, high) | (opus, high) | preset-immune | bypassPermissions |
| `quality-first` | (opus, max) | (opus, max) | (opus, xhigh) | preset-immune | bypassPermissions |
| `auto-mode-safe` | (opus, high) | (opus, high) | (opus, high) | preset-immune | **auto** |

**Notes:**

1. `cost-optimized` downgrades `:doer` and `:verifier` jointly via
   `(model, effort)` — true cost reduction (distinct from v0.13.0
   `cost-optimized` which was effort-only). Binding planners preserved at
   `(opus, xhigh)`.
2. `balanced` reproduces the v0.13.0 ship distribution byte-identically
   (Q-2 — representational change). Overrides pin every sonnet agent +
   binding-4; zero-diff on clean v0.13.0 install (AC-07 contract).
3. `quality-first` is aggressive. Claude Code docs warn `max` is "prone to
   overthinking"; use only for short-duration quality-critical milestones.
   "Sonnet falls back to high" (M008 rule) — sonnet agents stay at
   `(sonnet, high)` via overrides.
4. `auto-mode-safe` effort distribution identical to `balanced`; only the
   permission surface changes. See `annexes/permission-modes.md` for the
   caveat matrix printed before the full-word `auto-mode` confirmation.

## Preset-Immune Agents (ADR-M010-A supersedes ADR-M008-C — 2 → 4)

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

M010 extends ADR-M008-C's 2-agent immunity list to the full 4-agent
`:adversarial` cohort. Semantics identical (preset runs skip this cohort
at write time); the enumeration grew from hardcoded name-list to
cohort-lookup against `cohorts.md`.

---

## Preset: cost-optimized

**Intent:** minimum token spend across the fleet. Joint `(model, effort)`
downgrade on `:doer` and `:verifier`; binding planners preserved.

| Cohort | Model | Effort | Notes |
|--------|-------|--------|-------|
| `:planner` | opus | high | binding planners → overrides (opus, xhigh) |
| `:doer` | sonnet | high | |
| `:verifier` | sonnet | medium | |
| `:adversarial` | — | — | preset-immune |

Permission mode: `bypassPermissions` (unchanged).

### Overrides

- `architect, planner, product-manager, roadmapper → (opus, xhigh)` — binding planners preserved
- `advisor-researcher, assumptions-analyzer, framework-selector, research-synthesizer, ux-designer → (sonnet, high)` — 5 sonnet-planners preserved

(2 grouped lines / 9 agent entries.)

---

## Preset: balanced

**Intent:** default post-v0.14.0. Ships functionally equivalent to v0.13.0
`cost-optimized` distribution (Q-2 representational change). Zero-diff
reversibility on clean v0.13.0 install (AC-07).

| Cohort | Model | Effort | Notes |
|--------|-------|--------|-------|
| `:planner` | opus | high | binding planners → overrides (opus, xhigh) |
| `:doer` | opus | high | 3 sonnet-doers preserved via overrides |
| `:verifier` | opus | high | 3 sonnet-verifiers preserved via overrides |
| `:adversarial` | — | — | preset-immune |

Permission mode: `bypassPermissions`.

### Overrides

- `architect, planner, product-manager, roadmapper → (opus, xhigh)` — binding-4
- `advisor-researcher, assumptions-analyzer, framework-selector, research-synthesizer, ux-designer → (sonnet, high)` — 5 sonnet-planners
- `notion-sync, pattern-mapper, test-writer → (sonnet, high)` — 3 sonnet-doers
- `doc-verifier, ui-checker, user-profiler → (sonnet, high)` — 3 sonnet-verifiers

(4 grouped lines / 15 agent entries. Every sonnet agent pinned at
`(sonnet, high)`; binding-4 planners pinned at `(opus, xhigh)`. Applying
`balanced` on clean v0.13.0 install = zero frontmatter diff.)

---

## Preset: quality-first

**Intent:** maximum quality, accept higher token spend. Coding/agentic
agents pulled to `max`; verifiers bumped to `xhigh`. Sonnet agents stay at
`(sonnet, high)` — "sonnet falls back to high" (M008 rule; `xhigh`/`max`
on sonnet collapses to `high` at runtime).

| Cohort | Model | Effort | Notes |
|--------|-------|--------|-------|
| `:planner` | opus | max | sonnet-planners preserved at (sonnet, high) |
| `:doer` | opus | max | sonnet-doers preserved at (sonnet, high) |
| `:verifier` | opus | xhigh | sonnet-verifiers preserved at (sonnet, high) |
| `:adversarial` | — | — | preset-immune |

Permission mode: `bypassPermissions`.

### Overrides

- `advisor-researcher, assumptions-analyzer, framework-selector, research-synthesizer, ux-designer → (sonnet, high)` — 5 sonnet-planners
- `notion-sync, pattern-mapper, test-writer → (sonnet, high)` — 3 sonnet-doers
- `doc-verifier, ui-checker, user-profiler → (sonnet, high)` — 3 sonnet-verifiers

(3 grouped lines / 11 agent entries. Binding-4 planners resolve to
`(opus, max)` via the `:planner` default — higher than baseline `xhigh`,
matching `quality-first` intent.)

Adversarial members (`plan-checker`, `contrarian`, `reviewer`,
`code-reviewer`) retain baseline `(opus, max|high)` — preset-immune.

---

## Preset: auto-mode-safe

**Intent:** effort distribution identical to `balanced`; ONLY the
permission surface changes (D-5 — cohort shape resolves to the same
frontmatter state as `balanced`). Requires full-word `auto-mode`
confirmation and passes the plan/version pre-checks in SKILL.md Phase 3.

| Cohort | Model | Effort | Notes |
|--------|-------|--------|-------|
| `:planner` | opus | high | same as balanced |
| `:doer` | opus | high | same as balanced |
| `:verifier` | opus | high | same as balanced |
| `:adversarial` | — | — | preset-immune |

Permission mode: `auto`.

### Overrides

Identical to `balanced`:
- `architect, planner, product-manager, roadmapper → (opus, xhigh)`
- `advisor-researcher, assumptions-analyzer, framework-selector, research-synthesizer, ux-designer → (sonnet, high)`
- `notion-sync, pattern-mapper, test-writer → (sonnet, high)`
- `doc-verifier, ui-checker, user-profiler → (sonnet, high)`

(4 grouped lines / 15 agent entries — identical to `balanced`.)

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
