# memory/reviews/ — Reviewer Output and Common Findings

## Purpose

This bucket holds structured output from the reviewer and code-reviewer
agents: accumulated findings, anti-pattern logs, and plan-checker
observations. It is the long-term record of what recurring issues the
adversarial agents have identified across milestone reviews.

## What goes here

- `common-findings.md` — cross-milestone aggregate; plan-checker + reviewer + code-reviewer
  + verifier may append directly (ADR-M013-A scoped-writer whitelist exception)
- `false-positives.md` — cross-milestone aggregate; reviewer + code-reviewer may append
  directly (same ADR-M013-A whitelist exception)
- `<M0XX>-reviewer.md` — per-milestone reviewer summary, written by orchestrator at
  completion-protocol Step 4.7 (ADR-M013-A; single-writer: orchestrator only)
- `<M0XX>-code-reviewer.md` — per-milestone code-reviewer summary, written by orchestrator
  at completion-protocol Step 4.7 (ADR-M013-A; single-writer: orchestrator only)
- Anti-pattern catalogs referenced by the evolution pass

## What does NOT go here

- Active milestone execution notes → belong in
  `milestones/<slug>/execution/KNOWLEDGE-LOG.md`
- Global patterns applicable to all agents → use `memory/global/`
- Backend or frontend implementation patterns → use `memory/backend/`
  or `memory/frontend/`

## Ownership (locked by ADR-M013-A — S04)

Ownership contract defined in ADR-M013-A (`.aihaus/decisions.md`):

**Cross-milestone aggregates (scoped-writer whitelist):**
- `common-findings.md`: reviewer, code-reviewer, verifier, plan-checker may append directly
- `false-positives.md`: reviewer, code-reviewer may append directly

**Per-milestone summaries (orchestrator sole-writer):**
- `<M0XX>-reviewer.md` and `<M0XX>-code-reviewer.md` are written by the orchestrator via
  completion-protocol Step 4.7. The reviewer/code-reviewer agents emit their summaries
  as fenced payload blocks; the orchestrator parses and Edit-applies.

Per ADR-M009-A, `/aih-update` never overwrites this directory.

## Cross-references

- ADR-M013-A — memory ownership contract (`.aihaus/decisions.md`)
- Completion-protocol Step 4.7 — per-milestone summary emission
- `memory/global/` — cross-cutting patterns from the evolution pass.
- `MEMORY.md` (index at `memory/MEMORY.md`) — entry point index.
