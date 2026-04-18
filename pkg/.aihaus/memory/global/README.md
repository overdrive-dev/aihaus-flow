# memory/global/ — Project-Wide Reusable Patterns

## Purpose

This bucket holds knowledge that is reusable across the entire project,
regardless of stack layer. It is the primary output surface for the
agent-evolution pass (ADR-M013-A) and the canonical landing zone for
discoveries made by any agent that apply to more than one domain.

## What goes here

- Cross-cutting patterns (error handling conventions, naming rules,
  logging contracts, commit discipline)
- Agent-evolution output: improvements proposed by the reviewer after
  milestone completion that affect all agents
- Global gotchas — traps that cost a story in any area of the codebase
- Shared architectural decisions that are not yet formal ADRs
- `gotchas.md` — persistent list of known pitfalls (all agents read this)
- `patterns.md` — reusable implementation patterns (all agents read this)

## What does NOT go here

- Backend-specific patterns → use `memory/backend/`
- Frontend-specific patterns → use `memory/frontend/`
- Reviewer-output findings logs → use `memory/reviews/`
- In-progress or per-run state → belongs in the milestone's
  `execution/KNOWLEDGE-LOG.md`, not here

## Ownership

Files in this bucket are **agent-written, human-reviewable**.
The implementer, code-fixer, and reviewer agents write here.
Per ADR-M009-A, `/aih-update` never overwrites this directory.

## Cross-references

- ADR-M013-A (to be written in S04) locks the full ownership contract.
- `memory/reviews/common-findings.md` holds the plan-checker's log.
- `MEMORY.md` (index at `memory/MEMORY.md`) is the entry point for
  agents loading context before a task.
