# Changelog

All notable changes to aihaus are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
