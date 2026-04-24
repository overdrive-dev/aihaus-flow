#!/usr/bin/env bash
# git-add-guard-cases/fixture.sh — M017/S08 smoke-test fixture
#
# Asserts git-add-guard.sh PreToolUse behavior:
#   DENY (exit 2) on milestone/* branch:
#     - git add -A
#     - git commit -am "msg"
#   ALLOW (exit 0) on milestone/* branch:
#     - git add explicit-file.txt
#   ALLOW (exit 0) on main branch (off-milestone bypass):
#     - git add -A
#
# Input to git-add-guard.sh: JSON on stdin matching PreToolUse schema.
# {"tool_name":"Bash","tool_input":{"command":"<cmd>"}}
#
# Self-contained: creates a temp git repo, checks out correct branch per test,
# invokes hook with JSON stdin, asserts exit codes. Cleans up.
# Returns: 0 on all-pass, 1 on any failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="${SCRIPT_DIR}/../../../../pkg/.aihaus/hooks/git-add-guard.sh"
HOOK="$(cd "$(dirname "$HOOK")" && pwd)/$(basename "$HOOK")"

if [[ ! -f "$HOOK" ]]; then
  echo "[FAIL] git-add-guard-cases: hook not found: $HOOK" >&2
  exit 1
fi

FAILURES=0
fail() { echo "[FAIL] git-add-guard-cases: $*" >&2; FAILURES=$((FAILURES+1)); }

# ---- Create temp git repo ----------------------------------------------------
TMPDIR_BASE="$(mktemp -d 2>/dev/null || mktemp -d -t aih-gag-fix)"
REPO="${TMPDIR_BASE}/repo"
mkdir -p "$REPO"
git -C "$REPO" init -b main >/dev/null 2>&1
git -C "$REPO" config user.email "smoke@test"
git -C "$REPO" config user.name "Smoke Test"
git -C "$REPO" config commit.gpgsign false 2>/dev/null || true

# Initial commit
touch "$REPO/seed.txt"
git -C "$REPO" add seed.txt
git -C "$REPO" commit -m "initial" >/dev/null 2>&1

# Helper: run hook with a command string, from REPO context, on given branch
# Usage: run_guard <branch> <command> → returns exit code
run_guard() {
  local branch="$1"
  local cmd="$2"
  local payload
  payload="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"${cmd}\"}}"

  (
    cd "$REPO"
    git checkout -B "$branch" >/dev/null 2>&1
    AIHAUS_AUDIT_LOG="${TMPDIR_BASE}/audit.jsonl" \
      printf '%s' "$payload" | bash "$HOOK" 2>/dev/null
  )
  return $?
}

# ---- Case 1: git add -A on milestone branch → deny (exit 2) -----------------
run_guard "milestone/M999-test" "git add -A" 2>/dev/null
case1_rc=$?
if [[ "$case1_rc" -ne 2 ]]; then
  fail "Case 1: 'git add -A' on milestone branch expected exit 2 (deny); got $case1_rc"
fi

# ---- Case 2: git commit -am on milestone branch → deny (exit 2) -------------
run_guard "milestone/M999-test" "git commit -am \"test message\"" 2>/dev/null
case2_rc=$?
if [[ "$case2_rc" -ne 2 ]]; then
  fail "Case 2: 'git commit -am' on milestone branch expected exit 2 (deny); got $case2_rc"
fi

# ---- Case 3: git add explicit-file.txt on milestone branch → allow (exit 0) -
run_guard "milestone/M999-test" "git add explicit-file.txt" 2>/dev/null
case3_rc=$?
if [[ "$case3_rc" -ne 0 ]]; then
  fail "Case 3: 'git add explicit-file.txt' on milestone branch expected exit 0 (allow); got $case3_rc"
fi

# ---- Case 4: git add -A on main branch → allow (exit 0, off-milestone) ------
run_guard "main" "git add -A" 2>/dev/null
case4_rc=$?
if [[ "$case4_rc" -ne 0 ]]; then
  fail "Case 4: 'git add -A' on main branch expected exit 0 (off-milestone bypass); got $case4_rc"
fi

# ---- Cleanup -----------------------------------------------------------------
rm -rf "$TMPDIR_BASE" 2>/dev/null || true

# ---- Report ------------------------------------------------------------------
if [[ "$FAILURES" -eq 0 ]]; then
  echo "[PASS] git-add-guard-cases: deny(add -A, commit -am) + allow(explicit-file, main-bypass) (M017/S08)"
  exit 0
else
  echo "[FAIL] git-add-guard-cases: $FAILURES assertion(s) failed" >&2
  exit 1
fi
