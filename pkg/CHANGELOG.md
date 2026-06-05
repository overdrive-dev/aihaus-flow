# Changelog

All notable changes to aihaus are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.40.1] - 2026-06-05 - install hygiene

### Fixed

- Install/update settings merges now prune stale package-managed aihaus hook commands while preserving user/custom hooks, preventing old `.claude/settings.local.json` entries from accumulating redundant guard hooks.
- PowerShell and Bash update flows now keep the managed `.gitignore` block aligned with the install fragment, including `/.aihaus/memory/local/` for repo-local private memory.
- Added a regression fixture for obsolete hook pruning so package smoke catches the drift seen in existing installs.

## [0.40.0] - 2026-05-31 - Business-Rules Contract

### Added

- **Business-rules contract** — a living per-project rules ledger (`.aihaus/memory/workflows/business-rules.md`) the agent decides from autonomously: premises are front-loaded once, and the agent derives every *covered* decision from the contract, returning to a human only on a genuine *gap/conflict* (which becomes a new rule). BDD (Given/When/Then) is the lingua franca. Spec in `workflows/business-rules.md`; 6 domains (`software`/`design`/`infra`/`security`/`data`/`compliance`).
- **Promotion-boundary determinism** — `flow-guard` blocks a deploy/online-action command unless an active flow exists (`phase-advance.sh` sets/clears `.claude/_state/active-flow`); composes with `role-guard`. The **rule-gate** (`calibrate-guard`) requires a non-vacuous testable rule before `tdd`. Opt-outs: `AIHAUS_FLOW_GUARD=0`, `AIHAUS_CALIBRATE_GUARD=0`.
- **aih-graph `Rule` node** (needs aih-graph ≥ v0.1.6) — bidirectional rule↔code binding (`implements`/`relates`/`decided_by`), BM25 + embedding search, and `aih-graph rule-drift` to flag unreviewed rules + dangling bindings.
- **Output-style `aihaus-contract`** — bakes decide-from-contract + BDD framing into the session prompt; enable with `/output-style aihaus-contract`.

### Fixed

- Shipped contract artifacts are project-agnostic — no aihaus-flow-specific identifiers leak into a client's seeded ledger, spec, or output-style.

## [0.39.0] - 2026-05-29 - aihaus 3.0: native-first stage workflow

### Added

- `/aih-env` — capture the test environment, credential *locations* (never values), env access, and deploy path once; persisted to `environment.md` and loaded by every session/agent (survives `/compact`).
- Role-based access (`pm`/`builder`/`dev`/`qa`/`devops`) with a hook-enforced staging→prod online boundary (`role-guard.sh`); `builder`/`dev`/`qa` are offline-local (Docker).
- Local SQLite kanban (`kanban.db`) as the default operational substrate across gated stages; tests run in local Docker by default.
- `workflows/parallelism.md` + ADR-260529-A — worktree isolation + Owned-Files sharding + sequential merge-back + single-writer invariant for conflict-free parallel agents.
- Homepage README fully revamped for 3.0.

### Changed

- Native-first orchestration: native `/goal` + auto-routed sub-flows (`aih-plan`/`aih-feature`/`aih-bugfix`) replace the `aih-goal` orchestrator skill; `/aih-*` is now an optional override. Plans surface to the native Plan panel.
- Sub-flows register their task + gate events in `kanban.db` by default.

### Fixed

- `audit-skill-enforcement.sh` is locale-portable — `grep -P` no longer aborts under a POSIX-C locale on Windows Git Bash (resolves Check 62).

### Removed

- The `aih-goal` orchestrator skill — its kanban/DB substrate relocated to `workflows/kanban/`, decoupled from any "goal" command.

## [0.38.18] - 2026-05-25 - project-agnostic fresh memory

### Fixed

- Fresh installs no longer bulk-copy package `.aihaus/` history into target
  repositories. Install now copies only package-owned base surfaces and seeds
  project knowledge, decisions, and memory from neutral templates.
- `knowledge.md`, `decisions.md`, and memory bucket seeds now start empty and
  explicitly require repository evidence or human answers before promotion.
- Context injection no longer preloads empty or stale project ledgers as
  required context; agents get bounded project/workflow memory and task
  artifacts by default.
- `/aih-init` now documents the bootstrap promotion policy: discovered evidence
  may populate operational memory, answered business questions may become
  rules/knowledge/decisions, and unanswered questions remain questions.

## [0.38.17] - 2026-05-25 - fresh install startup hardening

### Fixed

- `.claude/CLAUDE.md` no longer imports the large `.aihaus/decisions.md` and
  `.aihaus/knowledge.md` ledgers at startup. The bridge now imports bounded
  project/workflow memory and tells agents to search large ledgers selectively.
- Install, update, and continuous context refresh now remove legacy
  `@../.aihaus/decisions.md` and `@../.aihaus/knowledge.md` startup imports from
  existing `.claude/CLAUDE.md` bridge files.
- `session-start.sh` no longer requires `jq`; fresh machines without `jq` emit
  valid SessionStart JSON through a Bash fallback instead of surfacing a startup
  hook error.
- Smoke coverage now exercises the no-`jq` SessionStart path and verifies that
  refresh scrubs large ledger imports.

## [0.38.16] - 2026-05-25 - smoke guard regressions

### Fixed

- `manifest-helpers.sh` no longer lets the POSIX coarse-lock `exec` redirect
  stderr for the rest of the caller, so `merge-back.sh` refusal grammar remains
  visible to agents and smoke fixtures.
- `git-add-guard.sh` now uses POSIX-safe whitespace-boundary matching for
  destructive `git add` and `git commit -am` forms on milestone/feature
  branches.
- The M017 `git-add-guard` fixture now emits valid JSON for commands containing
  quotes.
- Smoke assertions for autonomy-gate JSON now accept both compact and formatted
  JSON, matching current hook output when `jq` is available.

## [0.38.15] - 2026-05-25 - continuous project context refresh

### Fixed

- Settings templates now call hooks through `.aihaus/hooks` instead of
  `.claude/hooks`, so update/init sessions no longer depend on a generated
  `.claude/hooks` junction or copy being present.
- Install/update now normalize legacy `.claude/hooks` command paths in
  existing `.claude/settings.local.json` files to the canonical `.aihaus/hooks`
  path.
- The package repository now pins shell files to LF through `.gitattributes` so
  Windows checkouts do not publish CRLF-broken Bash hooks.
- The Bash settings merge now uses the Python merger as the canonical path,
  avoiding the older `jq` hook-array edge case on Windows hosts.

### Added

- Added `project-context-refresh.sh`, a non-blocking SessionStart,
  TaskCompleted, and SessionEnd hook that repairs missing Claude context
  bridge files, workflow memory imports, workflow profile files, and legacy
  hook paths outside the one-time `/aih-init` flow.
- The refresh hook re-runs environment discovery and Claude context verification
  on a throttled cadence, and immediately after it repairs missing context.
- Smoke-test coverage now exercises the continuous refresh fixture and fails if
  settings regress to `.claude/hooks` paths.

## [0.38.14] - 2026-05-25 - init operational discovery

### Added

- `/aih-init` now runs an operational environment discovery pass that writes an
  evidence-based `AIHAUS:ENV-DISCOVERY` block to
  `.aihaus/memory/workflows/environment.md` and a report to
  `.aihaus/init/environment-discovery.md`.
- `/aih-init` now runs a Claude context verifier that writes
  `.aihaus/audit/claude-context-verify.md`, making missing `.claude/CLAUDE.md`,
  rule files, settings, or broken imports visible after init.
- Added `project-business-interviewer`, a non-blocking init agent that writes
  `.aihaus/init/business-context-questions.md` with one Socratic business-rule
  question per gap. It does not sync TUI-style prompts to kanban or Linear.
- Smoke-test coverage now exercises the environment discovery fixture, Claude
  context verifier fixture, and business-interview artifact contract.

## [0.38.13] - 2026-05-25 - workflow environment prompt backfill

### Fixed

- `/aih-update` now appends the runtime/CI/CodeBuild/credential-location
  scaffold to existing `.aihaus/memory/workflows/environment.md` files when
  that scaffold is missing. Existing installs get the same project-context
  prompts as fresh installs without overwriting local workflow memory.
- Smoke-test coverage now verifies the environment prompt backfill in both
  shell and PowerShell install/update scripts.

## [0.38.12] - 2026-05-25 - Claude-native project context bridge

### Added

- Install/update now seed `.claude/CLAUDE.md` and
  `.claude/rules/aihaus-project-memory.md` from managed templates so fresh
  Claude Code sessions load the repo-local aihaus workflow and memory context
  before slash commands or subagents run.
- `.aihaus/memory/workflows/environment.md` and the project template now expose
  explicit slots for runtime location, CodeBuild/CI, credential locations, dev
  URLs, Playwright/browser validation, and project protocols.
- Subagent context defaults and the `context-inject.sh` fallback now include the
  workflow profile and workflow environment memory, not only project/ADR/knowledge
  files.
- Install/update now seed `.aihaus/knowledge.md` from the bootstrap template
  when it is missing, so Claude imports do not point at a non-existent knowledge
  file.
- Smoke-test coverage verifies the Claude-native bridge, installer/updater
  seeding, environment-memory prompts, and subagent context defaults.

## [0.38.11] - 2026-05-25 - repo-local memory write boundary

### Fixed

- Workflow agents now propose workflow memory through `## Memory Candidate`
  sections and reserve `aihaus:agent-memory` for
  `.aihaus/memory/agents/<agent>.md`, matching the single-writer contract.
- `/aih-goal` memory promotion now rejects or defers agent-memory blocks that
  target workflow/global/review/backend/frontend memory, absolute paths, or
  Claude internal paths such as `~/.claude/**`.
- `file-guard.sh` now explains that blocked writes to
  `~/.claude/projects/**/memory` should be mirrored into project-local
  `.aihaus/memory/**` instead of whitelisted.
- Smoke-test coverage now verifies the repo-local memory boundary and the
  `~/.claude/projects/**/memory` block/remediation path.

## [0.38.10] - 2026-05-24 - review-dev Playwright dispatch

### Fixed

- `/aih-goal` now treats entry into `review-dev` as a mandatory dispatch edge:
  every task reaching the stage must immediately spawn `workflow-dev-reviewer`
  instead of letting the coordinator or prior test gate self-evaluate dev
  review.
- `workflow-test-gate` now states that a Playwright dev-review plan is only
  preparation and does not replace running `workflow-dev-reviewer`.
- `workflow-dev-reviewer` now has an explicit Playwright execution contract:
  identify the dev route/auth/data, prefer the repo Playwright command, capture
  command/result/evidence, and block rather than reporting a browser pass
  without concrete execution evidence.
- Smoke-test coverage now verifies the review-dev agent dispatch contract.

## [0.38.9] - 2026-05-24 - task-specific planning blockers

### Added

- Smoke-test regression coverage for `/aih-goal` business-rule gap wording and
  per-task Linear/local-kanban blocker sync.

### Fixed

- `/aih-goal` planning blockers now require task-specific business-rule gaps
  instead of TUI-style or mixed batch questions when syncing to Linear, local
  kanban, memory, and run artifacts.

## [0.38.8] - 2026-05-24 - goal workflow memory and dev review gates

### Added

- Repository workflow-stage documentation for new users downloading aihaus-flow.
- `/aih-goal` durable memory promotion contract, including workflow memory,
  per-agent memory, `memory_events`, and run-manifest memory outcomes.
- Workflow memory starter files for environment, user preferences, rules, and
  gotchas; install/update seed missing files without overwriting local memory.
- External-kanban reconciliation guidance so resumed goal runs refresh source
  status before trusting cached DB state.

### Fixed

- `/aih-goal` now treats external stage sync as a per-stage gate instead of a
  final-only closeout action.
- `review-dev` now requires Playwright/headless-browser evidence for UI and
  user-flow work, or an explicit backend-only skip/blocker.
- Install/update gitignore normalization now ignores nested `.aihaus` and
  `.claude` folders under sub-repositories.

## [0.38.7] - 2026-05-22 - legacy cleanup diagnostics

### Fixed

- `purity-check.sh` now creates temp files reliably on Windows Git Bash and
  allowlists legacy-migration files that must name old harness artifacts.
- `/aih-update` now captures full smoke output and prints failing checks instead
  of tailing away the diagnosis; framework-purity failures auto-run the delegated
  `purity-check.sh` output.

### Added

- Install/update scripts now warn when the target is under a synced folder and
  when copy mode will overwrite package-managed `.aihaus`/`.claude` files.
- Legacy preflight reports `.claude/worktrees/agent-*` counts and documents the
  manual de-register-plus-move cleanup pattern for stale agent worktrees.
- Managed copy refresh output now states that package-owned copies are
  orphan-pruned against the shipped package tree.

## [0.38.6] - 2026-05-22 - legacy repo hygiene

### Added

- `/aih-init` now runs a legacy hygiene preflight that writes
  `.aihaus/audit/legacy-preflight-*.md`, archives untracked known-disposable
  nested hook leftovers into `.aihaus/backups/legacy-cleanup/`, and leaves Git
  worktrees, `.gsd`, `.hermes`, `.mcp.json`, and tracked files untouched for
  manual review.
- Smoke-test coverage for the legacy preflight, safe archive behavior, and
  expanded gitignore fragment entries.

### Fixed

- Install/update gitignore management now normalizes existing
  `AIHAUS:GITIGNORE` blocks instead of treating old blocks as complete.
- The managed gitignore block now ignores package-owned `.aihaus` and `.claude`
  mirrors plus legacy harness runtime directories (`.bg-shell`, `.worktrees`,
  `.gsd`, `.hermes`) so older repos stop showing framework files as product
  changes.

## [0.38.5] - 2026-05-22 - goal aftermath hardening

### Fixed

- Hook audit/cache defaults are now anchored to the project root, preventing
  nested `.claude/audit/` folders when hooks fire from `.aihaus/state/`,
  `.aihaus/plans/`, or other subdirectories.
- `manifest-auto-close.sh` no longer migrates skipped/refused historical
  manifests during session-start sweeps; schema migration is deferred until all
  close conditions hold and a manifest will actually be updated.
- `/aih-goal` now documents DB-to-markdown projection requirements so task files
  keep `Stage:` and per-task gate rows aligned with `aih-goal.db`.

### Added

- Packaged `/aih-goal` SQLite initializer and schema under
  `skills/aih-goal/scripts/`, avoiding ad hoc `schema.sql` or import helper
  files in consumer `.aihaus/state/` directories.
- Smoke-test regression coverage for project-root audit writes, no auto-close
  manifest churn, and packaged goal DB schema.

## [0.38.4] - 2026-05-22 - settings hook array migration

### Fixed

- Windows `install.ps1` and `update.ps1` now normalize every
  `.claude/settings.local.json` `hooks.<Event>` value to an array of matchers
  after merge, repairing older installs that stored single hook matchers as
  objects.
- Bash/Python settings merge fallback now performs the same legacy hook-event
  normalization as the jq path.
- Install/update scripts now merge settings from the canonical
  `pkg/.aihaus/templates/settings.local.json` template, so newer hook events are
  not missed by stale root-level template files.

## [0.38.3] - 2026-05-22 - Windows aih-graph installer fix

### Fixed

- Windows `install.ps1` and `update.ps1` now use a native PowerShell
  `install-aih-graph-binary.ps1` helper before falling back to Git Bash, avoiding
  MSYS path conversion failures that left `aih-graph.exe.tmp.*` files without
  promoting them to `.aihaus/bin/aih-graph.exe`.
- The native helper removes stale `aih-graph.exe.tmp.*` files before retrying
  the binary install.

## [0.38.2] - 2026-05-22 - local kanban planning contracts

### Added

- `aih-goal` local kanban annex defining task registration, planning
  question/answer contracts, related-task links, and local-only mode.
- SQLite schema for `planning_questions`, `planning_answers`, and `task_links`.

### Changed

- `/aih-goal` now requires every task entering `planejamento` to be registered in
  the local kanban before planning runs.
- Planning questions and answers are now structured contracts: agents must
  record questions before asking them and answers before moving work to `tdd`.
- Goal discovery now searches the local kanban for related tasks before creating
  or importing new planning work.

## [0.38.1] - 2026-05-22 - aih-goal source discovery and SQLite journal

### Changed

- `/aih-goal` now discovers the planned kanban/backlog by default instead of
  requiring source flags such as `--from-linear`.
- Source flags now act as overrides; the default discovery path checks existing
  goal DB state, workflow memory, project/workflow hints, connected kanban
  systems, and local workflow task files.
- Goal state now distinguishes the local SQLite operational cache/journal from
  the external kanban source of truth for task descriptions, priority, status,
  assignee, and board membership.

### Added

- `aih-goal` source discovery annex.
- `aih-goal` SQLite state annex for `.aihaus/state/aih-goal.db`, including
  snapshot, gate-event, and sync-event contracts.

## [0.38.0] - 2026-05-22 - M049 goal runner workflow orchestration

### Added

- `/aih-goal`, an autonomous goal runner that can import source-backed tasks,
  evaluate workflow gates, and run ready work until a target stage such as
  `human-review`.
- Goal run artifacts under `.aihaus/workflows/runs/`, including task files,
  manifest state, and evidence packages.
- Five workflow agents for TDD gates, execution review, test gates, human-review
  packaging, and workflow design, bringing the packaged agent set to 57 agents.
- Linear intake and sync guidance for source-backed planning questions and
  human-review evidence comments.

### Changed

- Workflow gates now have an explicit evaluation contract: `PASS`, `SKIPPED`,
  `BLOCKED-TO-PLANNING`, or `BLOCKED`.
- The planning gate now reads source issue descriptions/comments before
  recording missing planning questions, so answers already captured in Linear
  are not re-asked.

## [0.37.0] - 2026-05-22 - M048 native repository memory + workflow agents

### Added

- Native repository memory defaults for installed projects: `aihaus memory ...` now uses repo-local `.aihaus/state/aih-graph.db`, with `.aihaus/bin/aih-graph[.exe]` as the preferred runtime binary location.
- Four workflow agents for intake, planning gates, CI/CD support, and development review, bringing the packaged agent set to 52 agents.
- Repo-local workflow profile and workflow memory scaffolding under `.aihaus/workflows/` and `.aihaus/memory/workflows/`.
- Installed-layout extraction coverage for `.aihaus/{agents,skills,hooks}` with package-layout fallback, plus indexing for project markdown memory and recent commits.

### Changed

- `aih-graph` now fixes local semantic embeddings to Ollama `nomic-embed-text`; provider selection surfaces were removed from the package flow.
- Lifecycle hooks, context injection, install, and update scripts now prefer repo-local `.aihaus/state`, `.aihaus/runtime`, `.aihaus/backups`, and `.aihaus/bin` paths instead of placing graph state at repository root.
- Workflow guidance now encodes the user-facing chain from backlog through planning, TDD, review, tests, development publication, Playwright-backed development review, human review, and box-dev handoff.

### Verification

- `go test ./...` and `go build ./cmd/aih-graph` pass for the memory engine.
- `tools/smoke-test.sh` passes with 87/87 package checks.

## [0.20.0] - 2026-04-24 — M016: agent memory + context passing + self-recycling evolution

Operationalizes M013's substrate end-to-end across data-plane (recurrence + composite scoring + per-cohort budgets + cache + telemetry) and file-plane (EVOLVING blocks in `project.md` + `CLAUDE.md`, per-agent memory pattern, SKILL-EVOLUTION ledger, unconditional curator cadence). Mid-milestone gate caught two BLOCKERs in flight (ADR-M015-A ID collision → renumbered M015→M016; telemetry single-writer violation → refactored stdout-only).

### Added

- **Hooks:** `pkg/.aihaus/hooks/warning-recurrence.sh` (185 LOC, Jaccard-similarity clustering primary per S00 noise-floor verdict 100%), `composite-score.sh` (299 LOC, 3 deterministic subscores), `scaffold-assert.sh` (62 LOC, exit-13 gate on `planning→running`)
- **Hook config:** `pkg/.aihaus/hooks/context-budget.conf` (6-cohort defaults: planner-binding=4000, planner=3000, doer=2500, verifier=1500, adversarial-scout=3000, adversarial-review=3000)
- **Skills annexes:** `pkg/.aihaus/skills/_shared/per-agent-memory.md` (parse contract + Q2 emission threshold), `pkg/.aihaus/skills/aih-milestone/annexes/milestone-scoped/SKILL-EVOLUTION.md` (template scaffold)
- **Templates:** `pkg/.aihaus/templates/gitignore-fragment` (manual fallback)
- **Memory README:** `pkg/.aihaus/memory/agents/README.md` (per-agent contract doc)
- **Tools:** `tools/telemetry-collect.sh` (maintainer-only, stdout-only post-BLOCKER-2), `tools/s00-noise-floor-check.sh` (synthetic-fixture noise-floor analysis)
- **Smoke-test checks (5 net new):** Check 43 `/aih-init` regression test (S13), Check 44 filename-prefix guard on per-agent memory tree (S15a), Check 45 EVOLVING block well-formed (S16), Check 46 SKILL-EVOLUTION post-apply sub-modes accessible (S16), Check 47 `memory-scores.jsonl` single-writer prose assertion (S16). All PURPOSE-labeled (no integer hardcoding per R12).
- **JSONL audit files (3 new):** `.claude/audit/warning-recurrence.jsonl`, `.claude/audit/memory-scores.jsonl`, `.claude/audit/evolution-apply.jsonl` — all single-writer per ADR-M016-A writer table.
- **Sidecar:** `.aihaus/.context-budgets` (user-owned, ADR-M009-A precedent; per-agent budget overrides)
- **ADRs:** ADR-M016-A (data-plane: scoring, supersession blocks, writer discipline, α-discrepancy disclosure, M017 kill-switch), ADR-M016-B (file-plane: EVOLVING blocks, per-agent memory writer, scaffold-assert.sh as Step E2 gate, 4 PURPOSE-labeled smoke-test checks). ADR-M013-A row-additive amendment via S13 (Cluster A reconciliation byte-identical with ADR-M016-B).

### Changed

- **`pkg/.aihaus/hooks/learning-advisor.sh`:** schema v1→v2 (additive — `recurrence_count`, `last_seen_milestone`, `recurrence_hash`, `schema_version`). Existing fields preserved; v1 readers tolerate.
- **`pkg/.aihaus/hooks/context-inject.sh`:** +247 LOC across S05 (recurring-warnings feedback loop) + S06 (per-cohort budgets + sidecar overrides) + S07 (5-min cache mirroring learning-advisor pattern + `cache_hit` audit field).
- **`pkg/.aihaus/hooks/phase-advance.sh`:** wired `scaffold-assert.sh` invocation on `planning→running` transition (exit 13 propagates).
- **`pkg/.aihaus/skills/aih-milestone/annexes/execution.md`:** Step E2 prose updated to scaffold both AGENT-EVOLUTION.md AND SKILL-EVOLUTION.md unconditionally; new Step E5.5 (mid-milestone adversarial gate primitive, ADR-M016-A governed).
- **`pkg/.aihaus/skills/aih-milestone/completion-protocol.md`:** Step 4.5 audit emission unconditional (closes M014 silent-skip class); new Step 4.6 (skill-evolution apply with smoke-test gate); existing Step 4.6 renamed to 4.6b; new Step 4.7b (per-agent memory apply); Step 6.5 cache invalidation; Step 6.7 telemetry-collect orchestrator-Edit pattern (post-BLOCKER-2).
- **`pkg/.aihaus/agents/*.md` (46 files):** `## Per-agent memory (optional)` template appended; opt-in emission contract per Q2 (prose-only threshold).
- **`pkg/.aihaus/agents/knowledge-curator.md`:** prompt amended for unconditional cadence + Q1 `<!-- no-signal-this-milestone -->` marker on empty inputs (S15b).
- **`pkg/scripts/install.sh` + `install.ps1`:** idempotent `.gitignore` injection with guard-comment block (S04.5).
- **`pkg/scripts/update.sh` + `update.ps1`:** new `--no-gitignore` flag + explicit user-prompt gate for one-shot backfill on existing installs (S04.6).
- **`pkg/.aihaus/templates/project.md`:** nested EVOLVING block inside MANUAL section (S13).
- **`CLAUDE.md`:** EVOLVING block appended at EOF (S14; CRLF-preserving).

### Mid-flight saves

- **BLOCKER 1 (commit `9a75840`):** ADR-M015-A ID collision with shipped v0.19.0 cursor-removal ADR. Renumbered the entire milestone M015→M016 (all hook headers, ADR cross-refs, story files, branch name, dir name).
- **BLOCKER 2 (commit `6c41847`):** `tools/telemetry-collect.sh` violated ADR-M013-A's single-writer invariant by writing `.aihaus/memory/global/architecture.md` directly. Refactored stdout-only; orchestrator captures + Edit-applies at completion-protocol Step 6.7.
- **CRITICAL bootstrap (S17 catch):** M016's own `SKILL-EVOLUTION.md` scaffold missing because `scaffold-assert.sh` didn't exist when M016 transitioned `planning→running`. Trivial fix; future milestones gated correctly.

### Upgrade impact

Downstream users running `bash pkg/scripts/update.sh --target /path` will be prompted to backfill `.gitignore` with `.aihaus/audit/` + `.claude/audit/` paths (`--no-gitignore` flag bypasses). New installs get the injection automatically. Pre-existing user content in `project.md` MANUAL section (outside the new nested EVOLVING block) and in `CLAUDE.md` (outside the new appended EVOLVING block) remains entirely untouched.

### Verification

`bash tools/smoke-test.sh` 47/47 PASS. `bash tools/purity-check.sh` PASS. E7 verifier=PASS (10/10 PRD acceptance criteria with evidence). E7 integration-checker=PASS (15/15 e2e chains intact).

## [0.19.1] - 2026-04-22 — Migration messaging fix-ups

Patch release. Two fix-ups discovered during dogfood `/aih-update` from v0.17.0:

- **`pkg/scripts/lib/merge-settings.sh`** — the post-merge "Settings migrated" notice still claimed `permissions.allow replaced by template defaults (includes Bash(*) wildcard)`. That message was true pre-M014 but stale after the v0.18.0 strip. Rewritten to detect legacy `permissions.allow` carried over from older installs and explain that the template no longer ships any `permissions.{allow,deny,defaultMode}` — autonomy now comes from the DSP wrapper + PreToolUse hooks. Includes guidance for completing the migration by removing the vestigial `permissions.allow` array.
- **`pkg/.aihaus/skills/aih-update/SKILL.md`** — added two new version-gated migration notice blocks:
  - `prev_version < 0.18.0` — DSP launch boundary (M014, BREAKING): documents `/aih-automode` deletion, the `bash .aihaus/auto.sh` launch path, the permission-stack strip, and the resume-substrate rewrite. Points at ADR-M014-A and ADR-M014-B.
  - `prev_version < 0.19.0` — Cursor removal boundary (M015, BREAKING): documents the `--platform` flag removal, the deleted plugin/rules dirs, and ADR-M015-A.

No functional code changes; no agent / skill / hook count changes (12 / 46 / 20 unchanged).

## [0.19.0] - 2026-04-22 — Drop Cursor support (BREAKING)

**BREAKING.** Cursor support is removed entirely. aihaus is Claude Code-only going forward.

### Removed

- `pkg/.aihaus/rules/` directory (`aihaus.mdc`, `COMPAT-MATRIX.md`, `README.md`) -- Cursor plugin rules
- `pkg/.aihaus/.cursor-plugin/` directory (`plugin.json`, `README.md`) -- Cursor plugin manifest
- `--platform` flag from `install.sh`, `install.ps1`, `uninstall.sh`, `uninstall.ps1`
- Cursor cleanup block from `uninstall.sh` (no longer removes `~/.cursor/plugins/local/aihaus`)
- "Multi-platform authoring" section from `CLAUDE.md`
- Cursor badge and "Claude Code AND Cursor" claims from `README.md`

### Governance

- ADR-M015-A supersedes ADR-002 and ADR-005

### Migration

If you had aihaus installed on Cursor: re-install on Claude Code via `bash pkg/scripts/install.sh --target .` and launch via `bash .aihaus/auto.sh` (M014 v0.18.0 wrapper).

### Inventory unchanged

12 skills / 46 agents / 20 hooks (no change from v0.18.0 -- this feature only deletes the Cursor-specific layer).

---

## [0.18.0] - 2026-04-22 — M014 Auto-Launch + Resume Substrate (BREAKING)

**BREAKING.** The 7-layer permission stack is collapsed to 1 launch path. The skill `/aih-automode` is deleted (no shim). The `/aih-resume` skill is rewritten with sub-story checkpoint awareness. Re-install + relaunch via the new wrapper is required.

### DSP launch supersedes permission stack

- New wrapper: `bash .aihaus/auto.sh` (or `.aihaus/auto.ps1` on Windows PowerShell) `exec`s `claude --dangerously-skip-permissions`. This is now the **sole autonomy path** — bare `claude` is non-auto and will prompt normally.
- Stripped from `settings.local.json` template: `permissions.{defaultMode,allow,deny}` + entire `PermissionRequest` hooks block.
- Deleted hooks: `auto-approve-bash.sh`, `auto-approve-writes.sh`, `permission-debug.sh` (3 hooks gone).
- Deleted skill: `pkg/.aihaus/skills/aih-automode/` (the entire directory + 3 annexes). Typing `/aih-automode` returns skill-not-found, mirroring the M012 hard-rename precedent. Also deleted: `pkg/scripts/lib/restore-automode.sh`.
- Safety migrated entirely to PreToolUse: `bash-guard.sh` absorbed all 30+ M007 DANGEROUS_PATTERNS; `file-guard.sh` gained `$CLAUDE_PROJECT_DIR` path-scope check; NEW `read-guard.sh` denies `.env`/`.pem`/`.key`/`credentials*`/`id_*` reads.
- Subagent frontmatter `permissionMode: bypassPermissions` retained on `implementer`/`frontend-dev`/`code-fixer` as defense-in-depth.
- `install.sh` + `install.ps1` create `<target>/.aihaus/auto.sh` (and `.ps1`) symlink, hard-reject `--platform cursor` for DSP-related installs (ADR-005 boundary), and emit a soft warning if `claude --version` is below 2.0.0.

### Resume substrate fix (CORE)

`/aih-resume` no longer re-spawns from story 1 after a mid-implementer crash. Instead:

- **RUN-MANIFEST schema v3** — adds an additive `## Checkpoints` section: `| ts | story | agent | substep | event | result | sha |`. `event` ∈ `{enter, exit, resumed}`; `result` ∈ `{OK, ERR, SKIP}` (only on exit). Substep convention: `<kind>:<identifier>` (e.g. `file:foo.sh`, `step:cherrypick`). v3 = v2 + optional section — backward compatible with v2 readers; `manifest-migrate.sh` is idempotent + additive.
- **`manifest-append.sh`** gains 2 modes: `--checkpoint-enter <story> <agent> <substep>` and `--checkpoint-exit <story> <agent> <substep> <result> [<sha>]`. Auto-creates `## Checkpoints` if missing; rate-limits duplicate `enter` events within 1s.
- **Agent frontmatter** — all 46 agents declare `resumable: true|false` + `checkpoint_granularity: story|file|step`. Stateful (resumable=false): `implementer`, `frontend-dev`, `code-fixer` (file granularity); `debug-session-manager` (step). All 42 others are idempotent.
- **NEW `worktree-reconcile.sh`** — classifies each worktree as A (clean+merged → prune), B (clean+unmerged → emit cherry-pick recipe), C (dirty → preserve + surface). Auto-detects main branch via `origin/HEAD` → `main` → `pi-port` fallback chain.
- **NEW `_shared/checkpoint-protocol.md`** — binding rules for when agents emit checkpoints (entry/exit only, never mid-substep).
- **NEW `_shared/resume-handling-protocol.md`** — binding contract for stateful agents consuming `--resume-from <substep>` (free-text echo from manifest). The 4 stateful agents reference this annex via 1-line body pointers.
- **`/aih-resume` rewrite** — Phase 1 reads `## Checkpoints` last row authoritatively (no more file-existence heuristic), invokes `worktree-reconcile.sh`, cross-checks. Phase 2 branches on `resumable` field — re-spawn idempotent agents; dispatch stateful with `--resume-from`. Records resumption with `event=resumed`.
- **`--legacy-mode`** flag dispatches to `pkg/.aihaus/skills/aih-resume/annexes/legacy-mode.md` (preserved old heuristic flow). `REMOVE in M015 if no usage reported`.

### Governance

- **ADR-M014-A** in `pkg/.aihaus/decisions.md` — DSP launch supersedes ADR-M008-B; reconciles ADR-008/009 (M007 3-layer permission). The package decisions file gets the canonical write (was a long-standing drift between `pkg/.aihaus/decisions.md` and the dogfood-only `.aihaus/decisions.md`).
- **ADR-M014-B** — Resume substrate; extends ADR-004 (RUN-MANIFEST single-writer) additively.
- **COMPAT-MATRIX.md** — DSP marked NOT-SUPPORTED for Cursor (no equivalent CLI flag).

### Smoke-test additions

5 new dynamically-numbered checks: schema v2→v3 migration fixture, worktree-reconcile 3-category fixture, crash-mid-implementer + resume substep parse fixture, bash-guard contains M007 baseline DANGEROUS_PATTERNS, read-guard.sh existence/syntax. Plus Check 6 expanded from 6→8 required frontmatter fields.

### Hotfix included

`73de816` — `file-guard.sh` had two real bugs caught by self-dogfood: multi-arg grep pattern (each line treated as filename arg) + Windows path-scope comparison failed on backslash-vs-forward-slash mismatch between `realpath` output and `$CLAUDE_PROJECT_DIR`. Fixed via single combined regex + cross-platform path normalization (lowercase + slash + drive-prefix unify).

### Migration

```bash
# Re-install (settings template fully refreshed)
bash pkg/scripts/install.sh --target . --update

# Launch via the wrapper (DSP mode)
bash .aihaus/auto.sh

# Or on Windows PowerShell
.aihaus/auto.ps1
```

### Inventory after M014

- **Skills:** 12 (was 13 — `/aih-automode` deleted)
- **Agents:** 46 (CLAUDE.md was stale at 43; M013 added 4)
- **Hooks:** 20 (was 21; +read-guard +worktree-reconcile −auto-approve-bash −auto-approve-writes −permission-debug = -2)

### Open follow-ups (M015 candidates)

- A17 + Read-matcher live test (deferred via Option 2 fallback) — may collapse `read-guard.sh` to single matcher path
- `/aih-resume --legacy-mode` retirement
- Backfill M008-M013 ADRs into `pkg/.aihaus/decisions.md` (long-standing drift with dogfood copy)
- Smoke-test fixture for the D-S10-002 file-guard regression class

## [0.14.0] - 2026-04-16

- Cohort aliases shipped — `:planner` (17 agents), `:doer` (11), `:verifier` (11), `:adversarial` (4). Full mapping at `pkg/.aihaus/skills/aih-effort/annexes/cohorts.md` (Q-1 single source of truth)
- Joint `(model, effort)` tuple is the new calibration primitive — retires per-agent enumerations inside `presets.md`. 4 presets rewritten as cohort-tuple maps
- New CLI flags: `--cohort :<name> --model <m> --effort <e>` (both axes required); `--agent <name> --model <m> --effort <e>` (dual-axis escape hatch)
- `:adversarial` cohort is preset-immune — extends ADR-M008-C's 2-agent list (`plan-checker`, `contrarian`) to 4 agents (`reviewer`, `code-reviewer` added). Explicit `--cohort :adversarial` requires literal-word `adversarial` confirmation
- Sidecar schema v1 → v2 additive — new `cohort.<name>.model` + `cohort.<name>.effort` fields; per-agent `<agent>.model=<m>` override grammar. v1 sidecars keep restoring byte-identically via legacy dispatch
- ADR-M008-A amendment (M010) — scoped allowance for cohort-driven + explicit per-agent dual-axis `model:` edits. ADR-M010-A formalizes cohort taxonomy + preset-map shape
- Phase-1 distribution report now renders as GFM pipe table (5 columns: `Agent | Model | Effort | Cohort | PermissionMode`) — fixes box-drawing fragment clipping on cmd.exe / split panes / copy-back (independent S08 bugfix)
- Smoke-test suite extends to 28 checks — Check 27 gets A5 (adversarial explicit-entry honor); new Check 28 (v2 cohort round-trip, 6 assertions B1-B6)
- v0.14.0 ships functionally equivalent to v0.13.0 `cost-optimized` distribution (Q-2) — representational change; users opt into new vocabulary via `/aih-effort --preset <name>` (skill renamed from v0.13.0 name in v0.17.0)

## [0.8.0] - 2026-04-14

- Cursor coexistence layer (preview) at `cursor-preview/` — documentation-only, no code under `pkg/`
- Compat matrix classifying all 13 skills + 43 agents as WORKS / WORKS-WITH-CAVEAT / NOT-SUPPORTED
- ADR-002: aihaus remains Claude-Code-primary; Cursor support is compat-only
- Verified 2026-04-14: Cursor natively reads `.claude/skills/` and `.claude/agents/` as compat paths
- No installer changes; Cursor users copy `cursor-preview/aihaus.mdc` into `.cursor/rules/` manually

## [0.7.0] - 2026-04-14

- Relocated maintainer-only scripts from `pkg/scripts/` to new top-level `tools/`
- Added `tools/generate-release-notes.sh` to produce user-facing release-note drafts
- `pkg/scripts/` now contains only scripts users download (install/uninstall/update)
- New `## Releasing` section in `CLAUDE.md` documenting the workflow

## [0.1.0] - 2026-04-10

- Initial release
- 8 intent-based commands (init, plan, bugfix, feature, milestone, help, quick, sync-notion)
- /aih-init with project.md generation
- Cross-platform install script with symlink/junction support
