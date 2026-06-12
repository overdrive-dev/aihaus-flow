# aihaus Artifact Contract (storage & consumption)

How aihaus artifacts are stored and consumed **without failure**. Workflow agents
and the actions (sub-flows + native `/goal` runs) MUST follow this before producing
or reading any artifact. Much of this is already enforced by
`protocols/kanban/run-state.md` (projection rules) and `protocols/kanban/db-schema.md`
(sync safety + schema); this file is the single consolidated contract.

## Two trees (strict division)

- `.claude/` — native Claude Code surface: skill/agent/hook junctions,
  `agent-memory/`, `audit/*.jsonl`, `worktrees/`, settings. **Never** workflow state.
- `.aihaus/` — **all** aihaus artifacts.

Writing a workflow artifact into `.claude/` (or reading workflow state from it) is a bug.

## Taxonomy

| Class | Path | Scope | Authority |
|---|---|---|---|
| Operational state | `.aihaus/state/kanban.db` | local | **AUTHORITY (state)** |
| Readable projection | `.aihaus/runtime/runs/<YYMMDD-slug>/` (GOAL/TASKS/RUN-MANIFEST/tasks/) | local | derived from DB |
| Per-task evidence | `runs/<slug>/evidence/<task-id>/` | local (heavy) | referenced by DB |
| Durable knowledge (incl. business rules) | `.aihaus/decisions.md`, `.aihaus/knowledge.md`, `.aihaus/project.md`, `.aihaus/memory/**` (except `local/`) | **project (committed)** | **AUTHORITY (knowledge)** |
| Local memory | `.aihaus/memory/local/**` (incl. `environment-online.md`) | local (gitignored) | private authority |

## Consumption rules (anti-failure)

1. **One authority per fact.** State → `kanban.db`. Knowledge → durable docs.
   Evidence → the file the DB points to. Projections (`TASKS.md`, `tasks/<id>.md`,
   **and the native CLI task list**) are **derived** — never read as the source of
   truth; rewrite/sync them from the DB after every transition (the written plan and
   the CLI task list are one view).
2. **Reference by recorded pointer**, never a guessed filename. Consumers read
   `gate_events.evidence_path` / `memory_events.target_path` / `tasks.*` — they do
   not reconstruct paths. (Kills producer/consumer path mismatch.)
3. **Typed, DB-allocated, never-reused IDs.** Filenames embed the ID:
   `T-` task · `pq-` planning question · `GATE-` · `EV-` evidence · `BR-` business
   rule · `RUN-` run. `kanban.db` is the sole allocator. For source-backed tasks
   the **source ID is canonical** (e.g. Linear `NORACAR-123`) — no cross-builder
   collision.
4. **Single-writer per transition.** Only the stage's lead agent writes that
   stage's `gate_events` row + projection (ADR-004 single-writer discipline).
5. **Write-then-reference ordering.** Write the evidence file → record the
   `gate_events` row with its path → only then advance the stage. Never advance
   before the pointer persists. (Kills orphan references / advancing on missing evidence.)
6. **Worktree path normalization.** An isolated (`isolation: worktree`) agent
   resolves artifact paths against the **main repo root** via
   `resolve_manifest_path()` (`hooks/lib/manifest-helpers.sh`, M047) — never the
   worktree — so evidence survives merge-back.

## Scope: project vs local

Scope is encoded in the **path**, and `.gitignore` enforces it:

- **project (committed):** business-rules doc, `decisions.md`, `knowledge.md`,
  `project.md`, `memory/**` except `memory/local/`.
- **local (gitignored):** `memory/local/**`, `state/`, `runtime/runs/` evidence,
  `audit/`.

Writing a project-scoped fact into a local path (or vice versa) is a scope bug —
the path decides commit visibility and local-only exposure.

## Eval gate (S6)

At run finish, run `eval/eval-run.sh` over the run's `kanban.db`. A deterministic
FAIL (invalid verdict, missing evidence, planning-gate violation, gate churn) blocks
marking the run complete. The business-rule-coverage rubric is a separate judgment
pass — see `eval/README.md`.
