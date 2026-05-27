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
as a task-specific blocker or a Memory Candidate so `/aih-goal` can promote it
into project memory after human confirmation.

Route autonomous batch requests to `/aih-goal`. If the user provides a task
list/backlog or asks to work "sem checkpoints", "ininterruptamente", or "ate
terminar", invoke `/aih-goal --from-list --run-to-completion --until
human-review` when the list is in the prompt.

If Pi/aihaus-pi is present, keep its artifacts under `aihaus-pi/` only. Pi-owned
state, memory, MCP config, evidence, logs, temp files, and continuation files
must not be created under `.aihaus/`, `.aihaus-pi/`, `.pi/`, or root `aihaus/`.

For Pi/aihaus-pi runs, perform context auto-compaction around 95% of usable
context: update `aihaus-pi/state/execution.json`, `aihaus-pi/continue.md`, and
`aihaus-pi/memory/run-summaries/<run>.md`, then continue from the active slice
with a reduced context pack. This is harness state management, not a user
checkpoint, and must not interrupt, pause, or replace the agreed objective.

Never store plaintext secrets. Store only where credentials live and how an
authorized agent should retrieve or use them.
<!-- AIHAUS:CLAUDE-RULES-END -->
