# Per-Agent Memory

This directory holds per-agent memory files at `.aihaus/memory/agents/<agent-name>.md`.

## Purpose

Each file accumulates learnings from a specific agent role across milestones.
When an agent is respawned in a future milestone, it reads its own memory file
to recall project-specific context, recurring patterns, and gotchas from prior runs.

## Naming Convention

- File names match the agent slug exactly: `<agent-name>.md`
- Agent slugs are **hyphen-only** (no underscores). Example: `code-reviewer.md`,
  `knowledge-curator.md`, `user-profiler.md`.
- Reserved prefixes `feedback_*` and `user_*` (underscore) are FORBIDDEN in this
  directory — the smoke-test filename-prefix guard enforces this at CI time.

## Write Path (Single-Writer Invariant)

Files in this directory are written **only** by the orchestrator at
completion-protocol Step 4.7b. Agents emit an `aihaus:agent-memory` fenced block
in their return payload; the orchestrator parses and applies it.

**Agents never write here directly** (they have no Write or Edit tools in their
verifier/planner cohorts; stateful agents in the :doer cohort must still route
through Step 4.7b).

## Append Semantics

Each file is **accumulating** — content is only appended, never overwritten.
The separator between milestone entries is:

```
---
_appended <ISO-8601-timestamp>_
```

## File Format

```markdown
## <YYYY-MM-DD> <milestone-slug>
**Role context:** <what this agent learned about this project>
**Recurring patterns:** <patterns observed across stories>
**Gotchas:** <pitfalls to avoid on next invocation>
```

## Parse Contract

Full contract documented in:
`pkg/.aihaus/skills/_shared/per-agent-memory.md`

## ADR References

- ADR-M013-A: single-writer invariant for `.aihaus/memory/**`
- ADR-M016-B: writer-table row for `.aihaus/memory/agents/**` (Step 4.7b)
