#!/usr/bin/env bash
# reap-execute/fixture.sh — M018/S1 L4 reap 4-axis integration fixture
#
# Replicates the M010-M012 production failure conjunction case:
# locked + path-deleted + mtime-aged all simultaneously.
#
# 4-axis matrix (live/aged × path-present/path-deleted):
#   (a) aged-lock + path-deleted — M010-M012 case; MUST reap via unlock+rm-rf
#   (b) aged-lock + path-present — MUST reap via unlock+remove-force (or rm-rf metadata)
#   (c) live-lock + path-deleted — MUST NOT reap (preserves long-running agent lock)
#   (d) live-lock + path-present — MUST NOT reap
#
# Self-contained: sets up a temp git repo, runs worktree-reap.sh, asserts results.
# Returns: 0 on all-pass, 1 on any failure.
#
# Refs: M018/S1, CHECK C1 + H4 + H5, ADR-M017-B (L4 fallback).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Navigate from tools/fixtures/M017/reap-execute/ up to repo root
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../../" && pwd)"
REAP_HOOK="${REPO_ROOT}/pkg/.aihaus/hooks/worktree-reap.sh"
RECONCILE_HOOK="${REPO_ROOT}/pkg/.aihaus/hooks/worktree-reconcile.sh"

if [ ! -f "${REAP_HOOK}" ]; then
  echo "[FAIL] reap-execute: worktree-reap.sh not found: ${REAP_HOOK}" >&2
  exit 1
fi

if [ ! -f "${RECONCILE_HOOK}" ]; then
  echo "[FAIL] reap-execute: worktree-reconcile.sh not found: ${RECONCILE_HOOK}" >&2
  exit 1
fi

FAILURES=0
fail() { echo "[FAIL] reap-execute: $*" >&2; FAILURES=$((FAILURES + 1)); }

# ---- Create temp workspace ---------------------------------------------------
TMPDIR_BASE="$(mktemp -d 2>/dev/null || mktemp -d -t aih-reap-fix)"
REPO="${TMPDIR_BASE}/repo"

cleanup() {
  # Best-effort cleanup — ignore errors
  rm -rf "${TMPDIR_BASE}" 2>/dev/null || true
}
trap cleanup EXIT

# ---- Init repo ---------------------------------------------------------------
mkdir -p "${REPO}"
git -C "${REPO}" init -b main >/dev/null 2>&1
git -C "${REPO}" config user.email "smoke@test"
git -C "${REPO}" config user.name "Smoke Test"
git -C "${REPO}" config commit.gpgsign false 2>/dev/null || true

# Initial commit (needed for git worktree add to work)
touch "${REPO}/seed.txt"
git -C "${REPO}" add seed.txt
git -C "${REPO}" commit -m "initial" >/dev/null 2>&1

# ---- Create 4 worktrees ------------------------------------------------------
# All worktrees created with git worktree add so git writes correct gitdir files.
WT_A="${TMPDIR_BASE}/wt-a"   # aged-lock + path-deleted (M010-M012 case)
WT_B="${TMPDIR_BASE}/wt-b"   # aged-lock + path-present
WT_C="${TMPDIR_BASE}/wt-c"   # live-lock + path-deleted (must NOT reap)
WT_D="${TMPDIR_BASE}/wt-d"   # live-lock + path-present (must NOT reap)

git -C "${REPO}" worktree add -b wt-a-branch "${WT_A}" >/dev/null 2>&1
git -C "${REPO}" worktree add -b wt-b-branch "${WT_B}" >/dev/null 2>&1
git -C "${REPO}" worktree add -b wt-c-branch "${WT_C}" >/dev/null 2>&1
git -C "${REPO}" worktree add -b wt-d-branch "${WT_D}" >/dev/null 2>&1

# Lock all four worktrees (creates .git/worktrees/<name>/locked sentinel)
git -C "${REPO}" worktree lock "${WT_A}" 2>/dev/null || true
git -C "${REPO}" worktree lock "${WT_B}" 2>/dev/null || true
git -C "${REPO}" worktree lock "${WT_C}" 2>/dev/null || true
git -C "${REPO}" worktree lock "${WT_D}" 2>/dev/null || true

# Verify all 4 were locked (locked sentinel files exist)
GIT_DIR="${REPO}/.git"
WORKTREES_DIR="${GIT_DIR}/worktrees"

# ---- Find lock sentinel files ------------------------------------------------
# Match by branch name in the HEAD file inside each worktrees entry
LOCK_A="" LOCK_B="" LOCK_C="" LOCK_D=""
WT_REG_A="" WT_REG_B="" WT_REG_C="" WT_REG_D=""

for wt_entry in "${WORKTREES_DIR}"/*/; do
  [ -d "${wt_entry}" ] || continue
  _lock="${wt_entry}locked"
  [ -f "${_lock}" ] || continue
  _head_file="${wt_entry}HEAD"
  [ -f "${_head_file}" ] || continue
  _head_content="$(cat "${_head_file}" 2>/dev/null || echo "")"
  case "${_head_content}" in
    *wt-a-branch*) LOCK_A="${_lock}"; WT_REG_A="${wt_entry}" ;;
    *wt-b-branch*) LOCK_B="${_lock}"; WT_REG_B="${wt_entry}" ;;
    *wt-c-branch*) LOCK_C="${_lock}"; WT_REG_C="${wt_entry}" ;;
    *wt-d-branch*) LOCK_D="${_lock}"; WT_REG_D="${wt_entry}" ;;
  esac
done

if [ -z "${LOCK_A}" ]; then fail "could not locate lock sentinel for wt-a (branch wt-a-branch)"; fi
if [ -z "${LOCK_B}" ]; then fail "could not locate lock sentinel for wt-b (branch wt-b-branch)"; fi
if [ -z "${LOCK_C}" ]; then fail "could not locate lock sentinel for wt-c (branch wt-c-branch)"; fi
if [ -z "${LOCK_D}" ]; then fail "could not locate lock sentinel for wt-d (branch wt-d-branch)"; fi

if [ "${FAILURES}" -gt 0 ]; then
  echo "[FAIL] reap-execute: cannot locate lock sentinels — aborting" >&2
  exit 1
fi

# ---- Age the lock sentinels for (a) and (b) ----------------------------------
# These should be reaped: lock age must exceed --age-days 1 (1 day = 86400s).
# Use 2-days-ago to be safely above the threshold.
_age_sentinel() {
  local sentinel="$1"
  # GNU touch -d
  if touch -d "2 days ago" "${sentinel}" 2>/dev/null; then return 0; fi
  # BSD touch -v (macOS)
  local ts_2d_ago
  ts_2d_ago="$(date -v-2d '+%Y%m%d%H%M.%S' 2>/dev/null || echo "")"
  if [ -n "${ts_2d_ago}" ] && touch -t "${ts_2d_ago}" "${sentinel}" 2>/dev/null; then return 0; fi
  # POSIX date with -d (some shells)
  ts_2d_ago="$(date -d '2 days ago' '+%Y%m%d%H%M.%S' 2>/dev/null || echo "")"
  if [ -n "${ts_2d_ago}" ] && touch -t "${ts_2d_ago}" "${sentinel}" 2>/dev/null; then return 0; fi
  # Perl fallback
  if perl -e "my \$t=time()-2*86400;utime(\$t,\$t,'${sentinel}');" 2>/dev/null; then return 0; fi
  echo "[WARN] reap-execute: could not age sentinel ${sentinel} — test may be unreliable" >&2
  return 1
}

_age_sentinel "${LOCK_A}" || fail "could not age lock sentinel for wt-a"
_age_sentinel "${LOCK_B}" || fail "could not age lock sentinel for wt-b"
# Sentinels for (c) and (d) remain fresh (just-created) — live locks, must NOT reap

# Delete worktree dirs for (a) and (c): path-deleted cases
# Use rm -rf (git worktree remove requires unlock first; we want to simulate crash/force-delete)
rm -rf "${WT_A}" 2>/dev/null || true
rm -rf "${WT_C}" 2>/dev/null || true

# Verify dir states
if [ -d "${WT_A}" ]; then fail "setup: wt-a dir should be deleted but still exists"; fi
if [ -d "${WT_B}" ]; then : ; else fail "setup: wt-b dir should exist but is missing"; fi
if [ -d "${WT_C}" ]; then fail "setup: wt-c dir should be deleted but still exists"; fi
if [ -d "${WT_D}" ]; then : ; else fail "setup: wt-d dir should exist but is missing"; fi

if [ "${FAILURES}" -gt 0 ]; then
  echo "[FAIL] reap-execute: fixture setup failed — aborting" >&2
  exit 1
fi

# ---- Capture pre-run worktree registrations (from .git/worktrees/) -----------
# Use registration dirs to avoid path-format mismatches (Unix vs Windows style in git list).
PRE_REG_A=0; PRE_REG_B=0; PRE_REG_C=0; PRE_REG_D=0
[ -d "${WT_REG_A}" ] && PRE_REG_A=1
[ -d "${WT_REG_B}" ] && PRE_REG_B=1
[ -d "${WT_REG_C}" ] && PRE_REG_C=1
[ -d "${WT_REG_D}" ] && PRE_REG_D=1

if [ "${PRE_REG_A}" -eq 0 ]; then fail "pre-run: wt-a registration missing from .git/worktrees/"; fi
if [ "${PRE_REG_B}" -eq 0 ]; then fail "pre-run: wt-b registration missing from .git/worktrees/"; fi
if [ "${PRE_REG_C}" -eq 0 ]; then fail "pre-run: wt-c registration missing from .git/worktrees/"; fi
if [ "${PRE_REG_D}" -eq 0 ]; then fail "pre-run: wt-d registration missing from .git/worktrees/"; fi

if [ "${FAILURES}" -gt 0 ]; then
  echo "[FAIL] reap-execute: pre-run registration check failed — aborting" >&2
  exit 1
fi

echo "[SETUP] 4-axis fixture ready:"
echo "  (a) aged-lock + path-deleted: registration=${WT_REG_A}, dir_deleted"
echo "  (b) aged-lock + path-present: registration=${WT_REG_B}, dir_exists"
echo "  (c) live-lock + path-deleted: registration=${WT_REG_C}, dir_deleted"
echo "  (d) live-lock + path-present: registration=${WT_REG_D}, dir_exists"

# ---- Run worktree-reap.sh --confirm-reap --age-days 1 ------------------------
REAP_STDERR="${TMPDIR_BASE}/reap-stderr.txt"
REAP_STDOUT="${TMPDIR_BASE}/reap-stdout.txt"

reap_rc=0
(
  cd "${REPO}"
  AIHAUS_RECONCILE_SH="${RECONCILE_HOOK}" \
  AIHAUS_AUDIT_LOG="${TMPDIR_BASE}/audit.jsonl" \
    bash "${REAP_HOOK}" --confirm-reap --age-days 1 \
    >"${REAP_STDOUT}" 2>"${REAP_STDERR}"
) || reap_rc=$?

if [ "${reap_rc}" -ne 0 ]; then
  fail "worktree-reap.sh exited with non-zero code: ${reap_rc}"
fi

REAP_STDERR_CONTENT="$(cat "${REAP_STDERR}" 2>/dev/null || true)"
REAP_STDOUT_CONTENT="$(cat "${REAP_STDOUT}" 2>/dev/null || true)"
COMBINED_OUTPUT="${REAP_STDERR_CONTENT}
${REAP_STDOUT_CONTENT}"

# ---- Post-run: check registration dirs directly in .git/worktrees/ -----------
# This avoids Windows path-format mismatch in git worktree list output.

POST_REG_A=0; POST_REG_B=0; POST_REG_C=0; POST_REG_D=0
[ -d "${WT_REG_A}" ] && POST_REG_A=1
[ -d "${WT_REG_B}" ] && POST_REG_B=1
[ -d "${WT_REG_C}" ] && POST_REG_C=1
[ -d "${WT_REG_D}" ] && POST_REG_D=1

# ---- Assert (a) aged-lock + path-deleted: GONE from .git/worktrees/ ----------
if [ "${POST_REG_A}" -eq 0 ]; then
  echo "[CHECK] (a) aged-lock + path-deleted: wt-a registration GONE — PASS"
else
  fail "(a) aged-lock + path-deleted: wt-a registration still present in .git/worktrees/ (M010-M012 production case — rm-rf cleanup required)"
fi

# ---- Assert (b) aged-lock + path-present: GONE from .git/worktrees/ ----------
if [ "${POST_REG_B}" -eq 0 ]; then
  echo "[CHECK] (b) aged-lock + path-present: wt-b registration GONE — PASS"
else
  fail "(b) aged-lock + path-present: wt-b registration still present in .git/worktrees/ after reap"
fi

# ---- Assert (c) live-lock + path-deleted: PRESERVED in .git/worktrees/ ------
if [ "${POST_REG_C}" -eq 1 ]; then
  echo "[CHECK] (c) live-lock + path-deleted: wt-c registration preserved — PASS"
else
  fail "(c) live-lock + path-deleted: wt-c was incorrectly reaped (must preserve long-running agent lock)"
fi

# ---- Assert (d) live-lock + path-present: PRESERVED in .git/worktrees/ ------
if [ "${POST_REG_D}" -eq 1 ]; then
  echo "[CHECK] (d) live-lock + path-present: wt-d registration preserved — PASS"
else
  fail "(d) live-lock + path-present: wt-d was incorrectly reaped (must preserve live lock)"
fi

# ---- Assert [REAP-CANDIDATE] emitted for path-empty entry --------------------
# On Windows, path resolution (cd + pwd -P) fails for absolute Windows paths in gitdir,
# so both aged-lock cases emit [REAP-CANDIDATE] rather than attempting git worktree remove.
if printf '%s\n' "${COMBINED_OUTPUT}" | grep -qE '\[REAP-CANDIDATE\]'; then
  echo "[CHECK] [REAP-CANDIDATE] emitted for path-empty or path-unresolvable entry — PASS"
else
  fail "[REAP-CANDIDATE] marker not found in output (required for path-empty entries per S1 ACs)"
  echo "[DIAG] reap stderr:" >&2; printf '%s\n' "${REAP_STDERR_CONTENT}" >&2
  echo "[DIAG] reap stdout:" >&2; printf '%s\n' "${REAP_STDOUT_CONTENT}" >&2
fi

# ---- Assert [REAPED] NOT claimed for wt-a (the path-deleted case) ------------
# [REAPED] is only valid for verified-removed entries (where the path existed on disk).
# For path-empty entries, only [REAP-CANDIDATE] should be emitted (never [REAPED]).
if printf '%s\n' "${COMBINED_OUTPUT}" | grep -F '[REAPED]' | grep -qF "$(basename "${WT_REG_A}")"; then
  fail "[REAPED] emitted for wt-a registration (path-empty case); only [REAP-CANDIDATE] allowed"
else
  echo "[CHECK] [REAPED] not claimed for path-empty wt-a registration — PASS"
fi

# ---- Report ------------------------------------------------------------------
echo ""
if [ "${FAILURES}" -eq 0 ]; then
  echo "[PASS] reap-execute: all 4-axis L4 fixture checks passed (M018/S1 — CHECK C1+H4+H5)"
  exit 0
else
  echo "[FAIL] reap-execute: ${FAILURES} assertion(s) failed" >&2
  exit 1
fi
