# aih-goal source discovery

`/aih-goal` assumes work has already been planned in a kanban/backlog. Source
flags are overrides, not the default path.

### Discovery order

1. Explicit flags:
   - `--from-linear <selector>`
   - `--from-file <path>`
   - `--source <selector>`
2. Existing local operational state:
   - `.aihaus/state/aih-goal.db`
   - tasks not yet at the requested `--until` stage
   - unsynced source cursors/events
3. Workflow memory:
   - `.aihaus/memory/workflows/environment.md`
   - `.aihaus/memory/workflows/user-preferences.md`
   - `.aihaus/memory/workflows/rules.md`
   - any source hints such as Linear team/project/view names or Notion database
     URLs
4. Workflow/project files:
   - `.aihaus/workflows/default.md`
   - `.aihaus/project.md`
5. Connected external kanban systems:
   - Linear
   - Notion
   - Jira
   - Trello
   - GitHub Issues
6. Local task files under `.aihaus/workflows/`.
7. `$ARGUMENTS` as a single goal brief only when no planned source exists.

### Source selection

Prefer the source with the strongest repo-specific signal:

- explicit selector,
- source used by the most recent non-complete goal run,
- source named in workflow memory,
- source with tasks in planning/backlog/dev-review-like states,
- source whose task identifiers appear in recent commits or project memory.

If multiple plausible sources exist, pick the one with the clearest repo match
and record the reason in `RUN-MANIFEST.md`; do not stop for a menu.

### No source found

If no external source, local DB, or local task file can be found, stop before
code changes. Report the missing source and tell the user what to connect or
where to place the local task list.
