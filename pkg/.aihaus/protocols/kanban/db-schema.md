# Kanban SQLite state

The workflow uses `.aihaus/state/kanban.db` as an operational cache and
append-only journal. When an external kanban exists, the DB is not the human
source of truth. Linear, Notion, Jira, Trello, or GitHub Issues remain the task
source. When no external kanban exists, the DB plus readable run artifacts are
the local kanban source.

### Ownership rule

The DB owns:

- local-only task title, description, priority, visible status, and owner,
- current aihaus workflow stage,
- gate verdicts,
- local locks,
- task-specific planning questions and answers,
- related-task links,
- source snapshots,
- source sync cursors,
- evidence pending sync,
- append-only run events.

When `source_kind` is not `local`, the external source owns:

- task title and primary description,
- business priority,
- human-visible kanban status,
- assignee/owner fields,
- project/list/board membership.

Do not overwrite source-owned fields from local DB state unless the user
explicitly requested that mutation.

### Write chokepoint + gate grammar (M050/S07 — ADR-260611-C, normative)

`aihaus kanban gate|question|answer` is the **sanctioned write path** for
`gate_events`, `planning_questions`, and `planning_answers` rows. Raw
`sqlite3 .aihaus/state/kanban.db` write commands (INSERT/UPDATE/DELETE) are
**deprecated**: `bash-guard.sh` emits a warn-only stderr notice plus an audit
row (`.claude/audit/kanban-write-warn.jsonl`); reads stay silent. Opt-out:
`AIHAUS_KANBAN_WRITE_WARN=0` — audited bypass, never silent (BR-P4). The
warn-only posture is governed by ADR-260611-D: it flips to enforcing only via
a dedicated future ADR.

This section is the **normative home** of the gate grammar. The literals
below are byte-stable — eval and smoke checks grep them; do not reword:

- **Verdict 4-enum:** `PASS|SKIPPED|BLOCKED-TO-PLANNING|BLOCKED` — exactly
  one enum token, optionally followed by `: <reason>` (`SKIPPED: <reason>`,
  `BLOCKED-TO-PLANNING: <task-specific business-rule gap>`,
  `BLOCKED: <true blocker>`). Byte-matches `eval/eval-run.sh` check 1.
- **`rules_cited` grammar:** **comma-separated** elements, each one of
  `BR-F?[0-9]+ | GAP:pq-<id> | MECHANICS`,
  where `<id>` is `[A-Za-z0-9][A-Za-z0-9_-]*`. The `F?` is load-bearing:
  founding rules `BR-F1`..`BR-F4` match the same element regex as numbered
  rules (`BR-12`). The citation obligation itself is the harness gate law
  (`protocols/harness.md` §Gates) — this file only fixes the shape.
- **Validation is warn-only this cycle** (ADR-260611-C/D): malformed verdict
  or `rules_cited` ⇒ stderr warn + `"decision":"warn-allow"` audit row +
  exit 0 — never a block. Audited validation bypass:
  `AIHAUS_KANBAN_GATE_VALIDATE=0`.
- **Citation persistence is JSONL-only** (BR-P10): citations land in
  `.claude/audit/rule-cite.jsonl`, keyed `(task_id, stage, created_at)`; the
  wrapper is that file's **sole writer** (BR-P5). The `gate_events` schema
  below is **untouched** — the additive `rules_cited` column is paid only in
  the future enforce-flip ADR.

`rule-cite.jsonl` row schema (one row per `aihaus kanban gate` invocation;
every decision path — allow / warn-allow / bypass — emits its row before
exiting):

```json
{"ts":"2026-06-11T14:03:00Z","event":"kanban-gate","task_id":"T-014","stage":"tdd",
 "created_at":"2026-06-11T14:03:00Z","verdict":"PASS",
 "rules_cited":["BR-12","BR-F1","GAP:pq-7"],
 "validation":"ok|warn","warn_reason":null,
 "decision":"allow|warn-allow|bypass","opt_out":false,"shell":"bash|pwsh"}
```

`aihaus kanban question` records a task-specific business-rule gap (id
`pq-<n>`, max-scan allocated, status `open`); `aihaus kanban answer` records
the answer (id `pa-<n>`) and flips the question to `answered` — or to
`waived` when the answer is an explicit `no-rule:<reason>` waiver. Answered
questions feed the draft-BR promotion route in `memory-promotion.md`
(`Source: pq-<id>` join token).

### Required tables

Prefer the packaged initializer; do not generate ad hoc `schema.sql` or
`import_tasks.py` under `.aihaus/state/`:

```bash
bash .aihaus/protocols/kanban/init-kanban-db.sh .aihaus/state/kanban.db
```

If the packaged initializer is unavailable, create the DB with `sqlite3` from
the canonical schema below and write temporary import helpers under the current
run directory or OS temp, not `.aihaus/state/`. If SQLite is unavailable, keep
the markdown run artifacts and record `db-unavailable` as a sync blocker before
making source mutations.

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
  description TEXT,
  priority TEXT,
  owner TEXT,
  kanban_status TEXT NOT NULL DEFAULT 'backlog',
  stage TEXT NOT NULL,
  planning_status TEXT NOT NULL DEFAULT 'pending',
  source_updated_at TEXT,
  last_synced_at TEXT,
  sync_state TEXT NOT NULL DEFAULT 'pending',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
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

CREATE TABLE IF NOT EXISTS planning_questions (
  id TEXT PRIMARY KEY,
  task_id TEXT NOT NULL,
  question TEXT NOT NULL,
  reason TEXT,
  status TEXT NOT NULL DEFAULT 'open',
  source_kind TEXT NOT NULL DEFAULT 'local',
  source_ref TEXT,
  asked_at TEXT NOT NULL,
  answered_at TEXT
);

CREATE TABLE IF NOT EXISTS planning_answers (
  id TEXT PRIMARY KEY,
  question_id TEXT NOT NULL,
  answer TEXT NOT NULL,
  source_kind TEXT NOT NULL DEFAULT 'local',
  source_ref TEXT,
  answered_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS task_links (
  id TEXT PRIMARY KEY,
  from_task_id TEXT NOT NULL,
  to_task_id TEXT NOT NULL,
  relation TEXT NOT NULL,
  reason TEXT,
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

CREATE TABLE IF NOT EXISTS memory_events (
  id TEXT PRIMARY KEY,
  task_id TEXT,
  event_kind TEXT NOT NULL,
  status TEXT NOT NULL,
  target_path TEXT,
  payload TEXT NOT NULL,
  created_at TEXT NOT NULL,
  applied_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_tasks_goal_stage ON tasks(goal_id, stage);
CREATE INDEX IF NOT EXISTS idx_tasks_source ON tasks(source_kind, source_id);
CREATE INDEX IF NOT EXISTS idx_questions_task_status
  ON planning_questions(task_id, status);
CREATE INDEX IF NOT EXISTS idx_answers_question
  ON planning_answers(question_id);
CREATE INDEX IF NOT EXISTS idx_task_links_from
  ON task_links(from_task_id, relation);
CREATE INDEX IF NOT EXISTS idx_memory_events_task
  ON memory_events(task_id, event_kind);
```

### Schema evolution

If `tasks` already exists from an older aihaus version, add missing columns
before running a goal. Check table metadata first and ignore duplicate-column
errors only after confirming the column exists.

```sql
ALTER TABLE tasks ADD COLUMN description TEXT;
ALTER TABLE tasks ADD COLUMN priority TEXT;
ALTER TABLE tasks ADD COLUMN owner TEXT;
ALTER TABLE tasks ADD COLUMN kanban_status TEXT NOT NULL DEFAULT 'backlog';
ALTER TABLE tasks ADD COLUMN created_at TEXT;
ALTER TABLE tasks ADD COLUMN updated_at TEXT;
```

Create the new planning, relation, sync, and memory-event tables with
`CREATE TABLE IF NOT EXISTS`.

### Sync safety

- Save a raw source snapshot before summarizing or changing local stage.
- On resume, refresh source-backed tasks from the external source before using
  cached `kanban_status` or `source_updated_at` for execution decisions.
- Register every task locally before planning.
- Record task-specific business-rule gaps in `planning_questions` before
  syncing or asking them.
- Record planning answers before moving a task out of `planejamento`.
- A `planning_questions` row must describe one missing rule for one `task_id`.
  Batch runs may share evidence but must not share one planning question across
  multiple tasks.
- Record one `gate_events` row per task per evaluated stage, including
  `SKIPPED: reason` gates. Batch deploy/test evidence may be shared, but each
  task must have its own event pointing to that evidence.
- After every stage transition, project DB state back into `TASKS.md` and
  `tasks/<task-id>.md`; the task file `Stage:` line must match `tasks.stage`.
- For external kanban tasks, create one outbound `sync_events` row per evaluated
  stage before writing status/comments to the source. The payload should include
  task id, stage, verdict, evidence pointer, requested source status, and comment
  body if any.
- Do not advance a task to the next stage until the stage's outbound sync event
  is either marked synced or explicitly recorded as pending sync debt.
- Search and link related local tasks before creating duplicates.
- Compare `source_updated_at` before writing back.
- If the source changed after import, create a `sync_conflict` event instead of
  overwriting.
- For successful source refreshes, create a `sync_events` row with
  `direction='pull'`; for unavailable sources, record pending sync debt in DB
  and readable artifacts.
- Write evidence as comments/append-only updates whenever possible.
- Include a stable `sync_event.id` in outbound comments to avoid duplicates.
- If a source task disappears, mark local task `source_archived`; do not delete
  history.

### Memory safety

- Record a `memory_events` row for every durable-memory candidate, promotion,
  skipped `no-signal` review, and deferred memory write.
- `event_kind` is one of `candidate`, `promoted`, `no-signal`, `deferred`, or
  `agent-memory`.
- `target_path` must be under `.aihaus/decisions.md`, `.aihaus/knowledge.md`,
  `.aihaus/project.md`, or `.aihaus/memory/**`.
- Never treat `RUN-MANIFEST.md` alone as durable memory. It is evidence for the
  current run; reusable facts must be promoted to a durable target or explicitly
  recorded as `no-signal`/`deferred`.
