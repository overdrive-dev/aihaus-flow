# Resume Handling Protocol (shared annex)

Binding contract for stateful agents receiving `--resume-from <substep>` from `/aih-resume`.
Referenced by `implementer`, `frontend-dev`, `code-fixer` (file granularity) and
`debug-session-manager` (step granularity). Overrides contradictory prose in individual agent
definitions.

**Introduced:** M014 (2026-04-22). **Authority:** ADR-M014-B (extends ADR-004, LD-2).

---

## Purpose

When an agent crashes mid-story (Ctrl+C, session loss, OOM), `/aih-resume` re-dispatches it
with `--resume-from <substep>` instead of re-spawning from scratch. This avoids overwriting
files that were already written successfully. The agent MUST honor this argument by skipping
completed substeps and continuing from the correct resume point.

This protocol is the binding contract that makes `--resume-from` safe. Without it, a stateful
agent re-started at substep 1 will silently overwrite work already committed.

---

## Scope

This protocol applies to exactly **four** agents:

| Agent | `resumable` | `checkpoint_granularity` | Substep kind |
|-------|-------------|--------------------------|--------------|
| `implementer` | `false` | `file` | `file:<path>` |
| `frontend-dev` | `false` | `file` | `file:<path>` |
| `code-fixer` | `false` | `file` | `file:<path>` |
| `debug-session-manager` | `false` | `step` | `step:<name>` |

All other agents are `resumable: true` (idempotent re-spawn is safe) and do not need to honor
`--resume-from`. If they receive the argument, they MAY ignore it.

---

## The `--resume-from` Contract (LD-2)

When invoked with `--resume-from <substep>`, the agent MUST:

1. **Read `## Checkpoints`** in the RUN-MANIFEST for the current story. The MANIFEST_PATH
   env var points to the manifest file. If unset, search for `RUN-MANIFEST.md` in the
   closest parent `.aihaus/milestones/*/` or `.aihaus/features/*/` directory.

2. **Locate completed substeps** — iterate the `## Checkpoints` table and build a set of
   substeps that have `exit OK` or `exit SKIP` rows. These are done; do not re-execute them.

3. **Locate the resume point** — the `<substep>` value passed via `--resume-from` is the
   verbatim echo of the manifest `substep` column. Find the first substep in the agent's
   ordered work list that:
   - Matches `<substep>` exactly (string comparison, no parsing), OR
   - Has no `exit OK`/`exit SKIP` row (an orphan `enter` or no row at all).
   That is the first substep to (re-)execute.

4. **Skip all prior completed substeps** — any substep before the resume point that has
   `exit OK` or `exit SKIP` is skipped silently. No re-execution, no re-verification.

5. **Emit a new `enter` checkpoint** for the resume point before starting work:
   ```bash
   MANIFEST_PATH=<path> bash .aihaus/hooks/manifest-append.sh \
     --checkpoint-enter <story> <agent> <substep>
   ```

6. **Continue from the resume point** — execute the substep normally, then proceed through
   all remaining substeps in order.

**String-literal match rule:** The substep identifier passed via `--resume-from` must be
compared string-literally against the agent's own substep list. Do not parse, normalize, or
shorten it. If the identifier has no match (e.g., manifest is from a different story version),
log a warning and start from the first un-completed substep.

---

## Example (file granularity)

```
Story S03 planned to write 4 files:
  file:pkg/hooks/foo.sh
  file:pkg/hooks/bar.sh
  file:pkg/hooks/baz.sh
  file:pkg/hooks/qux.sh

RUN-MANIFEST ## Checkpoints (crash state):
  file:pkg/hooks/foo.sh  exit  OK   a1b2c3d
  file:pkg/hooks/bar.sh  enter                ← orphan (no exit)

/aih-resume dispatches:
  implementer --resume-from file:pkg/hooks/bar.sh

implementer:
  1. Reads ## Checkpoints for S03.
  2. Finds file:pkg/hooks/foo.sh → exit OK → SKIP.
  3. Finds file:pkg/hooks/bar.sh → orphan enter → RESUME HERE.
     (bar.sh may have partial content from the crash; check and clean up if needed)
  4. Emits --checkpoint-enter S03 implementer file:pkg/hooks/bar.sh
  5. Writes file:pkg/hooks/bar.sh
  6. Emits --checkpoint-exit S03 implementer file:pkg/hooks/bar.sh OK a1b2c3d
  7. Continues: baz.sh (enter/write/exit), qux.sh (enter/write/exit).
```

---

## Granularity Sub-sections

### `file` granularity (implementer, frontend-dev, code-fixer)

- Each substep corresponds to a single file write or edit.
- Substep ID format: `file:<relative-path-from-repo-root>`
  - Example: `file:pkg/.aihaus/hooks/manifest-append.sh`
- The agent maintains an ordered list of files to write (its "Owned files" list).
- On resume, the agent iterates this list, skips any with `exit OK`/`exit SKIP`, and begins
  at the first un-completed file.
- **Partial writes:** If resuming at a file that has an orphan `enter` (no `exit`), the file
  may have partial content from the crashed session. The agent SHOULD check the file for
  partial content and decide whether to overwrite from scratch or continue from where it left
  off. Overwriting from scratch is the safer default.
- After each file is written, emit `--checkpoint-exit ... OK <sha>` before moving to the next.

### `step` granularity (debug-session-manager)

- Each substep corresponds to a discrete named step in the multi-cycle debug loop.
- Substep ID format: `step:<step-name>`
  - Example: `step:cherrypick`, `step:run-tests`, `step:apply-fix`
- The agent maintains an ordered list of steps in its debug cycle.
- On resume, the agent iterates its step list, skips any with `exit OK`/`exit SKIP`, and
  begins at the first un-completed step.
- **Loop context:** Debug cycles may be multi-pass (the same step repeated for different
  errors). The substep ID MUST include enough context to identify the specific cycle and step
  (e.g., `step:cycle-2-apply-fix`). Generic `step:apply-fix` is ambiguous across cycles and
  may cause incorrect resume behavior.
- After each step completes, emit `--checkpoint-exit ... OK` before moving to the next.

---

## Interaction with checkpoint-protocol.md (S06)

This protocol extends `_shared/checkpoint-protocol.md`. Stateful agents:

1. **Emit checkpoints per `checkpoint-protocol.md`**: `--checkpoint-enter` before each
   substep, `--checkpoint-exit OK|ERR|SKIP` after.
2. **Honor `--resume-from` per this protocol**: skip completed substeps, resume at the right
   point.

The two contracts are complementary: checkpoint emission makes future resume possible;
resume-handling makes past checkpoints actionable.

When checkpoint-protocol.md and this protocol appear to conflict, this protocol governs the
`--resume-from` behavior, and checkpoint-protocol.md governs checkpoint emission.

---

## Single-writer rule

All checkpoint writes must go through `manifest-append.sh`. Agents must never write checkpoint
rows directly to the manifest file. See `_shared/checkpoint-protocol.md §Single-writer rule`.

---

## Authority

This annex overrides contradictory prose in individual agent files. When an agent's own body
says "always start from the first file" and this annex says "skip completed substeps", the
annex wins. Any agent whose body contradicts this protocol must be updated to reference this
annex and defer to it.
