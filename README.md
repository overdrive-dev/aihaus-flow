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

**A markdown-only multi-agent workflow for Claude Code. Plan heavy once — let a coordinated team of 43 specialized agents research, plan, architect, implement, review, test, verify, and ship.**

**Solves prompt fatigue — the death-by-a-thousand-prompts that happens when you babysit ai through every step.**

[![License](https://img.shields.io/badge/license-MIT-blue?style=for-the-badge)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.5.0-181717?style=for-the-badge&logo=github)](VERSION)
[![Built for Claude Code](https://img.shields.io/badge/built%20for-Claude%20Code-d97757?style=for-the-badge)](https://claude.ai/code)

<br>

```bash
git clone https://github.com/overdrive-dev/aihaus-flow ~/tools/aihaus
bash ~/tools/aihaus/pkg/scripts/install.sh --target .
```

**Works on Mac, Windows, and Linux.**

<br>

*"Plan once. Walk away. Come back to a verified milestone with clean git history."*

<br>

[The Problem](#the-problem) · [Getting Started](#getting-started) · [How It Works](#how-it-works) · [Why It Works](#why-it-works) · [Commands](#commands)

</div>

---

> [!IMPORTANT]
> ### v0.5.0 — `/aih-brainstorm` is here
>
> A new 8-phase exploratory skill for fuzzy "how should we think about X" questions. Spawns a multi-specialist panel, runs an adversarial `contrarian` agent, optionally pulls web research, and synthesizes a `BRIEF.md`. Pipe the brief straight into planning:
>
> ```bash
> /aih-brainstorm "how should we model multi-tenancy"
> /aih-plan --from-brainstorm <slug>      # or
> /aih-milestone --from-brainstorm <slug>
> ```
>
> Also new in 0.5.0: the **CONVERSATION.md turn-log convention** for multi-round agent workflows (ADR-001, single-writer discipline) and the **`brainstorm-synthesizer`** fan-in agent. See `pkg/.aihaus/decisions.md` for the architectural rationale.

---

## The Problem

You spend 80% of your time telling ai *how* to do things instead of *what* to do. Every prompt requires context about your stack, conventions, and past decisions. When you finally get a plan right, execution drifts because there's no shared memory between sessions. And when something breaks, you start from scratch.

## The Solution

aihaus flips the ratio. **You invest in planning — ai handles everything else.**

One approval gate. After that, a coordinated team of 43 specialized agents researches, plans, architects, implements, reviews, tests, verifies, and ships — autonomously. Every agent reads the same project context. Every decision is logged. Every lesson feeds back into the system. The more you use it, the smarter it gets.

---

## Getting Started

```bash
# 1. Clone the package somewhere stable
git clone https://github.com/overdrive-dev/aihaus-flow ~/tools/aihaus

# 2. Install into your project
cd your-project
bash ~/tools/aihaus/pkg/scripts/install.sh --target .

# 3. Bootstrap project context
/aih-init

# 4. Build something
/aih-feature Add rate limiting to the public API
```

The installer creates symlinks (or junctions on Windows) from `.claude/{skills,agents,hooks}` into `.aihaus/{skills,agents,hooks}`. Your existing `settings.local.json` is merged, not overwritten.

Verify with:

```bash
/aih-help
```

### Staying Updated

aihaus evolves fast. Update periodically:

```bash
/aih-update          # Pull latest from remote, re-link, re-run smoke-test
/aih-update --check  # Just check if an update is available
```

<details>
<summary><strong>Alternative: copy-mode install (no symlinks)</strong></summary>

If your filesystem doesn't support symlinks (some CI containers, network drives), use `--copy`:

```bash
bash ~/tools/aihaus/pkg/scripts/install.sh --target . --copy
```

`--copy` duplicates the package into `.claude/`. You lose live updates from the source — re-run the installer after every `/aih-update`.

</details>

<details>
<summary><strong>Dogfooding aihaus on the aihaus repo</strong></summary>

If you're contributing to aihaus itself:

```bash
git clone https://github.com/overdrive-dev/aihaus-flow
cd aihaus-flow
bash pkg/scripts/install.sh --target .
```

This creates `.aihaus/` (gitignored) with symlinks back to `pkg/.aihaus/`. Local artifacts accumulate in `.aihaus/`; package improvements go to `pkg/.aihaus/`.

</details>

---

## How It Works

### 1. Bootstrap

```
/aih-init
```

Scans your codebase, detects the stack, infers conventions, and writes `.aihaus/project.md` — the shared context every agent reads at runtime. Two regions: an **AUTO-GENERATED** block that `/aih-init` rewrites, and a **MANUAL** block you own (glossary, active milestones, manual decisions).

**Creates:** `.aihaus/project.md`, `.aihaus/memory/`, `.aihaus/decisions.md`, `.aihaus/knowledge.md`

---

### 2. Brainstorm or Plan

```
/aih-brainstorm "how should we approach multi-tenancy"
# or
/aih-plan "Add multi-tenant workspaces with role-based access"
```

`/aih-brainstorm` is for fuzzy questions — runs a panel of 3-5 specialists (architect + advisor-researcher + phase-researcher by default), an adversarial `contrarian`, optional web research, and a synthesizer. Outputs `BRIEF.md`.

`/aih-plan` is for concrete tasks — invokes `assumptions-analyzer`, `pattern-mapper`, optionally `phase-researcher`, then a `plan-checker` adversarial gate. Outputs `PLAN.md`.

Both feed forward via `--from-brainstorm <slug>` into `/aih-plan` or `/aih-milestone`.

**Creates:** `BRIEF.md` (brainstorm) or `PLAN.md` (plan), plus `ASSUMPTIONS.md`, `PATTERNS.md`, `CHECK.md`, `RESEARCH.md` as needed.

---

### 3. Execute

```
/aih-run <slug>          # any plan or milestone draft
```

Routes by scope. Small plan → feature execution inline (branch, implement, review, commit). Large or multi-story → auto-promotes to a milestone with full agent team.

For milestones, the orchestrator:

1. **Plans** — analyst → product-manager → architect → plan-checker (adversarial gate, max 2 iterations).
2. **Executes** — stories serialized; each story implemented in an isolated worktree by `implementer` or `frontend-dev`, reviewed by `reviewer`/`code-reviewer`, fixed by `code-fixer`, committed atomically. No `git add -A` — explicit owned-file lists.
3. **Verifies** — `verifier` (goal-backward), `integration-checker` (E2E wiring), `security-auditor` (when sensitive areas touched) — all in parallel.
4. **Completes** — promotes decisions to `decisions.md`, knowledge to `knowledge.md`, writes `MILESTONE-SUMMARY.md`, applies agent-evolution proposals.

**Creates:** atomic commits per story, `execution/MILESTONE-SUMMARY.md`, `execution/VERIFICATION.md`, `execution/INTEGRATION.md`, `execution/SECURITY.md` (if applicable).

---

### 4. Resume or Quick

```
/aih-resume              # pick up an interrupted run
/aih-quick "fix the typo in the welcome banner"
```

`/aih-resume` reads `RUN-MANIFEST.md` files across milestones/features/bugfixes and offers to continue any non-completed run. `/aih-quick` is the fast lane — skips planning entirely for trivial changes.

---

### 5. Self-Evolve

After every milestone, the **reviewer** evaluates what worked. Patterns agents kept rediscovering become permanent protocol. Gotchas that caused repeated failures become rules. Agent definitions evolve via evidence-based proposals applied during the completion protocol — not through manual editing.

Your project gets a memory. Future sessions start smarter.

**Creates:** updated `decisions.md`, `knowledge.md`, `.aihaus/memory/` index; revised agent definitions when evolution proposals carry evidence.

---

## Why It Works

### Context Engineering

Every agent reads the same project context. No per-prompt re-explaining your stack.

| File | What it does |
|------|--------------|
| `.aihaus/project.md` | Stack, conventions, architecture — loaded at runtime by every agent |
| `.aihaus/decisions.md` | ADRs — binding; every code-writing agent reads before touching code |
| `.aihaus/knowledge.md` | Accumulated lessons — avoids re-discovering pitfalls |
| `.aihaus/memory/` | Persistent global + project memory across sessions |
| `RUN-MANIFEST.md` | Per-milestone execution state — enables `/aih-resume` after interruptions |
| `CONVERSATION.md` | Turn-log for multi-round agent workflows (ADR-001 single-writer discipline) |

### Multi-Agent Orchestration

Every stage uses the same pattern: a thin orchestrator spawns specialized agents, collects results via files, routes to the next step.

| Stage | Orchestrator does | Agents do |
|-------|-------------------|-----------|
| Research | Coordinates, presents findings | analyst, project-researcher, domain-researcher, advisor-researcher, phase-researcher in parallel |
| Brainstorm | Spawns panel + contrarian + synthesizer | Per-perspective panelists write `PERSPECTIVE-*.md`; contrarian writes `CHALLENGES.md`; synthesizer writes `BRIEF.md` |
| Planning | Validates, manages iteration | planner, plan-checker (adversarial — must find issues), pattern-mapper, assumptions-analyzer |
| Architecture | Routes ADR decisions | architect, framework-selector |
| Execution | Groups into waves, tracks progress, cherry-picks worktree commits | implementer, frontend-dev, executor — each in isolated worktree, fresh context |
| Quality | Drives review-fix loop | code-reviewer (severity-classified), code-fixer (auto-patch), test-writer |
| Verification | Presents results, blocks completion on FAIL | verifier (goal-backward), integration-checker (E2E wiring), security-auditor (threat-model anchored) |
| Completion | Promotes decisions and knowledge | reviewer (evolution proposals), doc-writer/doc-verifier |

The orchestrator never does heavy lifting. The work happens in fresh subagent contexts; your main session stays responsive.

### Adversarial Contract

Five reviewer agents operate under a **mandatory problem-finding** rule: zero findings without written justification triggers re-analysis. They cannot rubber-stamp.

| Agent | Adversarial scope |
|-------|-------------------|
| `plan-checker` | Plans must achieve their stated goal — gate before execution |
| `contrarian` | Ideas must survive challenge — overlooked premises, missing framings, absent stakeholders (per invocation) |
| `code-reviewer` | Implementations must clear severity-classified review |
| `verifier` | Goal-backward — assume the goal was NOT achieved, hunt for gaps |
| `integration-checker` | Components must actually wire together — "existence is not integration" |
| `security-auditor` | Threat model mitigations must exist in implemented code |

### Atomic Git Commits

Each story gets its own commit immediately after implementation. Explicit `git add` with file lists from the story's Owned Files — never `git add -A`.

```
9ce646c feat(scripts): add dogfood-brainstorm.sh regression script (Story 8)
a873ed8 feat(release): /aih-brainstorm, contrarian, brainstorm-synthesizer (v0.5.0) (Story 7)
161ee96 feat(agent): add brainstorm-synthesizer fan-in agent (Story 3)
06dec6b feat(agent): add contrarian adversarial idea-challenger (Story 2)
dc739c2 feat(adr): seed pkg/.aihaus/decisions.md with ADR-001 (files are state)
```

> [!NOTE]
> **Why atomic:** git bisect finds the exact failing story. Each story is independently revertable. Clear history for ai in future sessions. The completion protocol can promote decisions and knowledge with surgical traceability.

### Files Are State

aihaus uses Claude Code's Agent tool plus file-based handoff. Per-agent artifact files (`REVIEW.md`, `CHALLENGES.md`, `VERIFICATION.md`) are the baseline; `CONVERSATION.md` turn logs are an optional shared shape for multi-round workflows. The parent skill is the sole writer on shared logs — agents never get `Write` access.

This means: no inter-agent messaging primitive, no shared mutable state, no race conditions. Every artifact is auditable. Every interrupted run is resumable. See **ADR-001** in `pkg/.aihaus/decisions.md`.

### Self-Evolution

After each milestone, the system reviews its own effectiveness:

1. **Reviewer** analyzes decisions and knowledge logs from the milestone.
2. Proposes edits to agent definitions (new rules, new reads, protocol improvements).
3. **Completion protocol** applies evidence-backed evolutions.
4. Smoke test + purity check validate the changes.
5. Next milestone starts with smarter agents.

This is not fine-tuning. It's protocol evolution — the markdown definitions that guide agents get refined through accumulated project experience.

---

## Commands

aihaus ships 13 intent-based skills. Every command follows the same pattern: **ask scoping questions → one approval → fully autonomous**.

### Core workflow

| Command | What it does |
|---------|--------------|
| `/aih-init` | Bootstrap — scans codebase, writes `project.md`, seeds memory |
| `/aih-brainstorm` | Multi-specialist exploratory panel for fuzzy topics — outputs `BRIEF.md` |
| `/aih-plan` | Research and plan a concrete change — outputs `PLAN.md` |
| `/aih-feature` | Plan → branch → implement → review → commit (single feature) |
| `/aih-bugfix` | Triage → branch → fix → test → commit |
| `/aih-milestone` | Conversational gathering for milestone-sized work — drafts to `STATUS.md` |
| `/aih-quick` | Fast-track for trivial changes — skips planning |

### Execution & resume

| Command | What it does |
|---------|--------------|
| `/aih-run [slug]` | Execute any ready plan or milestone draft — full agent team |
| `/aih-resume [slug]` | Pick up an interrupted run from `RUN-MANIFEST.md` |
| `/aih-plan-to-milestone [slug]` | Promote a plan to a milestone draft for conversational refinement |

### Brainstorm intake

| Command | What it does |
|---------|--------------|
| `/aih-plan --from-brainstorm <slug>` | Seed a plan from a `BRIEF.md` |
| `/aih-milestone --from-brainstorm <slug>` | Seed a milestone draft from a `BRIEF.md` |

### Utilities

| Command | What it does |
|---------|--------------|
| `/aih-help` | List all commands and conventions |
| `/aih-update [--check] [--force]` | Pull latest aihaus from remote, re-link, re-validate |
| `/aih-sync-notion` | Optional Notion Kanban sync for milestones |

---

## The Agent Catalog

| Category | Agents | What They Do |
|----------|--------|--------------|
| **Research** | project-researcher, domain-researcher, phase-researcher, advisor-researcher, ai-researcher | Deep-dive before any code is written |
| **Planning** | planner, assumptions-analyzer, roadmapper, pattern-mapper, plan-checker | Structured plans with adversarial review |
| **Brainstorm** | contrarian, brainstorm-synthesizer | Adversarial idea-challenge + fan-in synthesis to `BRIEF.md` |
| **Architecture** | architect, framework-selector | ADRs, system design, technology decisions |
| **Implementation** | implementer, frontend-dev, executor | Code that follows the plan and ADRs (worktree-isolated) |
| **Quality** | code-reviewer, code-fixer, test-writer | Severity-classified review + auto-fix loop |
| **Verification** | verifier, integration-checker, security-auditor, nyquist-auditor | Goal-backward proof, E2E wiring, threat-model verification |
| **Documentation** | doc-writer, doc-verifier, research-synthesizer | Docs verified against live code |
| **Intelligence** | project-analyst, codebase-mapper, intel-updater, user-profiler | Structured codebase knowledge |
| **Debug** | debugger, debug-session-manager | Scientific-method bug investigation |
| **UI** | ux-designer, ui-researcher, ui-checker, ui-auditor | Design contracts and visual audits |
| **AI/ML** | eval-planner, eval-auditor | Evaluation strategy and coverage |
| **Product** | analyst, product-manager | Analysis briefs and structured PRDs |
| **Coordination** | reviewer, notion-sync | QA lead + optional Kanban sync |

---

## What Gets Installed

```
your-project/
├── .aihaus/                     # aihaus workspace (git-tracked or gitignored — your call)
│   ├── skills/                  # 13 intent-based commands
│   ├── agents/                  # 43 specialized agent definitions
│   ├── hooks/                   # 12 lifecycle hooks
│   ├── templates/               # project.md + settings templates
│   ├── memory/                  # Persistent agent memory (grows over time)
│   ├── project.md               # Your codebase context (created by /aih-init)
│   ├── decisions.md             # Architecture Decision Records
│   └── knowledge.md             # Accumulated lessons
├── .claude/                     # Claude Code config
│   ├── settings.local.json      # Permissions + hooks (auto-merged)
│   ├── skills/  → .aihaus/skills/
│   ├── agents/  → .aihaus/agents/
│   └── hooks/   → .aihaus/hooks/
```

---

## Stack Agnostic

aihaus works with **any** language, framework, or toolchain. Agents read `project.md` at runtime — they never assume Python, Node, Go, or anything else. Settings ship with `Bash(*)` permissions so every dev tool works without prompts. Install in a Rust project, a Rails app, or a Go microservice — it adapts.

## Conflict Prevention

Multiple autonomous agents writing code simultaneously is a recipe for divergent choices. aihaus prevents this through:

- **ADR Gate** — every code-writing agent reads `decisions.md` before touching code.
- **Architect Mandate** — conflict-prone areas (API style, DB conventions, auth patterns) require explicit ADRs before implementation begins.
- **Plan Checker** — adversarial review that *must* find issues; zero findings triggers re-analysis.
- **Living Architecture** — the completion protocol updates `decisions.md` and `knowledge.md` after every milestone so future agents inherit the latest constraints.
- **Worktree isolation** — `implementer`, `frontend-dev`, and `code-fixer` work in isolated git worktrees; the orchestrator cherry-picks each story's commit onto the milestone branch with explicit owned-file lists (no `git add -A`).

---

## Token Usage

A full milestone with adversarial review, code review, security audit, and goal verification uses substantial context. **This is by design** — aihaus trades tokens for quality and autonomy. The alternative is spending your own time reviewing, re-prompting, and re-checking.

Cost-bound skills (like `/aih-brainstorm`) enforce hard caps pre-spawn so multi-specialist runs cannot explode. Default `/aih-brainstorm` flow: 5 subagent invocations. Maximum (5 panelists + `--deep` + `--research`): 13 invocations.

---

## Requirements

- **Claude Code** (CLI or Desktop)
- **git**
- **bash** (Unix) or **PowerShell 5+** (Windows)

No runtime. No build step. No package manager. The entire package is markdown and shell scripts.

---

## License

MIT License. See [LICENSE](LICENSE) for details.

---

<div align="center">

**Claude Code is powerful. aihaus makes it autonomous.**

</div>
