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

CREATE INDEX IF NOT EXISTS idx_tasks_goal_stage ON tasks(goal_id, stage);
CREATE INDEX IF NOT EXISTS idx_tasks_source ON tasks(source_kind, source_id);
CREATE INDEX IF NOT EXISTS idx_questions_task_status
  ON planning_questions(task_id, status);
CREATE INDEX IF NOT EXISTS idx_answers_question
  ON planning_answers(question_id);
CREATE INDEX IF NOT EXISTS idx_task_links_from
  ON task_links(from_task_id, relation);
