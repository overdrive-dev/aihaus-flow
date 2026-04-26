---
name: aih-resume
description: "Resume an interrupted autonomous run. Reads ## Checkpoints (schema v3) as authoritative truth; dispatches stateful agents with --resume-from. Pass --legacy-mode to fall back to heuristic detection."
disable-model-invocation: true
allowed-tools: Read Grep Glob Bash Write Edit Agent TaskCreate TaskUpdate
argument-hint: "[slug (optional)] [--legacy-mode]"
---

## Task
Pick up an interrupted autonomous run and continue it. No slug required — detects candidates
from RUN-MANIFEST.md files across `.aihaus/milestones/`, `.aihaus/features/`, `.aihaus/bugfixes/`.

$ARGUMENTS

## Flag parsing

Parse `$ARGUMENTS` before any other step.

**`--legacy-mode` flag:** If present, dispatch to `annexes/legacy-mode.md` and stop. That
annex contains the pre-v0.18.0 heuristic Phase 1+2 logic (file-existence inference, stateless
re-spawn). Use it only if the new checkpoint-based flow is not working for your manifest.

## Phase 1 — Detection

### 1. Schema migration

`Glob` for RUN-MANIFEST.md files in:
- `.aihaus/milestones/*/RUN-MANIFEST.md`
- `.aihaus/features/*/RUN-MANIFEST.md`
- `.aihaus/bugfixes/*/RUN-MANIFEST.md`

For each manifest found, run:
```bash
MANIFEST_PATH=<path> bash .aihaus/hooks/manifest-migrate.sh
```
This brings v1 → v2 → v3 idempotently. Required before reading `## Checkpoints` — only v3
manifests have the section.

### 2. Read authoritative checkpoint state

For each manifest, read the **last data row** of the `## Checkpoints` section (7-column LD-1
table: `ts | story | agent | substep | event | result | sha`). This row is the authoritative
source of truth for where execution stopped. Do **not** use file-existence heuristics.

If `## Checkpoints` is absent or has no data rows (header-only), fall through to reading
`## Story Records` last row + `Metadata.phase` (legacy-compatible path within the new flow).

Collect manifests where the last checkpoint's `event` is not `exit OK` for the final planned
substep — i.e., there is unfinished work.

### 3. Worktree reconciliation

Invoke:
```bash
bash .aihaus/hooks/worktree-reconcile.sh
bash .aihaus/hooks/worktree-reap.sh
```

Collect stdout:
- **Category B** entries: cherry-pick recipes — surface to user (do not auto-execute).
- **Category C** entries: dirty preserved worktrees — surface to user (do not auto-resolve).
- **REAP-CANDIDATE** lines: stale lock-marker worktrees (>14d) — surface to user; do not auto-prune.

Category A pruning occurs silently inside the reconcile hook.
L4 reap scan is non-destructive by default; prune only with explicit `--confirm-reap`.

### 4. Cross-check checkpoint vs worktree state

Compare the last checkpoint's `sha` and `substep` against `git worktree list` HEAD shas.
If mismatch is detected (e.g., manifest records `sha: a1b2c3d` but that worktree no longer
exists or has a different HEAD), flag it as an **informational warning** in your output.
Never auto-resolve mismatches — user decides.

### 5. Candidate selection

**When slug is given:** look up directly; error if not found or already completed.

**When no slug given:**
- **One candidate** → proceed silently; log one line: *"Resuming [slug] at [substep]."*
- **Multiple** → present a table and ask which to resume:
  ```
  # | Type      | Slug               | Last substep         | Last event | ts
  1 | milestone | M001-user-auth     | file:src/foo.sh      | enter      | 2026-04-22T15:30Z
  ```
- **Zero** → "Nothing to resume." Stop.

## Phase 2 — Resumption

### 6. Identify next substep

From the last checkpoint row:
- If `event == enter` with no matching `exit` → that substep crashed mid-execution; **resume
  from this substep** (the agent must retry it; may need to clean up partial writes).
- If `event == exit OK` → look ahead to the next substep declared by the agent's story plan
  or the next `enter` without a matching `exit`.
- If `event == resumed` → same as `enter` without exit; still in-progress.

### 7. Look up agent resumable field

Read the agent's frontmatter from `pkg/.aihaus/agents/<agent>.md`:
```yaml
resumable: true | false
checkpoint_granularity: story | file | step
```

### 8. Dispatch branch

**If `resumable: true`** → re-spawn the agent normally (no `--resume-from`). Re-spawn is safe;
the agent is idempotent. Prior completed work may be redone but produces equivalent output.

**If `resumable: false`** → dispatch with `--resume-from <substep>` argument, where `<substep>`
is the verbatim echo of the manifest `substep` column (free-text per LD-2). The agent reads
`_shared/resume-handling-protocol.md` to skip completed substeps and resume at the right point.

Before dispatching, record the resume event:
```bash
MANIFEST_PATH=<path> bash .aihaus/hooks/manifest-append.sh \
  --checkpoint-enter <story> aih-resume <substep>
```
Then after the agent is spawned, record with `event=resumed`:
```bash
MANIFEST_PATH=<path> bash .aihaus/hooks/manifest-append.sh \
  --checkpoint-exit <story> aih-resume <substep> SKIP
```
(The SKIP result indicates aih-resume itself transferred control; the agent's own checkpoints
record its progress.)

Append to the manifest progress log:
```bash
MANIFEST_PATH=<path> bash .aihaus/hooks/manifest-append.sh \
  --field progress-log \
  --payload "[<ts>] — Resumed by /aih-resume at <substep> (resumable=<value>)"
```

## Phase 3 — Finalize

### 9. Continue to completion

Follow the normal execution flow from the checkpoint forward (see `aih-milestone/annexes/execution.md`
for milestone execution steps, or the respective skill for feature/bugfix).

### 10. Report

When done, report the resume point and the final outcome.

## Guardrails
- NEVER re-run completed planning steps (reading their artifacts is enough).
- NEVER re-create completed TaskCreate tasks (check TaskList before creating).
- NEVER auto-execute cherry-pick recipes from Category B worktrees — user is the executor.
- NEVER auto-resolve checkpoint/worktree sha mismatches — flag and continue.
- If RUN-MANIFEST.md is corrupted or unreadable, use `--legacy-mode` path.
- The `--resume-from` argument is a verbatim echo of the manifest substep column — do not
  transform or shorten it.

## Annexes
- `annexes/legacy-mode.md` — legacy heuristic Phase 1+2 (pre-v0.18.0); dispatched only on
  `--legacy-mode` flag; contains `REMOVE in M015 if no usage reported` marker.

## Autonomy
See `_shared/autonomy-protocol.md` — binding rules for planning/threshold/execution phases,
no option menus, no honest checkpoints, no delegated typing. Overrides contradictory prose above.
