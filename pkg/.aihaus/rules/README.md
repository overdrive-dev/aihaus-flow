# aihaus on Cursor

aihaus is multi-platform — Cursor and Claude Code are both first-class install targets.
This directory holds the Cursor-facing rules file and compatibility matrix that travel
with the aihaus plugin when installed into a Cursor workspace (see ADR-005 in
`pkg/.aihaus/decisions.md`).

## How aihaus and Cursor coexist

Cursor's Skills and Subagents subsystems natively read `.claude/skills/`
and `.claude/agents/` as legacy-compatibility paths (verified 2026-04-14,
see `.aihaus/research/cursor-primitives-verification.md`). aihaus's
installer can target either `.claude/` (for Claude Code) or the Cursor
plugin root, so after `install.sh --target .` all aihaus skills and
agents that do not depend on Cursor-contradicted primitives are visible
to Cursor without any port or adaptation.

Two primitives aihaus relies on are CONTRADICTED on Cursor:

1. `isolation: worktree` frontmatter (used by `implementer`,
   `frontend-dev`, `code-fixer`, `executor`, `nyquist-auditor`) — Cursor
   subagent frontmatter does not accept an `isolation` field.
2. `permissionMode: bypassPermissions` (used by the same worktree agents
   to run autonomously under `/aih-run`) — Cursor's only subagent
   permission field is `readonly: true`, which is the opposite of bypass.

Any skill that depends on those primitives is NOT-SUPPORTED on Cursor.
For the per-skill and per-agent verdict, see `COMPAT-MATRIX.md`.

## Install on Cursor

```bash
git clone https://github.com/overdrive-dev/aihaus-flow ~/tools/aihaus
cd your-project
bash ~/tools/aihaus/pkg/scripts/install.sh --target . --platform cursor
```

The installer detects `--platform cursor` and symlinks (or copies, with
`--copy`) `~/.cursor/plugins/local/aihaus` → `pkg/.aihaus/`. Cursor's
plugin subsystem reads the manifest at `pkg/.aihaus/.cursor-plugin/plugin.json`
and discovers rules/, skills/, agents/, and hooks/ as siblings.

**After install, restart Cursor** to pick up the new plugin. Hot-reload
of `~/.cursor/plugins/local/` additions is not confirmed in the docs
(see Story 1 research notes); restart is the safe default.

Default `--platform` is auto-detected from the environment
(`CURSOR_*` env vars → cursor; `CLAUDE_*` → claude; both/neither → claude
with a warning). `--platform both` installs to both targets when the
machine runs both tools.

## What you get — and what you don't

**You get on Cursor:**
- Read-only research agents (`advisor-researcher`, `phase-researcher`,
  `domain-researcher`, `project-researcher`, `ui-researcher`,
  `ai-researcher`, `framework-selector`, `assumptions-analyzer`,
  `codebase-mapper`, `pattern-mapper`, `user-profiler`, `contrarian`).
- `/aih-help` — pure reference.
- `/aih-init` — bootstraps `project.md` (one write prompt).
- `/aih-plan`, `/aih-milestone --plan [slug]` — authoring flows that stop
  at a `PLAN.md` or milestone draft; no autonomous build.
- `/aih-brainstorm` in default conversational mode — ping-pong
  exploration, no agents spawned.
- `/aih-quick` — parent-agent implementation; Cursor prompts per write.

**You do NOT get on Cursor:**
- `/aih-run` — autonomous milestone execution. The load-bearing autonomy
  flow. Stays on Claude Code.
- `/aih-feature` and `/aih-bugfix` — both spawn worktree-isolated
  implementer agents.
- `/aih-resume` — resumes the above.
- Any subagent declaring `isolation: worktree` or
  `permissionMode: bypassPermissions`.

If you need `/aih-run` milestone execution, use Claude Code. Cursor
coverage is intentionally partial while Cursor's primitives differ.

## Uninstall

```bash
bash ~/tools/aihaus/pkg/scripts/uninstall.sh --platform cursor
```

Removes `~/.cursor/plugins/local/aihaus`. Your project's `.aihaus/` runtime
state is preserved.

## Feedback

Report mismatches, missing matrix rows, or breakage at
https://github.com/overdrive-dev/aihaus-flow/discussions.
