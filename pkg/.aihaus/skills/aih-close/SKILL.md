---
name: aih-close
description: Close a stale RUN-MANIFEST atomically. Default-to-completed if branch is merged; explicit --deferred / --cancelled / --completed / --awaiting-merge for partial work; --bulk for sweep over auto-closeable manifests.
disable-model-invocation: true
allowed-tools: Read Grep Glob Bash
argument-hint: "<slug> [--cancelled|--deferred|--completed|--awaiting-merge] [--reason \"<text>\"] | --bulk [--yes --<terminal-flag>]"
---

## Task

Close a stale RUN-MANIFEST by flipping its Status to a terminal value atomically via
`manifest-append.sh` (single-writer — never inline edits). Supports slug mode for targeted
closure, bulk mode for sweep over all auto-closeable manifests, and default-flag behavior
for branch-merge-aware auto-detection.

$ARGUMENTS

## Modes

### Slug mode: `/aih-close <slug>`

1. Resolve the manifest: glob `.aihaus/{milestones,features,bugfixes}/*<slug>*/RUN-MANIFEST.md`.
   If zero matches → print error and exit non-zero. If multiple matches → print all paths and
   exit non-zero (ambiguous slug; user must narrow).
2. Read current `Status:` field. If already terminal (`completed`, `deferred`, `cancelled`,
   `awaiting-merge`) → print "Already closed (Status: <value>)" and exit 0 (idempotent).
3. Apply **Default-flag behavior** (FR-34) — see section below.
4. Execute **Mutation path** (FR-35) — see section below.

### Bulk mode: `/aih-close --bulk`

1. Run `bash .aihaus/hooks/manifest-auto-close.sh --dry-run` to enumerate auto-closeable
   manifests. Capture output.
2. Print a markdown table `| slug | branch | last-updated | proposed-status |` of all
   auto-closeable manifests.
3. If no manifests found → print "No auto-closeable manifests found" and exit 0.
4. Apply **--yes discipline** (L4 / FR-33) — see section below.
5. On confirmed proceed: run `bash .aihaus/hooks/manifest-auto-close.sh` (full sweep).
6. Report count of manifests closed.

## Default-flag behavior (FR-34)

When `<slug>` mode is invoked with **no terminal flag** (`--completed`, `--deferred`,
`--cancelled`, `--awaiting-merge` are all absent):

1. Source `pkg/.aihaus/hooks/lib/integration-refs.sh` (or `.aihaus/hooks/lib/integration-refs.sh`
   — prefer installed path if present).
2. Read the `Branch:` field from the manifest.
3. Call `is_branch_merged_into_any "<branch>"` from the helper.
   - **Merged** → default terminal flag is `--completed`; proceed silently (no prompt).
   - **Unmerged** → this is a TRUE-blocker scoping question: ask the user which terminal
     value applies. Present exactly: "Branch <name> is not yet merged. Which terminal status?
     (completed / deferred / cancelled / awaiting-merge)" — this is a single classification
     question, not an option menu (distinct from autonomy-protocol forbidden A/B/C menus).
     Wait for user response before proceeding.

## --yes discipline (L4 / FR-33)

`/aih-close --bulk --yes` WITHOUT an explicit terminal flag → exit non-zero immediately.
Print to stderr exactly:

```
/aih-close: --yes requires explicit terminal flag (--deferred|--completed|--cancelled|--awaiting-merge)
```

`/aih-close --bulk --yes --completed` is the canonical non-interactive auto-close-everything
path. `--yes` with any terminal flag → skip the confirmation prompt and proceed directly to
the `manifest-auto-close.sh` full-sweep invocation.

## Mutation path (FR-35)

All Status writes MUST route through `manifest-append.sh` — never direct file edits.

1. **Status flip:**
   ```bash
   bash .aihaus/hooks/manifest-append.sh \
     --manifest "<resolved-manifest-path>" \
     --field status \
     --payload "<terminal-value>"
   ```
2. **Progress log entry:**
   ```bash
   bash .aihaus/hooks/manifest-append.sh \
     --manifest "<resolved-manifest-path>" \
     --field progress-log \
     --payload "Closed via /aih-close: <terminal-value> — <ISO-8601-timestamp>$([ -n "$REASON" ] && echo " — reason: $REASON")"
   ```
   The timestamp is `date -u +"%Y-%m-%dT%H:%M:%SZ"`. Include `--reason` text verbatim if
   provided.

## Outcome gate C-12

`/aih-close 260428-medico-empty-shifts-telemetry --deferred --reason "Phases 2+3 in M044"`
flips `Status: deferred` atomically. Re-running `/aih-resume` will not surface that slug
(terminal status excludes it from the candidate list). `/aih-close --bulk` prints the
auto-closeable table and waits for confirmation.

## Autonomy

See `_shared/autonomy-protocol.md` — binding rules for planning/threshold/execution phases;
no option menus; no honest checkpoints; no delegated typing. Overrides contradictory prose
above. The single user-prompt in Default-flag behavior (unmerged branch path) is explicitly
permitted as a TRUE-blocker scoping question per autonomy-protocol §TRUE blocker definition.
<!-- See pkg/.aihaus/skills/_shared/enforcement-audit.md for this SKILL's enforcement audit. -->
