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

### aihaus 3.0 — an autonomous, native-first developer workflow for Claude Code.

**Describe a feature in plain language. It auto-routes to the right sub-flow, drives it through gated stages on a local kanban, builds it in isolated worktrees with adversarial review, and verifies the result — while everything it knows about your project stays on your machine.**

[![License](https://img.shields.io/badge/license-MIT-blue?style=for-the-badge)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.42.0-181717?style=for-the-badge&logo=github)](pkg/VERSION)
[![aihaus 3.0](https://img.shields.io/badge/aihaus-3.0%20·%20native--first-7c3aed?style=for-the-badge)](#whats-new-in-30)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-first--class-d97757?style=for-the-badge)](https://claude.ai/code)

<br>

```bash
# 1 — Install aihaus (machine-once)
git clone https://github.com/overdrive-dev/aihaus-flow "$XDG_DATA_HOME/aihaus"
bash "$XDG_DATA_HOME/aihaus/pkg/scripts/install.sh"

# 2 — Bind it to a project (inside Claude Code)
cd ~/myproject && claude
> /aih-install
> /aih-init                      # writes project.md, captures env

# 3 — Launch with full autonomy (DSP wrapper)
bash .aihaus/auto.sh
```

Runs on macOS, Windows, Linux. No runtime, no build step — just markdown and shell scripts.

<br>

*"Describe it once. It routes, gates, builds, reviews, and tracks it on a local board — and never phones home."*

<br>

[Why](#why-aihaus) · [Quickstart](#your-first-5-minutes) · [The Four Pillars](#the-four-pillars) · [Online boundary](#-the-online-boundary) · [How the Engine Works](#how-the-engine-works) · [Architecture](docs/architecture-3.0.md) · [Commands](#commands) · [Requirements](#requirements)

</div>

---

## Why aihaus

Most of your time with ai-assisted coding goes into describing *how* instead of deciding *what*. Every prompt re-teaches the model your stack, your conventions, the decisions you already made. Sessions don't share memory, so execution drifts. There's no board tracking where work actually is, no gate stopping a half-understood task from shipping — and the moment you wire up a hosted "agent memory," your project's internals leave your machine.

**aihaus 3.0 inverts the loop.** You think; ai builds. A natural-language request auto-routes into a gated, staged workflow. The system understands the task to 100% before planning, writes failing tests before code, builds in isolated worktrees, runs the suite in local Docker, and parks the result at human-review. Everything it learns about your repo lives in local markdown and a private per-repo index. Nothing is hosted.

> [!NOTE]
> aihaus is **native-first**. It leans on Claude Code's own primitives — native `/goal`, native plan mode, the native task list, native git worktrees, native subagent memory — and layers gates, a kanban, and a local memory engine *on top*. It does **not** reinvent them.

---

## 🚀 Your first 5 minutes

### Minute 0 — Install once, bind once

```bash
git clone https://github.com/overdrive-dev/aihaus-flow "$XDG_DATA_HOME/aihaus"
bash "$XDG_DATA_HOME/aihaus/pkg/scripts/install.sh"   # machine-once: global /aih-* skills
# Windows PowerShell: replace $XDG_DATA_HOME with $env:LOCALAPPDATA
```

Then, inside the project you want to work in:

```bash
cd ~/myproject && claude
> /aih-install     # bind the per-repo overlay (hooks + workspace)
```

### Minute 1 — `/aih-init` captures who you are and how you ship

```
> /aih-init
```

It scans your codebase, detects the stack, and writes `.aihaus/project.md` — the shared context every agent reads. It also runs `/aih-env` to record your **test environment, credential *locations* (never secret values), and deploy path** into `environment.md`. You describe your setup **once**; every future session and agent reads it without you repeating yourself.

### Minutes 2–4 — Describe a feature; it auto-routes, gates, and tracks

You don't have to type a slash command. Just say what you want:

```
> Add multi-tenant workspaces with role-based access
```

aihaus classifies the request and **auto-routes** it to the right interactive sub-flow (here, `/aih-plan`). From there it drives the gated stages — and a **local SQLite kanban tracks every move**:

```
backlog → entendimento → planejamento → tdd → review-execucao
        → testes → homolog → human-review → prod → box-dev
```

Each stage has a gate (PASS / SKIPPED / BLOCKED). It won't leave `planejamento` until the business rules and acceptance criteria are pinned. It writes failing tests in `tdd` before any code. It builds in an isolated worktree, runs a Playwright smoke locally, then the **full suite in local Docker** — and parks the result at `human-review` for you.

### Minute 5 — Walk away with `/goal`

```
> /goal get the multi-tenant backlog to human-review
```

Set a completion condition and aihaus works autonomously, turn after turn, until a fast model verifies the condition is met — driving a planned kanban backlog hands-off to human-review.

That's the whole loop: **describe → auto-route → gate → build → review → track.** No board to babysit, no stack to re-explain, nothing hosted.

---

## 🧱 The Four Pillars

aihaus 3.0 stands on four foundations. Everything else is glue.

| Pillar | One line |
|--------|----------|
| 🧠 **Local Memory** | One harness, three tiers — code graph, project + business rules, your global preferences. Never hosted. |
| 📋 **Kanban** | A staged, gated workflow whose live state is a local SQLite board. |
| ⚙️ **Workflows** | Natural-language requests auto-route to the right sub-flow; native primitives handle fan-out. |
| 🎯 **Goals** | Native `/goal`: set a condition, walk away, a fast model verifies it's met. |

---

### 🧠 Pillar 1 — Local Memory (one harness, three tiers, never hosted)

Since v0.42.0, memory is exactly **three tiers** governed by **one harness** — all on disk, all yours, auto-injected into every session *and every subagent* so you never repeat yourself.

**The harness.** A single ≤2KB file (`.aihaus/protocols/harness.md`) carries the autonomy law, the memory map, and the gate grammar. The main session gets it as the first `CLAUDE.md` `@`-import; **every subagent gets it inlined verbatim at spawn** (it never yields to context-budget pressure), with an injection **receipt** logged per artifact — reading isn't advisory, it's by construction.

**Tier A — code memory & relations (derived, rebuildable).** `aih-graph`: a per-repo SQLite + BM25/FTS5 index (with optional local Ollama embeddings) of your **real code** (files, symbols, call-sites, tests), markdown memory, and commits — under the OS state directory, **never merged into the repo, never hosted.** Agents ground themselves through one batched call (`aihaus memory packet`, sub-second warm) plus targeted queries:

```bash
▸ aihaus memory query "where do we validate JWTs" --json
▸ aihaus memory callers "createSession" --json
▸ aihaus memory rule BR-12 --json        # one business rule + the code/tests bound to it
▸ aihaus memory why src/auth/session.ts  # which rules/decisions explain this file
```

**Tier B — project memory & business decisions (committed, the apex).** The canonical markdown set, auto-imported into every session:

| File | What it holds |
|------|---------------|
| `.aihaus/memory/workflows/business-rules.md` | **The autonomy contract.** Covered decision → the agent decides alone, citing the rule. Gap → it asks *once*, and the answer becomes a rule. Answered planning questions auto-draft new rules (`Source: pq-<id>`), confirmed at human-review — every answer permanently widens the autonomous surface |
| `.aihaus/project.md` | Stack, conventions, architecture — read at runtime by every agent |
| `.aihaus/decisions.md` | Architecture Decision Records. **Binding.** Every code-writing agent reads it before editing |
| `.aihaus/knowledge.md` | Lessons and gotchas carried forward so they stop repeating |
| `.aihaus/memory/workflows/environment.md` | Env access, credential **locations** (never values), and validation commands — captured once by `/aih-env` |

**Tier C — your preferences (global, cross-project).** `~/.aihaus/memory/user/preferences.md` follows *you*, not the repo — written only through the lock-atomic `aihaus prefs add`, surfaced to every session in every repo. Repo rules override global preferences on conflict; one deterministic sentence, no drift.

> [!IMPORTANT]
> `environment.md` records *where* credentials live and *how* to validate access — it never stores secret values. The private `aih-graph` index never leaves the OS state directory. Nothing about your project is hosted.

---

### 📋 Pillar 2 — Kanban (a gated, staged workflow on local SQLite)

Operational state isn't scattered across files — it lives in a **local SQLite kanban** (`kanban.db`). Every task moves through stages, and **every stage has a gate** (PASS / SKIPPED / BLOCKED):

| Stage | What has to be true to pass |
|-------|------------------------------|
| `backlog` | Captured, not yet started |
| `entendimento` | **100% understanding** of the request |
| `planejamento` | Business rules + acceptance criteria pinned |
| `tdd` | Impact mapped + **failing tests** written first |
| `review-execucao` | Built in a worktree + local **Playwright** smoke |
| `testes` | **Full suite in local Docker** |
| `homolog` | Staging + full Playwright |
| `human-review` | Your call |
| `prod` | Shipped |
| `box-dev` | Done |

**Local-first by design.** Tests run **100% in local Docker** by default. The board is the source of operational truth — and it **syncs out** to Linear, Notion, Jira, or GitHub Issues when you want a shared view.

---

### ⚙️ Pillar 3 — Workflows (native primitives, auto-routed)

aihaus 3.0 builds workflows on **native Claude Code primitives** rather than a bespoke engine.

- **Auto-routing.** A natural-language request **auto-routes** to the right interactive sub-flow — `/aih-plan`, `/aih-feature`, or `/aih-bugfix`. Typing `/aih-*` is an optional override, never required. Feature work → `aih-feature`; a defect → `aih-bugfix`; "think first" → `aih-plan`.
- **Native fan-out.** Native dynamic JS workflows handle autonomous fan-out — QA sweeps, deploy ops — and stay subject to the online boundary (see below).
- **Safe parallelism.** Many agents run at once with **zero file conflicts**: worktree isolation + **Owned-Files sharding** + sequential merge-back + a single-writer DB (**ADR-260529-A**).
- **Native surfaces.** Written plans surface to the native **Plan panel**, and the runner **projects to the native task list** so progress shows in the GUI, not just on disk.

```text
▸ "add a tenant switcher to the settings page"
   └─ auto-routed → /aih-feature  (interactive scoping → build)
```

---

### 🎯 Pillar 4 — Goals (native `/goal`, hands-off)

```
> /goal drive the planned backlog to human-review
```

Set a **completion condition** and aihaus works autonomously, turn after turn, until a **fast model verifies the condition is met**. It drives a planned kanban backlog through the gates to human-review, hands-off.

> [!NOTE]
> There is **no `aih-goal` skill** in 3.0. Native `/goal` plus auto-routed sub-flows replace it, and the kanban DB is a **default substrate** — decoupled from any "goal" command. This is the native-first thesis in practice.

---

## 🔐 The online boundary

aihaus 3.0 ships a **real security barrier**, not advice. `flow-guard.sh` — a
**PreToolUse hook** — blocks any deploy / online command that is not part of an
active tracked flow, so every promotion traces back to a gated flow and, through
it, to a business rule and its tests. Nothing reaches prod ad-hoc.

---

## 🛠 How the engine works

Under the native-first surface sits a deliberate, file-driven engine: **59 specialist agents** and **15 intent-based skills**.

### Thin coordinator, specialist workforce

The skill running a command is a **coordinator**. It spawns a specialist, reads the file that specialist writes, and picks the next one. The heavy work stays in subagent contexts — your main session window stays clean.

### Files as the handoff protocol

aihaus never tries to make agents "talk to each other." **Coordination happens through files** (`PLAN.md`, `REVIEW.md`, `VERIFICATION.md`, …). Every subagent writes its own artifact; the coordinator is the only writer. The payoff: a full audit trail, interruptions that resume cleanly, **zero write races**, and no dependency on an inter-agent messaging primitive Claude Code doesn't offer. See **ADR-001** in `pkg/.aihaus/decisions.md`.

### Adversarial reviewers that must push back

Reviewer agents carry a contract: **find at least one real problem, or justify the silence in writing.** A bare PASS is rejected.

| Reviewer | Scope of skepticism |
|----------|---------------------|
| `plan-checker` | Does this plan actually achieve its stated goal? Gate before execution |
| `contrarian` | What premises went unexamined? Whose perspective is missing? |
| `code-reviewer` | Severity-classified findings on the implementation diff |
| `verifier` | Goal-backward — start from "this did NOT work" and hunt counter-evidence |
| `integration-checker` | Do the pieces actually connect? Existence ≠ integration |
| `security-auditor` | Do the threat-model mitigations exist as code, not promises |

### One commit per story

Stories land one at a time. Each implementation commit uses an **explicit file list** drawn from that story's **Owned Files** — never `git add -A`, never a directory sweep. The history reads linearly, so `git bisect` lands on the exact failing story and every story is revertable on its own.

```
9ce646c feat(scripts): add dogfood-brainstorm.sh regression script (Story 8)
161ee96 feat(agent): add brainstorm-synthesizer fan-in agent (Story 3)
06dec6b feat(agent): add contrarian adversarial idea-challenger (Story 2)
```

### Agents that self-evolve

After every run, the **reviewer** inspects the accumulated decisions and knowledge, then drafts **evidence-backed** edits to agent definitions — new read requirements, new guardrails, new protocol steps. The completion protocol applies them. Nothing is fine-tuned and no weights move; what changes is the markdown that guides agents, refined against real project experience. **The next run starts slightly smarter.**

---

## 📋 Commands

aihaus ships **15 intent-based skills**. Every command follows the same pattern: **ask scoping questions → one approval → fully autonomous** (codified in `pkg/.aihaus/skills/_shared/autonomy-protocol.md`, referenced by every skill). Remember: with auto-routing, **typing these is optional** — a plain-language request lands on the right one.

### Setup & memory

| Command | What it does |
|---------|--------------|
| `/aih-install` | Bind / refresh the per-repo overlay in cwd (resolves `AIHAUS_HOME`) |
| `/aih-init` | Scan the codebase, write `project.md`, **capture env** |
| `/aih-env` | Capture the test environment, credential **locations**, access + deploy → `environment.md` |

### Scope, plan & build (auto-routable)

| Command | What it does |
|---------|--------------|
| `/aih-plan` | Research and plan a concrete change → `PLAN.md` |
| `/aih-feature` | Plan → branch → implement → review → commit (single feature) |
| `/aih-bugfix` | Triage → branch → fix → test → commit |
| `/aih-brainstorm` | Multi-specialist exploratory panel for fuzzy topics → `BRIEF.md` |
| `/aih-milestone` | Conversational gathering + execution for milestone-sized work |
| `/aih-quick` | Fast-track for trivial changes — skips planning |

### Run, resume & maintain

| Command | What it does |
|---------|--------------|
| `/aih-resume` | Pick up an interrupted run from its manifest |
| `/aih-close` | Close a stale run (slug or `--bulk`) |
| `/aih-update` | Pull the latest aihaus, re-link, re-validate (`--check` for a dry run) |
| `/aih-effort` | Retune agent effort tiers + model assignments (cohort-driven) |
| `/aih-sync-notion` | Optional kanban sync to Notion |
| `/aih-help` | List all commands and conventions |

> [!TIP]
> For autonomous, multi-turn execution against a completion condition, use **native `/goal`** — not a dedicated aih-skill. The kanban tracks the run regardless.

### Global CLI helper

```bash
aihaus memory <refresh|query|packet|context|callers|impact|rule|why|gotchas|status>   # the private aih-graph index; --json for agents
aihaus prefs add "<preference>"                  # the only write path into your global tier-C preferences
aihaus kanban <gate|question|answer> …           # the sanctioned write path for board state (warn-only rule citations)
aihaus feedback export                           # bundle gate stats + warnings + evolution proposals for upstreaming
```

---

## ✨ What's new in 3.0

**v0.42.0 — One Harness, Three Memory Tiers (M050):**

- **One harness file** (≤2KB) carries the autonomy law + memory map + gate grammar — first import for the main session, **inlined verbatim into every subagent** with per-artifact injection receipts. Reading is by construction, not by instruction.
- **Business rules become the autonomy engine** — covered decisions are made alone (citing the rule); gaps are asked *once* and the answer becomes a rule; answered planning questions auto-draft new rules confirmed at human-review. A deterministic eval reports **autonomous decisions per human answer**.
- **Tier-C global preferences** — `~/.aihaus/memory/user/preferences.md` follows you across repos, written only via lock-atomic `aihaus prefs add`; repo rules win on conflict.
- **Deterministic write chokepoints** — `aihaus kanban gate|question|answer` replaces free-form board writes (warn-only rule-citation validation; enforcement flips only by ADR + maintainer sign-off after a release of evidence).
- **aih-graph v0.2** — `rule <BR-id>` and `why <ref>` connect code to the rules that govern it; `rule-drift` flags rules whose bound files changed since last review; `--types` filters; one batched `memory packet` call grounds every spawn in <1s.
- **Transparency note:** the installer seeds a small marker block into `~/.claude/CLAUDE.md` (so even repos *without* aihaus get the autonomy-law digest) and enrolls repos in `~/.aihaus/.targets` for `aihaus update --all`. Both are opt-out: `--no-global-harness` / `AIHAUS_SKIP_GLOBAL_HARNESS=1`; removed by `uninstall --purge-user-global`.

**3.0 foundation:**

- **Native-first throughout** — native `/goal`, native plan mode, native task list, native worktrees, native subagent memory. aihaus layers gates + kanban + the memory engine on top.
- **No `aih-goal` skill** — native `/goal` + auto-routed sub-flows replace it; the kanban DB is a **default substrate**, decoupled from any "goal" command.
- **Auto-routing** — describe what you want; the right sub-flow is chosen for you. Slash commands are an optional override.
- **Local kanban** — operational state lives in `kanban.db` through gated stages; tests run **100% in local Docker** by default; syncs to Linear / Notion / Jira / GitHub Issues.
- **Flow-gated online boundary** — `flow-guard.sh` makes "deploys only inside a tracked flow" a hook-enforced barrier, so nothing reaches prod ad-hoc.
- **Private repo memory** — `aih-graph` indexes real code, markdown memory, and commits into a per-repo SQLite/BM25 index under the OS state dir. Never hosted.

---

## 📦 What gets installed

```
your-project/
├── .aihaus/                          # aihaus workspace
│   ├── skills/                       # 15 intent-based commands
│   │   └── _shared/
│   │       └── autonomy-protocol.md  # Binding execution-autonomy rules
│   ├── agents/                       # 59 specialist agent definitions
│   ├── hooks/                        # lifecycle + protocol hooks (incl. flow-guard.sh)
│   ├── protocols/                    # harness.md + stage workflow + kanban DB substrate
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

The installer creates symlinks (Unix) or directory junctions (Windows); `--copy` forces file copies. Settings are **merged**, not overwritten.

---

## ⚙️ Requirements

- **Claude Code** v2.0.0+ (the `--dangerously-skip-permissions` flag is required for `bash .aihaus/auto.sh`; older versions trigger a soft warning at install, and the rest of the toolkit still works under bare `claude`).
- **git**
- **bash** (Unix) or **Git Bash / WSL / PowerShell 5+** (Windows)
- **Docker** — to run the test stages locally (Pillar 2 default)
- **python** or **jq** — for JSON settings merging (optional; the installer degrades gracefully)
- **Ollama** *(optional)* — for local semantic embeddings in `aih-graph`; BM25/FTS5 works without it

No runtime. No build step. No package manager. The entire package is **markdown and shell scripts**.

> [!NOTE]
> aihaus is **stack-agnostic**. Agents read `project.md` at runtime — they never assume Python, Node, Go, or anything else. Install it in a Rust project, a Rails app, or a Go microservice; it adapts.

---

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.

---

<div align="center">

**You think. ai builds.**

*Describe it once. It routes, gates, builds, and tracks — locally, with a real online barrier, and nothing hosted.*

</div>
