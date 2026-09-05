# Changelog

## 1.5.0 - 2026-09-05

- Require a context check before substantive work and on resumption, with
  scoped memory retrieval, source verification, and durable task references.
- Track memory review provenance per claim, including worktree content hashes;
  recognize root and dot-prefixed sources and flag missing/ambiguous reviews.
- Keep blank/unresolved-only memory, line-ending changes, missing application
  files, and escaping paths from creating false readiness.
- Share AGENTS.md instructions through Claude's native import and report Codex
  root instruction overrides separately from refresh-skill availability.
- Preflight installation conflicts and required directories before writes;
  reject malformed/duplicate managed markers while preserving user content.
- Require complete PASS evidence for done tasks, reject vacuous evidence, handle
  CRLF task answers, and include rename origins/type changes in scope checks.

## 1.4.0 - 2026-07-29

- Renamed the installer command from `aihaus setup` to `aihaus init`;
  `aihaus setup` remains a deprecated alias for one release window.
- Renamed the memory bootstrap surface: `.aihaus/tools/init.mjs` became
  `.aihaus/tools/refresh.mjs`, `.aihaus/INIT.md` became `.aihaus/REFRESH.md`,
  and the host skills `aih-init` became `aih-refresh` (`/aih-refresh`,
  `$aih-refresh`). A deprecated `init.mjs` forwarding stub is kept for one
  release window.
- Upgrades retire the old `.aihaus/INIT.md` and aihaus-marked `aih-init` host
  skills; user-owned files at those paths are preserved.
- Status mode now reports advisory `memoryGaps` (template memory pages with
  cataloged candidate sources) and `staleClaims` (cited sources changed or
  missing since the page's newest cited review commit); both are read-only and
  only inform an agent-proposed refresh.
- When synthesis is blocked in a fresh repository, REFRESH.md now offers a
  scope interview whose owner answers are written to a root PROJECT-BRIEF.md
  as the authoritative source, then discovery is rerun.
- The router now suggests checking refresh status before substantive work and
  proposing a memory refresh when gaps or stale claims are reported.

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
