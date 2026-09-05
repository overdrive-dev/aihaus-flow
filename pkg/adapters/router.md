# aihaus router

This repository uses the local `.aihaus/` package.

1. Resolve the Git root; paths below are relative to that root. Read
   `.aihaus/MAP.md` and `.aihaus/contracts/harness.md`.
2. Before substantive work or resuming a task, follow the harness context
   check. Run `node .aihaus/tools/refresh.mjs --repo . --status --json` from
   the Git root, then read the rules and decisions relevant to this task.
3. Load one task room and one primary role. Use
   `.aihaus/memory/project/README.md` to select memory; indexes only locate
   sources and never establish authority or prove that a claim is current.
4. Recheck affected sources when memory is stale, incomplete, or unverified.
   Follow `.aihaus/REFRESH.md`; ask only about unresolved business conflicts.
5. Preserve applicable user instructions, including scoped instruction files.
   Record task context and evidence so another agent can resume from files.
6. Require the evidence contract before moving a task to `done`.
   Operational instructions and hooks are not a security sandbox.

Keep project-specific detail out of this router. Put it in the appropriate
room or `.aihaus/memory/project/` page.
