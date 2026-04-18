# memory/reviews/ — Reviewer Output and Common Findings

## Purpose

This bucket holds structured output from the reviewer and code-reviewer
agents: accumulated findings, anti-pattern logs, and plan-checker
observations. It is the long-term record of what recurring issues the
adversarial agents have identified across milestone reviews.

## What goes here

- `common-findings.md` — plan-checker log of patterns observed in
  multiple reviews (already present; do NOT delete or move)
- Future reviewer-adjacent logs as defined by ADR-M013-A (S04 locks
  final ownership; this README is a placeholder until then)
- Anti-pattern catalogs referenced by the evolution pass
- Code-reviewer observations that recur across multiple PRs

## What does NOT go here

- Active milestone execution notes → belong in
  `milestones/<slug>/execution/KNOWLEDGE-LOG.md`
- Global patterns applicable to all agents → use `memory/global/`
- Backend or frontend implementation patterns → use `memory/backend/`
  or `memory/frontend/`

## Ownership (placeholder — pending ADR-M013-A)

The final ownership contract for this bucket is defined in ADR-M013-A,
to be written in S04. Until then:
- `common-findings.md` is written by the plan-checker agent.
- Other files in this bucket are written by reviewer / code-reviewer.
- Per ADR-M009-A, `/aih-update` never overwrites this directory.

## Cross-references

- ADR-M013-A (S04) — will lock explicit per-file ownership.
- `memory/global/` — cross-cutting patterns from the evolution pass.
- `MEMORY.md` (index at `memory/MEMORY.md`) — entry point index.
