# Changelog

## 1.8.0 - 2026-10-09

Review integrity and delegation fixes from field feedback.

- Judgment passes: when an executor wrote the candidate, the orchestrator
  assigns each required pass, and the executor's own review, even through a
  subagent, is a self-check that never satisfies a required pass; a session
  that wrote the candidate without delegating it may start the separate context
  itself. The recheck assignment lists every earlier finding fixed on the task,
  across all rounds, and the recheck reruns their reproductions. A finding is
  dismissed as not applicable only with a recorded command or `path:line`
  showing the candidate cannot reach the required state; absence from current
  data suffices only for a historical state the candidate cannot recreate.
  Reviews gain a capacity lens (worst-case input against time, memory, and
  token limits, including downstream stages when volume rises).
- Evidence: reruns use a clean checkout or export of the candidate SHA; a check
  that passes only with files outside the commit (beyond documented setup) or
  leftover environment is a defect, not a degraded check. The verifier role
  runs its checks the same way.
- Delegation briefs carry the base or candidate SHA and any other source by path
  and revision; other local copies do not replace them. For rules over open
  inputs, the brief gives a decision rule and case table, not example lists.
- Orchestrator: a failed status read is unknown and never triggers action; a
  fix that opens a new case in the same logic counts toward the retry limit,
  then the affected work pauses; for a rule over open inputs the last allowed
  cycle runs from a brief rewritten as a decision rule and case table, not
  another patch.
- Implementers turn reviewer reproductions that can run as tests into
  regression tests that fail before the fix.
- README's Autonomy example notes per-permission conditions such as an
  integration window when merging deploys.
- Project memory templates are unchanged.

## 1.7.0 - 2026-10-09

Replace pasted orchestrator prompts with package guidance plus project data.

- The router adopts a default role and profile for the user-facing session when
  accepted project Assignments define them; without them, each task still gets
  one room and one primary role. Orchestration starts and resumes through the
  orchestrator role.
- The orchestrator role carries the start/resume loop: reread context and
  reconcile integrated work, group by outcome, brief and monitor executors,
  review each delivery, integrate only under explicit authorization (otherwise
  stop before the first remote write), pause on blockers, and promote verified
  findings.
- Planning is an optional read-only assignment that returns to the
  orchestrator, not another coordination level.
- The harness gains a Delegation section with executor preflight and
  profile-based model selection; unavailable requirements are reported, never
  silently substituted.
- MAP points to project Assignments (profiles, default session role) and
  Autonomy, checked before any integration, including solo work.
- Verdict receipts record the requested model and, when the host exposes it,
  the resolved model and settings.
- README documents illustrative profiles, the default-session setting, Autonomy,
  model naming, and a fallback resume prompt. Project memory templates are
  unchanged; installs without these sections retain per-task role selection
  without acquiring session defaults or integration permissions.

## 1.6.1 - 2026-10-09

Fixes from an independent audit of 1.6.0.

- Setup refuses to rewrite AGENTS.md, CLAUDE.md, or .gitignore when the file is
  not UTF-8 text instead of silently corrupting it, writes `.aihaus/VERSION`
  last, and reports a missing `--target` as a normal error.
- evidence-validate, scope-check, and online-action-gate no longer exit 0 without
  checking when invoked through a symlinked or junctioned path.
- `scope-check --base <ref>` also checks committed changes, so committed
  out-of-scope files fail the handoff check.
- task.mjs keeps titles on one line, reads identity fields only from
  frontmatter, files questions under the real `## Business-rule gaps` heading,
  tolerates status folders lost in a clone, accepts BOM-prefixed evidence and
  non-ASCII titles, and replaces task files atomically through a private temp
  file (never writing through a hard link). The discovery packet is replaced
  the same way.
- evidence.md documents the required evidence JSON, including the rung `source`.
- online-action-gate recognizes newline, subshell, git global-option, and
  `flyctl` forms; the host-specific `.claude/_state` sentinel is gone, and
  ops-safety.md defines `.aihaus/state/active-flow`. Vendor deploy families of
  the retired hook list are recorded as intentionally dropped.
- Package-owned files take precedence over procedure text in memory READMEs
  seeded by earlier versions.
- Removed the deprecated `aihaus setup` alias and `.aihaus/tools/init.mjs`
  stub announced in 1.4.0; use `aihaus init` and `.aihaus/tools/refresh.mjs`.
- Discovery no longer reads a Maven parent as the project identity or reports
  aihaus host-skill folders as project layout.

## 1.6.0 - 2026-10-08

- Define two coordination levels: orchestrators assign outcomes and executors
  perform them; the written assignment carries the route, next recipients on
  pass/rework/blocked, and the escalation owner. No distributor agent.
- Keep project-specific assignments in project memory (`procedures.md`,
  "Assignments"); package-owned files stay replaceable on upgrade.
- Bind judgment passes to a candidate SHA, run them in a separate context,
  and record verdict receipts; a recheck never approves unrelated changes.
- Let an accepted decision name an external tracker as task authority; the
  file kanban is then inactive even though setup recreates its folders.
- Add an upgrade runbook for customized installs covering `wouldRefresh`,
  `wouldRemove`, and `.aihaus/INIT.md` removal.
- The root router now sends project-specific detail to `.aihaus/memory/project/`
  instead of rooms, which upgrades replace.

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
  skills; unmarked user-owned skills are preserved. (Correction: `.aihaus/INIT.md`
  is removed whenever it exists, customized or not.)
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
