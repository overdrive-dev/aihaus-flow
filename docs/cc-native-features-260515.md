# Claude Code Native Features — Research Catalog

**Date captured:** 2026-05-15 (M043 follow-up — addresses user request "analise com calma a documentação completa")
**Source URLs:**
- https://code.claude.com/docs/en/agent-teams
- https://code.claude.com/docs/en/worktrees
- https://code.claude.com/docs/en/agent-view
- https://code.claude.com/docs/en/sub-agents

This file captures verbatim quotes + verified facts from the 4 CC docs so future maintainers don't need to re-WebFetch. Each finding is tagged VERIFIED (quoted verbatim) or CITED (paraphrased with URL anchor).

---

## 1. Sub-Agents

### `skills:` frontmatter field — CRITICAL CONSTRAINTS

**VERIFIED** (`/en/sub-agents` §Preload skills into subagents, ~L407-425):

> "Use the `skills` field to inject skill content into a subagent's context at startup. This gives the subagent domain knowledge without requiring it to discover and load skills during execution."

```yaml
---
name: api-developer
description: Implement API endpoints following team conventions
skills:
  - api-conventions
  - error-handling-patterns
---
```

> "The full content of each listed skill is injected into the subagent's context at startup. This field controls which skills are preloaded, not which skills the subagent can access: without it, the subagent can still discover and invoke project, user, and plugin skills through the Skill tool during execution."

**HARD CONSTRAINT (load-bearing for M043 B1):**

> "**You cannot preload skills that set `disable-model-invocation: true`**, since preloading draws from the same set of skills Claude can invoke. If a listed skill is missing or disabled, Claude Code skips it and logs a warning to the debug log."

**Implication for aihaus M044+ B1:** the proposed `aih-binding-context` skill (modeled on `aih-help` which has `disable-model-invocation: true`) **would be silently skipped at preload time**. To preload, the skill must be invocable (`disable-model-invocation: false` or absent).

### `memory:` field — verified semantics

**VERIFIED** (`/en/sub-agents` §Enable persistent memory):

> "The `memory` field gives the subagent a persistent directory that survives across conversations."

| Scope | Location | Use when |
|-------|----------|----------|
| `user` | `~/.claude/agent-memory/<name-of-agent>/` | broad applicability across projects |
| `project` | `.claude/agent-memory/<name-of-agent>/` | project-specific, version-controllable |
| `local` | `.claude/agent-memory-local/<name-of-agent>/` | project-specific, not VCS |

> "The subagent's system prompt also includes the first **200 lines or 25KB** of `MEMORY.md` in the memory directory, whichever comes first, with instructions to curate `MEMORY.md` if it exceeds that limit."

### `isolation: worktree` field — verified

**VERIFIED** (`/en/sub-agents` frontmatter table):

> "Set to `worktree` to run the subagent in a temporary [git worktree](/en/worktrees), giving it an isolated copy of the repository. The worktree is automatically cleaned up if the subagent makes no changes."

### Subagent invocation paths

**VERIFIED**: subagents can be spawned via:
- Task/Agent tool (from main session) — **aihaus's primary path**
- `claude --agent <name>` CLI as main-session agent
- `@<name>` mention in agent-view dispatch input

The `skills:` field applies **"at startup"** in all paths per docs §407 — does NOT specify Task-tool exclusion. **Inference:** works for Task-tool spawn (aihaus path) but unverified by canary test on disk.

### Built-in subagents

- **Explore** — Haiku model, read-only tools, file discovery
- **Plan** — inherits parent model, read-only, plan-mode research
- **General-purpose** — inherits parent model, all tools, complex tasks

Aihaus's 48-agent catalog runs alongside (not replaces) these.

---

## 2. Agent Teams

### Enablement

**VERIFIED** (`/en/agent-teams` §Enable agent teams):

> "Agent teams are disabled by default. Enable them by setting the `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` environment variable to `1`, either in your shell environment or through [settings.json](/en/settings):"

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

**Verified in aihaus:** `pkg/.aihaus/templates/settings.local.json:env` already ships this env var set to `"1"`. But **no aihaus skill currently invokes Agent Teams primitives** (`SendMessage`, `teammate_name`, `task_subject`).

### Subagent ↔ Teammate semantics

**VERIFIED CRITICAL** (`/en/agent-teams` §Use subagent definitions for teammates):

> "The `skills` and `mcpServers` frontmatter fields in a subagent definition are **not applied when that definition runs as a teammate**. Teammates load skills and MCP servers from your project and user settings, the same as a regular session."

> "The teammate honors that definition's `tools` allowlist and `model`, and the definition's body is **appended to the teammate's system prompt** as additional instructions rather than replacing it."

**Implication for aihaus M044+:** if we wire Agent Teams (e.g., `/aih-brainstorm --team`), our 48-agent definitions' `skills:` field (when added in B1) would be silently ignored when they run as teammates. Plan accordingly.

### Architecture

| Component | Role |
|-----------|------|
| Team lead | Main Claude Code session — coordinates work |
| Teammates | Separate Claude Code instances — each w/ own context window |
| Task list | Shared list at `~/.claude/tasks/{team-name}/` |
| Mailbox | Messaging system between agents |

**Storage:**
- Team config: `~/.claude/teams/{team-name}/config.json`
- Task list: `~/.claude/tasks/{team-name}/`

### Hooks for Agent Teams

**VERIFIED** new hook events:
- `TeammateIdle` — fires before teammate idles; exit code 2 sends feedback, keeps working
- `TaskCreated` — exit code 2 prevents creation
- `TaskCompleted` — exit code 2 prevents completion

**Verified in aihaus:** `pkg/.aihaus/hooks/teammate-idle.sh` exists as a stub; `task-created.sh` exists as audit-only. No `task-completed.sh`.

### Limitations (experimental)

- No `/resume` for in-process teammates
- No nested teams (teammates can't spawn teammates)
- Lead is fixed (can't promote teammate to lead)
- Permissions set at spawn (inherits from lead)
- Split-pane requires tmux or iTerm2 (Windows Terminal / VS Code integrated unsupported)
- One team at a time per Claude Code session

### Display modes

- **In-process** (default): all teammates in main terminal; Shift+Down cycles
- **Split panes**: tmux or iTerm2; each teammate own pane
- `teammateMode` setting in `~/.claude/settings.json`

---

## 3. Worktrees

### `--worktree` flag — verified

**VERIFIED** (`/en/worktrees` §Start Claude in a worktree):

> "Pass `--worktree` or `-w` to create an isolated worktree and start Claude in it. By default, the worktree is created under `.claude/worktrees/<value>/` at your repository root, on a new branch named `worktree-<value>`."

```bash
claude --worktree feature-auth
```

PR worktree: `claude --worktree "#1234"` — fetches `pull/<number>/head`, creates at `.claude/worktrees/pr-<number>`.

### `.worktreeinclude` — verified REAL feature

**VERIFIED** (`/en/worktrees` §Copy gitignored files into worktrees):

> "A worktree is a fresh checkout, so untracked files like `.env` or `.env.local` from your main repository are not present. To copy them automatically when Claude creates a worktree, add a `.worktreeinclude` file to your project root."

> "The file uses `.gitignore` syntax. **Only files that match a pattern and are also gitignored are copied**, so tracked files are never duplicated."

```text .worktreeinclude
.env
.env.local
config/secrets.json
```

> "This applies to worktrees created with `--worktree`, subagent worktrees, and parallel sessions in the desktop app."

**M043 verification:** all 5 paths in aihaus's `.worktreeinclude` (`.aihaus/.effort`, `.aihaus/.install-source`, `.aihaus/.calibration`, `.aihaus/auto.sh`, `.aihaus/auto.ps1`) are matched by `/.aihaus/` gitignore rule (`git check-ignore -v` confirmed). Copy semantics will apply.

### Cleanup lifecycle

- **No changes**: worktree + branch auto-removed
- **Uncommitted/untracked/new commits**: prompt to keep or remove
- **Subagent worktrees**: auto-removed if no changes; orphans swept on startup per `cleanupPeriodDays`

### Settings

- `worktree.baseRef` — `"fresh"` (default, `origin/HEAD`) or `"head"` (local HEAD with unpushed work)

### Non-git VCS

Configure `WorktreeCreate` + `WorktreeRemove` hooks to provide custom logic. **Important:** `.worktreeinclude` is NOT processed when custom hook replaces default git behavior.

---

## 4. Agent View

### CLI surface

**VERIFIED** (`/en/agent-view` §Manage sessions from the shell):

| Command | Purpose |
|---------|---------|
| `claude agents` | Open agent view TUI (pass `--cwd <path>` to scope) |
| `claude attach <id>` | Attach to a session |
| `claude logs <id>` | Print recent output |
| `claude stop <id>` | Stop a session |
| `claude respawn <id>` | Restart with conversation intact |
| `claude respawn --all` | Restart all stopped sessions |
| `claude rm <id>` | Remove from list + cleanup worktree if clean |

Dispatch from shell:
```bash
claude --bg "investigate the flaky test"
claude --bg --name "flaky-test-fix" --agent code-reviewer "..."
```

After backgrounding, Claude prints session ID:
```
backgrounded · 7c5dcf5d
  claude agents             list sessions
  claude attach 7c5dcf5d    open in this terminal
  claude logs 7c5dcf5d      show recent output
  claude stop 7c5dcf5d      stop this session
```

### State machine

| State | Icon | Meaning |
|-------|------|---------|
| Working | Animated | Running tools / generating |
| Needs input | Yellow | Waiting on question/permission |
| Idle | Dimmed | Nothing to do |
| Completed | Green | Finished |
| Failed | Red | Errored |
| Stopped | Grey | `Ctrl+X` or `claude stop` |

Process shapes: `✻` alive, `∙` exited (auto-restarts), `✢` `/loop` sleeping.

### PR status dots

When session opens a PR, dot at row-edge:
- Yellow: checks failing/pending
- Green: clean, mergeable
- Purple: merged
- Grey: draft/closed

### Worktree integration

**VERIFIED** (`/en/agent-view` §How file edits are isolated):

> "Every background session, whether started from agent view, `/bg`, or `claude --bg`, starts in your working directory. Before editing files, Claude moves the session into an isolated [git worktree](/en/worktrees) under `.claude/worktrees/`, so parallel sessions can read the same checkout but each writes to its own."

> "To make a subagent always run in its own worktree regardless of how it was started, set `isolation: worktree` in its frontmatter."

### Subagents in Agent View

**VERIFIED**: "[Subagents](/en/sub-agents) and [teammates](/en/agent-teams) a session spawns aren't listed as separate rows."

**Implication:** if aihaus dispatches an isolated subagent (implementer in worktree), it does NOT appear in `claude agents`. Only the parent session does.

### Storage

- Daemon log: `~/.claude/daemon.log`
- Roster: `~/.claude/daemon/roster.json`
- Per-session state: `~/.claude/jobs/<id>/state.json`

### Settings to disable

- `disableAgentView: true` in settings
- `CLAUDE_CODE_DISABLE_AGENT_VIEW=1` env var

### Version requirements

Agent View: Claude Code v2.1.139+
Per-claude-agents flags (`--permission-mode`, `--model`, `--effort`): v2.1.142+
Agent Teams: v2.1.32+

### Limitations (research preview)

- Rate limits apply per-session (10 parallel = 10× quota)
- Sessions local, stop on sleep/shutdown (`claude respawn --all` to restart)
- Worktrees deleted with session — merge/push first

---

## Quick-reference table — Native vs aihaus

| Concept | Native CC | Aihaus extension/overlay |
|---------|-----------|--------------------------|
| Subagent context preload | `skills:` frontmatter (constraint: invocable only) | `pkg/.aihaus/hooks/context-inject.sh` (M013/S05, SubagentStart hook) |
| Subagent persistent memory | `memory: user\|project\|local` | Used directly (46/48 agents declare `memory: project`) |
| Worktree isolation | `isolation: worktree` frontmatter | Used directly (5 agents); `merge-back.sh` extends with cross-story refuse |
| Worktree file copy | `.worktreeinclude` (gitignore syntax) | M043/S1 shipped (5 sidecars) |
| Background sessions | `claude --bg`, `claude agents` TUI | UNUSED (no skill leverages — M044+ candidate B4) |
| Multi-session coordination | Agent Teams (env-gated) | env-VAR enabled but UNUSED in skills (M044+ candidate B3) |
| Effort tier | `effort:` frontmatter | Used directly via M008 cohort taxonomy |
| Permission inheritance | `permissionMode:` frontmatter | Overlaid by `autonomy-guard.sh` policy enforcement |

---

## Open follow-ups for aihaus

1. **M044/S1 — Native `skills:` field canary test under Task-tool spawn.** Verify whether preload fires with our Task/Agent-tool dispatch. Use observable nonce (FIRST tool call = read sentinel file) since agent can't introspect own system prompt directly.

2. **M044/S2 — Agent Teams pilot in `/aih-brainstorm --team`.** Topic-divergence + cross-challenge is the canonical Agent Teams use case ("competing hypotheses" debate). Must account for `skills:`/`mcpServers` IGNORED when subagent runs as teammate.

3. **M044/S3 — Agent View leverage.** Two candidates: (a) `aih-milestone --bg` wrapper around `claude --bg`; (b) statusLine cross-ref ("For multi-milestone view, run `claude agents`"). Note: aihaus subagents don't appear as separate rows.

4. **M044/S4 — `context-budget.conf` M027 propagation.** Currently `:adversarial-scout` + `:adversarial-review` keys; M027 merged into `:adversarial`. 6 adversarial agents fall through to doer 2500 default instead of intended 3000.

5. **M044/S5 — aih-graph indexing of `.claude/agent-memory/*/MEMORY.md`.** New node type ("AgentMemory" or extend "Agent" with memory_excerpt field). Cross-agent semantic query via existing hybrid mode.
