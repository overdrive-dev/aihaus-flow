---
name: aih-automode
description: Enable or disable Claude Code auto permission-mode independently of effort calibration. Supports --enable (literal `auto` confirmation), --disable, and --status.
---

## Task
Toggle Claude Code's `permissions.defaultMode` between `auto` and
`bypassPermissions`. Writes a `.aihaus/.automode` sidecar to survive
`/aih-update` cycles. Effort calibration is separate — see `/aih-effort`.

For rationale: ADR-M012-A (skill-split decision) + ADR-M008-B (opt-in
discipline preserved). Tradeoff matrix: `annexes/permission-modes.md`.

See `_shared/autonomy-protocol.md` — one-question rule; no option menus.

## When to Use
- You are on Max/Team/Enterprise/API plan with Anthropic API (not Pro, not
  Bedrock/Vertex/Foundry) and want Claude Code to route permissions through
  the classifier instead of `bypassPermissions`.
- You want to revert from auto mode back to the default aihaus contract.
- You want to check whether auto mode is recorded as active in this repo.

## Invocation Modes

| Invocation | Behavior |
|-----------|----------|
| `/aih-automode --enable` | Display 4-caveat block; plan/version pre-check; prompt for literal `auto`; apply. |
| `/aih-automode --disable` | Revert to `bypassPermissions`; restore worktree frontmatter. No confirmation. |
| `/aih-automode --status` | Read `.aihaus/.automode`; print both fields. Missing file = `enabled=false`. |

Caveat block text: `annexes/caveat-block.md`.
Permission-mode tradeoff matrix + decision tree: `annexes/permission-modes.md`.
Sidecar schema + gitignore guidance: `annexes/state-file.md`.

## Execution Protocol — `--status`

1. Read `.aihaus/.automode`. If absent, print:
   ```
   enabled=false
   last_enabled_at=never
   ```
2. If present, print `enabled=` and `last_enabled_at=` verbatim.
3. If `settings.local.json` `permissions.defaultMode` disagrees with
   `enabled`, append drift warning (see `annexes/state-file.md`).
4. Exit. No commits, no writes.

## Execution Protocol — `--enable`

### Phase 1 — Pre-check
1. Silent context load: `.aihaus/project.md`, `.aihaus/decisions.md`
   (ADR-M012-A + ADR-M008-B are binding), `.aihaus/knowledge.md`.
2. **Plan/provider eligibility pre-check.** Run `claude --print-config`
   (or equivalent). If plan = Pro OR provider ≠ Anthropic API: print
   clear abort message + exit nonzero. No files edited on abort.
   If `claude` CLI is absent: print warning; ask "Proceed without
   eligibility check? (y/enter to proceed, anything else aborts)".
3. **Version pre-check.** Run `claude --version`. If below v2.1.83: warn
   that `defaultMode: auto` will be silently ignored by Claude Code; ask
   for explicit re-confirmation before writing. Graceful degrade: if
   `claude` absent, skip version check (covered by step 2 warning).

### Phase 2 — Confirm
4. Print the 4-caveat block **verbatim** from `annexes/caveat-block.md`.
5. Print the confirmation prompt:
   `To confirm, type the literal word 'auto' (any other response aborts):`
6. Read user input. If trimmed input ≠ `auto` (case-sensitive): print
   `Auto mode not enabled. No files were edited.` and exit 0. No writes.

### Phase 3 — Apply
7. **Merge `defaultMode=auto` into `settings.local.json`** using
   `pkg/scripts/lib/merge-settings.sh`. Pass the settings path as the
   `dst` argument. Do NOT parallel-implement JSON merging.
   If merge fails: exit nonzero; print error; no sidecar written.
8. **Strip `permissionMode: bypassPermissions`** from:
   - `pkg/.aihaus/agents/implementer.md`
   - `pkg/.aihaus/agents/frontend-dev.md`
   - `pkg/.aihaus/agents/code-fixer.md`
   Read each file first; remove only the exact line `permissionMode: bypassPermissions`
   (preserve all other frontmatter). Idempotent: no error if line absent.
   Use Read + Edit tool per ADR-M008-A — never sed/awk.
9. **Write `.aihaus/.automode`:**
   ```
   enabled=true
   last_enabled_at=<ISO8601-UTC-now>
   ```
   Overwrite if file exists (idempotent — no duplicate rows).

### Idempotence (FR-S04 — binding)
Re-running `--enable` after `/aih-update` restored worktree agent
frontmatter re-strips `permissionMode: bypassPermissions` with exit 0.
Every `--enable` call applies ALL side effects (steps 7–9) unconditionally.
There is no "already enabled" short-circuit past the pre-check + confirm.

## Execution Protocol — `--disable`

1. No confirmation prompt required (disabling is always safe).
2. **Merge `defaultMode=bypassPermissions` into `settings.local.json`**
   using `pkg/scripts/lib/merge-settings.sh`.
3. **Restore `permissionMode: bypassPermissions`** frontmatter on:
   - `pkg/.aihaus/agents/implementer.md`
   - `pkg/.aihaus/agents/frontend-dev.md`
   - `pkg/.aihaus/agents/code-fixer.md`
   Read each file first; if line absent, insert after `isolation: worktree`
   (or after the last frontmatter field before `---`). Use Read + Edit tool.
4. **Write `.aihaus/.automode`:**
   ```
   enabled=false
   last_enabled_at=<last_enabled_at value if present, else omit>
   ```
   Preserve `last_enabled_at` from the existing sidecar so history is
   retained. If no sidecar, write `enabled=false` only.

## Guardrails

1. **Never commit `.aihaus/.automode`.** It is user-owned and gitignored.
   Never `git add .aihaus/.automode` under any path (ADR-M009-A).
2. **`--enable` does NOT create a git commit.** Side effects land in
   `settings.local.json` (template file) and agent frontmatters directly.
   Rollback: run `/aih-automode --disable`.
3. **`--disable` does NOT create a git commit** for the same reason.
4. **No auto-replay during `/aih-update`.** `restore-automode.sh` reads
   `.automode` and prints an informational pointer if `enabled=true` — it
   does NOT mutate `settings.local.json` or agent frontmatter. User must
   re-run `/aih-automode --enable` manually (ADR-M009-A "record state,
   defer apply" preserved verbatim).
5. **Both axes of idempotence are required.** Strip-when-present (enable)
   and restore-when-absent (disable) must both work across repeated calls.

## Annexes (referenced, not duplicated)
- `annexes/caveat-block.md` — verbatim 4-caveat block + confirmation prompt.
- `annexes/permission-modes.md` — mode tradeoff matrix + decision tree.
- `annexes/state-file.md` — `.automode` sidecar schema v1, gitignore
  guidance, idempotence contract, drift detection.

## Autonomy
See `_shared/autonomy-protocol.md` — binding rules. Overrides any
contradictory prose above.
