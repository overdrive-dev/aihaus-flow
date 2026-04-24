# Changelog

All notable changes to aihaus are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.20.0] - 2026-04-24 — M016: agent memory + context passing + self-recycling evolution

Operationalizes M013's substrate end-to-end across data-plane (recurrence + composite scoring + per-cohort budgets + cache + telemetry) and file-plane (EVOLVING blocks in `project.md` + `CLAUDE.md`, per-agent memory pattern, SKILL-EVOLUTION ledger, unconditional curator cadence). Mid-milestone gate caught two BLOCKERs in flight (ADR-M015-A ID collision → renumbered M015→M016; telemetry single-writer violation → refactored stdout-only).

### Added

- **Hooks:** `pkg/.aihaus/hooks/warning-recurrence.sh` (185 LOC, Jaccard-similarity clustering primary per S00 noise-floor verdict 100%), `composite-score.sh` (299 LOC, 3 deterministic subscores), `scaffold-assert.sh` (62 LOC, exit-13 gate on `planning→running`)
- **Hook config:** `pkg/.aihaus/hooks/context-budget.conf` (6-cohort defaults: planner-binding=4000, planner=3000, doer=2500, verifier=1500, adversarial-scout=3000, adversarial-review=3000)
- **Skills annexes:** `pkg/.aihaus/skills/_shared/per-agent-memory.md` (parse contract + Q2 emission threshold), `pkg/.aihaus/skills/aih-milestone/annexes/milestone-scoped/SKILL-EVOLUTION.md` (template scaffold)
- **Templates:** `pkg/.aihaus/templates/gitignore-fragment` (manual fallback)
- **Memory README:** `pkg/.aihaus/memory/agents/README.md` (per-agent contract doc)
- **Tools:** `tools/telemetry-collect.sh` (maintainer-only, stdout-only post-BLOCKER-2), `tools/s00-noise-floor-check.sh` (synthetic-fixture noise-floor analysis)
- **Smoke-test checks (5 net new):** Check 43 `/aih-init` regression test (S13), Check 44 filename-prefix guard on per-agent memory tree (S15a), Check 45 EVOLVING block well-formed (S16), Check 46 SKILL-EVOLUTION post-apply sub-modes accessible (S16), Check 47 `memory-scores.jsonl` single-writer prose assertion (S16). All PURPOSE-labeled (no integer hardcoding per R12).
- **JSONL audit files (3 new):** `.claude/audit/warning-recurrence.jsonl`, `.claude/audit/memory-scores.jsonl`, `.claude/audit/evolution-apply.jsonl` — all single-writer per ADR-M016-A writer table.
- **Sidecar:** `.aihaus/.context-budgets` (user-owned, ADR-M009-A precedent; per-agent budget overrides)
- **ADRs:** ADR-M016-A (data-plane: scoring, supersession blocks, writer discipline, α-discrepancy disclosure, M017 kill-switch), ADR-M016-B (file-plane: EVOLVING blocks, per-agent memory writer, scaffold-assert.sh as Step E2 gate, 4 PURPOSE-labeled smoke-test checks). ADR-M013-A row-additive amendment via S13 (Cluster A reconciliation byte-identical with ADR-M016-B).

### Changed

- **`pkg/.aihaus/hooks/learning-advisor.sh`:** schema v1→v2 (additive — `recurrence_count`, `last_seen_milestone`, `recurrence_hash`, `schema_version`). Existing fields preserved; v1 readers tolerate.
- **`pkg/.aihaus/hooks/context-inject.sh`:** +247 LOC across S05 (recurring-warnings feedback loop) + S06 (per-cohort budgets + sidecar overrides) + S07 (5-min cache mirroring learning-advisor pattern + `cache_hit` audit field).
- **`pkg/.aihaus/hooks/phase-advance.sh`:** wired `scaffold-assert.sh` invocation on `planning→running` transition (exit 13 propagates).
- **`pkg/.aihaus/skills/aih-milestone/annexes/execution.md`:** Step E2 prose updated to scaffold both AGENT-EVOLUTION.md AND SKILL-EVOLUTION.md unconditionally; new Step E5.5 (mid-milestone adversarial gate primitive, ADR-M016-A governed).
- **`pkg/.aihaus/skills/aih-milestone/completion-protocol.md`:** Step 4.5 audit emission unconditional (closes M014 silent-skip class); new Step 4.6 (skill-evolution apply with smoke-test gate); existing Step 4.6 renamed to 4.6b; new Step 4.7b (per-agent memory apply); Step 6.5 cache invalidation; Step 6.7 telemetry-collect orchestrator-Edit pattern (post-BLOCKER-2).
- **`pkg/.aihaus/agents/*.md` (46 files):** `## Per-agent memory (optional)` template appended; opt-in emission contract per Q2 (prose-only threshold).
- **`pkg/.aihaus/agents/knowledge-curator.md`:** prompt amended for unconditional cadence + Q1 `<!-- no-signal-this-milestone -->` marker on empty inputs (S15b).
- **`pkg/scripts/install.sh` + `install.ps1`:** idempotent `.gitignore` injection with guard-comment block (S04.5).
- **`pkg/scripts/update.sh` + `update.ps1`:** new `--no-gitignore` flag + explicit user-prompt gate for one-shot backfill on existing installs (S04.6).
- **`pkg/.aihaus/templates/project.md`:** nested EVOLVING block inside MANUAL section (S13).
- **`CLAUDE.md`:** EVOLVING block appended at EOF (S14; CRLF-preserving).

### Mid-flight saves

- **BLOCKER 1 (commit `9a75840`):** ADR-M015-A ID collision with shipped v0.19.0 cursor-removal ADR. Renumbered the entire milestone M015→M016 (all hook headers, ADR cross-refs, story files, branch name, dir name).
- **BLOCKER 2 (commit `6c41847`):** `tools/telemetry-collect.sh` violated ADR-M013-A's single-writer invariant by writing `.aihaus/memory/global/architecture.md` directly. Refactored stdout-only; orchestrator captures + Edit-applies at completion-protocol Step 6.7.
- **CRITICAL bootstrap (S17 catch):** M016's own `SKILL-EVOLUTION.md` scaffold missing because `scaffold-assert.sh` didn't exist when M016 transitioned `planning→running`. Trivial fix; future milestones gated correctly.

### Upgrade impact

Downstream users running `bash pkg/scripts/update.sh --target /path` will be prompted to backfill `.gitignore` with `.aihaus/audit/` + `.claude/audit/` paths (`--no-gitignore` flag bypasses). New installs get the injection automatically. Pre-existing user content in `project.md` MANUAL section (outside the new nested EVOLVING block) and in `CLAUDE.md` (outside the new appended EVOLVING block) remains entirely untouched.

### Verification

`bash tools/smoke-test.sh` 47/47 PASS. `bash tools/purity-check.sh` PASS. E7 verifier=PASS (10/10 PRD acceptance criteria with evidence). E7 integration-checker=PASS (15/15 e2e chains intact).

## [0.19.1] - 2026-04-22 — Migration messaging fix-ups

Patch release. Two fix-ups discovered during dogfood `/aih-update` from v0.17.0:

- **`pkg/scripts/lib/merge-settings.sh`** — the post-merge "Settings migrated" notice still claimed `permissions.allow replaced by template defaults (includes Bash(*) wildcard)`. That message was true pre-M014 but stale after the v0.18.0 strip. Rewritten to detect legacy `permissions.allow` carried over from older installs and explain that the template no longer ships any `permissions.{allow,deny,defaultMode}` — autonomy now comes from the DSP wrapper + PreToolUse hooks. Includes guidance for completing the migration by removing the vestigial `permissions.allow` array.
- **`pkg/.aihaus/skills/aih-update/SKILL.md`** — added two new version-gated migration notice blocks:
  - `prev_version < 0.18.0` — DSP launch boundary (M014, BREAKING): documents `/aih-automode` deletion, the `bash .aihaus/auto.sh` launch path, the permission-stack strip, and the resume-substrate rewrite. Points at ADR-M014-A and ADR-M014-B.
  - `prev_version < 0.19.0` — Cursor removal boundary (M015, BREAKING): documents the `--platform` flag removal, the deleted plugin/rules dirs, and ADR-M015-A.

No functional code changes; no agent / skill / hook count changes (12 / 46 / 20 unchanged).

## [0.19.0] - 2026-04-22 — Drop Cursor support (BREAKING)

**BREAKING.** Cursor support is removed entirely. aihaus is Claude Code-only going forward.

### Removed

- `pkg/.aihaus/rules/` directory (`aihaus.mdc`, `COMPAT-MATRIX.md`, `README.md`) -- Cursor plugin rules
- `pkg/.aihaus/.cursor-plugin/` directory (`plugin.json`, `README.md`) -- Cursor plugin manifest
- `--platform` flag from `install.sh`, `install.ps1`, `uninstall.sh`, `uninstall.ps1`
- Cursor cleanup block from `uninstall.sh` (no longer removes `~/.cursor/plugins/local/aihaus`)
- "Multi-platform authoring" section from `CLAUDE.md`
- Cursor badge and "Claude Code AND Cursor" claims from `README.md`

### Governance

- ADR-M015-A supersedes ADR-002 and ADR-005

### Migration

If you had aihaus installed on Cursor: re-install on Claude Code via `bash pkg/scripts/install.sh --target .` and launch via `bash .aihaus/auto.sh` (M014 v0.18.0 wrapper).

### Inventory unchanged

12 skills / 46 agents / 20 hooks (no change from v0.18.0 -- this feature only deletes the Cursor-specific layer).

---

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
