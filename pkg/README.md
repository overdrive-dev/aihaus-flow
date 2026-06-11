<div align="center">

# aihaus

```
    _    ___ _
   / \  |_ _| |__   __ _ _   _ ___
  / _ \  | || '_ \ / _` | | | / __|
 / ___ \ | || | | | (_| | |_| \__ \
/_/   \_\___|_| |_|\__,_|\__,_|___/
```

**You think. ai builds.**

### aihaus 3.0 — specialist agents that run *inside* gated workflows, with local memory and role-based access.

**Describe what you want in plain language. aihaus routes it into a staged workflow, runs specialist agents inside that workflow — each in its own isolated worktree — gates every step, tracks the run on a local kanban, and keeps everything it learns about your repo on your machine.**

[![License](https://img.shields.io/badge/license-MIT-blue?style=for-the-badge)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.39.0-181717?style=for-the-badge&logo=github)](VERSION)
[![aihaus 3.0](https://img.shields.io/badge/aihaus-3.0%20·%20native--first-7c3aed?style=for-the-badge)](#what-aihaus-30-is)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-first--class-d97757?style=for-the-badge)](https://claude.ai/code)

<br>

```bash
# 1 — Install aihaus (machine-once)
git clone https://github.com/overdrive-dev/aihaus-flow "$XDG_DATA_HOME/aihaus"
bash "$XDG_DATA_HOME/aihaus/pkg/scripts/install.sh"

# 2 — Bind it to a project (inside Claude Code)
cd ~/myproject && claude
> /aih-install
> /aih-init                      # writes project.md, captures roles + env

# 3 — Launch with full autonomy (DSP wrapper)
bash .aihaus/auto.sh
```

Runs on macOS, Windows, Linux. No runtime, no build step — just markdown and shell scripts.

<br>

[What 3.0 is](#what-aihaus-30-is) · [Workflows](#workflows) · [Memory](#memory) · [Roles](#roles) · [The Engine](#the-engine) · [Commands](#commands)

</div>

---

## What aihaus 3.0 is

aihaus 3.0 is **specialist agents running inside gated workflows, with local memory and role-based access.**

- ⚙️ **Agents inside workflows.** You don't prompt one model and hope. A natural-language request auto-routes into a **staged workflow**; specialist agents execute the stages — each in its own isolated git worktree — and **every stage is gated** (understood → planned → tested → reviewed → shipped). The live state is a **local kanban**.
- 🧠 **With memory.** Everything aihaus learns about your repo — decisions, conventions, environment, even a code-aware index — lives in **local files**, auto-loaded into every session and agent. Nothing is hosted.
- 🔐 **And roles.** Who can do what is a **real, hook-enforced barrier**: only a `devops` profile crosses the staging→prod line. A `builder` scopes and builds features locally — and *cannot* deploy.

> [!NOTE]
> **Native-first.** aihaus 3.0 builds on Claude Code's own primitives — native `/goal`, native plan mode, the native task list, native git worktrees, native subagent memory — and layers the gates, roles, kanban, and memory engine *on top*. It does **not** reinvent them. There is no `aih-goal` skill in 3.0; native `/goal` + auto-routed sub-flows replace it.

---

## Install

```bash
# Machine-once: clone + bootstrap the global /aih-* skill set
git clone https://github.com/overdrive-dev/aihaus-flow "$XDG_DATA_HOME/aihaus"
bash "$XDG_DATA_HOME/aihaus/pkg/scripts/install.sh"
# Windows PowerShell: replace $XDG_DATA_HOME with $env:LOCALAPPDATA
```

Then, inside any project:

```bash
cd ~/myproject && claude
> /aih-install     # bind the per-repo overlay (hooks + workspace)
> /aih-init        # scan the codebase, write project.md, capture roles + env
```

`install.sh` symlinks (or junctions on Windows) `.claude/{skills,agents,hooks}` into `.aihaus/{skills,agents,hooks}`; `--copy` forces file copies for filesystems without symlinks. Your `settings.local.json` is **merged**, never clobbered. Stay current with `/aih-update` (or `/aih-update --check` for a dry run).

---

## Workflows

This is the heart of 3.0: **agents never run loose — they run inside a gated workflow.**

### The stage workflow (a local kanban)

Every task moves through stages, and **every stage has a gate** (`PASS` / `SKIPPED` / `BLOCKED`). Operational state lives in a local SQLite kanban — `.aihaus/state/kanban.db`:

```
backlog → entendimento → planejamento → tdd → review-execucao
        → testes → homolog → human-review → prod → box-dev
```

| Stage | What has to be true to pass |
|-------|------------------------------|
| `entendimento` | **100% understanding** of the request |
| `planejamento` | Business rules + acceptance criteria pinned |
| `tdd` | Impact mapped + **failing tests** written first |
| `review-execucao` | Built in a worktree + local **Playwright** smoke |
| `testes` | **Full suite in local Docker** |
| `homolog` | Staging + full Playwright **(devops only)** |
| `human-review` | Your call |
| `prod` | Shipped **(devops only)** |

The board is **local-first** — tests run **100% in local Docker** by default — and **syncs out** to Linear, Notion, Jira, or GitHub Issues for a shared view.

### Auto-routing → interactive sub-flows

A plain-language request **auto-routes** to the right interactive sub-flow — `/aih-plan`, `/aih-feature`, or `/aih-bugfix`. Typing `/aih-*` is an optional override, never required. The sub-flow scopes the work with you, then drives the gated stages above.

### Native `/goal` — the autonomous loop

```
> /goal drive the planned backlog to human-review
```

Set a **completion condition**; aihaus works autonomously, turn after turn, until a fast model verifies the condition is met — driving a planned kanban backlog through the gates, hands-off.

### Native dynamic workflows — fan-out

For autonomous fan-out — QA sweeps, devops deploys, cross-checked audits — aihaus uses Claude Code's **native dynamic JS workflows**, and they're **role-gated** (only `qa` / `devops`). Subagents inherit the tool allowlist, so the online boundary holds even inside a workflow.

### Agents in parallel, zero file conflicts

Many agents run at once, safely. The invariant (**ADR-260529-A**): **worktree isolation** + **Owned-Files sharding** + sequential merge-back + a single-writer DB. Two agents never edit the same file — parallelism comes from disjoint file sets. Written plans surface to the native **Plan panel**; the runner projects to the native **task list**, so progress shows in the GUI, not just on disk.

---

## Memory

Local, layered, never hosted — auto-injected so you never re-explain your project.

**(a) Markdown source-of-truth** — auto-imported into **every session** via `CLAUDE.md` `@`-imports, so it survives `/compact`:

| File | What it holds |
|------|---------------|
| `.aihaus/project.md` | Stack, conventions, architecture — read at runtime by every agent |
| `.aihaus/decisions.md` | Architecture Decision Records. **Binding** — every code-writing agent reads it first |
| `.aihaus/knowledge.md` | Lessons + gotchas carried forward so they stop repeating |
| `.aihaus/memory/workflows/environment.md` | Env access, credential **locations** (never values), validation commands |

**(b) `aih-graph`** — a private, per-repo SQLite + BM25/FTS5 index (with optional local Ollama embeddings) of your **real code** (files, symbols, call-sites, tests), markdown memory, and commits. It lives under the OS state directory — **never merged into the repo, never hosted**. Agents query it to ground their work:

```bash
aihaus memory query "where do we validate JWTs" --json
aihaus memory callers "createSession" --json
```

**(c) `/aih-env`** — capture the test environment, credential **locations** (never secret values), env access, and deploy path **once**; persisted to `environment.md` and read by every session and agent. Re-run it whenever new definitions surface.

---

## Roles

Captured at `/aih-init`, your profile is one of five — and the staging→prod **online boundary is a real, hook-enforced barrier**, not advice:

| Profile | Scope | Crosses staging → prod? |
|---------|-------|:---:|
| `pm` | Scope, plan, prioritize | ✕ |
| `builder` | Scope + build features **locally** | ✕ |
| `dev` | Implement, **offline-local** | ✕ |
| `qa` | Test, **offline-local** (Docker) | ✕ |
| `devops` | Build **and** deploy | ✓ |

`role-guard.sh` (a PreToolUse hook) blocks deploy / online commands for any non-devops role. That's what lets a client safely become a **builder** — they build features end-to-end locally, and **cannot deploy**.

---

## The Engine

Under the native-first surface sits a file-driven engine: **59 specialist agents** and **15 intent-based skills**.

- **Thin coordinator, specialist workforce.** The skill running a command is a coordinator: it spawns a specialist, reads the file that specialist writes, and picks the next one. Heavy work stays in subagent contexts — your main window stays clean.
- **Files as the handoff protocol.** Agents never "talk to each other"; coordination is through files (`PLAN.md`, `REVIEW.md`, `VERIFICATION.md`, …). One writer per file. The payoff: a full audit trail, clean resumes, zero write races (ADR-001).
- **Adversarial reviewers.** `plan-checker`, `contrarian`, `code-reviewer`, `verifier`, `integration-checker`, `security-auditor` carry a contract: **find a real problem or justify the silence in writing.** A bare PASS is rejected.
- **One commit per story.** Each commit uses an explicit Owned-Files list — never `git add -A`. `git bisect` lands on the exact failing story; every story reverts on its own.
- **Self-evolving.** After each run, the reviewer drafts **evidence-backed** edits to agent definitions; the completion protocol applies them. No weights move — the markdown that guides agents improves. The next run starts slightly smarter.

---

## Commands

aihaus ships **15 intent-based skills**. Every command follows the same pattern: **ask scoping questions → one approval → fully autonomous** (`pkg/.aihaus/skills/_shared/autonomy-protocol.md`). With auto-routing, **typing these is optional** — a plain-language request lands on the right one.

### Setup & memory

| Command | What it does |
|---------|--------------|
| `/aih-install` | Bind / refresh the per-repo overlay in cwd |
| `/aih-init` | Scan the codebase, write `project.md`, **capture roles + env** |
| `/aih-env` | Capture the test environment, credential **locations**, access + deploy → `environment.md` |

### Scope, plan & build (auto-routable)

| Command | What it does |
|---------|--------------|
| `/aih-plan` | Research and plan a concrete change → `PLAN.md` |
| `/aih-feature` | Plan → branch → implement → review → commit (single feature) |
| `/aih-bugfix` | Triage → branch → fix → test → commit |
| `/aih-brainstorm` | Multi-specialist exploratory panel → `BRIEF.md` |
| `/aih-milestone` | Conversational gathering + execution for milestone-sized work |
| `/aih-quick` | Fast-track for trivial changes — skips planning |

### Run, resume & maintain

| Command | What it does |
|---------|--------------|
| `/aih-resume` | Pick up an interrupted run from its manifest |
| `/aih-close` | Close a stale run (slug or `--bulk`) |
| `/aih-update` | Pull the latest aihaus, re-link, re-validate (`--check` = dry run) |
| `/aih-effort` | Retune agent effort tiers + model assignments (cohort-driven) |
| `/aih-sync-notion` | Optional kanban sync to Notion |
| `/aih-help` | List all commands and conventions |

> For autonomous, multi-turn execution toward a completion condition, use **native `/goal`** — the kanban tracks the run regardless.

```bash
# Global CLI helper — query the private aih-graph index (hooks use it automatically)
aihaus memory <refresh|query|context|callers|impact|gotchas|status>   # --json for agents
```

---

## What gets installed

```
your-project/
├── .aihaus/                          # aihaus workspace
│   ├── skills/                       # 15 intent-based commands
│   │   └── _shared/autonomy-protocol.md
│   ├── agents/                       # 59 specialist agent definitions
│   ├── hooks/                        # lifecycle + protocol hooks (incl. role-guard.sh)
│   ├── protocols/                    # workflow protocols + kanban substrate + parallelism contract
│   ├── memory/                       # local markdown memory (project.md, environment.md, …)
│   ├── decisions.md                  # Architecture Decision Records (binding)
│   └── knowledge.md                  # Accumulated lessons
│
└── .claude/                          # Claude Code config
    ├── settings.local.json           # Permissions + hooks (auto-merged)
    ├── skills/   → .aihaus/skills/
    ├── agents/   → .aihaus/agents/
    └── hooks/    → .aihaus/hooks/
```

---

## Requirements

- **Claude Code** v2.0.0+ (the `--dangerously-skip-permissions` flag powers `bash .aihaus/auto.sh`; older versions soft-warn at install and still work under bare `claude`)
- **git**
- **bash** (Unix) or **Git Bash / WSL / PowerShell 5+** (Windows)
- **Docker** — to run the test stages locally (the kanban default)
- **python** or **jq** — for JSON settings merging (optional; the installer degrades gracefully)
- **Ollama** *(optional)* — for local semantic embeddings in `aih-graph`; BM25/FTS5 works without it

No runtime. No build step. No package manager. The entire package is **markdown and shell scripts**.

> [!NOTE]
> **Stack-agnostic.** Agents read `project.md` at runtime — they never assume Python, Node, Go, or anything else. Install it in a Rust project, a Rails app, or a Go microservice; it adapts.

---

## License

MIT License. See [LICENSE](LICENSE) for details.

---

<div align="center">

**You think. ai builds.**

*Describe it once. It routes, gates, builds, and tracks — locally, with a real role barrier, and nothing hosted.*

</div>
