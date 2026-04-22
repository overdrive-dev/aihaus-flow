# RUN-MANIFEST schema v3 (backward compatible with v2 readers)

<!-- DO-NOT-EDIT-MANUALLY at runtime: this is the TEMPLATE. Live RUN-MANIFEST.md files are written by manifest-append.sh / phase-advance.sh / manifest-migrate.sh only. Humans MAY read runtime manifests; writes must go through hooks. -->

**Status:** Canonical — ADR-004 (amendment to ADR-001) + ADR-M014-B (v3 extension).
**Introduced:** M003 (2026-04-14). **v3 extension:** M014 (2026-04-22).

## Purpose

`RUN-MANIFEST.md` is the single source of truth for step-update state during aihaus autonomous runs. Every milestone, feature, and bugfix writes one manifest. `STATUS.md` is a derived projection of this file (per ADR-004); never the authoritative state.

v2 adds an `Invoke stack` section (for ADR-003's marker protocol), formalizes `Metadata` as a keyed block, and converts the free-form `Progress Log` into append-only pipe-delimited `Story Records`.

**v3 = v2 + optional `## Checkpoints` section.** v3 is fully backward compatible: a v2 manifest with no `## Checkpoints` section is a valid v3 manifest. v2 readers that do not know about `## Checkpoints` continue to parse the manifest correctly — the new section appears after all v2 sections. The `schema` Metadata key bumps from `v2` to `v3` on migration.

## Structure

Three sections in fixed order, separated by blank lines:

```text
manifest       := metadata BLANK invoke-stack BLANK story-records
metadata       := "## Metadata" "\n" meta-kv+
meta-kv        := key ": " value "\n"
invoke-stack   := "## Invoke stack" "\n" invoke-row*        # max 3 rows (ADR-003 depth cap)
invoke-row     := skill "|" args "|" rationale "|" blocking "|" depth "\n"
story-records  := "## Story Records" "\n" story-header "\n" story-row*
story-header   := "story_id|status|started_at|commit_sha|verified|notes"
story-row      := story-id "|" status "|" started-at "|" commit-sha "|" verified "|" notes "\n"

BLANK          := "\n"
key            := [a-z][a-z0-9_]*
value          := [^\n]*
skill          := "aih-" [a-z0-9-]+
args           := [^|]{0,200}                                # pipe-escaped with \|
rationale      := [^|]{0,200}                                # pipe-escaped with \|
blocking       := "true" | "false"
depth          := "0" | "1" | "2" | "3"
story-id       := [A-Za-z0-9_.-]+
status         := "pending" | "running" | "complete" | "failed" | "blocked"
started-at     := iso-8601-utc                               # e.g. 2026-04-14T10:15:00Z
commit-sha     := [0-9a-f]{7,40} | ""
verified       := "true" | "false" | ""
notes          := [^\n]*                                     # pipe-escaped with \|
```

### Metadata keys

| Key | Required | Values | Notes |
|-----|----------|--------|-------|
| `milestone` | yes (for milestone runs) | e.g. `M003-260414-workflow-core-atomicity-invoke` | empty for feature/bugfix runs |
| `branch` | yes | `milestone/M0XX-<slug>` / `feature/<slug>` / `bugfix/<slug>` | git branch holding commits |
| `started` | yes | ISO-8601 UTC | run start timestamp |
| `schema` | yes | `v2` | detector key for migration (`manifest-migrate.sh`) |
| `phase` | yes | `planning` / `execute-stories` / `verifying` / `completed` / `paused` | projected to STATUS.md |
| `status` | yes | `running` / `completed` / `paused` / `failed` | run-level status |
| `last_updated` | yes | ISO-8601 UTC | stamped on every mutation |

### Invoke stack semantics (ADR-003)

- Empty section (just the H2 heading + empty body) = no invocation in flight. Normal state.
- Rows appended by `manifest-append.sh --field invoke-push --payload "<skill>|<args>|<rationale>|<blocking>|<depth>"`.
- Rows popped (tail removal) by `manifest-append.sh --field invoke-pop`.
- Max 3 rows total. Attempting `invoke-push` on a 3-row stack → hook exits 4 (stack-full).
- `depth` column: 1-indexed depth of this frame. Top of stack has highest depth number.
- `phase-advance.sh` refuses to advance while the Invoke stack is non-empty (active invocation in flight).

### Story Records semantics

- Append-only. Never rewrite an existing line.
- `status` transitions: `pending` → `running` → (`complete` | `failed` | `blocked`). A story that was previously `running` and later completes is recorded as a NEW line with `status: complete` — the old `running` line is NOT edited.
- `commit_sha` populated only on `complete`. On `running` / `pending` / `blocked`, leave empty.
- `verified` set to `true` by the milestone's verifier agent after Track B / integration-check passes.
- Orchestrator reads the MOST RECENT row per `story_id` to determine current state. (Append-only lets history survive.)

### Pipe escaping

The pipe character (`|`) inside any field must be backslash-escaped as `\|`. Readers un-escape before display. Applied to: `args`, `rationale`, `notes`. Other fields have restricted grammars that exclude the character.

## Full example (2 stories, 1 invoke-frame live)

```markdown
## Metadata
milestone: M003-260414-workflow-core-atomicity-invoke
branch: milestone/M003-260414-workflow-core-atomicity-invoke
started: 2026-04-14T02:30:00Z
schema: v2
phase: execute-stories
status: running
last_updated: 2026-04-14T10:45:00Z

## Invoke stack
aih-quick|draft-adr proposal for ADR-005|semantic-design CRITICAL surfaced by plan-checker|true|1

## Story Records
story_id|status|started_at|commit_sha|verified|notes
01-B0-write-site-audit|complete|2026-04-14T02:40:00Z|90ecffd|true|
03-B1-schema-v2-spec|complete|2026-04-14T04:20:00Z|abc1234|true|this file itself
05-B2-manifest-append-hook|running|2026-04-14T10:30:00Z|||implementer spawned
```

## Empty-stack variant (typical running state)

```markdown
## Metadata
milestone: M003-260414-workflow-core-atomicity-invoke
branch: milestone/M003-260414-workflow-core-atomicity-invoke
started: 2026-04-14T02:30:00Z
schema: v2
phase: execute-stories
status: running
last_updated: 2026-04-14T10:45:00Z

## Invoke stack

## Story Records
story_id|status|started_at|commit_sha|verified|notes
01-B0-write-site-audit|complete|2026-04-14T02:40:00Z|90ecffd|true|
```

## Backward compatibility

v1 manifests are detected by the ABSENCE of `schema: v2` in Metadata (or absence of `## Metadata` section entirely). `manifest-migrate.sh` (story 07) converts v1 → v2 in place, preserving a `.v1.bak` backup. `aih-resume` calls `manifest-migrate.sh` on entry; `aih-milestone` (via `annexes/execution.md` Step E2) calls it once before the first `manifest-append.sh` operation. After migration, the `.v1.bak` file remains until the milestone completes (cleanup during completion protocol).

## Consumers

| Consumer | Operation | Fields read |
|----------|-----------|-------------|
| `aih-resume/SKILL.md` | recovery | Metadata.status, Metadata.phase, Story Records (most recent per story_id) |
| `aih-milestone/annexes/execution.md` | execution | Metadata, Story Records (append), Invoke stack (push/pop) |
| `manifest-append.sh` | mutation | all three sections |
| `manifest-migrate.sh` | conversion | all three sections (from v1 shape) |
| `phase-advance.sh` | STATUS projection | Metadata.phase, Invoke stack (non-empty refusal) |
| `invoke-guard.sh` | depth check | Invoke stack (row count) |
| `project-analyst` agent (`--refresh-active-milestones`) | reporting | Metadata only |

## Non-goals

- **No JSON body.** Pipe-delimited is the contract; consumers use grep/awk/sed, not jq. Cross-platform reliable on Git Bash.
- **No schema version in Story Records rows.** One schema per manifest; migration converts whole files.
- **No multi-writer coordination across different manifests.** The locking discipline (see ADR-004 + `manifest-append.sh`) protects a single manifest's concurrent appends within one milestone's orchestration.

---

## Schema v3 extension: `## Checkpoints` section (M014 / ADR-M014-B)

> **File path unchanged** — this schema document stays at `pkg/.aihaus/templates/RUN-MANIFEST-schema-v2.md` per F-10 lock. The file name reflects the base schema; the title reflects the current version.

### v3 = v2 + optional `## Checkpoints` section

The `## Checkpoints` section is **optional** and appears after all v2 sections. Its absence does not make a manifest invalid. After `manifest-migrate.sh` v2→v3 migration, the section always exists (at minimum with the column header and separator, no data rows).

`manifest-append.sh` is the SOLE writer of `## Checkpoints` (ADR-004 single-writer rule extends to v3 per ADR-M014-B). Agents MUST NOT write checkpoint rows directly.

### v3 manifest structure

```text
manifest-v3 := metadata BLANK invoke-stack BLANK story-records BLANK checkpoints
checkpoints  := "## Checkpoints" "\n" checkpoint-header "\n" checkpoint-sep "\n" checkpoint-row*
checkpoint-header := "| ts | story | agent | substep | event | result | sha |"
checkpoint-sep    := "|---|---|---|---|---|---|---|"   (column-width separator)
checkpoint-row    := ts "|" story "|" agent "|" substep "|" event "|" result "|" sha "|" "\n"
```

### Column definitions (LD-1 verbatim)

| Column | Type | Required | Constraints |
|--------|------|----------|-------------|
| `ts` | ISO-8601 UTC string | yes | Format `YYYY-MM-DDTHH:MM:SSZ`; rows appended in lexicographic order |
| `story` | string | yes | Matches `^S\d{2}$` (e.g. `S03`) |
| `agent` | string | yes | Agent slug from `pkg/.aihaus/agents/*.md` (filename without `.md`) |
| `substep` | string | yes | Free-text; convention `<kind>:<identifier>` (e.g. `file:foo.sh`, `step:cherrypick`, `subtask:run-smoke`) |
| `event` | enum | yes | `enter` \| `exit` \| `resumed` |
| `result` | enum | conditional | Required on `exit` and `resumed`; **empty** on `enter`; values: `OK` \| `ERR` \| `SKIP` |
| `sha` | string | optional | 7-char short git sha; empty if no commit produced |

**Substep convention:** `<kind>:<identifier>` where `kind` is one of `file`, `step`, or `subtask`. Examples: `file:src/foo.sh`, `step:cherry-pick`, `subtask:run-smoke-test`. Free-text is accepted; convention aids `/aih-resume` substep matching.

**Event enum:**
- `enter` — recorded at the START of a substep (before the work begins). `result` and `sha` are empty.
- `exit` — recorded at the END of a substep (after the work completes or fails). `result` is required; `sha` is set if a commit was produced.
- `resumed` — recorded when `/aih-resume` re-dispatches an agent from a prior checkpoint. `result` reflects the resumption outcome.

**Result enum (on `exit` and `resumed` only):**
- `OK` — substep completed successfully.
- `ERR` — substep failed; agent may or may not have produced partial output.
- `SKIP` — substep was intentionally skipped (already complete, out-of-scope, or not applicable).

### Example rows

```markdown
## Checkpoints

| ts                   | story | agent       | substep             | event   | result | sha     |
|----------------------|-------|-------------|---------------------|---------|--------|---------|
| 2026-04-22T15:30:01Z | S03   | implementer | file:foo.sh         | enter   |        |         |
| 2026-04-22T15:32:14Z | S03   | implementer | file:foo.sh         | exit    | OK     | a1b2c3d |
| 2026-04-22T15:38:44Z | S03   | implementer | file:bar.sh         | exit    | ERR    |         |
| 2026-04-22T15:45:09Z | S03   | implementer | file:bar.sh         | resumed | OK     | b2c3d4e |
```

### Write modes (manifest-append.sh)

- `--checkpoint-enter <story> <agent> <substep>` — appends a row with `event=enter`, empty `result` and `sha`, current ISO-8601 UTC timestamp.
- `--checkpoint-exit <story> <agent> <substep> <result> [<sha>]` — appends a row with `event=exit`, validated `result` ∈ `{OK,ERR,SKIP}`, optional 7-char sha.

Both modes auto-create the `## Checkpoints` section if absent (defense-in-depth; `manifest-migrate.sh` is the primary creation path).

**Rate-limit guard:** duplicate `enter` events for identical `(story, agent, substep)` within 1 second are silently dropped (anti-spam per Risk table LOW item).

### Migration (v2 → v3)

Run `manifest-migrate.sh` once per manifest. The migration:
1. Detects the literal heading `## Checkpoints` — if present, no-op.
2. If absent, appends the heading + column header + separator row. Does NOT add data rows.
3. Updates `Metadata.schema` from `v2` to `v3`.
4. Idempotent: running twice produces no diff.

Consumers updated to read v3:

| Consumer | Operation | New field read |
|----------|-----------|----------------|
| `aih-resume/SKILL.md` | checkpoint-aware recovery | `## Checkpoints` last data row (`event`, `substep`, `sha`) |
| `manifest-append.sh` | checkpoint write | `## Checkpoints` section (append-only) |
| `manifest-migrate.sh` | v2→v3 migration | creates `## Checkpoints` heading if absent |
