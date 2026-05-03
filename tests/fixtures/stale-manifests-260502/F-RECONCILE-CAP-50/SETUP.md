# Setup — F-RECONCILE-CAP-50

**Fixture type:** Manual integration test / future harness placeholder
**Boundary tested:** 51 commits ahead of integration ref → `[INTEGRATION-LAG]` path

## What this fixture tests

When a worktree has more commits ahead of the closest integration ref than
`AIHAUS_RECONCILE_CAP` (default 50), `worktree-reconcile.sh` must emit exactly
one `[INTEGRATION-LAG]` line and zero `[CATEGORY B]` recipe blocks.

This fixture documents the boundary at cap+1 (51 commits).

## How to construct the test git state

A future `tools/test-reconcile.sh` harness should source this setup or replicate
the following steps to build a temporary git repo:

```bash
#!/usr/bin/env bash
# SETUP.sh — construct a stub git repo with 51 commits ahead of a stub integration ref.
set -euo pipefail

TMP_REPO="$(mktemp -d)"
git -C "$TMP_REPO" init
git -C "$TMP_REPO" commit --allow-empty -m "initial"

# Create stub origin/staging (the integration ref) at the initial commit
git -C "$TMP_REPO" branch -f refs/remotes/origin/staging HEAD

# Create a worktree branch with exactly 51 commits
git -C "$TMP_REPO" checkout -b feature/cap-boundary
for i in $(seq 1 51); do
  git -C "$TMP_REPO" commit --allow-empty -m "commit $i"
done

# Add a worktree pointing at feature/cap-boundary
WK="$(mktemp -d)"
git -C "$TMP_REPO" worktree add "$WK" feature/cap-boundary

# Now run worktree-reconcile.sh --dry-run from $TMP_REPO.
# Expected stdout: one [INTEGRATION-LAG] line, no [CATEGORY B] blocks.
bash pkg/.aihaus/hooks/worktree-reconcile.sh --dry-run
```

## Verification note

`tools/test-auto-close.sh` does not exercise reconcile fixtures — it is focused on
`manifest-auto-close.sh`. These fixtures (F-RECONCILE-CAP-49 and F-RECONCILE-CAP-50)
are for manual verification today and for a future `tools/test-reconcile.sh` harness.

## Expected output

See EXPECTED.md.
