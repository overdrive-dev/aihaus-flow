# Agent Routing — Step 7 Implementation Contract

Binding contract for `/aih-feature` Step 7. The orchestrator delegates implementation work to specialty agents; raw-model inline edits are budgeted and audited.

**Enforcement status:** Phase A (this annex): prose-only, soft mandate — orchestrator self-discipline. Phase B (deferred follow-up): hook-level advisory in `autonomy-guard.sh` + `code-reviewer` Step 7 compliance check. Until Phase B ships, the inline-edit budget is enforced by the orchestrator reading this annex and the post-hoc reviewer optionally surfacing drift. Treat as evolving contract.

## Routing table

| Change scope | Agent | Notes |
|---|---|---|
| Backend: services, schemas, endpoints, migrations | `implementer` | Pre-loaded with backend conventions + ADR history |
| Frontend: components, screens, types, API helpers | `frontend-dev` | Pre-loaded with FE patterns + design system + a11y rules |
| New tests bundled with source changes | bundle into the same agent that owns the source | Tests live next to the code they exercise |
| Test-only refactors (e.g., signature ripple) | `implementer` | Mechanical changes, no new product behavior |
| Cross-subsystem (BE schema → FE type) | sequential `implementer` then `frontend-dev` | Spawn second only after first reports success |

## Parallelism rule

**Independent agents run in parallel** — single message with multiple Agent tool calls. Dependent agents (e.g., backend schema before frontend type) run sequentially.

## Inline-edit budget

The orchestrator MAY make at most **3 small edits inline** (< 5 lines each, single file each) WHEN the work is too small to justify a sub-agent spawn (e.g., adding a single import, flipping a feature flag, fixing a typo).

Anything larger MUST go through an agent. Inline edits beyond this budget MUST be flagged in the manifest progress log with:
```
deviation: inline-only-because: <one-line reason>
```
and become a CRITICAL finding for the Step 9 reviewer (Phase B R4 — coming).

## Pre-spawn briefing checklist

Every agent prompt MUST include all of:

- `MANIFEST_PATH` env binding (mandatory per M011/S03 F-04)
- Repo root absolute path
- Target branch (currently checked out — agents do NOT switch branches)
- Plan reference path (`.aihaus/plans/<slug>/PLAN.md` if applicable)
- Specific files to change (full paths) with line-number anchors where useful
- Out-of-scope guard list ("do NOT touch X, Y, Z")
- "Do NOT commit" — the whole feature lands as one atomic commit later
- Verification commands the agent should run before reporting (e.g., smoke-test, lint, typecheck)
- Brief report contract — what the agent must include in its return summary (worktree path, files touched, verification outputs)

## Why this exists

Raw-model orchestrator inline edits lose three things specialty agents bring:
1. **Project memory** — agent system prompts pre-loaded with conventions, prior PRs, lessons-learned warnings
2. **Context isolation** — main thread stays clean for orchestration; agent burns its own budget
3. **Parallelism** — independent backend + frontend changes run simultaneously instead of serially

Documented evidence: downstream consumer audit post-mortem `260503-aih-feature-step7-agent-delegation` (a 4-edit inline path took ~25–30 minutes; the same work via parallel `implementer` + `frontend-dev` agents took ~12 minutes, with cleaner main-context budget).

## Same class as Step 13/16

This contract closes the same antipattern as M020's Step 13/16 terminal-vocabulary fix (ADR-260502-A): model-driven SKILL steps with no structural enforcement. Phase B (autonomy-guard advisory + code-reviewer compliance check) closes the loop with hook-level enforcement.
