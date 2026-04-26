<!-- BOOTSTRAP-ONLY: This file is read at completion-protocol Step 6 to populate per-milestone MILESTONE-SUMMARY.md. Do NOT promote retrospectives here.
     The single canonical promotion target is the per-milestone execution/MILESTONE-SUMMARY.md (gitignored; local).
     All completion-protocol Step 6 writes go to .aihaus/milestones/<slug>/execution/MILESTONE-SUMMARY.md — never to this template. -->

# [Milestone title goes here]

**Branch:** `milestone/M0XX-<slug>`
**Version:** vX.Y.Z
**Completed:** YYYY-MM-DD

## Goal delivered

<!-- One paragraph describing what problem this milestone solved and why it matters to users.
     Focus on outcomes, not tasks. Example: "Closed the M017 dogfood regression loop: worktree-reap
     locked-entry handling now survives the Windows/OneDrive path-format mismatch identified in K-001." -->

_[Describe the goal that was delivered and the user-visible outcome.]_

## Stories shipped

<!-- Required table for generate-release-notes.sh to extract user-facing story titles.
     The canonical section header MUST be exactly: ## Stories Completed
     (generate-release-notes.sh accepts '## Commits shipped' as a non-canonical fallback with WARN;
     that alternative will be removed in M020.) -->

## Stories Completed

| # | Story | Status | Key files | Commit |
|---|-------|--------|-----------|--------|
| 1 | [Story title — appears verbatim in release notes] | complete | `path/to/file` | `abc1234` |

<!-- Add one row per completed story. Stories mentioning smoke-test, purity-check, or dogfood-brainstorm
     are automatically filtered from user-facing release notes by generate-release-notes.sh. -->

## Artifacts

<!-- List significant new files, templates, or configuration added by this milestone.
     Helps future milestones know what was introduced. -->

- `path/to/new-file.md` — what it does
- `path/to/another-file.sh` — what it does

## Validation gates

<!-- List the smoke-test and purity-check results that confirmed this milestone is ship-ready.
     Include the check count and any notable new checks added. -->

- `bash tools/smoke-test.sh` — X/X PASS
- `bash tools/purity-check.sh` — clean

## Side effects / cleanup

<!-- Anything this milestone changes that future milestones or adopters need to be aware of:
     renamed files, removed commands, deprecated behaviors, migration notes. -->

_[List any breaking changes, deprecations, or migration steps. If none, write "None."]_
