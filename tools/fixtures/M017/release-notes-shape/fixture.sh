#!/usr/bin/env bash
# release-notes-shape/fixture.sh — M018/S4 shape validation for generate-release-notes.sh
#
# Validates dual-path + dual-section tolerance introduced in M018/S4 (CHECK H1 + H2):
#   - default mode: accepts non-canonical path/section with WARN to stderr, exits 0
#   - --strict mode: converts WARN to exit 1
#
# 3 scenarios:
#   canonical:              execution/MILESTONE-SUMMARY.md + ## Stories Completed
#                           -> default exits 0 no WARN; --strict exits 0
#   non-canonical-path:     root MILESTONE-SUMMARY.md + ## Stories Completed
#                           -> default exits 0 with WARN; --strict exits 1
#   non-canonical-section:  execution/MILESTONE-SUMMARY.md + ## Commits shipped
#                           -> default exits 0 with WARN; --strict exits 1
#
# Self-contained: temp git repo, cleanup on exit.
# Package-relative: derives absolute paths from script location (CHECK H1).
# Isolation strategy: the real generator computes REPO_ROOT from SCRIPT_DIR.
# We create a patched copy of the generator inside the temp repo so that
# REPO_ROOT resolves to the temp repo. No exec-delegation needed.
#
# Returns: 0 on all-pass, 1 on any failure.
#
# Refs: M018/S4, CHECK C3 (do not touch smoke-test.sh), CHECK H1 + H2.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Navigate from tools/fixtures/M017/release-notes-shape/ up to repo root
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../../" && pwd)"
REAL_GENERATOR="${REPO_ROOT}/tools/generate-release-notes.sh"

if [ ! -f "${REAL_GENERATOR}" ]; then
  echo "[FAIL] release-notes-shape: generator not found: ${REAL_GENERATOR}" >&2
  exit 1
fi

FAILURES=0
fail() { echo "[FAIL] release-notes-shape: $*" >&2; FAILURES=$((FAILURES + 1)); }
pass() { echo "[PASS] release-notes-shape: $*"; }

# ---- Create temp workspace ---------------------------------------------------
TMPDIR_BASE="$(mktemp -d 2>/dev/null || mktemp -d -t aih-rn-shape)"

cleanup() {
  rm -rf "${TMPDIR_BASE}" 2>/dev/null || true
}
trap cleanup EXIT

# ---- Init a bare git repo (needed for merge-base resolution) -----------------
FAKE_REPO="${TMPDIR_BASE}/repo"
mkdir -p "${FAKE_REPO}"
git -C "${FAKE_REPO}" init -b main >/dev/null 2>&1
git -C "${FAKE_REPO}" config user.email "fixture@test"
git -C "${FAKE_REPO}" config user.name "Fixture Test"
git -C "${FAKE_REPO}" config commit.gpgsign false 2>/dev/null || true

# Initial commit on main
mkdir -p "${FAKE_REPO}/seed"
touch "${FAKE_REPO}/seed/init.txt"
git -C "${FAKE_REPO}" add seed/init.txt
git -C "${FAKE_REPO}" commit -m "initial" >/dev/null 2>&1

# Create a milestone branch with one user-facing commit
git -C "${FAKE_REPO}" checkout -b "milestone/M999-test-milestone" >/dev/null 2>&1
mkdir -p "${FAKE_REPO}/pkg"
touch "${FAKE_REPO}/pkg/feature.md"
git -C "${FAKE_REPO}" add pkg/feature.md
git -C "${FAKE_REPO}" commit -m "feat: add feature for M999" >/dev/null 2>&1

BRANCH_SHA="$(git -C "${FAKE_REPO}" rev-parse --short HEAD)"

# ---- Milestone dir scaffold --------------------------------------------------
MILESTONE_DIR="${FAKE_REPO}/.aihaus/milestones/M999-test-milestone"
mkdir -p "${MILESTONE_DIR}/execution"
mkdir -p "${MILESTONE_DIR}/stories"

# ---- Create a patched copy of the generator inside the fake repo -------------
# The generator computes REPO_ROOT as one level above SCRIPT_DIR.
# By placing it at fake_repo/tools/generate-release-notes.sh, REPO_ROOT = fake_repo.
mkdir -p "${FAKE_REPO}/tools"
# Copy the real generator verbatim — SCRIPT_DIR is $0's directory so it resolves correctly
cp "${REAL_GENERATOR}" "${FAKE_REPO}/tools/generate-release-notes.sh"
PATCHED_GENERATOR="${FAKE_REPO}/tools/generate-release-notes.sh"

# Verify patched copy syntax
if ! bash -n "${PATCHED_GENERATOR}" 2>/dev/null; then
  fail "patched generator copy failed bash -n syntax check"
  exit 1
fi

# Also need VERSION file so generator doesn't fail reading it
mkdir -p "${FAKE_REPO}/pkg"
echo "9.99.0" > "${FAKE_REPO}/pkg/VERSION"

# ---- Helper: build a minimal MILESTONE-SUMMARY.md body ----------------------
# $1 = section header ("## Stories Completed" or "## Commits shipped")
# $2 = branch short sha
make_summary_body() {
  local section_header="$1"
  local branch_sha="$2"
  printf '%s\n' \
    "# M999 Test Milestone" \
    "" \
    "**Branch:** \`milestone/M999-test-milestone\`" \
    "**Version:** v9.99.0" \
    "**Completed:** 2026-04-26" \
    "" \
    "## Goal delivered" \
    "" \
    "Test fixture milestone for shape validation." \
    "" \
    "${section_header}" \
    "" \
    "| # | Story | Status | Key files | Commit |" \
    "|---|-------|--------|-----------|--------|" \
    "| 1 | Add feature for M999 | complete | \`pkg/feature.md\` | \`${branch_sha}\` |" \
    "" \
    "## Artifacts" \
    "" \
    "- \`pkg/feature.md\` — new feature" \
    "" \
    "## Validation gates" \
    "" \
    "- \`bash tools/smoke-test.sh\` — 52/52 PASS" \
    "" \
    "## Side effects / cleanup" \
    "" \
    "None."
}

# ---- Scenario 1: canonical --------------------------------------------------
# execution/MILESTONE-SUMMARY.md + ## Stories Completed -> default 0/no-WARN; strict 0
echo "[SCENARIO] canonical: execution/MILESTONE-SUMMARY.md + '## Stories Completed'"

rm -f "${MILESTONE_DIR}/MILESTONE-SUMMARY.md" 2>/dev/null || true
rm -f "${MILESTONE_DIR}/execution/MILESTONE-SUMMARY.md" 2>/dev/null || true

make_summary_body "## Stories Completed" "${BRANCH_SHA}" \
  > "${MILESTONE_DIR}/execution/MILESTONE-SUMMARY.md"

stderr_canonical="${TMPDIR_BASE}/stderr-canonical.txt"
rc_canonical_default=0
bash "${PATCHED_GENERATOR}" M999 >/dev/null 2>"${stderr_canonical}" || rc_canonical_default=$?

if [ "${rc_canonical_default}" -ne 0 ]; then
  fail "canonical: default mode exited ${rc_canonical_default} (expected 0)"
  echo "  stderr:" >&2; cat "${stderr_canonical}" >&2
else
  pass "canonical: default mode exited 0"
fi

if grep -q "WARN:" "${stderr_canonical}" 2>/dev/null; then
  fail "canonical: default mode emitted unexpected WARN to stderr"
  echo "  stderr was:" >&2; cat "${stderr_canonical}" >&2
else
  pass "canonical: default mode emitted no WARN"
fi

rc_canonical_strict=0
bash "${PATCHED_GENERATOR}" M999 --strict >/dev/null 2>"${stderr_canonical}" || rc_canonical_strict=$?

if [ "${rc_canonical_strict}" -ne 0 ]; then
  fail "canonical: --strict exited ${rc_canonical_strict} (expected 0)"
  echo "  stderr:" >&2; cat "${stderr_canonical}" >&2
else
  pass "canonical: --strict exited 0"
fi

# ---- Scenario 2: non-canonical-path -----------------------------------------
# root MILESTONE-SUMMARY.md + ## Stories Completed -> default 0/WARN; strict 1
echo "[SCENARIO] non-canonical-path: root MILESTONE-SUMMARY.md + '## Stories Completed'"

rm -f "${MILESTONE_DIR}/execution/MILESTONE-SUMMARY.md" 2>/dev/null || true
rm -f "${MILESTONE_DIR}/MILESTONE-SUMMARY.md" 2>/dev/null || true

make_summary_body "## Stories Completed" "${BRANCH_SHA}" \
  > "${MILESTONE_DIR}/MILESTONE-SUMMARY.md"

stderr_nc_path="${TMPDIR_BASE}/stderr-nc-path.txt"
rc_nc_path_default=0
bash "${PATCHED_GENERATOR}" M999 >/dev/null 2>"${stderr_nc_path}" || rc_nc_path_default=$?

if [ "${rc_nc_path_default}" -ne 0 ]; then
  fail "non-canonical-path: default mode exited ${rc_nc_path_default} (expected 0)"
  echo "  stderr:" >&2; cat "${stderr_nc_path}" >&2
else
  pass "non-canonical-path: default mode exited 0"
fi

if grep -q "WARN:" "${stderr_nc_path}" 2>/dev/null; then
  pass "non-canonical-path: default mode emitted WARN (expected)"
else
  fail "non-canonical-path: default mode did NOT emit WARN (expected WARN for root path)"
  echo "  stderr was:" >&2; cat "${stderr_nc_path}" >&2
fi

rc_nc_path_strict=0
bash "${PATCHED_GENERATOR}" M999 --strict >/dev/null 2>"${stderr_nc_path}" || rc_nc_path_strict=$?

if [ "${rc_nc_path_strict}" -eq 1 ]; then
  pass "non-canonical-path: --strict exited 1 (WARN promoted to error)"
else
  fail "non-canonical-path: --strict exited ${rc_nc_path_strict} (expected 1)"
fi

# ---- Scenario 3: non-canonical-section ---------------------------------------
# execution/MILESTONE-SUMMARY.md + ## Commits shipped -> default 0/WARN; strict 1
echo "[SCENARIO] non-canonical-section: execution/MILESTONE-SUMMARY.md + '## Commits shipped'"

rm -f "${MILESTONE_DIR}/MILESTONE-SUMMARY.md" 2>/dev/null || true
rm -f "${MILESTONE_DIR}/execution/MILESTONE-SUMMARY.md" 2>/dev/null || true

make_summary_body "## Commits shipped" "${BRANCH_SHA}" \
  > "${MILESTONE_DIR}/execution/MILESTONE-SUMMARY.md"

stderr_nc_sec="${TMPDIR_BASE}/stderr-nc-sec.txt"
rc_nc_sec_default=0
bash "${PATCHED_GENERATOR}" M999 >/dev/null 2>"${stderr_nc_sec}" || rc_nc_sec_default=$?

if [ "${rc_nc_sec_default}" -ne 0 ]; then
  fail "non-canonical-section: default mode exited ${rc_nc_sec_default} (expected 0)"
  echo "  stderr:" >&2; cat "${stderr_nc_sec}" >&2
else
  pass "non-canonical-section: default mode exited 0"
fi

if grep -q "WARN:" "${stderr_nc_sec}" 2>/dev/null; then
  pass "non-canonical-section: default mode emitted WARN (expected)"
else
  fail "non-canonical-section: default mode did NOT emit WARN (expected WARN for ## Commits shipped)"
  echo "  stderr was:" >&2; cat "${stderr_nc_sec}" >&2
fi

rc_nc_sec_strict=0
bash "${PATCHED_GENERATOR}" M999 --strict >/dev/null 2>"${stderr_nc_sec}" || rc_nc_sec_strict=$?

if [ "${rc_nc_sec_strict}" -eq 1 ]; then
  pass "non-canonical-section: --strict exited 1 (WARN promoted to error)"
else
  fail "non-canonical-section: --strict exited ${rc_nc_sec_strict} (expected 1)"
fi

# ---- Report ------------------------------------------------------------------
echo ""
if [ "${FAILURES}" -eq 0 ]; then
  echo "[PASS] release-notes-shape: all 3-scenario fixture checks passed (M018/S4 -- CHECK H1+H2)"
  exit 0
else
  echo "[FAIL] release-notes-shape: ${FAILURES} assertion(s) failed" >&2
  exit 1
fi
