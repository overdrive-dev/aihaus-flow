# RUN-MANIFEST.md — Schema v2 Specification

<!-- DO-NOT-EDIT-MANUALLY at runtime: this is the TEMPLATE. Live RUN-MANIFEST.md files are written by manifest-append.sh / phase-advance.sh / manifest-migrate.sh only. Humans MAY read runtime manifests; writes must go through hooks. -->

**Status:** Canonical — ADR-004 (amendment to ADR-001).
**Introduced:** M003 (2026-04-14).

## Purpose

`RUN-MANIFEST.md` is the single source of truth for step-update state during aihaus autonomous runs. Every milestone, feature, and bugfix writes one manifest. `STATUS.md` is a derived projection of this file (per ADR-004); never the authoritative state.

v2 adds an `Invoke stack` section (for ADR-003's marker protocol), formalizes `Metadata` as a keyed block, and converts the free-form `Progress Log` into append-only pipe-delimited `Story Records`.

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

v1 manifests are detected by the ABSENCE of `schema: v2` in Metadata (or absence of `## Metadata` section entirely). `manifest-migrate.sh` (story 07) converts v1 → v2 in place, preserving a `.v1.bak` backup. `aih-resume` calls `manifest-migrate.sh` on entry; `aih-run` calls it once before the first `manifest-append.sh` operation. After migration, the `.v1.bak` file remains until the milestone completes (cleanup during completion protocol).

## Consumers

| Consumer | Operation | Fields read |
|----------|-----------|-------------|
| `aih-resume/SKILL.md` | recovery | Metadata.status, Metadata.phase, Story Records (most recent per story_id) |
| `aih-run/SKILL.md` | execution | Metadata, Story Records (append), Invoke stack (push/pop) |
| `manifest-append.sh` | mutation | all three sections |
| `manifest-migrate.sh` | conversion | all three sections (from v1 shape) |
| `phase-advance.sh` | STATUS projection | Metadata.phase, Invoke stack (non-empty refusal) |
| `invoke-guard.sh` | depth check | Invoke stack (row count) |
| `project-analyst` agent (`--refresh-active-milestones`) | reporting | Metadata only |

## Non-goals

- **No JSON body.** Pipe-delimited is the contract; consumers use grep/awk/sed, not jq. Cross-platform reliable on Git Bash.
- **No schema version in Story Records rows.** One schema per manifest; migration converts whole files.
- **No multi-writer coordination across different manifests.** The locking discipline (see ADR-004 + `manifest-append.sh`) protects a single manifest's concurrent appends within one milestone's orchestration.
