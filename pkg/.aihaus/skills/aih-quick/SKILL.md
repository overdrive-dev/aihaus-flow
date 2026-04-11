---
name: aih-quick
description: Fast-track for small, well-understood changes. Skips full planning — analyze, implement, and review in one shot.
disable-model-invocation: true
allowed-tools: Read Write Edit Grep Glob Bash
argument-hint: "[what to fix or change]"
---

## Task
This is a small, well-understood change. Skip the full planning pipeline.

$ARGUMENTS

## Protocol
1. **Understand**: Read relevant code, understand the change needed
2. **Check decisions**: Read `.aihaus/decisions.md` (if present) — don't contradict ADRs. Also read `.aihaus/project.md` (if present) for project context.
3. **Implement**: Make the change
4. **Verify**: Run relevant tests and type checks
5. **Self-review**: Check your own work for bugs, security, edge cases
6. **Commit**: Atomic commit with descriptive message

## Guardrails
- If the change touches more than 5 files, STOP and suggest using `/aih-feature` instead
- If the change requires a database migration or schema change (and the project uses a database), STOP and suggest `/aih-plan` or `/aih-milestone` first
- If the change affects user-facing behavior in a meaningful way, STOP and suggest `/aih-feature` first so it gets a plan and review
