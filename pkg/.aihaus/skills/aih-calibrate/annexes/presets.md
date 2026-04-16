# Preset → Effort Distribution Map

This annex is the contract that `/aih-calibrate` Phase-2 reads. The top-level
matrix describes preset intent; the per-preset sub-sections enumerate every
agent by name so the skill's diff logic is deterministic.

**Source of truth:** the post-Story-A agent frontmatters
(`grep '^effort:' pkg/.aihaus/agents/*.md`). The `balanced` row below MUST
match that state byte-identically — this is asserted by the reversibility
contract (Story B AC).

## Preset Distribution Matrix

| Preset | Opus coding/agentic | Opus structured | Opus binding | Sonnet | Permission mode |
|--------|---------------------|-----------------|--------------|--------|-----------------|
| `cost-optimized` | high | high | xhigh | high | bypassPermissions |
| `balanced` (default post-v0.13.0) | xhigh | high | max | high | bypassPermissions |
| `quality-first` | max | xhigh | max | high | bypassPermissions |
| `auto-mode-safe` | xhigh | high | max | high | **auto** |

**Notes:**

1. `cost-optimized` lowers opus coding/agentic back to `high` (Opus 4.6
   behavior) to cut reasoning-token spend; keeps `max` on binding agents as
   `xhigh` (the only binding-output downgrade any preset makes, accepted
   because "cost-first" is the explicit user intent). **Adversarial agents
   (`plan-checker`, `contrarian`) are preset-immune** per ADR-M008-C — they
   retain `effort: max` regardless of preset.
2. `quality-first` is aggressive. Claude Code docs warn `max` is "prone to
   overthinking"; use only for short-duration quality-critical milestones.
3. `auto-mode-safe` keeps effort distribution identical to `balanced` —
   only the permission surface differs. Switching both effort and
   permission mode at once is not offered as a preset; run
   `--preset quality-first` then `--permission-mode auto` sequentially if
   desired.

## Preset-Immune Agents (ADR-M008-C)

Regardless of preset, the following agents retain their `effort: max`
value. Only an explicit `/aih-calibrate --agent <name> --effort <level>`
invocation (with the agent named literally) can change them:

- `plan-checker` — every `/aih-plan` and `/aih-milestone` adversarial gate
  depends on this agent producing real findings at depth. A silent
  downgrade would weaken the quality gate all other calibrations rely on.
- `contrarian` — produces minority-view findings against other agents'
  outputs. A shallow contrarian restates consensus, defeating its purpose.

---

## Preset: cost-optimized

**Intent:** minimum token spend. Reasoning tiers pulled to Opus 4.6
behavior; binding agents soft-downgraded from `max` to `xhigh`.

- **Opus coding/agentic (22 agents) → `effort: high`:**
  - `ai-researcher`, `analyst`, `code-fixer`, `code-reviewer`,
    `codebase-mapper`, `debug-session-manager`, `debugger`,
    `domain-researcher`, `eval-auditor`, `eval-planner`, `executor`,
    `frontend-dev`, `implementer`, `integration-checker`, `nyquist-auditor`,
    `phase-researcher`, `project-researcher`, `reviewer`,
    `security-auditor`, `ui-auditor`, `ui-researcher`, `verifier`
- **Opus binding (non-adversarial — 4 agents) → `effort: xhigh`:**
  - `architect`, `planner`, `product-manager`, `roadmapper`
- **Opus binding (adversarial — 2 agents) → UNCHANGED at `max`:**
  - `plan-checker`, `contrarian` — preset-immune per ADR-M008-C.
- **Opus structured (4 agents) → UNCHANGED at `high`:**
  - `brainstorm-synthesizer`, `doc-writer`, `intel-updater`,
    `project-analyst`
- **Sonnet (11 agents) → UNCHANGED at `high`:**
  - `advisor-researcher`, `assumptions-analyzer`, `doc-verifier`,
    `framework-selector`, `notion-sync`, `pattern-mapper`,
    `research-synthesizer`, `test-writer`, `ui-checker`,
    `user-profiler`, `ux-designer`
- **Permission mode:** `bypassPermissions` (unchanged).

Total edits: 22 opus agent files + 4 opus-binding-non-adversarial files
= 26 file edits maximum (actual count depends on current state).

---

## Preset: balanced

**Intent:** post-Story-A default. This is the shipped state after
v0.13.0 merges.

- **Opus coding/agentic (22 agents) → `effort: xhigh`:** (same 22 listed above)
- **Opus binding (6 agents) → `effort: max`:**
  - `architect`, `contrarian`, `plan-checker`, `planner`,
    `product-manager`, `roadmapper`
- **Opus structured (4 agents) → `effort: high`:**
  - `brainstorm-synthesizer`, `doc-writer`, `intel-updater`,
    `project-analyst`
- **Sonnet (11 agents) → `effort: high`:** (same 11 listed above)
- **Permission mode:** `bypassPermissions`.

Total distinct tiers: 22 `xhigh` + 6 `max` + 4 `high` + 11 `high` = 43 ✓.
On a clean post-Story-A install, `--preset balanced` produces a zero-diff
no-op commit.

---

## Preset: quality-first

**Intent:** maximum quality, accept higher token spend. Coding/agentic
agents pulled to `max`; structured agents bumped to `xhigh`.

- **Opus coding/agentic (22 agents) → `effort: max`:** (same 22 listed above)
- **Opus binding (6 agents) → `effort: max`:** (unchanged from balanced)
- **Opus structured (4 agents) → `effort: xhigh`:**
  - `brainstorm-synthesizer`, `doc-writer`, `intel-updater`,
    `project-analyst`
- **Sonnet (11 agents) → UNCHANGED at `high`** — `xhigh` falls back to
  `high` on sonnet; no-op edits are noise.
- **Permission mode:** `bypassPermissions`.

Adversarial agents (`plan-checker`, `contrarian`) are preset-immune but
their `balanced` value (`max`) already matches `quality-first` — no actual
edit, no conflict. `annexes/permission-modes.md` notes the
"prone to overthinking" warning; users should run this for
quality-critical short milestones, not indefinitely.

---

## Preset: auto-mode-safe

**Intent:** identical effort distribution to `balanced`; ONLY the
permission surface changes. Requires full-word `auto-mode` confirmation
and passes the plan/version pre-checks in SKILL.md Phase 3.

- **Effort distribution:** identical to `balanced` — no agent effort
  changes.
- **Permission mode:** `auto` — switches `.aihaus/settings.local.json`
  `permissions.defaultMode` from `bypassPermissions` to `auto`.
- **Side effect — deletes `permissionMode: bypassPermissions`** from:
  - `implementer`
  - `frontend-dev`
  - `code-fixer`
  (The field becomes a no-op under auto mode per the documented caveats;
  removing it prevents user confusion about a setting that isn't doing
  anything.)
- **Side effect — widens `pkg/.aihaus/hooks/auto-approve-bash.sh`
  SAFE_PATTERNS additively** (R6 compensation from PLAN.md Rev. 3). This
  buys back some narrow-rule surface the classifier would otherwise block
  on every call. The edit is strictly additive — no existing patterns are
  removed, and smoke-test Check 22 MUST stay green.

See `annexes/permission-modes.md` for the full caveat matrix printed
before the confirmation prompt.
