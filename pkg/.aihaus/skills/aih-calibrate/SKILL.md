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
| `/aih-calibrate --agent <name> --effort <level>` | Single-agent frontmatter edit. |
| `/aih-calibrate --permission-mode <m>` | Edits `settings.local.json` only. |

Preset → effort distribution map: `annexes/presets.md`.
Permission-mode tradeoff matrix + caveats: `annexes/permission-modes.md`.

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
4. Print the distribution report (agents-by-name + model + effort +
   permissionMode) plus a one-line cost-estimate delta vs. the `balanced`
   preset.
5. **Stop here if `--inspect` given.** No edits, no commit.

### Phase 2 — Compute target distribution
6. Parse `$ARGUMENTS`: resolve `--preset`, `--agent`+`--effort`, or
   `--permission-mode`.
7. **Filter out `plan-checker` and `contrarian` before applying any
   preset-driven diff** (ADR-M008-C — adversarial agents are preset-immune).
   Only an explicit `--agent plan-checker` or `--agent contrarian`
   invocation is allowed to mutate their `effort:`.
8. For `--preset`, load the per-preset agent enumeration from
   `annexes/presets.md`; compute the file-by-file diff (list of
   `pkg/.aihaus/agents/*.md` paths whose `effort:` differs from the target,
   plus the settings template if the preset changes `defaultMode`).
9. Print the computed diff (explicit path list + old→new transitions). This
   list is the exact `git add` argument vector for Phase 4.

### Phase 3 — Confirm + apply
10. **One question per autonomy-protocol:** *"Aplicar preset X
    (N agent edits + settings change)? y/sim/enter"*. No A/B/C menus.
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
14. Apply edits via the Edit tool (exact string replacement on
    `effort: <old>` per agent file; INSERT or Edit-replace on
    `"defaultMode": "<current>"` per architecture §Edit Application
    Strategy). Never sed/awk — Edit's Read precondition is free safety.
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

## Guardrails

Three non-negotiables — referenced in `annexes/permission-modes.md`:

1. **plan-checker and contrarian are preset-immune.** No `--preset
   <name>` invocation changes their `effort:`. Only explicit
   `--agent plan-checker --effort <level>` (or the equivalent for
   contrarian) can touch them. See ADR-M008-C.
2. **`--preset auto-mode-safe` requires full-word `auto-mode` confirmation.**
   Any other response (including `y`, `sim`, empty, `yes`) aborts with no
   edits. The 4-caveat matrix MUST print before the prompt.
3. **Never edit `model:` frontmatter.** Out of scope for this milestone;
   aliases auto-upgrade and pinning forces future sweeps.

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
- `annexes/presets.md` — preset → distribution map + per-preset agent
  enumeration.
- `annexes/permission-modes.md` — permission-mode tradeoff matrix +
  4-caveat list + decision tree.

## Autonomy
See `_shared/autonomy-protocol.md` — binding rules. Overrides any
contradictory prose above.
