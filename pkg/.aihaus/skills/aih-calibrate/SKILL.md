---
name: aih-calibrate
description: Retune agent effort tiers and permission mode after install. Interactive by default; accepts --preset, --agent, --effort, --permission-mode flags. All edits atomic + git-committed + reversible.
---

## Task
Retune effort tiers (`effort:` frontmatter) across the 43 agents and/or the
`permissions.defaultMode` in `.aihaus/settings.local.json`. Every invocation
produces exactly one git commit; `git revert HEAD` is the canonical rollback.

See `_shared/autonomy-protocol.md` — Phase-1 one-question rule applies; no
option menus, no delegated typing.

## When to Use
- Token spend on Opus 4.7 `effort: xhigh` is higher than expected → run
  `/aih-calibrate --preset cost-optimized` for a coding-tier downgrade.
- A specific agent over- or under-reasons on your project → run
  `/aih-calibrate --agent <name> --effort <level>`.
- You want to opt into Claude Code auto mode (v2.1.83+; Max/Team/Enterprise/API
  plan; Anthropic API provider) → run `/aih-calibrate --preset auto-mode-safe`
  and read the 4-caveat matrix before typing the full-word confirmation.
- Read-only audit of current distribution → `/aih-calibrate --inspect`.

## Invocation Modes

| Invocation | Behavior |
|-----------|----------|
| `/aih-calibrate` | Interactive: print current distribution; offer 4 presets. |
| `/aih-calibrate --inspect` | Read-only report of all 43 agents + settings. No commit. |
| `/aih-calibrate --preset cost-optimized` | Opus coding/agentic → `high`; binding → `xhigh`; `bypassPermissions` kept. |
| `/aih-calibrate --preset balanced` | Post-Story-A distribution (default post-v0.13.0). |
| `/aih-calibrate --preset quality-first` | Opus coding/agentic → `max`; binding → `max`. Docs warn "prone to overthinking". |
| `/aih-calibrate --preset auto-mode-safe` | Switches `defaultMode` to `auto`; keeps balanced effort; requires full-word `auto-mode` confirm. |
| `/aih-calibrate --agent <name> --effort <level>` | Single-agent effort edit (v0.13 preserved). |
| `/aih-calibrate --cohort :<name> --model <m> --effort <e>` | Joint cohort apply — both axes required (D-2). `:adversarial` requires literal-word `adversarial` confirm. |
| `/aih-calibrate --agent <name> --model <m> --effort <e>` | Per-agent joint override — ADR-M008-A amendment (D-3 dual-axis escape hatch). |
| `/aih-calibrate --permission-mode <m>` | Edits `settings.local.json` only. |

Preset → cohort tuple map: `annexes/presets.md`.
Cohort membership (43 agents → 5 cohorts): `annexes/cohorts.md`.
Permission-mode tradeoff matrix + caveats: `annexes/permission-modes.md`.
CLI surface detail + adversarial bypass + Phase-4 v2 write: `annexes/cli-surface.md`.

## Execution Protocol

### Phase 1 — Read + inspect
1. Silent context load: `.aihaus/project.md`, `.aihaus/decisions.md`
   (ADR-M008-A/B/C are binding), `.aihaus/knowledge.md` (K-001 allow-list
   discipline, K-002 worktree).
2. Read all 43 agent frontmatters at `pkg/.aihaus/agents/*.md` —
   `grep '^effort:' pkg/.aihaus/agents/*.md | sort | uniq -c` gives the
   current tier distribution.
3. Read `pkg/.aihaus/templates/settings.local.json` to capture current
   `permissions.defaultMode` (and surface `_aihaus_alt_auto_mode_comment`).
4. Print the distribution report as a **GFM Markdown pipe table** (`| Agent
   | Model | Effort | Cohort | PermissionMode |` with a `---` separator
   row) — NOT Unicode box-drawing (`┌──┬──┐` / `├──┼──┤`). Pipe tables wrap
   safely on narrow terminals and copy cleanly; box-drawing clips to
   garbage on cmd.exe and split panes. Cohort value is looked up from
   `annexes/cohorts.md` per agent. Follow the table with a one-line
   cost-estimate delta vs. the `balanced` preset.
5. **Stop here if `--inspect` given.** No edits, no commit.

### Phase 2 — Compute target distribution
6. Parse `$ARGUMENTS`: resolve `--preset`, `--cohort :<name> --model
   --effort`, `--agent --effort`, `--agent --model --effort`, or
   `--permission-mode`. Validate dual-axis requirements per
   `annexes/cli-surface.md` — reject single-axis `--cohort` and
   single-axis `--agent --model`.
7. **Load `:adversarial` member list from `annexes/cohorts.md` and
   filter those 4 agents out of any preset-driven diff** (ADR-M010-A
   supersedes ADR-M008-C — immune list grows 2→4). Only explicit
   `--cohort :adversarial` (with literal-word confirm) or
   `--agent <member>` can mutate adversarial frontmatter.
8. For `--preset`, load cohort tuples from `annexes/presets.md` and
   expand each member via `annexes/cohorts.md`; compute the file-by-file
   diff (target `(model, effort)` per agent, plus settings template if
   the preset changes `defaultMode`). Diff entry exists when either axis
   differs from target.
9. Print the computed diff (explicit path list + old→new transitions per
   axis). This list is the exact `git add` argument vector for Phase 4.

### Phase 3 — Confirm + apply
10. **One question per autonomy-protocol:** *"Aplicar preset X
    (N agent edits across K cohorts + settings change)? y/sim/enter"*.
    No A/B/C menus. N = total file edits; K = cohorts touched.
11. **Exception — `--preset auto-mode-safe`:** print the 4-caveat matrix
    from `annexes/permission-modes.md` inline first, then ask *"Para
    confirmar, digite a palavra `auto-mode` (qualquer outra resposta
    aborta):"*. Any response other than the literal string `auto-mode`
    aborts with no edits and no commit.
12. **Plan-eligibility pre-check for `auto-mode-safe`:** run
    `claude --print-config` (or equivalent); if plan is Pro or provider is
    Bedrock/Vertex/Foundry, abort with a clear message — no commit.
13. **Version pre-check for `auto-mode-safe`:** run `claude --version`; if
    below v2.1.83, warn that `defaultMode: auto` will be silently ignored
    and re-confirm before writing.
14. Apply edits via the Edit tool — for cohort/preset apply, do BOTH
    `model: <old>` → `model: <target>` AND `effort: <old>` → `effort:
    <target>` per agent file when both differ (two Edit calls per file;
    `git checkout -- <file>` on mid-sequence failure). For
    `--permission-mode`: INSERT/replace `"defaultMode": "<current>"` per
    architecture. Never sed/awk — Edit's Read precondition is free safety.
14a. **Adversarial bypass (explicit `--cohort :adversarial` or
    `--agent <adversarial-member>`):** layered full-word confirmation
    required. Full prompt shape + abort semantics in
    `annexes/cli-surface.md` § Adversarial bypass.
15. For `auto-mode-safe`: also delete `permissionMode: bypassPermissions`
    from `implementer`, `frontend-dev`, `code-fixer` (the field is a no-op
    under auto mode) AND widen the safe-pattern allowlist in
    `pkg/.aihaus/hooks/auto-approve-bash.sh` additively (never remove
    existing entries).

### Phase 4 — Commit + post-edit gate
16. Explicit `git add <path1> <path2> ...` — one path per edited file; NEVER
    `git add -A` or `git add pkg/.aihaus/agents/` (per
    `feedback_worktree_merge_back_race.md`).
17. Single commit. Message shape:
    - Preset: `chore(calibrate): apply <preset> preset (<N> agents + settings)`
    - Per-agent: `chore(calibrate): set <agent-name> effort to <level>`
    - Permission-mode: `chore(calibrate): set permission mode to <mode>`
    - Reset: `chore(calibrate): reset to balanced preset`
18. Run `bash tools/smoke-test.sh && bash tools/purity-check.sh` as the
    post-edit gate. On non-zero exit from either, run
    `git reset --hard HEAD~1` (atomic revert of the just-created commit),
    print the failing check output, exit without retry.
19. On green: print final distribution delta + one-line cost-estimate
    change; print the `git revert <sha>` rollback one-liner.
20. **Post-gate sidecar write** (`.aihaus/.calibration`, `schema=2`). Only
    after the commit + gate pass; never on `--dry-run` / `--inspect`.
    Emit `schema=2`, `permission_mode=<current>`, `last_preset=<name>`,
    `last_commit=$(git rev-parse --short HEAD)`, one `cohort.<name>.model`
    + `cohort.<name>.effort` pair per cohort touched (preset runs filter
    `:adversarial`), and per-agent `<agent>=<effort>` + `<agent>.model=<m>`
    lines for each override. If a `schema=1` sidecar is present at write
    time, run the v1→v2 auto-infer migration. Full layout, write-time
    filter, and migration pseudocode: `annexes/cli-surface.md` § Phase-4
    step 20 — v2 sidecar write. Schema contract:
    `annexes/state-file.md`.
    - **20-guard** — if step 18 self-reverted (`git reset` fired), SKIP
      the write.
    - **20-ownership** — NEVER `git add .aihaus/.calibration` under any
      mode (ADR-M009-A; dogfood `.gitignore:19` covers it).
    - **20-adversarial-immune** — preset-write filter excludes all 4
      `:adversarial` members via `annexes/cohorts.md` lookup (ADR-M010-A
      supersedes ADR-M008-C's 2-agent list).

## Guardrails

Three non-negotiables — referenced in `annexes/permission-modes.md`:

1. **The `:adversarial` cohort is preset-immune (4 agents: plan-checker,
   contrarian, reviewer, code-reviewer).** No `--preset <name>`
   invocation mutates any member. Explicit `--cohort :adversarial
   --model X --effort Y` or `--agent <member> --model X --effort Y` is
   the only path — literal-word `adversarial` confirmation required.
   See ADR-M010-A (supersedes ADR-M008-C's 2-agent list).
2. **`--preset auto-mode-safe` requires full-word `auto-mode` confirmation.**
   Any other response (including `y`, `sim`, empty, `yes`) aborts with no
   edits. The 4-caveat matrix MUST print before the prompt.
3. **`model:` edits are scoped to cohort iteration or explicit per-agent
   dual-axis.** Presets mutate `model:` only via cohort iteration (see
   `annexes/presets.md` + ADR-M010-A). Per-agent paths: `--agent X
   --model Y --effort Z` (both axes required, ADR-M008-A amendment);
   single-axis `--agent X --model Y` without `--effort` remains rejected.

Additional invariants:

- Edits are always in-place on `pkg/.aihaus/agents/*.md` (ADR-M008-A — no
  override-file layer, no new agent-spawn hook).
- Commits always list explicit paths (`feedback_worktree_merge_back_race.md`).
- The post-edit gate self-reverts on red (see Phase 4 step 18).

## Reversibility
Every invocation produces exactly one commit. `git revert HEAD` restores
byte-identical pre-invocation state (agent frontmatters + settings).
`--reset` re-applies the `balanced` preset if you want to undo an arbitrary
tuning without searching through git history.

## Annexes (referenced, not duplicated)
- `annexes/presets.md` — preset → cohort tuple map + override blocks.
- `annexes/cohorts.md` — 43 agents → 5 cohorts + per-cohort default model; single source of truth.
- `annexes/cli-surface.md` — CLI validation, adversarial bypass, v2
  sidecar write + migration detail.
- `annexes/permission-modes.md` — permission-mode tradeoff matrix +
  4-caveat list + decision tree.
- `annexes/state-file.md` — `.aihaus/.calibration` schema v1 + v2,
  ownership, CRLF rules, migration paths.

## Autonomy
See `_shared/autonomy-protocol.md` — binding rules. Overrides any
contradictory prose above.
