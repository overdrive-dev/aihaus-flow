# Changelog

## 1.1.0 - 2026-07-15

- Added an offline, provider-neutral project bootstrap with deterministic
  discovery, dry-run and status modes, source provenance, secret-path
  exclusion, conflict reporting, and an agent-driven synthesis contract for
  canonical project memory.

## 1.0.0 - 2026-07-15

Breaking refactor from the Claude-specific workflow harness to a portable,
repository-local package.

- Added a thin OKF-style Map, three rooms, six roles, and four contracts.
- Added typed Markdown project memory and a folder-authoritative file kanban.
- Added a local-only idempotent Node installer that preserves project content.
- Added structured preflight, source provenance, package ownership,
  preservation, verification, warning, and cleanup reporting to the installer.
- Added an agent-install lab scenario and hardened guidance against host skill
  installers, global clones, silent unpinned installs, and vague overwrite
  claims.
- Added the `aihaus setup` CLI, npm-compatible GitHub Release tarball,
  release provenance manifest and checksum, and an end-to-end release-package
  smoke test with no visible source clone.
- Added deterministic evidence, path, online-action, task, and graph-wrapper
  tools.
- Kept `aih-graph` as the single optional semantic/relationship index with
  explicit consent and repository-local state.
- Removed the archived plugin/marketplace preview, specialist prompt swarm,
  global Claude hooks/settings pipeline, SQLite kanban, Notion core,
  manifest/status bureaucracy, and their migration fixtures.
