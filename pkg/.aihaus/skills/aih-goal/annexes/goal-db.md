# aih-goal SQLite state

`/aih-goal` uses `.aihaus/state/aih-goal.db` as an operational cache and
append-only journal. It is not the human source of truth. Linear, Notion, Jira,
Trello, GitHub Issues, or local task files remain the task source.

### Ownership rule

The DB owns:

- current aihaus workflow stage,
- gate verdicts,
- local locks,
- source snapshots,
- source sync cursors,
- evidence pending sync,
- append-only run events.

The external source owns:

- task title and primary description,
- business priority,
- human-visible kanban status,
- assignee/owner fields,
- project/list/board membership.

Do not overwrite source-owned fields from local DB state unless the user
explicitly requested that mutation.

### Required tables

The agent may create the DB with `sqlite3` when available. If a SQLite client is
unavailable, keep the markdown run artifacts and record `db-unavailable` as a
sync blocker before making source mutations.

```sql
CREATE TABLE IF NOT EXISTS goals (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  target_stage TEXT NOT NULL,
  status TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS tasks (
  id TEXT PRIMARY KEY,
  goal_id TEXT NOT NULL,
  source_kind TEXT NOT NULL,
  source_id TEXT,
  source_url TEXT,
  title TEXT NOT NULL,
  stage TEXT NOT NULL,
  planning_status TEXT NOT NULL DEFAULT 'pending',
  source_updated_at TEXT,
  last_synced_at TEXT,
  sync_state TEXT NOT NULL DEFAULT 'pending'
);

CREATE TABLE IF NOT EXISTS source_snapshots (
  id TEXT PRIMARY KEY,
  task_id TEXT NOT NULL,
  captured_at TEXT NOT NULL,
  source_updated_at TEXT,
  raw_payload TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS gate_events (
  id TEXT PRIMARY KEY,
  task_id TEXT NOT NULL,
  stage TEXT NOT NULL,
  verdict TEXT NOT NULL,
  reason TEXT,
  evidence_path TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS sync_events (
  id TEXT PRIMARY KEY,
  task_id TEXT NOT NULL,
  direction TEXT NOT NULL,
  status TEXT NOT NULL,
  source_version TEXT,
  payload TEXT NOT NULL,
  created_at TEXT NOT NULL,
  synced_at TEXT
);
```

### Sync safety

- Save a raw source snapshot before summarizing or changing local stage.
- Compare `source_updated_at` before writing back.
- If the source changed after import, create a `sync_conflict` event instead of
  overwriting.
- Write evidence as comments/append-only updates whenever possible.
- Include a stable `sync_event.id` in outbound comments to avoid duplicates.
- If a source task disappears, mark local task `source_archived`; do not delete
  history.
