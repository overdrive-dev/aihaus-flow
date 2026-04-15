# aihaus on Cursor — Compatibility Matrix

**Last generated:** 2026-04-14
**Verification source:** `.aihaus/research/cursor-primitives-verification.md` (2026-04-14 live WebFetch pass)
**Scope:** every skill under `pkg/.aihaus/skills/` and every agent under `pkg/.aihaus/agents/` at the time of authoring.

## Legend

- **WORKS** — Runs on Cursor via `.claude/*` compat paths without modification or caveat.
- **WORKS-WITH-CAVEAT** — Functions, but with a behavioral delta Cursor users should know (permission prompts, tool-inheritance weakening, subagent-invocation vehicle rename, etc.).
- **NOT-SUPPORTED** — Depends on a Cursor-contradicted primitive (`isolation: worktree`, `permissionMode: bypassPermissions`). Should not be invoked from Cursor.

Rows are sorted by type (skill first, then agent), name ascending.

## Skills

| Name | Type | Status | Why | Last verified |
|------|------|--------|-----|---------------|
| aih-brainstorm | skill | WORKS-WITH-CAVEAT | Default conversational mode is single-turn, no agents — works as-is. `--panel` / `--deep` / `--research` modes spawn multiple subagents via `Agent` tool — on Cursor the vehicle is `Task` + `/name` mentions (see rules file translation table). | 2026-04-14 |
| aih-bugfix | skill | NOT-SUPPORTED | Spawns `implementer` (worktree-isolated) to apply the fix. Cursor has no `isolation: worktree` or `bypassPermissions` equivalent. Since v0.12.0, `disable-model-invocation` is removed — Cursor NL-trigger surface widens (Cursor honors the flag identically per cursor-primitives-verification.md:106-109). | 2026-04-14 |
| aih-feature | skill | NOT-SUPPORTED | Spawns `implementer` / `frontend-dev` (worktree-isolated) for the build step. Same primitive gap as aih-bugfix. Since v0.12.0, NL-trigger surface widens on Cursor (flag removed). | 2026-04-14 |
| aih-help | skill | WORKS | Pure read — prints command list. No subagents, no writes. | 2026-04-14 |
| aih-init | skill | WORKS-WITH-CAVEAT | Reads codebase, writes `project.md`. Cursor will surface a permission prompt on the write; accept to proceed. No worktree dependency. | 2026-04-14 |
| aih-milestone | skill | NOT-SUPPORTED | Gathering mode + `--plan` promotion work on Cursor, but `--execute` and start-intent trigger `annexes/execution.md` which spawns worktree-isolated `implementer`/`frontend-dev`/`code-fixer` agents — primitives absent on Cursor. Entire skill marked NOT-SUPPORTED to avoid partial-execution footgun. Since v0.12.0, NL-trigger surface widens on Cursor (flag removed). | 2026-04-14 |
| aih-plan | skill | WORKS-WITH-CAVEAT | Research + plan authoring. Writes `PLAN.md` only; no worktree, no autonomous implementation. Subagent fan-out uses `Task` vehicle on Cursor. Since v0.12.0: chained dispatch (Phase 4 threshold gate → `/aih-milestone --plan` or `/aih-feature --plan`) silently no-ops on Cursor when targeting NOT-SUPPORTED skills — use `--no-chain` to get the legacy print-suggestion behavior. | 2026-04-14 |
| aih-quick | skill | WORKS-WITH-CAVEAT | Parent-agent implementation — Cursor prompts per write (aihaus users on Claude Code autoapprove via `bypassPermissions`; Cursor has no equivalent). Final `code-reviewer` pass is read-only and works. Since v0.12.0: NL-trigger surface widens on Cursor (flag removed). | 2026-04-14 |
| aih-resume | skill | NOT-SUPPORTED | Resumes in-progress milestone / feature / bugfix flows, all of which depend on worktree-isolated implementer agents. | 2026-04-14 |
| aih-sync-notion | skill | WORKS-WITH-CAVEAT | Spawns `notion-sync` agent which has `tools: Read, Write, Edit, Grep, Glob, Bash`. No worktree dependency — works, but Cursor will prompt per write to milestone files and/or Notion MCP calls. | 2026-04-14 |
| aih-update | skill | WORKS-WITH-CAVEAT | Fetches and applies package updates from the aihaus remote. Runs `git` / `bash` commands the user must approve under Cursor's permission model. | 2026-04-14 |

## Agents

| Name | Type | Status | Why | Last verified |
|------|------|--------|-----|---------------|
| advisor-researcher | agent | WORKS | Read-only research agent. Tools: Read, Bash, Grep, Glob, WebSearch, WebFetch — no Write/Edit. | 2026-04-14 |
| ai-researcher | agent | WORKS | Research agent with Write for artifact authoring. No worktree dependency. Cursor prompts per write. | 2026-04-14 |
| analyst | agent | WORKS | Read + Bash tooling, no Write/Edit. No worktree dependency. | 2026-04-14 |
| architect | agent | WORKS | Read + Bash + WebFetch, no Write/Edit. Pure analysis. | 2026-04-14 |
| assumptions-analyzer | agent | WORKS | Read + Bash + Grep + Glob only. Read-only. | 2026-04-14 |
| brainstorm-synthesizer | agent | WORKS | Tools: Read, Write, Grep, Glob. Writes synthesis artifacts; no worktree dependency. | 2026-04-14 |
| code-fixer | agent | NOT-SUPPORTED | Declares `isolation: worktree` + `permissionMode: bypassPermissions`. Cursor subagent frontmatter does not accept `isolation`; no bypassPermissions equivalent. | 2026-04-14 |
| code-reviewer | agent | WORKS-WITH-CAVEAT | Tools: Read, Grep, Glob, Bash. No Write, but Cursor inheritance model means a child of this subagent could regain write tools unless `readonly: true` is set on the Cursor side. Read-only discipline is prompt-level. | 2026-04-14 |
| codebase-mapper | agent | WORKS | Tools: Read, Bash, Grep, Glob, Write. Writes map artifacts; no worktree dependency. | 2026-04-14 |
| contrarian | agent | WORKS-WITH-CAVEAT | Tools: Read, Grep, Glob (read-only whitelist). On Cursor, subagents inherit all parent tools — the read-only guarantee becomes prompt-level, not tool-level. Functional but weaker safety. | 2026-04-14 |
| debug-session-manager | agent | WORKS-WITH-CAVEAT | Tools: Read, Write, Bash, Grep, Glob, Task. Orchestrates `debugger` subagent. No worktree dependency; works but Cursor prompts per write. | 2026-04-14 |
| debugger | agent | WORKS-WITH-CAVEAT | Tools: Read, Write, Edit, Bash, Grep, Glob, WebSearch. Writes fixes directly. No worktree dependency — but Cursor prompts per write. For production autonomous debugging, stay on Claude Code. | 2026-04-14 |
| doc-verifier | agent | WORKS | Tools: Read, Write, Bash, Grep, Glob. Writes verification artifacts; no worktree dependency. | 2026-04-14 |
| doc-writer | agent | WORKS | Tools: Read, Write, Bash, Grep, Glob. No worktree dependency. | 2026-04-14 |
| domain-researcher | agent | WORKS | Research agent with Web tools + Write for artifacts. No worktree dependency. | 2026-04-14 |
| eval-auditor | agent | WORKS | Tools: Read, Write, Bash, Grep, Glob. No worktree dependency. | 2026-04-14 |
| eval-planner | agent | WORKS | Tools: Read, Write, Bash, Grep, Glob. No worktree dependency. | 2026-04-14 |
| executor | agent | NOT-SUPPORTED | Declares `isolation: worktree` + `permissionMode: bypassPermissions`. Same primitive gap as implementer. | 2026-04-14 |
| framework-selector | agent | WORKS | Tools: Read, Bash, Grep, Glob, WebSearch. Read-only. | 2026-04-14 |
| frontend-dev | agent | NOT-SUPPORTED | Declares `isolation: worktree` + `permissionMode: bypassPermissions`. | 2026-04-14 |
| implementer | agent | NOT-SUPPORTED | Declares `isolation: worktree` + `permissionMode: bypassPermissions`. The load-bearing write agent for `/aih-milestone` execution path. | 2026-04-14 |
| integration-checker | agent | WORKS | Tools: Read, Bash, Grep, Glob. Read-only audit. | 2026-04-14 |
| intel-updater | agent | WORKS | Tools: Read, Write, Bash, Glob, Grep. No worktree dependency. | 2026-04-14 |
| notion-sync | agent | WORKS-WITH-CAVEAT | Tools: Read, Write, Edit, Grep, Glob, Bash. No worktree dependency but talks to Notion MCP — Cursor prompts per write and per MCP call. | 2026-04-14 |
| nyquist-auditor | agent | NOT-SUPPORTED | Declares `isolation: worktree` + `permissionMode: bypassPermissions`. | 2026-04-14 |
| pattern-mapper | agent | WORKS | Tools: Read, Bash, Glob, Grep, Write. No worktree dependency. | 2026-04-14 |
| phase-researcher | agent | WORKS | Research agent with Web tools + Write. No worktree dependency. | 2026-04-14 |
| plan-checker | agent | WORKS-WITH-CAVEAT | Tools: Read, Grep, Glob, Bash. Read-only whitelist — Cursor inheritance weakens this (see contrarian). Functional. | 2026-04-14 |
| planner | agent | WORKS | Tools: Read, Write, Bash, Glob, Grep, WebFetch. No worktree dependency. | 2026-04-14 |
| product-manager | agent | WORKS-WITH-CAVEAT | Tools: Read, Grep, Glob, Bash. Read-only whitelist — Cursor weakens this. | 2026-04-14 |
| project-analyst | agent | WORKS-WITH-CAVEAT | Tools: Read, Grep, Glob, Bash. Same read-only-weakening caveat. | 2026-04-14 |
| project-researcher | agent | WORKS | Research agent with Web tools + Write. No worktree dependency. | 2026-04-14 |
| research-synthesizer | agent | WORKS | Tools: Read, Write, Bash. No worktree dependency. | 2026-04-14 |
| reviewer | agent | WORKS-WITH-CAVEAT | Tools: Read, Grep, Glob, Bash. Read-only whitelist — Cursor weakens this. Also: Cursor ships built-in `/agent-review`; relationship with aihaus `reviewer` is untested. | 2026-04-14 |
| roadmapper | agent | WORKS | Tools: Read, Write, Bash, Glob, Grep. No worktree dependency. | 2026-04-14 |
| security-auditor | agent | WORKS | Tools: Read, Write, Bash, Grep, Glob. No worktree dependency. | 2026-04-14 |
| test-writer | agent | WORKS-WITH-CAVEAT | Tools: Read, Write, Edit, Grep, Glob, Bash. Writes tests directly — Cursor prompts per write. Under `/aih-milestone` execution normally called inside an implementer worktree; outside that context on Cursor, still functional with permission prompts. | 2026-04-14 |
| ui-auditor | agent | WORKS | Tools: Read, Write, Bash, Grep, Glob. No worktree dependency. | 2026-04-14 |
| ui-checker | agent | WORKS-WITH-CAVEAT | Tools: Read, Bash, Glob, Grep. Read-only whitelist — Cursor inheritance weakens. | 2026-04-14 |
| ui-researcher | agent | WORKS | Tools: Read, Write, Bash, Grep, Glob, WebSearch, WebFetch. No worktree dependency. | 2026-04-14 |
| user-profiler | agent | WORKS-WITH-CAVEAT | Tools: Read only. Strongest read-only whitelist in the set — on Cursor this becomes a prompt-level constraint, not a tool-level one. | 2026-04-14 |
| ux-designer | agent | WORKS-WITH-CAVEAT | Tools: Read, Grep, Glob, Bash. Read-only whitelist — Cursor weakens this. | 2026-04-14 |
| verifier | agent | WORKS | Tools: Read, Write, Bash, Grep, Glob. No worktree dependency. | 2026-04-14 |

## Summary

- **Skills:** 11 rows — 2 WORKS, 5 WORKS-WITH-CAVEAT, 4 NOT-SUPPORTED.
- **Agents:** 43 rows — 25 WORKS, 13 WORKS-WITH-CAVEAT, 5 NOT-SUPPORTED.

## Maintenance

Update this matrix when:
- A new skill ships under `pkg/.aihaus/skills/`.
- A new agent ships under `pkg/.aihaus/agents/`.
- An agent's frontmatter gains/loses `isolation`, `permissionMode`, or `tools:` whitelist.
- Cursor ships a release that changes its `.claude/*` compat behavior, adds `isolation`-like fields, or modifies tool-inheritance defaults (re-fetch `.aihaus/research/cursor-primitives-verification.md` first, then update rows).

Rows that change status should bump their `Last verified` date to the date of re-check.
