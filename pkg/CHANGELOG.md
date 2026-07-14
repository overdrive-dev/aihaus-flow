# Changelog

## 1.0.0 - Unreleased

Breaking refactor from the Claude-specific workflow harness to a portable,
repository-local package.

- Added a thin OKF-style Map, three rooms, six roles, and four contracts.
- Added typed Markdown project memory and a folder-authoritative file kanban.
- Added a local-only idempotent Node installer that preserves project content.
- Added deterministic evidence, path, online-action, task, and graph-wrapper
  tools.
- Kept `aih-graph` as the single optional semantic/relationship index with
  explicit consent and repository-local state.
- Removed the archived plugin/marketplace preview, specialist prompt swarm,
  global Claude hooks/settings pipeline, SQLite kanban, Notion core,
  manifest/status bureaucracy, and their migration fixtures.
