# aihaus Project Memory Rule

<!-- AIHAUS:CLAUDE-RULES-START -->
This repository uses aihaus-flow. Do not depend only on the current prompt.

Before non-trivial planning, implementation, review, test, deployment, or
workflow-sync work, check the repo-local context sources:

- `.aihaus/project.md` for stack, architecture, conventions, and project-owned
  operating notes.
- `.aihaus/workflows/default.md` and `.aihaus/workflows/agents.md` for stage
  gates and agent responsibilities.
- `.aihaus/memory/workflows/environment.md` for runtime location, CI/CD,
  CodeBuild or deploy jobs, test credential locations, dev URLs, and validation
  commands.
- `.aihaus/memory/workflows/rules.md`, `user-preferences.md`, and `gotchas.md`
  for durable workflow rules and repeated failures.
- Search or read targeted sections of `.aihaus/decisions.md` and
  `.aihaus/knowledge.md` for binding decisions and reusable technical findings.
  Do not import entire large ledgers into startup context.

If a required fact is absent, do not invent it. Record the missing project fact
as a task-specific blocker or a Memory Candidate so the workflow can promote it
into project memory after human confirmation.

Never store plaintext secrets. Store only where credentials live and how an
authorized agent should retrieve or use them.
<!-- AIHAUS:CLAUDE-RULES-END -->
