# Changelog

> [!IMPORTANT]
> aihaus-flow is no longer maintained.
>
> For ongoing use, start with [`gsd2`](https://github.com/gsd-build/gsd-2) or [`gsd1`](https://github.com/gsd-build/get-shit-done) instead. This changelog remains here as historical reference only.

All notable changes to aihaus are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.18.0] - 2026-04-22 — M014 Auto-Launch + Resume Substrate (BREAKING)

**BREAKING.** The 7-layer permission stack is collapsed to 1 launch path. The skill `/aih-automode` is deleted (no shim). The `/aih-resume` skill is rewritten with sub-story checkpoint awareness. Re-install + relaunch via the new wrapper is required.

### DSP launch supersedes permission stack

- New wrapper: `bash .aihaus/auto.sh` (or `.aihaus/auto.ps1` on Windows PowerShell) `exec`s `claude --dangerously-skip-permissions`. This is now the **sole autonomy path** — bare `claude` is non-auto and will prompt normally.
- Stripped from `settings.local.json` template: `permissions.{defaultMode,allow,deny}` + entire `PermissionRequest` hooks block.
- Deleted hooks: `auto-approve-bash.sh`, `auto-approve-writes.sh`, `permission-debug.sh` (3 hooks gone).
- Deleted skill: `pkg/.aihaus/skills/aih-automode/` (the entire directory + 3 annexes). Typing `/aih-automode` returns skill-not-found, mirroring the M012 hard-rename precedent. Also deleted: `pkg/scripts/lib/restore-automode.sh`.
- Safety migrated entirely to PreToolUse: `bash-guard.sh` absorbed all 30+ M007 DANGEROUS_PATTERNS; `file-guard.sh` gained `$CLAUDE_PROJECT_DIR` path-scope check; NEW `read-guard.sh` denies `.env`/`.pem`/`.key`/`credentials*`/`id_*` reads.
- Subagent frontmatter `permissionMode: bypassPermissions` retained on `implementer`/`frontend-dev`/`code-fixer` as defense-in-depth.
- `install.sh` + `install.ps1` create `<target>/.aihaus/auto.sh` (and `.ps1`) symlink, hard-reject `--platform cursor` for DSP-related installs (ADR-005 boundary), and emit a soft warning if `claude --version` is below 2.0.0.

### Resume substrate fix (CORE)

`/aih-resume` no longer re-spawns from story 1 after a mid-implementer crash. Instead:

- **RUN-MANIFEST schema v3** — adds an additive `## Checkpoints` section: `| ts | story | agent | substep | event | result | sha |`. `event` ∈ `{enter, exit, resumed}`; `result` ∈ `{OK, ERR, SKIP}` (only on exit). Substep convention: `<kind>:<identifier>` (e.g. `file:foo.sh`, `step:cherrypick`). v3 = v2 + optional section — backward compatible with v2 readers; `manifest-migrate.sh` is idempotent + additive.
- **`manifest-append.sh`** gains 2 modes: `--checkpoint-enter <story> <agent> <substep>` and `--checkpoint-exit <story> <agent> <substep> <result> [<sha>]`. Auto-creates `## Checkpoints` if missing; rate-limits duplicate `enter` events within 1s.
- **Agent frontmatter** — all 46 agents declare `resumable: true|false` + `checkpoint_granularity: story|file|step`. Stateful (resumable=false): `implementer`, `frontend-dev`, `code-fixer` (file granularity); `debug-session-manager` (step). All 42 others are idempotent.
- **NEW `worktree-reconcile.sh`** — classifies each worktree as A (clean+merged → prune), B (clean+unmerged → emit cherry-pick recipe), C (dirty → preserve + surface). Auto-detects main branch via `origin/HEAD` → `main` → `pi-port` fallback chain.
- **NEW `_shared/checkpoint-protocol.md`** — binding rules for when agents emit checkpoints (entry/exit only, never mid-substep).
- **NEW `_shared/resume-handling-protocol.md`** — binding contract for stateful agents consuming `--resume-from <substep>` (free-text echo from manifest). The 4 stateful agents reference this annex via 1-line body pointers.
- **`/aih-resume` rewrite** — Phase 1 reads `## Checkpoints` last row authoritatively (no more file-existence heuristic), invokes `worktree-reconcile.sh`, cross-checks. Phase 2 branches on `resumable` field — re-spawn idempotent agents; dispatch stateful with `--resume-from`. Records resumption with `event=resumed`.
- **`--legacy-mode`** flag dispatches to `pkg/.aihaus/skills/aih-resume/annexes/legacy-mode.md` (preserved old heuristic flow). `REMOVE in M015 if no usage reported`.

### Governance

- **ADR-M014-A** in `pkg/.aihaus/decisions.md` — DSP launch supersedes ADR-M008-B; reconciles ADR-008/009 (M007 3-layer permission). The package decisions file gets the canonical write (was a long-standing drift between `pkg/.aihaus/decisions.md` and the dogfood-only `.aihaus/decisions.md`).
- **ADR-M014-B** — Resume substrate; extends ADR-004 (RUN-MANIFEST single-writer) additively.
- **COMPAT-MATRIX.md** — DSP marked NOT-SUPPORTED for Cursor (no equivalent CLI flag).

### Smoke-test additions

5 new dynamically-numbered checks: schema v2→v3 migration fixture, worktree-reconcile 3-category fixture, crash-mid-implementer + resume substep parse fixture, bash-guard contains M007 baseline DANGEROUS_PATTERNS, read-guard.sh existence/syntax. Plus Check 6 expanded from 6→8 required frontmatter fields.

### Hotfix included

`73de816` — `file-guard.sh` had two real bugs caught by self-dogfood: multi-arg grep pattern (each line treated as filename arg) + Windows path-scope comparison failed on backslash-vs-forward-slash mismatch between `realpath` output and `$CLAUDE_PROJECT_DIR`. Fixed via single combined regex + cross-platform path normalization (lowercase + slash + drive-prefix unify).

### Migration

```bash
# Re-install (settings template fully refreshed)
bash pkg/scripts/install.sh --target . --update

# Launch via the wrapper (DSP mode)
bash .aihaus/auto.sh

# Or on Windows PowerShell
.aihaus/auto.ps1
```

### Inventory after M014

- **Skills:** 12 (was 13 — `/aih-automode` deleted)
- **Agents:** 46 (CLAUDE.md was stale at 43; M013 added 4)
- **Hooks:** 20 (was 21; +read-guard +worktree-reconcile −auto-approve-bash −auto-approve-writes −permission-debug = -2)

### Open follow-ups (M015 candidates)

- A17 + Read-matcher live test (deferred via Option 2 fallback) — may collapse `read-guard.sh` to single matcher path
- `/aih-resume --legacy-mode` retirement
- Backfill M008-M013 ADRs into `pkg/.aihaus/decisions.md` (long-standing drift with dogfood copy)
- Smoke-test fixture for the D-S10-002 file-guard regression class

## [0.14.0] - 2026-04-16

- Cohort aliases shipped — `:planner` (17 agents), `:doer` (11), `:verifier` (11), `:adversarial` (4). Full mapping at `pkg/.aihaus/skills/aih-effort/annexes/cohorts.md` (Q-1 single source of truth)
- Joint `(model, effort)` tuple is the new calibration primitive — retires per-agent enumerations inside `presets.md`. 4 presets rewritten as cohort-tuple maps
- New CLI flags: `--cohort :<name> --model <m> --effort <e>` (both axes required); `--agent <name> --model <m> --effort <e>` (dual-axis escape hatch)
- `:adversarial` cohort is preset-immune — extends ADR-M008-C's 2-agent list (`plan-checker`, `contrarian`) to 4 agents (`reviewer`, `code-reviewer` added). Explicit `--cohort :adversarial` requires literal-word `adversarial` confirmation
- Sidecar schema v1 → v2 additive — new `cohort.<name>.model` + `cohort.<name>.effort` fields; per-agent `<agent>.model=<m>` override grammar. v1 sidecars keep restoring byte-identically via legacy dispatch
- ADR-M008-A amendment (M010) — scoped allowance for cohort-driven + explicit per-agent dual-axis `model:` edits. ADR-M010-A formalizes cohort taxonomy + preset-map shape
- Phase-1 distribution report now renders as GFM pipe table (5 columns: `Agent | Model | Effort | Cohort | PermissionMode`) — fixes box-drawing fragment clipping on cmd.exe / split panes / copy-back (independent S08 bugfix)
- Smoke-test suite extends to 28 checks — Check 27 gets A5 (adversarial explicit-entry honor); new Check 28 (v2 cohort round-trip, 6 assertions B1-B6)
- v0.14.0 ships functionally equivalent to v0.13.0 `cost-optimized` distribution (Q-2) — representational change; users opt into new vocabulary via `/aih-effort --preset <name>` (skill renamed from v0.13.0 name in v0.17.0)

## [0.8.0] - 2026-04-14

- Cursor coexistence layer (preview) at `cursor-preview/` — documentation-only, no code under `pkg/`
- Compat matrix classifying all 13 skills + 43 agents as WORKS / WORKS-WITH-CAVEAT / NOT-SUPPORTED
- ADR-002: aihaus remains Claude-Code-primary; Cursor support is compat-only
- Verified 2026-04-14: Cursor natively reads `.claude/skills/` and `.claude/agents/` as compat paths
- No installer changes; Cursor users copy `cursor-preview/aihaus.mdc` into `.cursor/rules/` manually

## [0.7.0] - 2026-04-14

- Relocated maintainer-only scripts from `pkg/scripts/` to new top-level `tools/`
- Added `tools/generate-release-notes.sh` to produce user-facing release-note drafts
- `pkg/scripts/` now contains only scripts users download (install/uninstall/update)
- New `## Releasing` section in `CLAUDE.md` documenting the workflow

## [0.1.0] - 2026-04-10

- Initial release
- 8 intent-based commands (init, plan, bugfix, feature, milestone, help, quick, sync-notion)
- /aih-init with project.md generation
- Cross-platform install script with symlink/junction support
