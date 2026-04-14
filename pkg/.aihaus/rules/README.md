# aihaus on Cursor — PREVIEW

> Preview, not production. Feedback: https://github.com/overdrive-dev/aihaus-flow/discussions

aihaus is Claude-Code-primary. This `cursor-preview/` directory documents
the extent to which aihaus coexists with Cursor via Cursor's `.claude/*`
compatibility paths. It is documentation — no Cursor-specific code, no
installer changes, no changes to anything Claude Code users see.

## How aihaus and Cursor coexist

Cursor's Skills and Subagents subsystems natively read `.claude/skills/`
and `.claude/agents/` as legacy-compatibility paths (verified 2026-04-14,
see `.aihaus/research/cursor-primitives-verification.md`). aihaus's
standard installer symlinks these paths to `.aihaus/skills` and
`.aihaus/agents`. The result: on any machine with both tools installed,
aihaus skills and agents that do not depend on Cursor-contradicted
primitives are visible to Cursor without any port or adaptation.

Two primitives aihaus relies on are CONTRADICTED on Cursor:

1. `isolation: worktree` frontmatter (used by `implementer`,
   `frontend-dev`, `code-fixer`, `executor`, `nyquist-auditor`) — Cursor
   subagent frontmatter does not accept an `isolation` field.
2. `permissionMode: bypassPermissions` (used by the same worktree agents
   to run autonomously under `/aih-run`) — Cursor's only subagent
   permission field is `readonly: true`, which is the opposite of bypass.

Any skill that depends on those primitives is NOT-SUPPORTED on Cursor.
For the per-skill and per-agent verdict, see `COMPAT-MATRIX.md`.

## How to adopt the preview

**Step 1 — install aihaus normally.** Nothing Cursor-specific here; the
installer is unchanged:

```bash
git clone https://github.com/overdrive-dev/aihaus-flow ~/tools/aihaus
cd your-project
bash ~/tools/aihaus/pkg/scripts/install.sh --target .
```

This creates `.claude/skills` and `.claude/agents` as symlinks to
`.aihaus/skills` and `.aihaus/agents`. Cursor reads these automatically.

**Step 2 — copy the Cursor rules file into your project.** One file, one
command:

```bash
cp ~/tools/aihaus/cursor-preview/aihaus.mdc .cursor/rules/
```

The rules file documents tool-name translation
(`Agent` + `subagent_type:` → `Task` + `/name` mention), the hook event
rename (`userPromptSubmit` → `beforeSubmitPrompt`), and explicitly lists
flows that are NOT-SUPPORTED so Cursor's agent does not try to run them.

**Step 3 — consult the compatibility matrix.** Before invoking any skill
or agent from Cursor, check `COMPAT-MATRIX.md` for its status. The
matrix is hand-authored and dated; row status reflects a 2026-04-14
verification pass against the Cursor docs.

## What you get — and what you don't

**You get on Cursor:**
- Read-only research agents (`advisor-researcher`, `phase-researcher`,
  `domain-researcher`, `project-researcher`, `ui-researcher`,
  `ai-researcher`, `framework-selector`, `assumptions-analyzer`,
  `codebase-mapper`, `pattern-mapper`, `user-profiler`, `contrarian`).
- `/aih-help` — pure reference.
- `/aih-init` — bootstraps `project.md` (one write prompt).
- `/aih-plan`, `/aih-plan-to-milestone` — authoring flows that stop at a
  `PLAN.md` or milestone draft; no autonomous build.
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

If you want `/aih-run` milestone execution, use Claude Code. Cursor
preview is compat-only.

## Reversibility

This preview is designed to be reversed in one commit. To uninstall:

```bash
rm -rf ~/your-project/.cursor/rules/aihaus.mdc
```

On the aihaus side, deleting `cursor-preview/` + removing the README
subsection + removing the smoke-test lint + reverting ADR-002 restores
pre-preview state. No `pkg/` changes were made.

## Feedback

This is a preview. Report mismatches, missing matrix rows, breakage, or
ideas at https://github.com/overdrive-dev/aihaus-flow/discussions.

Signal threshold for continued investment: ≥3 distinct engagements
(issues, discussions, PRs — not stars) by 2026-06-01. Below that, the
preview will be sunset. See
`.aihaus/milestones/drafts/.pending/260601-cursor-preview-decision.md`.
