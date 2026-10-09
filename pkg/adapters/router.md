# aihaus router

This repository uses the local `.aihaus/` package.

1. Resolve the Git root; paths below are relative to that root. Read
   `.aihaus/MAP.md` and `.aihaus/contracts/harness.md`.
2. Before substantive work or resuming a task, follow the harness context
   check. Run `node .aihaus/tools/refresh.mjs --repo . --status --json` from
   the Git root, then read the rules and decisions relevant to this task.
3. Load one task room and one primary role. When accepted project Assignments
   in `.aihaus/memory/project/procedures.md` define a default role and profile
   for the user-facing session, adopt them unless the user or higher-priority
   instructions direct otherwise. Apply the project's delegation policy within
   the requested scope and existing authorization. Delegated agents retain
   their assigned roles. Without these defaults, select one room and one
   primary role per task.
4. Route orchestration starts and resumes through the MAP, harness, task
   context, and `.aihaus/roles/orchestrator.md`.
5. Use `.aihaus/memory/project/README.md` to select memory; indexes only locate
   sources and never establish authority or prove that a claim is current.
   Recheck affected sources when memory is stale, incomplete, or unverified.
   Follow `.aihaus/REFRESH.md`.
6. Preserve applicable user instructions, including scoped instruction files.
   Record task context and evidence so another agent can resume from files.
7. Require the evidence contract before moving a task to `done`.
   Operational instructions and hooks are not a security sandbox.

Keep project-specific detail, routes, and runbooks in `.aihaus/memory/project/`.
Upgrades replace package-owned files (see `.aihaus/conventions.md`).
