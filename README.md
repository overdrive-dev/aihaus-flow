# AIhaus

> **You think. AI builds.** Plan heavy, then let 41 autonomous agents execute — from research to deployment.

```
    _    ___ _
   / \  |_ _| |__   __ _ _   _ ___
  / _ \  | || '_ \ / _` | | | / __|
 / ___ \ | || | | | (_| | |_| \__ \
/_/   \_\___|_| |_|\__,_|\__,_|___/
```

---

## The Problem

You spend 80% of your time telling AI *how* to do things instead of *what* to do. Every prompt requires context about your stack, conventions, and past decisions. When you finally get a plan right, execution drifts because there's no shared memory between sessions. And when something breaks, you start from scratch.

## The Solution

AIhaus flips the ratio. **You invest in planning — AI handles everything else.**

One approval gate. After that, a coordinated team of 41 specialized agents researches, plans, architects, implements, reviews, tests, verifies, and ships — autonomously. Every agent reads the same project context. Every decision is logged. Every lesson feeds back into the system. The more you use it, the smarter it gets.

---

## How It Works

### 1. You Think Heavy

```
/aih-plan Add multi-tenant workspaces with role-based access
```

AIhaus asks 3-5 scoping questions. You answer once. That's your last input.

### 2. AI Builds Autonomously

Behind a single approval, AIhaus orchestrates a full agent team:

```
Research → Analysis → Requirements → Architecture → Plan Review (adversarial)
→ Implementation → Code Review → Fix → Testing → Security Audit
→ Integration Check → Goal Verification → Completion (with self-evolution)
```

Each step is a specialized agent. The **plan-checker** forces adversarial review — it *must* find issues before approving. The **verifier** checks if the *goal* was actually achieved, not just if tasks were completed. The **code-reviewer** classifies findings by severity. The **integration-checker** ensures components actually wire together ("existence is not integration").

### 3. The System Learns

After every milestone, the **reviewer** evaluates what worked and what didn't. Patterns that agents kept rediscovering become permanent protocol. Gotchas that caused repeated failures become rules. Agent definitions evolve — not through manual editing, but through evidence-based proposals that the completion protocol applies automatically.

Your project gets a memory. Future sessions start smarter.

---

## Built on Claude Code Multi-Agent

AIhaus is a workflow package for [Claude Code](https://claude.ai/code). It's not a wrapper or a framework — it's 9 intent-based skills, 41 agent definitions, and 12 lifecycle hooks that install directly into your repo. No runtime, no build step, no package manager. Just markdown and shell scripts that Claude Code reads natively.

**Token usage is significant.** A full milestone with adversarial review, code review, security audit, and goal verification uses substantial context. This is by design — AIhaus trades tokens for quality and autonomy. The alternative is spending your own time reviewing, re-prompting, and re-checking.

### Per-Agent Model Configuration

Not every agent needs the most expensive model. Each of the 41 agents declares its own `model` in YAML frontmatter — Claude Code reads it automatically when spawning the agent. The current defaults:

| Model | Agents | Rationale |
|-------|--------|-----------|
| **Opus** (32) | implementer, architect, reviewer, code-reviewer, debugger, verifier, planner, ... | Complex reasoning, code generation, adversarial review |
| **Sonnet** (9) | test-writer, assumptions-analyzer, ux-designer, pattern-mapper, doc-verifier, ... | Structured output, lighter analysis, template-driven work |

To change any agent's model, edit the `model:` field in its definition file:

```yaml
# .aihaus/agents/test-writer.md
---
name: test-writer
model: opus      # was: sonnet — upgrade for harder test suites
---
```

Valid values: `opus`, `sonnet`, `haiku`. Skills can also override per-call — a normally-opus agent can be downgraded to sonnet for a specific invocation without changing the definition.

### Real-Time Progress Tracking

Long autonomous runs aren't a black box. Every execution skill creates a visible task checklist in your terminal using Claude Code's native task tracking:

```
 [✓] Create feature branch
 [→] Implement changes              ← spinner with active step
 [ ] Run verification
 [ ] Self-review changes
 [ ] Commit changes
 [ ] Write artifacts
```

Each step transitions from pending → in-progress (with spinner) → completed (with checkmark) as the skill executes. You always know what's happening, what's next, and what's done. Task events are also logged to `.claude/audit/` for post-session review.

Available in `/aih-feature` (6 steps), `/aih-bugfix` (6 steps), and `/aih-milestone` (6 phases covering the full planning-to-completion pipeline).

### The Agent Catalog

| Category | Agents | What They Do |
|----------|--------|-------------|
| **Research** | project-researcher, domain-researcher, phase-researcher, advisor-researcher, ai-researcher | Deep-dive before any code is written |
| **Planning** | planner, assumptions-analyzer, roadmapper, pattern-mapper, plan-checker | Structured plans with adversarial review |
| **Architecture** | architect, framework-selector | ADRs, system design, technology decisions |
| **Implementation** | implementer, frontend-dev, executor | Code that follows the plan and ADRs |
| **Quality** | code-reviewer, code-fixer, test-writer | Severity-classified review + auto-fix loop |
| **Verification** | verifier, integration-checker, security-auditor, nyquist-auditor | Goal-backward proof, E2E wiring, threat model verification |
| **Documentation** | doc-writer, doc-verifier, research-synthesizer | Docs verified against live code |
| **Intelligence** | project-analyst, codebase-mapper, intel-updater, user-profiler | Structured codebase knowledge |
| **Debug** | debugger, debug-session-manager | Scientific method bug investigation |
| **UI** | ux-designer, ui-researcher, ui-checker, ui-auditor | Design contracts and visual audits |
| **AI/ML** | eval-planner, eval-auditor, domain-researcher | Evaluation strategy and coverage |
| **Product** | analyst, product-manager | Analysis briefs and structured PRDs |
| **Coordination** | reviewer, notion-sync | QA lead + optional Kanban sync |

---

## Commands

```bash
/aih-init          # Bootstrap project.md — AI learns your codebase
/aih-plan          # Research and plan without writing code
/aih-bugfix        # Triage → branch → fix → test → commit
/aih-feature       # Plan → branch → implement → review → commit
/aih-milestone     # Full lifecycle with agent team — the big one
/aih-quick         # Fast-track for trivial changes
/aih-help          # Show all commands
/aih-update        # Pull latest AIhaus from remote
/aih-sync-notion   # Notion Kanban sync (optional)
```

Every command follows the same pattern: **ask questions → one approval → fully autonomous**. No babysitting. No mid-execution prompts.

---

## Quickstart

```bash
# 1. Clone
git clone https://github.com/overdrive-dev/aihaus-flow ~/tools/aihaus

# 2. Install into your project
cd your-project
bash ~/tools/aihaus/pkg/scripts/install.sh

# 3. Bootstrap
/aih-init

# 4. Build something
/aih-feature Add rate limiting to the public API
```

## What Gets Installed

```
your-project/
├── .aihaus/                    # AIhaus workspace (git-tracked)
│   ├── skills/                 # 9 intent-based commands
│   ├── agents/                 # 41 specialized agent definitions
│   ├── hooks/                  # 12 lifecycle hooks
│   ├── templates/              # project.md + settings templates
│   ├── memory/                 # Persistent agent memory (grows over time)
│   ├── project.md              # Your codebase context (created by /aih-init)
│   ├── decisions.md            # Architecture Decision Records
│   └── knowledge.md            # Lessons learned
├── .claude/                    # Claude Code config
│   ├── settings.local.json     # Permissions + hooks (auto-configured)
│   ├── skills/ → .aihaus/skills/
│   ├── agents/ → .aihaus/agents/
│   └── hooks/ → .aihaus/hooks/
```

## Stack Agnostic

AIhaus works with **any** language, framework, or toolchain. Agents read `project.md` at runtime — they never assume Python, Node, Go, or anything else. The settings ship with `Bash(*)` permissions so every dev tool works without prompts. Install it in a Rust project, a Rails app, or a Go microservice — it adapts.

## Self-Evolving Agents

After each milestone, the system reviews its own effectiveness:

1. **Reviewer** analyzes decisions and knowledge logs from the milestone
2. Proposes edits to agent definitions (new rules, new reads, protocol improvements)
3. **Completion protocol** applies evidence-backed evolutions
4. Smoke test + purity check validate the changes
5. Next milestone starts with smarter agents

This is not fine-tuning. It's protocol evolution — the markdown definitions that guide agents get refined through accumulated project experience.

## Conflict Prevention

Multiple autonomous agents writing code simultaneously is a recipe for divergent choices. AIhaus prevents this through:

- **ADR Gate**: Every code-writing agent reads `decisions.md` before touching code
- **Architect Mandate**: Conflict-prone areas (API style, DB conventions, auth patterns) require explicit ADRs *before* implementation begins
- **Plan Checker**: Adversarial review that *must find issues* — zero findings triggers re-analysis
- **Living Architecture**: The completion protocol updates decisions and knowledge after every milestone

## Update

```bash
/aih-update          # Pull latest version from remote
/aih-update --check  # Just check if update is available
```

## Requirements

- **Claude Code** (CLI or Desktop)
- **git**
- **bash** (Unix) or **PowerShell 5+** (Windows)

No runtime. No build step. No package manager. The entire package is markdown and shell scripts.

## License

MIT. See [LICENSE](LICENSE).
