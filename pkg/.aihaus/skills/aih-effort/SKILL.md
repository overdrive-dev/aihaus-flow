---
name: aih-effort
description: Retune agent effort tiers and model assignments after install. Interactive by default; accepts --preset, --cohort, --agent, --status, --inspect flags. All edits atomic + git-committed + reversible.
---

## Task
Retune effort tiers (`effort:` frontmatter) and model assignments across the 43
agents. Every invocation produces exactly one git commit; `git revert HEAD` is
the canonical rollback.

See `_shared/autonomy-protocol.md` — Phase-1 one-question rule applies; no
option menus, no delegated typing.

## When to Use
- Token spend on Opus 4.7 `effort: xhigh` is higher than expected → run
  `/aih-effort --preset cost` for a coding-tier downgrade.
- A specific agent over- or under-reasons on your project → run
  `/aih-effort --agent <name> --model <m> --effort <level>`.
- You want maximum quality on a short-duration milestone → run
  `/aih-effort --preset high`.
- Read-only audit of current distribution → `/aih-effort --inspect`.
- Check the recorded calibration state → `/aih-effort --status`.

## Invocation Modes

| Invocation | Behavior |
|-----------|----------|
| `/aih-effort` | Interactive: print current distribution; offer 3 presets. |
| `/aih-effort --inspect` | Read-only report of all 46 agents. No commit. |
| `/aih-effort --status` | Print recorded `.aihaus/.effort` sidecar state. Triggers v2→v3 migration if sidecar is still schema v2. No commit. |
| `/aih-effort --preset cost` | `:verifier` to `(haiku, medium)`; `:doer` sonnet; binding planners kept at `(opus, xhigh)`. |
| `/aih-effort --preset balanced` | Default post-v0.16.0. Zero-diff no-op on clean install. |
| `/aih-effort --preset high` | `:doer` escalates from `(sonnet, high)` to `(opus, high)`; planners to `max`. |
| `/aih-effort --agent <name> --model <m> --effort <e>` | Per-agent joint override — both axes required (ADR-M008-A amendment). |
| `/aih-effort --cohort :<name> --model <m> --effort <e>` | Joint cohort apply — both axes required. `:adversarial-scout`/`:adversarial-review` require literal-word `adversarial` confirm. |

**Removed flag:** `--permission-mode` was removed in v0.16.0. Invoking it exits
nonzero with stderr: `--permission-mode flag removed in v0.16.0; use bash .aihaus/auto.sh for autonomous launch (DSP mode)`.

Preset → cohort tuple map: `annexes/presets.md`.
Cohort membership (46 agents → 6 cohorts): `annexes/cohorts.md`.
CLI surface detail + adversarial bypass + Phase-4 v3 write: `annexes/cli-surface.md`.

## Execution Protocol

### Phase 1 — Read + inspect
1. Silent context load: `.aihaus/project.md`, `.aihaus/decisions.md`
   (ADR-M012-A is binding — supersedes ADR-M008-C + ADR-M010-A),
   `.aihaus/knowledge.md`.
2. Read all 46 agent frontmatters at `pkg/.aihaus/agents/*.md` —
   `grep '^effort:' pkg/.aihaus/agents/*.md | sort | uniq -c` gives the
   current tier distribution.
3. Print the distribution report as a GFM Markdown pipe table
   (`| Agent | Model | Effort | Cohort |` with a `---` separator row).
   Cohort value is looked up from `annexes/cohorts.md` per agent. Follow
   with a one-line cost-estimate delta vs. the `balanced` preset.
4. **Stop here if `--inspect` given.** No edits, no commit.
5. **If `--status` given:** read `.aihaus/.effort` (trigger v2→v3 migration
   if schema=2 sidecar present); print recorded state; exit. No commit.

### Phase 2 — Compute target distribution
6. Parse `$ARGUMENTS`: guard `--permission-mode` with error exit (stderr
   message + nonzero exit) before any other processing. Then resolve
   `--preset`, `--cohort :<name> --model --effort`, `--agent --model
   --effort`. Validate dual-axis requirements per `annexes/cli-surface.md`
   — reject single-axis `--cohort` and single-axis `--agent --model`.
7. **Load preset-immune cohorts via `is_preset_immune(cohort)` from
   `pkg/scripts/lib/restore-effort.sh`** (F-010 resolution: single
   authoritative location — SKILL.md and annexes reference the helper, never
   embed it). Filter `:adversarial-scout` + `:adversarial-review` out of
   any preset-driven diff. Only explicit `--cohort :adversarial-*`
   (with literal-word `adversarial` confirm) or `--agent <member>` can
   mutate adversarial frontmatter.
8. For `--preset`, load cohort tuples from `annexes/presets.md` and
   expand each member via `annexes/cohorts.md`; compute the file-by-file
   diff (target `(model, effort)` per agent). Diff entry exists when
   either axis differs from target. `sonnet`/`haiku` agents silently clip
   to `effort: high` when preset requests `xhigh`/`max` (ADR-M012-A §4).
9. Print the computed diff (explicit path list + old→new transitions per
   axis). This list is the exact `git add` argument vector for Phase 4.

### Phase 3 — Confirm + apply
10. **One question per autonomy-protocol:** *"Apply preset X (N agent edits
    across K cohorts)? y/enter"*. No A/B/C menus.
11. Apply edits via the Edit tool — for cohort/preset apply, do BOTH
    `model: <old>` → `model: <target>` AND `effort: <old>` → `effort:
    <target>` per agent file when both differ (two Edit calls per file;
    `git checkout -- <file>` on mid-sequence failure). Never sed/awk —
    Edit's Read precondition is free safety.
12. **Adversarial bypass (explicit `--cohort :adversarial-*` or
    `--agent <adversarial-member>`):** layered full-word `adversarial`
    confirmation required. Full prompt shape in `annexes/cli-surface.md`.

### Phase 4 — Commit + post-edit gate
13. Explicit `git add <path1> <path2> ...` — one path per edited file;
    NEVER `git add -A` (per `feedback_worktree_merge_back_race.md`).
14. Single commit. Message shape:
    - Preset: `chore(effort): apply <preset> preset (<N> agents)`
    - Per-agent: `chore(effort): set <agent-name> to (<model>, <effort>)`
    - Reset: `chore(effort): reset to balanced preset`
15. Run `bash tools/smoke-test.sh && bash tools/purity-check.sh` as the
    post-edit gate. On non-zero exit, run `git reset --hard HEAD~1`,
    print the failing check output, exit without retry.
16. On green: print final distribution delta + one-line cost-estimate
    change; print the `git revert <sha>` rollback one-liner.
17. **Post-gate sidecar write** (`.aihaus/.effort`, `schema=3`). Only after
    the commit + gate pass; never on `--inspect` / `--status` / self-revert.
    Emit `schema=3`, `last_preset=<name>`, `last_commit=$(git rev-parse
    --short HEAD)`, one `cohort.<name>.model` + `cohort.<name>.effort`
    pair per cohort touched (preset runs filter adversarial cohorts via
    `is_preset_immune()`), and per-agent override lines. Schema contract:
    `annexes/state-file.md`.
    - **17-guard** — if step 15 self-reverted, SKIP the write.
    - **17-ownership** — NEVER `git add .aihaus/.effort` (ADR-M009-A).
    - **17-adversarial-immune** — filter via `is_preset_immune()` helper.

## Guardrails

1. **Both adversarial cohorts are preset-immune.** `:adversarial-scout`
   (plan-checker, contrarian) and `:adversarial-review` (reviewer,
   code-reviewer) are skipped by all `--preset` invocations. Enforced via
   `is_preset_immune(cohort)` in `pkg/scripts/lib/restore-effort.sh`.
   Only explicit `--cohort :adversarial-*` (literal-word `adversarial`
   confirmation) or `--agent <member>` can mutate them. See ADR-M012-A.
2. **`model:` edits are scoped to cohort iteration or explicit per-agent
   dual-axis.** Single-axis `--agent X --model Y` without `--effort` is
   rejected. Single-axis `--cohort :<name>` without both model+effort is
   rejected.
3. **`sonnet`/`haiku` agents clip to `effort: high`** when a preset
   requests `xhigh` or `max`. Silent clip — no warning emitted.

Additional invariants:
- Edits always in-place on `pkg/.aihaus/agents/*.md` (ADR-M008-A).
- Commits always list explicit paths.
- Post-edit gate self-reverts on red (Phase 4 step 15).

## Reversibility
Every invocation produces exactly one commit. `git revert HEAD` restores
byte-identical pre-invocation state. `--reset` re-applies the `balanced`
preset without searching git history.

## Annexes (referenced, not duplicated)
- `annexes/presets.md` — 3 preset sections + 6×3 Distribution Matrix.
- `annexes/cohorts.md` — 46 agents → 6 cohorts; single source of truth.
- `annexes/cli-surface.md` — CLI validation, adversarial bypass, v3 sidecar write.
- `annexes/state-file.md` — `.aihaus/.effort` schema v3, ownership, migration.
- `annexes/renamed-from-*.md` — rename history note (M012 BREAKING).

## Autonomy
See `_shared/autonomy-protocol.md` — binding rules. Overrides any
contradictory prose above.
