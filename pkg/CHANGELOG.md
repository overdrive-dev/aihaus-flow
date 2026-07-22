# Changelog

## 1.3.0 - 2026-07-22

- Removed the retired graph runtime, Ollama/embedding support, release
  workflows, wrappers, installers, and tests.
- Made setup remove known repository-local graph binaries and generated SQLite
  artifacts during upgrades while preserving Markdown memory and file kanban.
- Added optional external task identifiers with case-insensitive deduplication
  across every kanban status.
- Defined one-task-per-worktree ownership and branch-local kanban snapshots.
- Rejected forward task transitions with placeholder acceptance, missing scope,
  or missing review evidence, without rewriting existing tasks.
- Made scope checks preserve Unicode paths and include deleted files reported
  by Git.

## 1.2.0 - 2026-07-15

- Added thin repository-local `aih-init` skills for Claude Code and Codex while
  keeping the Node bootstrap as the provider-neutral source of truth.
- Added structured host-capability and collision reporting. Updates refresh
  only aihaus-marked host skills and preserve user-owned files at the same path.
- Added evidence-readiness gates so empty repositories keep their memory
  templates and cannot be reported initialized from aihaus-generated adapters.
- Made `aihaus setup` content-aware: unchanged reruns are no-ops, `--check`
  previews changes without writing, and `--force` repairs package-owned files
  while still preserving project memory and user-owned adapter collisions.
- Rejected hard-linked managed files so setup cannot mutate an inode shared
  with a path outside the repository.

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
- Added deterministic evidence, path, online-action, and task tools.
- Removed the archived plugin/marketplace preview, specialist prompt swarm,
  global Claude hooks/settings pipeline, SQLite kanban, Notion core,
  manifest/status bureaucracy, and their migration fixtures.
