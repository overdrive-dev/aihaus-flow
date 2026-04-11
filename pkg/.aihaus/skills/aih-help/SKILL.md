---
name: aih-help
description: Show all available AIhaus workflow commands and their usage. Use when someone asks for help or types /aih-help.
disable-model-invocation: true
---

# AIhaus Workflow Commands

AIhaus is an intent-based workflow package. Each command asks its questions upfront, gets your approval once, then runs autonomously.

## Commands

| Command | What It Does | Use When |
|---------|-------------|----------|
| `/aih-init` | Bootstrap AIhaus in a project — creates `.aihaus/` layout and seeds project memory | First time using AIhaus in a repo |
| `/aih-plan [description]` | Research and write a plan without changing code | You want to think before building |
| `/aih-bugfix [description or error]` | Triage root cause, branch, fix, test, commit | Known bug or error message |
| `/aih-feature [description]` | Scoped feature: plan, branch, implement, test, commit — single agent | Change touching up to ~10 files |
| `/aih-milestone [description]` | Full milestone lifecycle: plan, architect, implement, QA — all autonomous after approval | Large feature or multi-story work |
| `/aih-help` | This help page | You forgot what's available |
| `/aih-quick [description]` | Fast-track a known change without planning overhead | Trivial change you already know how to do |
| `/aih-sync-notion [action]` | Sync the Notion Kanban board with current execution state | You mirror work to Notion |
| `/aih-update [--check\|--force]` | Update AIhaus to the latest version from the remote repo | New version available or agents need updating |

## Typical Flows

### Plan first, then build

```
/aih-plan Add rate limiting to the public API
  -> review plan, decide scope
/aih-feature --plan 260410-rate-limiting
  -> approve plan summary, walk away, come back to built code on a feature branch
```

### Straight to a milestone

```
/aih-milestone Multi-tenant workspaces
  -> answer scoping questions, approve plan
  -> walk away, come back to fully built milestone with QA
```

### Quick fixes

```
/aih-bugfix "TypeError: cannot read property 'id' of undefined"
  -> approve fix plan, walk away, come back to fix on a branch

/aih-quick Add missing import for the Status enum
  -> done immediately
```

## Project Memory

AIhaus reads `.aihaus/project.md` at the start of every command so every agent
shares the same project context — stack, conventions, verification commands, and
team norms — without you having to repeat them.

**What it contains:**
- Project name, purpose, and current status
- Tech stack and primary languages
- Directory conventions (where models, endpoints, components, tests live)
- Verification commands (build, typecheck, test, lint)
- Team norms that aren't obvious from code (branch policy, commit style, review rules)
- Links to `.aihaus/decisions.md` and `.aihaus/knowledge.md` if used

**How it is used:**
- `/aih-plan`, `/aih-feature`, `/aih-milestone`, `/aih-bugfix`, and
  `/aih-quick` all load it before doing any work
- Commands never print its contents to the user — it is silent context
- When you run `/aih-init`, a starter `.aihaus/project.md` is scaffolded for
  you to fill in

**Keeping it current:**
- Update it whenever the stack, conventions, or verification commands change
- Milestone completion may append to it when durable team norms emerge

## Artifacts Produced

All AIhaus artifacts live under `.aihaus/`:

- `.aihaus/project.md` — Project-level context loaded by every command
- `.aihaus/milestones/[M0XX]-[slug]/` — Full milestone artifacts (analysis, PRD, architecture, stories, execution logs, reviews)
- `.aihaus/features/[YYMMDD]-[slug]/` — Feature plan and summary
- `.aihaus/bugfixes/[YYMMDD]-[slug]/` — Triage and fix summary
- `.aihaus/plans/[slug]/` — Standalone plans from `/aih-plan`
- `.aihaus/memory/` — Persistent agent memory across sessions
- `.aihaus/decisions.md` — Optional project-wide ADR log
- `.aihaus/knowledge.md` — Optional project-wide lessons-learned log

## Tips

- Start with `/aih-plan` to research before committing to a command
- Use `/aih-feature` or `/aih-bugfix` for most day-to-day work
- Use `/aih-milestone` for large, multi-story features
- Use `/aih-quick` for trivial changes you already know how to do (< 5 files)
- All commands are one-gate: answer questions once, then fully autonomous
- Every artifact is git-tracked under `.aihaus/`
