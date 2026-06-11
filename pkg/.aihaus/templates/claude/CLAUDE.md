# Claude Project Context

<!-- AIHAUS:CLAUDE-CONTEXT-START -->
This repository uses aihaus-flow. Treat `.aihaus/` as the repository-local
workflow and memory plane. Before planning or executing non-trivial work, load
the imported files below and prefer their project-specific facts over generic
assumptions.

If `.aihaus/project.md` is still generic or missing generated content, run
`/aih-init` before relying on project architecture, commands, environments, or
credentials.

## Request Orchestration

Treat every new top-level user request as an intent-routing event before
planning or acting. Spawn `workflow-orchestrator` first and follow its routing
decision unless one of these exceptions applies:

- the conversation is already inside an active aihaus workflow and the user is
  continuing, correcting, or answering that workflow;
- the user explicitly asks to avoid workflow routing for this turn;
- the request is a trivial direct answer with no repository, task, memory, or
  workflow impact.

The orchestrator may choose no workflow. Otherwise it maps the user's intent to
the correct aihaus workflow entry and returns the next action for the main
session to run.

@../.aihaus/project.md
@../.aihaus/protocols/default.md
@../.aihaus/protocols/agents.md
@../.aihaus/protocols/routing.md
@../.aihaus/memory/workflows/README.md
@../.aihaus/memory/workflows/environment.md
@../.aihaus/memory/workflows/business-rules.md
@../.aihaus/memory/workflows/rules.md
@../.aihaus/memory/workflows/user-preferences.md
@../.aihaus/memory/workflows/gotchas.md

Large ledgers are intentionally not imported on startup. Consult them
selectively with search or targeted reads when the task needs ADRs or reusable
findings:

- `.aihaus/decisions.md`
- `.aihaus/knowledge.md`
<!-- AIHAUS:CLAUDE-CONTEXT-END -->
