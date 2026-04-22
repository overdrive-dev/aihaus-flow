<!-- LEGACY MODE — REMOVE in M015 if no usage reported -->

# aih-resume Legacy Mode (pre-v0.18.0 heuristic flow)

If you are reading this as a model, you were dispatched here because `/aih-resume --legacy-mode`
was invoked. Execute the old heuristic Phase 1+2 flow below instead of the new checkpoint-based
logic in SKILL.md.

**Why this exists:** Schema v3 `## Checkpoints` was introduced in M014. Users on older manifests
(v1/v2) or who encounter issues with the new flow may pass `--legacy-mode` to fall back to the
pre-v0.18.0 stateless re-spawn behavior.

---

## Legacy Phase 1 — Detection (heuristic)

### 1. Scan for interrupted runs

`Glob` for RUN-MANIFEST.md files in:
- `.aihaus/milestones/*/RUN-MANIFEST.md`
- `.aihaus/features/*/RUN-MANIFEST.md`
- `.aihaus/bugfixes/*/RUN-MANIFEST.md`

**For each, FIRST call `bash .aihaus/hooks/manifest-migrate.sh` with `MANIFEST_PATH=<path>`**
(ADR-004 / story B.3). Migrates v1 → v2 in place (backup to `.v1.bak`); no-op if already v2.
Required before parsing — v2 uses `Metadata` block not `**Status:**` bullets.

Then read Metadata `status:` field (v2) or fallback to `**Status:**` line (legacy,
pre-migration). Collect those where status is `running`, `paused`, or any value that is NOT
`completed`.

### 2. Legacy fallback (pre-manifest milestones)

For milestone dirs WITHOUT a RUN-MANIFEST.md, check for presence of
`execution/MILESTONE-SUMMARY.md`. If missing, treat as "legacy interrupted" and include with
a flag.

### 3. Present candidates

**When slug is given:** look up directly, error if not found or already completed.

**When no slug given:**
- **One interrupted run** → proceed silently; log one line: *"Resuming [slug] at [phase]."*
  (No Y/n — see `_shared/autonomy-protocol.md`.)
- **Multiple** → present a table:
  ```
  # | Type      | Slug                 | Phase            | Status   | Last updated
  1 | milestone | M001-user-auth       | execute-stories  | running  | [mtime]
  2 | feature   | 260411-rate-limit    | implement        | paused   | [mtime]
  ```
  Ask user to pick.
- **Zero** → "Nothing to resume." Stop.

---

## Legacy Phase 2 — Resumption (heuristic, stateless)

### 4. Read manifest

Parse RUN-MANIFEST.md for:
- Phase (planning | execute-stories | completion | implement | verify | commit)
- Current story/task (for milestones)
- Progress log (what's been done)

For legacy milestones without a manifest, inspect artifact files to infer phase:
- `analysis-brief.md` exists? → past analyst
- `PRD.md` exists? → past product-manager
- `architecture.md` exists? → past architect
- `stories/` has files AND execution/*-SUMMARY.md exists? → mid-execution
- No MILESTONE-SUMMARY.md? → not done

If the inferred phase is unambiguous (only one plausible stopping point) proceed silently and
log *"Resuming at [phase]."*. Only ask when genuinely ambiguous (e.g., analyst output exists
but incomplete and stories also partially written — unclear whether to re-spawn PM or resume
implementation). See `_shared/autonomy-protocol.md`.

### 5. Cross-check with Claude Code tasks

Call TaskList. Match against manifest's task IDs. If tasks are `in_progress` or `pending`,
those need to complete. Re-create any task that's missing but should exist per manifest.

### 6. Continue execution

Based on phase:
- **planning** → re-spawn missing planning agents (skip those whose artifacts exist).
- **execute-stories** → re-assign incomplete stories to teammates. Create TaskCreate entries
  for missing story tasks.
- **completion** → re-run completion protocol.
- **implement / verify / commit** (feature/bugfix) → resume from next uncompleted step.

**Note:** This legacy path always re-spawns agents from scratch regardless of `resumable`
frontmatter. This risks collision/overwrite for stateful agents (`implementer`, `frontend-dev`,
`code-fixer`, `debug-session-manager`). If a stateful agent was mid-execution, review its
output for partial writes before proceeding.

### 7. Update manifest + refresh Active Milestones

Append to Progress Log: `[ts] — Resumed by /aih-resume (legacy-mode)`. Update Status to
`running` and Phase as appropriate.

If `.aihaus/project.md` exists, spawn `project-analyst` with `--refresh-active-milestones`
and merge the scratch file into `project.md` between the `ACTIVE-MILESTONES-START/END` markers.
This removes the entry from the Paused table and adds it to Running.

---

## Legacy Guardrails
- NEVER re-run completed planning steps (reading their artifacts is enough).
- NEVER re-create completed TaskCreate tasks (check TaskList before creating).
- If legacy milestone detection is ambiguous, ask the user.
- If RUN-MANIFEST.md is corrupted or unreadable, fall back to legacy detection + user
  confirmation.

## Autonomy
See `_shared/autonomy-protocol.md` — binding rules apply in legacy mode equally.
