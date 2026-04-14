---
name: aih-help
description: Show all available aihaus workflow commands and their usage. Use when someone asks for help or types /aih-help.
disable-model-invocation: true
---

# aihaus Workflow Commands

aihaus is a four-pillar intent-based workflow package. **Scope** the work, optionally **promote** a plan into a milestone draft, **execute** autonomously, and **resume** if interrupted.

## ⚠️ Upgrading from v0.1.x? Read this first

**`/aih-run` is NOT a rename of `/aih-milestone`.** They are distinct commands with different jobs:

| Command | Job | Produces |
|---------|-----|----------|
| `/aih-milestone` | **Scope** — conversational gathering mode. You send context across multiple messages; each one is absorbed into a draft. Never executes. | Draft at `.aihaus/milestones/drafts/[slug]/` |
| `/aih-run` | **Execute** — runs whatever ready draft or plan you point at. Full autonomous pipeline (planning agents → team → stories → completion). | Milestone at `.aihaus/milestones/[M0XX]-[slug]/` |

The old `/aih-milestone "description"` one-shot flow was **split in two**. If you want the old behavior, pass `--execute`: `/aih-milestone "desc" --execute`.

`team-template.md` and `completion-protocol.md` moved from `aih-milestone/` to `aih-run/` because that's where the execution logic now lives. `/aih-milestone` only deals with drafts.

## Four-Pillar Command Surface

| Pillar | Commands | Purpose |
|--------|----------|---------|
| **Scope** | `/aih-plan`, `/aih-milestone`, `/aih-brainstorm` | Create plans / gather milestone context / explore fuzzy ideas |
| **Promote** | `/aih-plan-to-milestone` | Hand off a plan into a milestone draft for refinement |
| **Execute** | `/aih-run`, `/aih-feature`, `/aih-bugfix`, `/aih-quick` | Start autonomous work |
| **Continue** | `/aih-resume` | Pick up an interrupted run |

## All Commands

| Command | What It Does | Use When |
|---------|-------------|----------|
| `/aih-init` | Bootstrap aihaus in a project — creates `.aihaus/` layout and seeds project memory | First time using aihaus in a repo |
| `/aih-plan [description]` | Research and write a concrete, implementable plan without changing code — produces `PLAN.md` | You have a concrete task and want to think before building |
| `/aih-brainstorm "<topic>" [--panel <roles>] [--deep] [--research]` | Multi-specialist exploratory panel for fuzzy "how should we think about X" questions — produces `BRIEF.md` that feeds `/aih-plan --from-brainstorm` or `/aih-milestone --from-brainstorm` | The problem is open-ended and you want diverse perspectives before committing to an approach |
| `/aih-plan-to-milestone [slug]` | Promote a plan to a milestone draft for conversational refinement | Plan is big enough to warrant milestone treatment |
| `/aih-milestone [description]` | Enter gathering mode — iteratively build a milestone draft via conversation | You want to scope a milestone across multiple messages |
| `/aih-run [slug]` | Execute a ready milestone draft or plan — no slug required, picks from available | You have a draft/plan ready to execute |
| `/aih-resume [slug]` | Resume an interrupted run — detects in-progress work via RUN-MANIFEST.md | Session crashed, context reset, or you paused execution |
| `/aih-bugfix [description or error]` | Triage root cause, branch, fix, test, commit | Known bug or error message |
| `/aih-feature [description]` | Scoped feature: plan, branch, implement, test, commit — single agent | Change touching up to ~10 files |
| `/aih-quick [description]` | Fast-track a known change without planning overhead | Trivial change you already know how to do |
| `/aih-help` | This help page | You forgot what's available |
| `/aih-sync-notion [action]` | Sync the Notion Kanban board with current execution state | You mirror work to Notion |
| `/aih-update [--check\|--force]` | Update aihaus to the latest version from the remote repo | New version available or agents need updating |

## Typical Flows

### Conversational milestone (recommended for large work)

```
/aih-milestone Multi-tenant workspaces
  -> draft created, gathering mode active
(user sends more context messages)
  -> each message absorbed into CONTEXT.md
(user: "start" or /aih-run [slug])
  -> autonomous execution from draft
```

### Plan first, then promote to milestone

```
/aih-plan Add billing subsystem with Stripe
  -> PLAN.md created
/aih-plan-to-milestone 260412-billing
  -> milestone draft seeded from plan
(iterate context conversationally)
/aih-run 260412-billing
  -> full milestone execution
```

### Quick feature from a plan

```
/aih-plan Add rate limiting to the public API
/aih-run 260410-rate-limiting
  -> small plan → feature-style single-branch execution
```

### Resume after interruption

```
(session crashes during milestone execution)
(new session starts)
/aih-resume
  -> detects interrupted milestone, resumes from checkpoint
```

### Quick fixes

```
/aih-bugfix "TypeError: cannot read property 'id' of undefined"
/aih-quick Add missing import for the Status enum
```

## Backward Compat

- `/aih-milestone "desc" --execute` — one-shot behavior (pre-gathering-mode) preserved as escape hatch.
- `/aih-milestone --plan [slug]` — auto-routes to `/aih-plan-to-milestone [slug]`, then enters gathering.
- `/aih-feature --plan [slug]` — still works for feature-from-plan shortcuts.

## Project Memory

All commands read `.aihaus/project.md` at the start so every agent shares the same project context — stack, conventions, verification commands — without you repeating them.

## Adversarial Review (v0.3.0+)

Review-role agents (`code-reviewer`, `verifier`, `integration-checker`, `security-auditor`, `plan-checker`, `contrarian`) now operate under an adversarial contract: **zero findings without written justification triggers re-analysis**. Cynical stance by default — must prove the work is clean, not just assume it.

Applied at these gates:
- `/aih-plan` → `plan-checker` on the drafted plan
- `/aih-bugfix` → `code-reviewer` + `code-fixer` loop (2 iterations) after fix
- `/aih-feature` → `code-reviewer` + `code-fixer` + `verifier` + conditional `integration-checker`
- `/aih-quick` → single `code-reviewer` pass
- `/aih-run` → always-on `verifier` + `integration-checker`, systematic `security-auditor` for sensitive work
- `/aih-brainstorm` → `contrarian` round on panelist perspectives; `brainstorm-synthesizer` fans in all artifacts into `BRIEF.md`.

## Inter-agent Conventions

### CONVERSATION.md turn log

Used by multi-round agent workflows (e.g. `/aih-brainstorm`). Append-only ordered log. **The parent skill is the sole writer — agents NEVER get `Write` access to `CONVERSATION.md`; the parent skill appends turn blocks via heredoc after subagents return.** For parallel rounds, the skill appends turns in alphabetical-by-role order after all subagents return — deterministic, no interleaving. Per-agent artifact files (`PERSPECTIVE-<role>.md`, `CHALLENGES.md`, `RESEARCH.md`) are the baseline; the turn log is an optional escalation when later rounds must read prior rounds.

Two shapes share this filename, distinguished by the first line:

| Shape | First line | Used by |
|-------|-----------|---------|
| User-message log | `# Conversation Log: [slug]` | `/aih-milestone`, `/aih-plan-to-milestone` |
| Turn log | `# Conversation: [slug]` | `/aih-brainstorm` (and future panels) |

Turn block format (most recent last, `---` separator between turns):

```markdown
## Turn N — <agent-or-user> — <ISO-8601 timestamp>
<body>

---
```

See ADR-001 in `pkg/.aihaus/decisions.md` for rationale.

## Autonomous Execution — Troubleshooting Prompts

If you see lots of permission prompts during autonomous execution:

1. **Check you're on v0.4.1+.** Run `/aih-update --check`. The auto-approve hooks only work silently if `bash-guard.sh` and `file-guard.sh` have the jq-optional fallback (shipped in v0.4.0) AND `auto-approve-bash.sh` + `auto-approve-writes.sh` have it too (shipped in v0.4.1). Older installs prompt every command.

2. **Some prompts are hardcoded in Claude Code — not aihaus:**
   - `cd <path> && git <cmd>` → "Compound commands with cd and git require approval to prevent bare repo attacks." Post-v0.4.1 agents use `git -C <path> <cmd>` instead, which sidesteps the guard. If you see this prompt, it means an older agent definition is still in play — run `/aih-update`.
   - `rm -rf /`, `git push --force main`, drop table — blocked by aihaus `deny` list (intentional).
   - Writes to `.env`, credentials, `.pem`, `id_rsa` — blocked by file-guard (intentional).

3. **Terminal noise from git CRLF warnings (Windows)** — not permission prompts, just stderr spam. `/aih-init` on Windows will offer to create a `.gitattributes` that suppresses them. Or manually: `git config core.safecrlf false` in the repo.

## Living project.md (v0.4.0+)

`project.md` stays fresh without manual editing:
- **Inventory** refreshes mid-milestone after each story touches structural dirs (not just at completion).
- **Active Milestones** table auto-populates with gathering drafts, running milestones, paused runs. Updates on every state change.
- **Recent Decisions + Knowledge** show the last 5 ADRs and lessons, refreshed whenever those files change.
- Manual content in `project.md` (Glossary, your own notes) is preserved byte-for-byte outside the auto-populated markers.

## Intake Discipline (v0.4.0+)

During `/aih-milestone` gathering, `/aih-plan` research, `/aih-plan-to-milestone` handoff, and `/aih-sync-notion` triage, implementable mid-conversation requests are **captured** into the artifact's task list — never executed inline. Explicit execution signals ("fix this now", "just do it") hand off to `/aih-quick` or `/aih-bugfix` with an acknowledged context switch.

## Multimodal Attachments (v0.3.0+)

Paste images, screenshots, or drop files during any scoping or execution command. They persist under `.aihaus/[artifact-dir]/attachments/`, get referenced in the artifact's `## Attachments` section, and are passed to spawned agents so they can Read them via the Read tool. Survives sessions and `/aih-resume`.

## Artifacts

All artifacts live under `.aihaus/`:
- `.aihaus/project.md` — Project-level context
- `.aihaus/plans/[slug]/` — Plans from `/aih-plan`
- `.aihaus/milestones/drafts/[slug]/` — In-progress milestone drafts (CONTEXT.md, STATUS.md, CONVERSATION.md)
- `.aihaus/milestones/drafts/.archive/` — Drafts that have been promoted to milestones
- `.aihaus/milestones/[M0XX]-[slug]/` — Full milestone artifacts + RUN-MANIFEST.md checkpoint
- `.aihaus/features/[YYMMDD]-[slug]/` — Feature summaries + RUN-MANIFEST.md
- `.aihaus/bugfixes/[YYMMDD]-[slug]/` — Bugfix summaries + RUN-MANIFEST.md
- `.aihaus/memory/` — Persistent agent memory
- `.aihaus/decisions.md` / `.aihaus/knowledge.md` — Optional project-wide logs

## Autonomy
See `_shared/autonomy-protocol.md` — binding rules for planning/threshold/execution phases, no option menus, no honest checkpoints, no delegated typing. Overrides contradictory prose above.
