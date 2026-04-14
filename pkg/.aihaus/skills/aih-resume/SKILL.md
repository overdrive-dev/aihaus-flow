---
name: aih-resume
description: "Resume an interrupted autonomous run. Detects in-progress milestones, features, or bugfixes via RUN-MANIFEST.md and picks up where execution stopped."
disable-model-invocation: true
allowed-tools: Read Grep Glob Bash Write Edit Agent TaskCreate TaskUpdate
argument-hint: "[slug (optional)]"
---

## Task
Pick up an interrupted autonomous run and continue it. No slug required — detects candidates from RUN-MANIFEST.md files across `.aihaus/milestones/`, `.aihaus/features/`, `.aihaus/bugfixes/`.

$ARGUMENTS

## Phase 1 — Detection

### 1. Scan for interrupted runs

`Glob` for RUN-MANIFEST.md files in:
- `.aihaus/milestones/*/RUN-MANIFEST.md`
- `.aihaus/features/*/RUN-MANIFEST.md`
- `.aihaus/bugfixes/*/RUN-MANIFEST.md`

**For each, FIRST call `bash .aihaus/hooks/manifest-migrate.sh` with `MANIFEST_PATH=<path>`** (ADR-004 / story B.3). Migrates v1 → v2 in place (backup to `.v1.bak`); no-op if already v2. Required before parsing — v2 uses `Metadata` block not `**Status:**` bullets.

Then read Metadata `status:` field (v2) or fallback to `**Status:**` line (legacy, pre-migration). Collect those where status is `running`, `paused`, or any value that is NOT `completed`.

### 2. Legacy fallback (pre-manifest milestones)

For milestone dirs WITHOUT a RUN-MANIFEST.md, check for presence of `execution/MILESTONE-SUMMARY.md`. If missing, treat as "legacy interrupted" and include with a flag.

### 3. Present candidates

**When slug is given:** look up directly, error if not found or already completed.

**When no slug given:**
- **One interrupted run** → confirm ("Resume [slug] at [phase]? Y/n") and continue.
- **Multiple** → present a table:
  ```
  # | Type      | Slug                 | Phase            | Status   | Last updated
  1 | milestone | M001-user-auth       | execute-stories  | running  | [mtime]
  2 | feature   | 260411-rate-limit    | implement        | paused   | [mtime]
  ```
  Ask user to pick.
- **Zero** → "Nothing to resume." Stop.

## Phase 2 — Resumption

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
Ask the user to confirm: "Looks like milestone paused at [phase]. Resume from there?"

### 5. Cross-check with Claude Code tasks

Call TaskList. Match against manifest's task IDs. If tasks are `in_progress` or `pending`, those need to complete. Re-create any task that's missing but should exist per manifest.

### 6. Continue execution

Based on phase:
- **planning** → re-spawn missing planning agents (skip those whose artifacts exist).
- **execute-stories** → re-assign incomplete stories to teammates. Create TaskCreate entries for missing story tasks.
- **completion** → re-run completion protocol.
- **implement / verify / commit** (feature/bugfix) → resume from next uncompleted step.

### 7. Update manifest + refresh Active Milestones

Append to Progress Log: `[ts] — Resumed by /aih-resume`. Update Status to `running` and Phase as appropriate.

If `.aihaus/project.md` exists, spawn `project-analyst` with `--refresh-active-milestones` and merge the scratch file into `project.md` between the `ACTIVE-MILESTONES-START/END` markers. This removes the entry from the Paused table and adds it to Running.

## Phase 3 — Finalize

### 8. Continue to completion

Follow the normal execution flow from the checkpoint forward (see `/aih-run` for milestone execution steps, or the respective skill for feature/bugfix).

### 9. Report

When done, report the resume point and the final outcome.

## Guardrails
- NEVER re-run completed planning steps (reading their artifacts is enough).
- NEVER re-create completed TaskCreate tasks (check TaskList before creating).
- If legacy milestone detection is ambiguous, ask the user.
- If RUN-MANIFEST.md is corrupted or unreadable, fall back to legacy detection + user confirmation.
