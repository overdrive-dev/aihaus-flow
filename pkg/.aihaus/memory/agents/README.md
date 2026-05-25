# Per-Agent Memory

This directory holds per-agent memory files at
`.aihaus/memory/agents/<agent-name>.md`.

## Purpose

Each file accumulates learnings from a specific agent role across project runs.
When an agent is respawned later, it can read its own memory file to recall
project-specific context, recurring patterns, and gotchas from prior work.

Fresh installs intentionally start with no agent memory.

## Naming Convention

- File names match the agent slug exactly: `<agent-name>.md`.
- Agent slugs use hyphens, not underscores.
- Reserved prefixes `feedback_*` and `user_*` are not used here.

## Write Path

Agents should emit candidate memory in their return payload. The orchestrator or
completion protocol promotes durable facts after evidence review.

Agents should not write Claude internal project memory paths such as
`~/.claude/projects/**/memory`. aihaus durable memory stays under
`.aihaus/memory/**`.

## File Format

```markdown
## <YYYY-MM-DD> <run-or-task-slug>
**Role context:** <what this agent learned about this project>
**Recurring patterns:** <patterns observed across tasks>
**Gotchas:** <pitfalls to avoid on next invocation>
```
