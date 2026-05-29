# Source discovery

The workflow assumes work has already been planned in a kanban/backlog. Source
flags are overrides, not the default path.

### Discovery order

1. Explicit flags:
   - `--from-linear <selector>`
   - `--from-file <path>`
   - `--source <selector>`
2. Existing local operational state:
   - `.aihaus/state/kanban.db`
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

### External reconciliation

When discovery finds existing `kanban.db` tasks with `source_kind != local`,
refresh those tasks from the external source before using local stage/status for
execution decisions.

For each source-backed task:

- fetch current source status, assignee/owner, comments, and `updatedAt` when the
  connector exposes them,
- save a new `source_snapshots` row with the raw payload,
- update local source-owned projection fields such as `kanban_status`,
  `source_updated_at`, and `sync_state`,
- create a `sync_events` row with `direction='pull'` and status `done` when the
  refresh succeeds,
- if the source is unavailable, keep the cached row but mark the run artifacts
  with sync debt before acting on that task.

Never call the local DB "synced" merely because it was synced in a previous run.
The DB is an operational cache; the external kanban remains authoritative for
source-owned fields.

### Local kanban lookup

Before creating or importing a task into `planejamento`, query the local kanban
for related tasks using source ids, URLs, titles, module/file names, source
snapshots, planning questions, and planning answers.

If a related task exists, link it in `task_links` and mention it in the task
file. Do not silently collapse two tasks into one unless they share the same
source id or the user explicitly asked for deduplication.

### No source found

If no external source, local DB, or local task file can be found, stop before
code changes. Report the missing source and tell the user what to connect or
where to place the local task list.
