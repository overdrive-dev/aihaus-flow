# Claude Project Context

<!-- AIHAUS:CLAUDE-CONTEXT-START -->
This repository uses aihaus-flow. Treat `.aihaus/` as the repository-local
workflow and memory plane. Before planning or executing non-trivial work, load
the imported files below and prefer their project-specific facts over generic
assumptions.

If `.aihaus/project.md` is still generic or missing generated content, run
`/aih-init` before relying on project architecture, commands, environments, or
credentials.

@../.aihaus/project.md
@../.aihaus/workflows/default.md
@../.aihaus/workflows/agents.md
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
