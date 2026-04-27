#!/usr/bin/env bash
# F260427/branch-switch-warn/fixture.sh — branch-switch soft-warn behavior fixture
#
# Asserts bash-guard.sh ADR-260427-B behavior (7 cases):
#   1. git checkout <ref> while a running manifest exists → warn to stderr +
#      audit row in branch-switch-warn.jsonl (exit 0, never blocks).
#   2. git checkout -- <file> (file-mode) → no warn (excluded).
#   3. git checkout -b <new-branch> → no warn (creating, not switching).
#   4. AIHAUS_BRANCH_SWITCH_GUARD=0 → opt-out, no warn even with running manifest.
#   5. git switch --detach <ref> → no warn (excluded).
#   6. git switch -c <new-branch> → no warn (creating, not switching).
#   7. git checkout - (previous-branch shortcut) → no warn (excluded).
#
# Self-contained: temp git repo + synthetic running manifest, invokes hook
# with JSON stdin, asserts stderr content + audit row presence/absence.
# Returns 0 on all-pass, 1 on any failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="${SCRIPT_DIR}/../../../../pkg/.aihaus/hooks/bash-guard.sh"
HOOK="$(cd "$(dirname "$HOOK")" && pwd)/$(basename "$HOOK")"

if [[ ! -f "$HOOK" ]]; then
  echo "[FAIL] branch-switch-warn: hook not found: $HOOK" >&2
  exit 1
fi

FAILURES=0
fail() { echo "[FAIL] branch-switch-warn: $*" >&2; FAILURES=$((FAILURES+1)); }
pass() { :; }

# ---- temp repo ---------------------------------------------------------------
TMPDIR_BASE="$(mktemp -d 2>/dev/null || mktemp -d -t aih-bsw-fix)"
REPO="${TMPDIR_BASE}/repo"
mkdir -p "$REPO"
git -C "$REPO" init -b main >/dev/null 2>&1
git -C "$REPO" config user.email "smoke@test"
git -C "$REPO" config user.name "Smoke Test"
git -C "$REPO" config commit.gpgsign false 2>/dev/null || true

touch "$REPO/seed.txt"
git -C "$REPO" add seed.txt
git -C "$REPO" commit -m "initial" >/dev/null 2>&1
git -C "$REPO" checkout -qb feature/test-target
echo y > "$REPO/extra.txt"
git -C "$REPO" add extra.txt
git -C "$REPO" commit -m "extra" >/dev/null 2>&1
git -C "$REPO" checkout -q main

# Plant a running feature manifest pointing to feature/test-target
mkdir -p "$REPO/.aihaus/features/test"
cat > "$REPO/.aihaus/features/test/RUN-MANIFEST.md" <<'EOF'
## Metadata
feature: test
branch: feature/test-target
status: running
schema: v3

## Invoke stack

## Story Records
EOF

# Helper: run hook from REPO context with a command string. Captures stderr +
# audit log path. Returns: <exit-code>|<stderr-bytes>|<audit-row-count>
AUDIT_LOG="${TMPDIR_BASE}/branch-switch-warn.jsonl"
rm -f "$AUDIT_LOG" 2>/dev/null

run_guard() {
  local cmd="$1" optout="${2:-}"
  local payload="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"${cmd}\"}}"
  local stderr_file="${TMPDIR_BASE}/stderr.$$"
  rm -f "$stderr_file"
  (
    cd "$REPO"
    export AIHAUS_BRANCH_SWITCH_LOG="$AUDIT_LOG"
    if [ -n "$optout" ]; then
      export AIHAUS_BRANCH_SWITCH_GUARD=0
    fi
    printf '%s' "$payload" | bash "$HOOK" 2>"$stderr_file"
  )
  local rc=$?
  local err
  err=$(cat "$stderr_file" 2>/dev/null || echo "")
  rm -f "$stderr_file"
  printf '%s|%s\n' "$rc" "$err"
}

audit_count() {
  [ -f "$AUDIT_LOG" ] || { echo 0; return; }
  wc -l < "$AUDIT_LOG" | tr -d ' '
}

# ---- Test 1: branch-switch with running manifest → warn + audit row --------
rm -f "$AUDIT_LOG"
out1=$(run_guard "git checkout feature/test-target")
rc1="${out1%%|*}"
err1="${out1#*|}"
[ "$rc1" = "0" ] || fail "T1 expected exit 0, got $rc1"
echo "$err1" | grep -q "branch switch detected" || fail "T1 expected stderr warn"
[ "$(audit_count)" = "1" ] || fail "T1 expected 1 audit row, got $(audit_count)"

# ---- Test 2: file-mode checkout → no warn, no audit row -------------------
rm -f "$AUDIT_LOG"
out2=$(run_guard "git checkout -- seed.txt")
rc2="${out2%%|*}"
err2="${out2#*|}"
[ "$rc2" = "0" ] || fail "T2 expected exit 0, got $rc2"
echo "$err2" | grep -q "branch switch detected" && fail "T2 should not warn for file-mode"
[ "$(audit_count)" = "0" ] || fail "T2 expected 0 audit rows, got $(audit_count)"

# ---- Test 3: branch creation (-b) → no warn -------------------------------
rm -f "$AUDIT_LOG"
out3=$(run_guard "git checkout -b feature/new-branch")
rc3="${out3%%|*}"
err3="${out3#*|}"
[ "$rc3" = "0" ] || fail "T3 expected exit 0, got $rc3"
echo "$err3" | grep -q "branch switch detected" && fail "T3 should not warn for -b"
[ "$(audit_count)" = "0" ] || fail "T3 expected 0 audit rows, got $(audit_count)"

# ---- Test 4: opt-out via env var → no warn -------------------------------
rm -f "$AUDIT_LOG"
out4=$(run_guard "git checkout feature/test-target" "optout")
rc4="${out4%%|*}"
err4="${out4#*|}"
[ "$rc4" = "0" ] || fail "T4 expected exit 0, got $rc4"
echo "$err4" | grep -q "branch switch detected" && fail "T4 should not warn with opt-out"
[ "$(audit_count)" = "0" ] || fail "T4 expected 0 audit rows with opt-out, got $(audit_count)"

# ---- Test 5: --detach (allowed by ADR-260427-B) → no warn ----------------
rm -f "$AUDIT_LOG"
out5=$(run_guard "git switch --detach feature/test-target")
rc5="${out5%%|*}"
err5="${out5#*|}"
[ "$rc5" = "0" ] || fail "T5 expected exit 0, got $rc5"
echo "$err5" | grep -q "branch switch detected" && fail "T5 should not warn for --detach"
[ "$(audit_count)" = "0" ] || fail "T5 expected 0 audit rows, got $(audit_count)"

# ---- Test 6: switch -c new-branch (creating, not switching) → no warn ----
rm -f "$AUDIT_LOG"
out6=$(run_guard "git switch -c feature/another-new")
rc6="${out6%%|*}"
err6="${out6#*|}"
[ "$rc6" = "0" ] || fail "T6 expected exit 0, got $rc6"
echo "$err6" | grep -q "branch switch detected" && fail "T6 should not warn for switch -c"
[ "$(audit_count)" = "0" ] || fail "T6 expected 0 audit rows, got $(audit_count)"

# ---- Test 7: previous-branch shortcut (-) → no warn ----------------------
rm -f "$AUDIT_LOG"
out7=$(run_guard "git checkout -")
rc7="${out7%%|*}"
err7="${out7#*|}"
[ "$rc7" = "0" ] || fail "T7 expected exit 0, got $rc7"
echo "$err7" | grep -q "branch switch detected" && fail "T7 should not warn for -"
[ "$(audit_count)" = "0" ] || fail "T7 expected 0 audit rows, got $(audit_count)"

# ---- cleanup -----------------------------------------------------------------
rm -rf "$TMPDIR_BASE" 2>/dev/null || true

if [ "$FAILURES" -eq 0 ]; then
  exit 0
else
  exit 1
fi
