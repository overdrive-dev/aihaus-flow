# Checkpoint Protocol (shared annex)

Binding rules for checkpoint emission across all aihaus agents. Referenced by stateful agents
(`implementer`, `frontend-dev`, `code-fixer`, `debug-session-manager`) and consumed by
`/aih-resume`. Overrides contradictory prose in individual agent definitions.

**Introduced:** M014 (2026-04-22). **Authority:** ADR-M014-B (extends ADR-004).

---

## Purpose

Sub-story checkpoints in `RUN-MANIFEST.md ## Checkpoints` are the authoritative record of
where an agent stopped within a story. `/aih-resume` reads the last checkpoint row — not
file-existence heuristics — to determine whether to re-spawn an agent (`resumable: true`) or
dispatch it with `--resume-from <substep>` (`resumable: false`). Accurate checkpoint emission
is therefore a contract obligation: incorrect or missing checkpoints cause resume to miscalculate
the next substep.

---

## When to emit checkpoints

Emit exactly **two** checkpoints per substep:

1. **`enter` at the start** — before any work begins on the substep.
2. **`exit` at the end** — after the substep completes (successfully, with error, or as a skip).

```
agent starts substep "file:src/foo.sh"
  → emit --checkpoint-enter S03 implementer file:src/foo.sh
  → ... do the work ...
  → emit --checkpoint-exit  S03 implementer file:src/foo.sh OK a1b2c3d
```

**Never emit mid-substep.** A checkpoint is a boundary event, not a progress log. Do not call
`--checkpoint-enter` partway through a substep; do not call it multiple times for the same
substep without a matching `--checkpoint-exit` in between.

**Never edit checkpoint rows.** Rows are append-only per ADR-004 single-writer rule. If a
substep is retried, append a new pair of enter/exit rows; do not alter existing ones.

---

## Substep naming convention

Use the `<kind>:<identifier>` format for every substep. Stable identifiers are required for
`--resume-from` matching — `/aih-resume` echoes the substep string verbatim and the agent
must be able to locate it.

| Kind | When to use | Example |
|------|-------------|---------|
| `file` | Writing or modifying a specific file | `file:src/hooks/manifest-append.sh` |
| `step` | A discrete named operation (not a file) | `step:cherry-pick`, `step:smoke-test` |
| `subtask` | A named sub-task within a story | `subtask:run-purity-check` |

Use the shortest unambiguous identifier for the `identifier` part. For `file`, use the
relative path from the repo root (e.g. `file:pkg/.aihaus/hooks/manifest-append.sh`).

Free-text substep strings are accepted by `manifest-append.sh`, but violating the convention
breaks resume substep matching. Agents that violate it will be caught at the S10 dogfood gate.

---

## Event enum

| Event | When | `result` | `sha` |
|-------|------|----------|-------|
| `enter` | Start of substep (before work) | empty | empty |
| `exit` | End of substep (after work) | required | set if commit produced |
| `resumed` | `/aih-resume` re-dispatch recorded | required | empty or set |

`resumed` rows are written by `/aih-resume` itself — agents do not emit `resumed` directly.

---

## Result enum (on `exit` and `resumed`)

| Result | Meaning |
|--------|---------|
| `OK` | Substep completed successfully; output is valid. |
| `ERR` | Substep failed; output may be partial or absent. |
| `SKIP` | Substep intentionally skipped (already complete, not applicable, or out of scope). |

`manifest-append.sh` validates the result enum and rejects invalid values with exit code 9.

---

## Stateful agent classification

Agents are classified by two frontmatter fields (`resumable`, `checkpoint_granularity`):

| Class | `resumable` | `checkpoint_granularity` | Members |
|-------|-------------|--------------------------|---------|
| Idempotent | `true` | `story` | All agents except the three below |
| Stateful | `false` | `file` | `implementer`, `frontend-dev`, `code-fixer` |
| Multi-cycle | `false` | `step` | `debug-session-manager` |

**Idempotent agents** (`resumable: true`): re-spawn from scratch is safe. `/aih-resume`
dispatches them normally without `--resume-from`. They MAY emit checkpoints for observability
but are not required to honor `--resume-from`.

**Stateful agents** (`resumable: false`): re-spawn risks collision or silent overwrite.
`/aih-resume` dispatches them with `--resume-from <substep>`. They MUST honor the argument
(see `--resume-from` contract below).

---

## `--resume-from` contract for stateful agents

When a stateful agent (`resumable: false`) is dispatched with `--resume-from <substep>`:

1. **Read `## Checkpoints`** in the RUN-MANIFEST for the current story.
2. **Locate the substep** — find the last `exit` row for `<substep>` that has `result=OK` or
   `result=SKIP`. If found, this substep is complete; proceed to the next one.
3. **Skip all prior completed substeps** — iterate the agent's substep list in order; any
   substep with a matching `exit OK` or `exit SKIP` row is skipped.
4. **Resume at the first incomplete substep** — the first substep with no `exit OK`/`exit SKIP`
   row (an orphan `enter` with no `exit`, or no row at all) is where the agent continues.
5. **Emit a new `enter` checkpoint** for the resumed substep before starting work.

The `<substep>` value passed via `--resume-from` is the verbatim echo of the manifest
`substep` column (per LD-2 free-text contract). Agents must not parse it; they must compare it
string-literally against their own substep identifiers.

**Example:**

```
RUN-MANIFEST ## Checkpoints (last known state):
  file:src/foo.sh   exit  OK
  file:src/bar.sh   enter            ← orphan (no matching exit)

/aih-resume dispatches: implementer --resume-from file:src/bar.sh

implementer:
  1. Reads ## Checkpoints for current story.
  2. Finds file:src/foo.sh → exit OK → SKIP.
  3. Finds file:src/bar.sh → enter only → resume here.
  4. Emits --checkpoint-enter S03 implementer file:src/bar.sh
  5. Writes file:src/bar.sh
  6. Emits --checkpoint-exit S03 implementer file:src/bar.sh OK a1b2c3d
  7. Continues with file:src/baz.sh (next in list).
```

---

## Single-writer rule

`manifest-append.sh` is the SOLE writer of `## Checkpoints` (ADR-004 + ADR-M014-B C.3).
Agents MUST call `manifest-append.sh` — never write checkpoint rows directly to the manifest.

```bash
# Correct — delegate to manifest-append.sh
MANIFEST_PATH=/path/to/RUN-MANIFEST.md \
  bash .aihaus/hooks/manifest-append.sh \
  --checkpoint-enter S03 implementer file:src/foo.sh

MANIFEST_PATH=/path/to/RUN-MANIFEST.md \
  bash .aihaus/hooks/manifest-append.sh \
  --checkpoint-exit S03 implementer file:src/foo.sh OK a1b2c3d
```

---

## Rate-limit guard

`manifest-append.sh --checkpoint-enter` silently drops duplicate `enter` events for the same
`(story, agent, substep)` tuple within 1 second. This prevents emission spam from retry loops.
Agents that need to re-enter a substep after a quick abort should wait at least 1 second or
use a distinct substep identifier.

---

## Authority

This annex overrides contradictory prose in individual agent files. When an agent's own body
says "emit a checkpoint at the start of each file" and this annex says "emit at substep
entry/exit only", the annex wins. Any agent whose body contradicts this protocol must be
updated to reference this annex and defer to it.
