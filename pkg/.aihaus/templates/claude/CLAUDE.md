# Claude Project Context

<!-- AIHAUS:CLAUDE-CONTEXT-START -->
This repository uses aihaus-flow. Treat `.aihaus/` as the repository-local
workflow and memory plane. Before planning or executing non-trivial work, load
the imported files below and prefer their project-specific facts over generic
assumptions.

If `.aihaus/project.md` is still generic or missing generated content, run
`/aih-init` before relying on project architecture, commands, environments, or
credentials.

Autonomous batch routing: when the user asks to work through a list, backlog,
many tasks, "sem checkpoints", "ininterruptamente", or "ate terminar", invoke
`/aih-goal` instead of manually executing the items in chat. If the list is in
the prompt, route to `/aih-goal --from-list --run-to-completion --until
human-review`; do not tell the user to type it.

aihaus-pi boundary: if this repository also uses Pi/aihaus-pi, all Pi-owned
artifacts belong under the visible `aihaus-pi/` tree. Do not write Pi-owned
state, memory, MCP config, evidence, logs, temporary files, or continuation
handoffs under `.aihaus/`, `.aihaus-pi/`, `.pi/`, or a root `aihaus/` folder.

Context auto-compaction: when a Pi/aihaus-pi run approaches 95% of the usable
context budget, compact harness state before continuing. Write/update
`aihaus-pi/state/execution.json`, `aihaus-pi/continue.md`, and
`aihaus-pi/memory/run-summaries/<run>.md`; keep only the original objective,
active slice, decisions, blockers, touched files, pending checks, and evidence
requirements in the live prompt. This is harness state management, not a user
checkpoint: do not interrupt, pause, or replace the agreed objective, and do
not ask the user for permission unless a true blocker appears.

@../.aihaus/project.md
@../.aihaus/workflows/default.md
@../.aihaus/workflows/agents.md
@../.aihaus/memory/workflows/README.md
@../.aihaus/memory/workflows/environment.md
@../.aihaus/memory/workflows/rules.md
@../.aihaus/memory/workflows/user-preferences.md
@../.aihaus/memory/workflows/gotchas.md

Large ledgers are intentionally not imported on startup. Consult them
selectively with search or targeted reads when the task needs ADRs or reusable
findings:

- `.aihaus/decisions.md`
- `.aihaus/knowledge.md`
<!-- AIHAUS:CLAUDE-CONTEXT-END -->
