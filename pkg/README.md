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

**An autonomous developer workflow for Claude Code. One approval gate, then 43 specialist agents run the whole pipeline — research, planning, architecture, implementation, review, testing, verification, release.**

**Built for people who'd rather shape an idea than chaperone a model.**

[![License](https://img.shields.io/badge/license-MIT-blue?style=for-the-badge)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.16.0-181717?style=for-the-badge&logo=github)](VERSION)
[![Built for Claude Code](https://img.shields.io/badge/built%20for-Claude%20Code-d97757?style=for-the-badge)](https://claude.ai/code)

<br>

```bash
git clone https://github.com/overdrive-dev/aihaus-flow ~/tools/aihaus
bash ~/tools/aihaus/pkg/scripts/install.sh --target .
```

Runs anywhere Claude Code runs — macOS, Windows, Linux.

<br>

*"Describe it once. Walk away. Come back to a verified milestone with clean git history."*

<br>

[The Problem](#the-problem) · [Install](#install) · [How It Works](#how-it-works) · [The Design](#the-design) · [Commands](#commands)

</div>

---

> [!IMPORTANT]
> ## This project is no longer maintained.
>
> aihaus-flow is archived in place as historical reference. We are not maintaining it further, and we are not recommending it for new installs.
>
> **Use [`gsd2`](https://github.com/gsd-build/gsd-2) or [`gsd1`](https://github.com/gsd-build/get-shit-done) instead.**
>
> If you are reading the packaged README from an old install or copied package tree, treat it as end-of-life documentation rather than an active release channel.

---

## The Problem

Most of your time with ai-assisted coding gets spent describing *how* instead of deciding *what*. Every prompt re-teaches the model your stack, your conventions, the decisions you already made. Sessions don't share memory, so execution drifts. When something breaks you restart from nothing.

## The Trade

aihaus inverts that loop. **Front-load the thinking once; the system runs the rest.**

After a single approval, a coordinated team of 43 specialist agents handles research, requirements, architecture, implementation, review, testing, verification, and release. They all read the same project context file. They log every decision. They accumulate lessons across milestones. Each new run starts slightly smarter than the last.

---

## Install

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

The installer symlinks (or junctions on Windows) `.claude/{skills,agents,hooks}` into `.aihaus/{skills,agents,hooks}`. Your existing `settings.local.json` gets merged in, never clobbered.

Verify with:

```bash
/aih-help
```

### Keeping it current

aihaus ships often. When you want the latest:

```bash
/aih-update          # Pull latest from remote, re-link, re-run validation
/aih-update --check  # Just check whether an update is available
```

<details>
<summary><strong>Filesystems without symlinks: <code>--copy</code> mode</strong></summary>

Some CI containers and network drives don't do symlinks. Fall back with:

```bash
bash ~/tools/aihaus/pkg/scripts/install.sh --target . --copy
```

`--copy` duplicates the package into `.claude/`. Live updates are gone — re-run the installer after every `/aih-update`.

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
/aih-milestone <slug> + say "start"    # any ready milestone draft (executes via annexes/execution.md)
/aih-milestone --execute "desc"         # one-shot direct execution
/aih-feature --plan <slug>              # small-plan inline execution (single branch)
```

Milestone execution routes multi-story work through the `annexes/execution.md` pipeline. Small plans go through `/aih-feature --plan` for single-branch execution. (Pre-v0.11.0 `/aih-run` handled both paths; absorbed into `/aih-milestone` + `/aih-feature` respectively.)

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

## The Design

Five ideas, each a file on disk. Together they're the reason the system works.

### Shared project memory

Every agent reads the same small set of files before it touches anything else. No prompt re-teaches the stack; no session starts from zero.

| File | Purpose |
|------|---------|
| `.aihaus/project.md` | Stack, conventions, architecture — read at runtime by every agent |
| `.aihaus/decisions.md` | Architecture Decision Records. Binding. Every code-writing agent reads this before editing code |
| `.aihaus/knowledge.md` | Lessons and gotchas carried forward across milestones so they stop repeating |
| `.aihaus/memory/` | Persistent scoped memory (global + project) spanning sessions |
| `RUN-MANIFEST.md` | Per-milestone execution state. Lets `/aih-resume` pick up exactly where a crashed run stopped |
| `CONVERSATION.md` | Append-only turn log for multi-round agent workflows (see ADR-001 — single-writer discipline) |

### Thin coordinator, specialist workforce

The skill running a command is a coordinator. It spawns the specialist, reads the artifact the specialist writes, picks the next specialist. Nothing big happens in the coordinator's own context.

| Stage | Coordinator | Specialists |
|-------|-------------|-------------|
| Research | Gathers findings, presents brief | analyst, project-researcher, domain-researcher, advisor-researcher, phase-researcher — fan-out |
| Brainstorm | Spawns panel, contrarian, synthesizer; serializes turn log | Panelists write `PERSPECTIVE-*.md`; contrarian writes `CHALLENGES.md`; synthesizer writes `BRIEF.md` |
| Planning | Validates, runs up to 2 plan-checker iterations | planner, plan-checker (must produce findings or justify silence), pattern-mapper, assumptions-analyzer |
| Architecture | Routes ADR decisions | architect, framework-selector |
| Execution | Groups work into waves, cherry-picks worktree commits | implementer, frontend-dev, executor — each in an isolated worktree with a fresh context window |
| Quality | Runs the review → fix → re-review loop | code-reviewer (severity-classified), code-fixer (applies patches), test-writer |
| Verification | Gates completion on FAIL verdicts | verifier (goal-backward), integration-checker (E2E wiring), security-auditor (threat-model anchored) |
| Completion | Promotes decisions and knowledge, applies agent evolutions | reviewer, doc-writer, doc-verifier |

Because every step hands off via files, your main session window stays clean — the heavy lifting lives in subagent contexts and stays there.

### Reviewers that must push back

Six reviewer agents carry a contract: **find at least one real problem, or explain in writing why the artifact is actually clean.** A silent PASS is rejected and triggers re-analysis.

| Agent | Scope of skepticism |
|-------|---------------------|
| `plan-checker` | Does this plan actually achieve its stated goal? Gate before execution |
| `contrarian` | What premises are unexamined? What framings got skipped? Whose perspective is missing? |
| `code-reviewer` | Severity-classified findings on the implementation diff |
| `verifier` | Goal-backward — start from "this did NOT work" and hunt for counter-evidence |
| `integration-checker` | Do the pieces actually connect? Existence ≠ integration |
| `security-auditor` | Do the threat-model mitigations exist as code, not promises |

### One commit per story

Stories land one at a time. Each implementation commit uses an explicit file list drawn from that story's Owned Files — never `git add -A`, never a directory sweep. The history reads linearly:

```
9ce646c feat(scripts): add dogfood-brainstorm.sh regression script (Story 8)
a873ed8 feat(release): /aih-brainstorm, contrarian, brainstorm-synthesizer (v0.5.0) (Story 7)
161ee96 feat(agent): add brainstorm-synthesizer fan-in agent (Story 3)
06dec6b feat(agent): add contrarian adversarial idea-challenger (Story 2)
dc739c2 feat(adr): seed pkg/.aihaus/decisions.md with ADR-001 (files are state)
```

> [!NOTE]
> `git bisect` lands on the exact failing story. Each story is revertable on its own. And the completion protocol can promote decisions and knowledge back into `decisions.md` / `knowledge.md` with surgical traceability.

### Files as the handoff protocol

aihaus never tries to have agents "talk to each other." Coordination happens through files. Every subagent writes its own artifact (`REVIEW.md`, `CHALLENGES.md`, `VERIFICATION.md`, etc.); for multi-round workflows an optional `CONVERSATION.md` turn log is kept, but the coordinator is the only writer — agents get `Read`, never `Write`.

What you get: full audit trail, mid-flight interruptions that resume cleanly, zero write races, and no dependency on an inter-agent messaging primitive that Claude Code doesn't actually offer. Details live in **ADR-001** at `pkg/.aihaus/decisions.md`.

### Protocol that learns

Every completion protocol does one extra thing: reviews itself.

1. **Reviewer** inspects the milestone's decisions and knowledge logs.
2. Drafts proposed edits to agent definitions — new read requirements, new protocol steps, new guardrails — backed by evidence from the milestone.
3. The completion protocol applies evidence-backed proposals automatically.
4. Smoke and purity checks validate the edits.
5. The next milestone starts with agents that are slightly better-informed.

Nothing is fine-tuned and no weights move. What changes is the markdown that guides agents — refined against real project experience, one milestone at a time.

---

## Commands

aihaus ships 11 intent-based skills. Every command follows the same pattern: **ask scoping questions → one approval → fully autonomous**.

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
| `/aih-milestone [slug]` + start-intent / `--execute` | Execute a ready milestone draft — full agent team (via `annexes/execution.md`) |
| `/aih-feature --plan [slug]` | Execute a small plan inline on a single `feature/[slug]` branch |
| `/aih-resume [slug]` | Pick up an interrupted run from `RUN-MANIFEST.md` |
| `/aih-milestone --plan [slug]` | Promote a plan to a milestone draft for conversational refinement (absorbs retired `/aih-plan-to-milestone`) |

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
│   ├── skills/                  # 11 intent-based commands
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

## A note on token cost

A full milestone — adversarial review, code review, goal verification, and a security audit when relevant — is genuinely expensive. **That's the point of the trade.** You spend tokens to skip the parts of the job you used to do by hand: re-prompting, re-checking, re-reading diffs, re-explaining your stack every session.

Skills that could explode cost enforce hard caps *before* spawning. `/aih-brainstorm` runs 5 subagent invocations in its default flow; the maximum reachable run (5 panelists + `--deep` + `--research`) tops out at 13. Nothing hidden, nothing unbounded.

---

## Requirements

- **Claude Code** (CLI or Desktop)
- **git**
- **bash** (Unix) or **PowerShell 5+** (Windows)
- **Claude Code v2.1.111+** recommended to activate Opus 4.7 `effort: xhigh`. Older Claude Code works — `xhigh` falls back to `high` automatically.
- **Optional:** users on Anthropic API + Max/Team/Enterprise can switch to Claude Code auto mode via `/aih-automode --enable`. See caveats in `pkg/.aihaus/skills/aih-automode/annexes/permission-modes.md`.

No runtime. No build step. No package manager. The entire package is markdown and shell scripts.

---

## License

MIT License. See [LICENSE](LICENSE) for details.

---

<div align="center">

**Think once. Approve once. Ship a milestone.**

</div>
