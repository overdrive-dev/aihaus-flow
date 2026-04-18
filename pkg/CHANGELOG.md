# Changelog

> [!IMPORTANT]
> aihaus-flow is no longer maintained.
>
> For ongoing use, start with [`gsd2`](https://github.com/gsd-build/gsd-2) or [`gsd1`](https://github.com/gsd-build/get-shit-done) instead. This changelog remains here as historical reference only.

All notable changes to aihaus are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
