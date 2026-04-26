#!/usr/bin/env bash
# merge-back-refusal/fixture.sh — M017/S08 smoke-test fixture
#
# Scenario: 2026-04-12 incident replay.
# A worktree has one Owned File (expected.sh) BUT also stages an extra file
# (unexpected.sh). merge-back.sh must refuse with:
#   exit 3
#   stderr: MERGE_BACK_REFUSED story=S99 reason=unexpected-files
#           expected=<path> actual=<path1>,<path2> worktree=<path>
#
# Self-contained: sets up a temp git repo, runs the hook, asserts results, cleans up.
# Returns: 0 on all-pass, 1 on any failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="${SCRIPT_DIR}/../../../../pkg/.aihaus/hooks/merge-back.sh"

# Resolve HOOK absolute path (removes ../ sequences)
HOOK="$(cd "$(dirname "$HOOK")" && pwd)/$(basename "$HOOK")"

if [[ ! -f "$HOOK" ]]; then
  echo "[FAIL] merge-back-refusal: hook not found: $HOOK" >&2
  exit 1
fi

FAILURES=0
fail() { echo "[FAIL] merge-back-refusal: $*" >&2; FAILURES=$((FAILURES+1)); }

# ---- Create temp workspace ---------------------------------------------------
TMPDIR_BASE="$(mktemp -d 2>/dev/null || mktemp -d -t aih-mb-fix)"

# Main repo (simulates milestone branch in real repo)
REPO="${TMPDIR_BASE}/repo"
mkdir -p "$REPO"
git -C "$REPO" init -b milestone/S99-test >/dev/null 2>&1
git -C "$REPO" config user.email "smoke@test"
git -C "$REPO" config user.name "Smoke Test"
git -C "$REPO" config commit.gpgsign false 2>/dev/null || true

# Initial commit to establish HEAD (needed for git diff --cached to work)
touch "$REPO/seed.txt"
git -C "$REPO" add seed.txt
git -C "$REPO" commit -m "initial" >/dev/null 2>&1

# ---- Build milestone dir with story file ------------------------------------
MILESTONE_DIR="${TMPDIR_BASE}/milestones/M999-test"
STORIES_DIR="${MILESTONE_DIR}/stories"
mkdir -p "$STORIES_DIR"

MANIFEST="${MILESTONE_DIR}/RUN-MANIFEST.md"
cat > "$MANIFEST" <<'MANIFEST_EOF'
## Metadata
milestone: M999-test
branch: milestone/S99-test
started: 2026-04-24T00:00:00Z
schema: v3
phase: execute-stories
status: running
last_updated: 2026-04-24T00:00:00Z

## Invoke stack

## Story Records
story_id|status|started_at|commit_sha|verified|notes
S99|running|2026-04-24T00:01:00Z|||

## Checkpoints
| ts | story | agent | substep | event | result | sha |
MANIFEST_EOF

# Story file with ONE owned file: expected.sh
cat > "$STORIES_DIR/S99.md" <<'STORY_EOF'
# [S99] — Test story for merge-back refusal fixture

## Owned Files

- `expected.sh` — the sole owned file

## Acceptance Criteria

- [ ] Test passes
STORY_EOF

# ---- Create the worktree with TWO files -------------------------------------
# expected.sh (owned) + unexpected.sh (NOT owned)
WORKTREE="${TMPDIR_BASE}/worktree"
mkdir -p "$WORKTREE"

# Create both files in a worktree dir (not a git worktree, just a directory)
# merge-back.sh copies files from worktree dir, then does git add per owned list
# The refusal triggers during the staged == expected check after git add loop

# Actually merge-back.sh requires git context. Let's set up the repo correctly:
# merge-back.sh stages files in the CWD (main repo). The worktree is the source dir.

echo "#!/usr/bin/env bash" > "$WORKTREE/expected.sh"
echo "#!/usr/bin/env bash" > "$WORKTREE/unexpected.sh"

# ---- Set up the main repo to have an extra staged file ----------------------
# merge-back.sh will:
#   1. cp expected.sh from worktree → main repo
#   2. git add expected.sh
#   3. check git diff --cached --name-only == Owned list
#
# To trigger unexpected-files refusal, we need unexpected.sh ALREADY staged
# before merge-back.sh runs. This simulates a prior git add that slipped through.
cp "$WORKTREE/unexpected.sh" "$REPO/unexpected.sh"
git -C "$REPO" add unexpected.sh

# ---- Run merge-back.sh -------------------------------------------------------
MERGE_BACK_STDERR="${TMPDIR_BASE}/stderr.txt"

# Opt out of manifest-append side effects (no live hooks setup)
# Run from the REPO dir so git operations work correctly
merge_back_rc=0
(
  cd "$REPO"
  # Disable audit writes by pointing to a throwaway log
  AIHAUS_AUDIT_LOG="${TMPDIR_BASE}/audit.jsonl" \
    bash "$HOOK" \
    --story S99 \
    --manifest "$MANIFEST" \
    --worktree "$WORKTREE" \
    2>"$MERGE_BACK_STDERR"
) || merge_back_rc=$?

# ---- Assert exit code == 3 ---------------------------------------------------
if [[ "$merge_back_rc" -ne 3 ]]; then
  fail "expected exit code 3 (unexpected-files refusal); got $merge_back_rc"
fi

# ---- Assert stderr grammar ---------------------------------------------------
STDERR_CONTENT=""
if [[ -f "$MERGE_BACK_STDERR" ]]; then
  STDERR_CONTENT="$(cat "$MERGE_BACK_STDERR")"
fi

if ! printf '%s\n' "$STDERR_CONTENT" | grep -q 'MERGE_BACK_REFUSED'; then
  fail "stderr missing 'MERGE_BACK_REFUSED' token"
fi

if ! printf '%s\n' "$STDERR_CONTENT" | grep -qE 'story=S99'; then
  fail "stderr missing 'story=S99' field"
fi

if ! printf '%s\n' "$STDERR_CONTENT" | grep -qE 'reason=unexpected-files'; then
  fail "stderr missing 'reason=unexpected-files' field"
fi

if ! printf '%s\n' "$STDERR_CONTENT" | grep -qE 'expected='; then
  fail "stderr missing 'expected=' field"
fi

if ! printf '%s\n' "$STDERR_CONTENT" | grep -qE 'actual='; then
  fail "stderr missing 'actual=' field"
fi

if ! printf '%s\n' "$STDERR_CONTENT" | grep -qE 'worktree='; then
  fail "stderr missing 'worktree=' field"
fi

# ---- Cleanup -----------------------------------------------------------------
rm -rf "$TMPDIR_BASE" 2>/dev/null || true

# ---- Report ------------------------------------------------------------------
if [[ "$FAILURES" -eq 0 ]]; then
  echo "[PASS] merge-back-refusal: exit=3 + MERGE_BACK_REFUSED grammar with all 5 fields (M017/S08)"
  exit 0
else
  echo "[FAIL] merge-back-refusal: $FAILURES assertion(s) failed" >&2
  exit 1
fi
