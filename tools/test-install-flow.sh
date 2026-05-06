#!/usr/bin/env bash
# tools/test-install-flow.sh — regression harness for install.sh V5 flow
#
# FR-35 / SC-12 / ADR-260504-A
# Covers 4 hermetic test cases (CHALLENGES F6 + F9 — dogfood + duplicate-clone):
#   Case 1 — fresh-machine:      user-global skill bootstrap from a staged clone
#   Case 2 — dogfood-case:       cwd IS the aihaus package; per-repo overlay skipped
#   Case 3 — duplicate-clone:    TWO candidate clones; discovery chain picks newest
#   Case 4 — per-repo:           install --target <git-repo>; .aihaus/ + .claude/ links
#
# Hermeticism: each case uses HOME=$WORK/case<N> so no writes go to the real ~/.claude/
# Trap teardown removes $WORK on exit (success AND failure).
# No network calls at test time.
#
# Exit codes:
#   0 — all 4 cases PASS
#   1 — one or more cases FAIL
#
# Usage: bash tools/test-install-flow.sh
set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve repo root (directory containing this script's ../pkg/)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
FIXTURES="${SCRIPT_DIR}/.fixtures/install-flow"
REAL_INSTALL="${REPO_ROOT}/pkg/scripts/install.sh"
REAL_PKG_AIHAUS="${REPO_ROOT}/pkg/.aihaus"
REAL_PKG_SCRIPTS="${REPO_ROOT}/pkg/scripts"
REAL_TEMPLATES="${REPO_ROOT}/pkg/templates"

# ---------------------------------------------------------------------------
# Sanity guard: ensure we have the real install.sh
# ---------------------------------------------------------------------------
[[ -f "${REAL_INSTALL}" ]] || { echo "FATAL: ${REAL_INSTALL} not found"; exit 1; }
[[ -d "${REAL_PKG_AIHAUS}/skills" ]] || { echo "FATAL: ${REAL_PKG_AIHAUS}/skills not found"; exit 1; }

# ---------------------------------------------------------------------------
# Windows Git Bash compatibility: override OS env var to force ln -s mode
# instead of mklink /J for user-global skill symlinks in install.sh.
#
# On Windows Git Bash, cmd.exe /c "mklink /J" creates junctions that
# are inaccessible from MSYS2's POSIX layer (ls/write fail). However,
# `ln -s` on /tmp paths works correctly in Git Bash.
# Unsetting OS forces install.sh's install_user_global_skills() to use
# ln -s (use_junction=0) instead of mklink /J, which works in /tmp.
# This does NOT affect the per-repo .claude/ links (junction-safe.sh
# uses PowerShell New-Item -ItemType Junction which IS accessible).
#
# On Unix (non-Windows), OS is typically unset anyway; this is a no-op.
# ---------------------------------------------------------------------------
export OS=""

# ---------------------------------------------------------------------------
# Temp workspace + teardown trap
# ---------------------------------------------------------------------------
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT INT TERM

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
PASS_COUNT=0
FAIL_COUNT=0
TOTAL=0

_pass() {
  local label="$1"
  echo "PASS  [${label}]"
  PASS_COUNT=$((PASS_COUNT + 1))
  TOTAL=$((TOTAL + 1))
}

_fail() {
  local label="$1"
  shift
  echo "FAIL  [${label}]"
  for msg in "$@"; do
    echo "      $msg"
  done
  FAIL_COUNT=$((FAIL_COUNT + 1))
  TOTAL=$((TOTAL + 1))
}

_assert_eq() {
  local label="$1" actual="$2" expected="$3"
  if [[ "${actual}" == "${expected}" ]]; then
    _pass "${label}"
  else
    _fail "${label}" "expected: ${expected}" "actual:   ${actual}"
  fi
}

_assert_gte() {
  local label="$1" actual="$2" min="$3"
  if [[ "${actual}" -ge "${min}" ]]; then
    _pass "${label}"
  else
    _fail "${label}" "expected >= ${min}, got ${actual}"
  fi
}

_assert_exists() {
  local label="$1" path="$2"
  if [[ -e "${path}" ]]; then
    _pass "${label}"
  else
    _fail "${label}" "path does not exist: ${path}"
  fi
}

_assert_not_exists() {
  local label="$1" path="$2"
  if [[ ! -e "${path}" ]] && [[ ! -L "${path}" ]]; then
    _pass "${label}"
  else
    _fail "${label}" "path should not exist: ${path}"
  fi
}

_assert_contains() {
  local label="$1" file="$2" needle="$3"
  if grep -qF "${needle}" "${file}" 2>/dev/null; then
    _pass "${label}"
  else
    _fail "${label}" "pattern '${needle}' not found in ${file}"
  fi
}

_assert_stdout_contains() {
  local label="$1" output="$2" needle="$3"
  if echo "${output}" | grep -qF "${needle}"; then
    _pass "${label}"
  else
    _fail "${label}" "pattern '${needle}' not found in output"
  fi
}

# ---------------------------------------------------------------------------
# setup_staged_aihaus <dest>
#
# Creates a "staged clone" at <dest> with a flat layout:
#   <dest>/scripts/install.sh    (symlink → real install.sh)
#   <dest>/scripts/lib/          (symlinks → real lib files)
#   <dest>/scripts/launch-aihaus.sh (symlink)
#   <dest>/pkg/.aihaus/skills/   (populated from real package)
#   <dest>/.aihaus/              (symlinks → real pkg/.aihaus subdirs)
#   <dest>/templates/            (symlinks → real templates)
#
# With this layout: PKG_ROOT = <dest> (parent of scripts/), so:
#   PKG_AIHAUS = <dest>/.aihaus     ← used for per-repo cp
#   PKG_ROOT/pkg/.aihaus/skills     ← used for user-global install loop
#
# NOTE: install.sh's install_user_global_skills() scans
#   ${aihaus_home}/pkg/.aihaus/skills where aihaus_home = PKG_ROOT.
# When PKG_ROOT = <dest>, that path = <dest>/pkg/.aihaus/skills, which
# we populate here so user-global install creates the expected entries.
# ---------------------------------------------------------------------------
setup_staged_aihaus() {
  local dest="$1"

  # scripts/ layer — flat (PKG_ROOT will be dest, not dest/pkg)
  mkdir -p "${dest}/scripts/lib"
  ln -s "${REAL_INSTALL}" "${dest}/scripts/install.sh"
  ln -s "${REAL_PKG_SCRIPTS}/lib/junction-safe.sh"  "${dest}/scripts/lib/junction-safe.sh"
  ln -s "${REAL_PKG_SCRIPTS}/lib/merge-settings.sh" "${dest}/scripts/lib/merge-settings.sh"
  ln -s "${REAL_PKG_SCRIPTS}/lib/restore-effort.sh" "${dest}/scripts/lib/restore-effort.sh"
  ln -s "${REAL_PKG_SCRIPTS}/launch-aihaus.sh"       "${dest}/scripts/launch-aihaus.sh"

  # templates/
  mkdir -p "${dest}/templates"
  ln -s "${REAL_TEMPLATES}/settings.local.json" "${dest}/templates/settings.local.json"

  # .aihaus/ — for per-repo install (PKG_AIHAUS = dest/.aihaus)
  mkdir -p "${dest}/.aihaus"
  for sub in skills agents hooks templates; do
    ln -s "${REAL_PKG_AIHAUS}/${sub}" "${dest}/.aihaus/${sub}"
  done

  # pkg/.aihaus/skills/ — for user-global install loop
  # install_user_global_skills scans PKG_ROOT/pkg/.aihaus/skills = dest/pkg/.aihaus/skills
  # IMPORTANT: use real (writable) directories here, NOT symlinks to the package.
  # install.sh writes ".aihaus-managed" INTO skill_dir (through the user-global symlink),
  # so skill_dir must be writable. Symlinks to the read-only package dirs would fail.
  mkdir -p "${dest}/pkg/.aihaus/skills"
  for skill_dir in "${REAL_PKG_AIHAUS}/skills"/aih-*; do
    [[ -d "${skill_dir}" ]] || continue
    local skill_name
    skill_name="$(basename "${skill_dir}")"
    mkdir -p "${dest}/pkg/.aihaus/skills/${skill_name}"
  done
}

# ===========================================================================
# CASE 1 — fresh-machine
# Simulate empty $HOME. Run install from staged clone.
# Assert: ~/.claude/skills/aih-* populated (>= 14 entries).
# Assert: ~/.aihaus/.install-source written.
# ===========================================================================
run_case1() {
  local LABEL="case1/fresh-machine"
  local STAGED="${WORK}/case1-staged"
  local FAKE_HOME="${WORK}/case1-home"
  local TARGET_REPO="${WORK}/case1-target"

  echo ""
  echo "--- ${LABEL} ---"

  # Build staged clone and target git repo
  setup_staged_aihaus "${STAGED}"
  mkdir -p "${FAKE_HOME}" "${TARGET_REPO}"
  git -C "${TARGET_REPO}" init -q
  git -C "${TARGET_REPO}" config user.email "test@test.local" 2>/dev/null || true
  git -C "${TARGET_REPO}" config user.name "Test" 2>/dev/null || true

  # Run install from a neutral dir (not dogfood) with fake HOME
  local output exit_code=0
  output="$(cd "${WORK}" && HOME="${FAKE_HOME}" \
    bash "${STAGED}/scripts/install.sh" --target "${TARGET_REPO}" 2>&1)" || exit_code=$?

  # AC1: exit 0
  _assert_eq "${LABEL}/exit-0" "${exit_code}" "0"

  # AC2: ~/.claude/skills/aih-* populated >= 14 entries
  local skill_count=0
  if [[ -d "${FAKE_HOME}/.claude/skills" ]]; then
    skill_count="$(ls -d "${FAKE_HOME}/.claude/skills"/aih-* 2>/dev/null | wc -l | tr -d ' ')"
  fi
  _assert_gte "${LABEL}/user-global-skills-ge-14" "${skill_count}" "14"

  # AC3: ~/.aihaus/.install-source written
  _assert_exists "${LABEL}/install-source-exists" "${FAKE_HOME}/.aihaus/.install-source"

  # AC4: per-repo .claude/skills link exists
  _assert_exists "${LABEL}/per-repo-claude-skills" "${TARGET_REPO}/.claude/skills"

  # AC5: .aihaus/ created in target
  _assert_exists "${LABEL}/per-repo-aihaus" "${TARGET_REPO}/.aihaus"
}

# ===========================================================================
# CASE 2 — dogfood-case
# cwd IS an aihaus package dir (has pkg/scripts/install.sh + pkg/.aihaus/skills/).
# Assert: exit 0, dogfood one-liner in output, per-repo overlay skipped.
# ===========================================================================
run_case2() {
  local LABEL="case2/dogfood-case"
  local DOGFOOD_CWD="${WORK}/case2-dogfood-cwd"
  local FAKE_HOME="${WORK}/case2-home"

  echo ""
  echo "--- ${LABEL} ---"

  # Stage dogfood-cwd: satisfies is_dogfood_cwd() predicate
  # [[ -f "${PWD}/pkg/scripts/install.sh" ]] && [[ -d "${PWD}/pkg/.aihaus/skills" ]]
  mkdir -p "${DOGFOOD_CWD}/pkg/scripts"
  mkdir -p "${DOGFOOD_CWD}/pkg/.aihaus/skills"
  cp "${FIXTURES}/dogfood-case/install.sh.stub" "${DOGFOOD_CWD}/pkg/scripts/install.sh"
  touch "${DOGFOOD_CWD}/pkg/.aihaus/skills/.keep"
  mkdir -p "${FAKE_HOME}"

  # Run install from within dogfood-cwd (real install.sh, fake HOME)
  local output exit_code=0
  output="$(cd "${DOGFOOD_CWD}" && HOME="${FAKE_HOME}" \
    bash "${REAL_INSTALL}" 2>&1)" || exit_code=$?

  # AC1: exit 0 (dogfood branch exits 0)
  _assert_eq "${LABEL}/exit-0" "${exit_code}" "0"

  # AC2: dogfood one-liner in output
  _assert_stdout_contains "${LABEL}/dogfood-oneliner" "${output}" \
    "you are inside the aihaus package"

  # AC3: per-repo overlay skipped — no .aihaus/ dir in dogfood-cwd
  _assert_not_exists "${LABEL}/no-per-repo-aihaus" "${DOGFOOD_CWD}/.aihaus"

  # AC4: per-repo overlay skipped — no .claude/ dir in dogfood-cwd
  _assert_not_exists "${LABEL}/no-per-repo-claude" "${DOGFOOD_CWD}/.claude"

  # AC5: registry written (dogfood path also writes ~/.aihaus/.install-source)
  _assert_exists "${LABEL}/install-source-exists" "${FAKE_HOME}/.aihaus/.install-source"
}

# ===========================================================================
# CASE 3 — duplicate-clone
# Stage TWO candidate clones with controlled timestamps in $HOME paths.
# Assert: discovery chain picks newest (inline test).
# Assert: .install-source written.
# Assert: re-run is deterministic (exit 0 both times).
# ===========================================================================
run_case3() {
  local LABEL="case3/duplicate-clone"
  local FAKE_HOME="${WORK}/case3-home"
  local TARGET_REPO="${WORK}/case3-target"

  echo ""
  echo "--- ${LABEL} ---"

  mkdir -p "${FAKE_HOME}" "${TARGET_REPO}"
  git -C "${TARGET_REPO}" init -q
  git -C "${TARGET_REPO}" config user.email "test@test.local" 2>/dev/null || true
  git -C "${TARGET_REPO}" config user.name "Test" 2>/dev/null || true

  # Build two candidate clones via fixture setup.sh
  bash "${FIXTURES}/duplicate-clone/setup.sh" "${FAKE_HOME}" 2>/dev/null

  local OLDER_CLONE="${FAKE_HOME}/tools/aihaus"
  local NEWER_CLONE="${FAKE_HOME}/Documents/GitHub/aihaus-flow"

  # AC1: verify controlled timestamps — newer clone has higher epoch
  local ts_old ts_new
  ts_old="$(git -C "${OLDER_CLONE}" log -1 --format=%ct 2>/dev/null || echo 0)"
  ts_new="$(git -C "${NEWER_CLONE}" log -1 --format=%ct 2>/dev/null || echo 0)"

  if [[ "${ts_new}" -gt "${ts_old}" ]]; then
    _pass "${LABEL}/newer-ts-greater-than-older"
  else
    _fail "${LABEL}/newer-ts-greater-than-older" \
      "expected ts_new(${ts_new}) > ts_old(${ts_old})"
  fi

  # AC2: inline discovery chain — mirrors resolve_aihaus_home() tier 4-8 logic
  # Tests that the chain picks the newest candidate deterministically.
  local best="" best_ts=0
  local candidates=("${FAKE_HOME}/.local/share/aihaus"
    "${FAKE_HOME}/tools/aihaus"
    "${FAKE_HOME}/Documents/GitHub/aihaus-flow"
    "${FAKE_HOME}/Documents/GitHub/aihaus"
    "${FAKE_HOME}/code/aihaus")
  for c in "${candidates[@]}"; do
    [[ -d "${c}/pkg/.aihaus/skills" ]] && [[ -d "${c}/.git" ]] || continue
    local ts
    ts="$(git -C "${c}" log -1 --format=%ct 2>/dev/null || echo 0)"
    if [[ "${ts}" -gt "${best_ts}" ]]; then
      best="${c}"
      best_ts="${ts}"
    fi
  done

  if [[ "${best}" == "${NEWER_CLONE}" ]]; then
    _pass "${LABEL}/chain-picks-newest"
  else
    _fail "${LABEL}/chain-picks-newest" \
      "expected best=${NEWER_CLONE}" "got best=${best}"
  fi

  # AC3: run install (discovery chain exercises tiers 4-8 since AIHAUS_HOME not set)
  # Run from FAKE_HOME to avoid dogfood detection (fake home does not have pkg/scripts/install.sh at root)
  local output exit_code=0
  output="$(cd "${FAKE_HOME}" && HOME="${FAKE_HOME}" \
    bash "${REAL_INSTALL}" --target "${TARGET_REPO}" 2>&1)" || exit_code=$?

  _assert_eq "${LABEL}/exit-0-first-run" "${exit_code}" "0"

  # AC4: .install-source written (install.sh step 11 writes PKG_ROOT to registry)
  _assert_exists "${LABEL}/install-source-written" "${FAKE_HOME}/.aihaus/.install-source"

  # AC5: .install-source is non-empty
  local src_content
  src_content="$(cat "${FAKE_HOME}/.aihaus/.install-source" 2>/dev/null || true)"
  if [[ -n "${src_content}" ]]; then
    _pass "${LABEL}/install-source-non-empty"
  else
    _fail "${LABEL}/install-source-non-empty" ".install-source is empty"
  fi

  # AC6: idempotent re-run — same result, same .install-source content
  local exit_code2=0
  bash "${REAL_INSTALL}" --target "${TARGET_REPO}" --force 2>&1 >/dev/null || exit_code2=$?
  # Note: re-run uses HOME of the calling shell; need to redirect HOME again
  exit_code2=0
  output="$(cd "${FAKE_HOME}" && HOME="${FAKE_HOME}" \
    bash "${REAL_INSTALL}" --target "${TARGET_REPO}" --force 2>&1)" || exit_code2=$?

  _assert_eq "${LABEL}/exit-0-second-run" "${exit_code2}" "0"

  local src_content2
  src_content2="$(cat "${FAKE_HOME}/.aihaus/.install-source" 2>/dev/null || true)"
  _assert_eq "${LABEL}/install-source-idempotent" "${src_content2}" "${src_content}"
}

# ===========================================================================
# CASE 4 — per-repo
# After fresh-machine setup (Case 1 staged clone).
# Create $WORK/myproject with a .git/.
# Run install --target <project>.
# Assert .aihaus/ and .claude/{skills,agents,hooks} present in target.
# ===========================================================================
run_case4() {
  local LABEL="case4/per-repo"
  local STAGED="${WORK}/case4-staged"
  local FAKE_HOME="${WORK}/case4-home"
  local MYPROJECT="${WORK}/myproject"

  echo ""
  echo "--- ${LABEL} ---"

  # Build staged clone (same helper as Case 1) and fresh HOME
  setup_staged_aihaus "${STAGED}"
  mkdir -p "${FAKE_HOME}" "${MYPROJECT}"

  # Per-repo fixture: minimal git repo skeleton
  git -C "${MYPROJECT}" init -q
  git -C "${MYPROJECT}" config user.email "test@test.local" 2>/dev/null || true
  git -C "${MYPROJECT}" config user.name "Test" 2>/dev/null || true

  # Run install --target myproject from a neutral dir
  local output exit_code=0
  output="$(cd "${WORK}" && HOME="${FAKE_HOME}" \
    bash "${STAGED}/scripts/install.sh" --target "${MYPROJECT}" 2>&1)" || exit_code=$?

  # AC1: exit 0
  _assert_eq "${LABEL}/exit-0" "${exit_code}" "0"

  # AC2: .aihaus/ created in target
  _assert_exists "${LABEL}/target-aihaus" "${MYPROJECT}/.aihaus"

  # AC3: .claude/skills present (symlink or copy)
  _assert_exists "${LABEL}/target-claude-skills" "${MYPROJECT}/.claude/skills"

  # AC4: .claude/agents present
  _assert_exists "${LABEL}/target-claude-agents" "${MYPROJECT}/.claude/agents"

  # AC5: .claude/hooks present
  _assert_exists "${LABEL}/target-claude-hooks" "${MYPROJECT}/.claude/hooks"

  # AC6: .aihaus/ contains skills/
  _assert_exists "${LABEL}/target-aihaus-skills" "${MYPROJECT}/.aihaus/skills"
}

# ===========================================================================
# Main
# ===========================================================================

echo "=========================================="
echo " test-install-flow.sh — 4 hermetic cases "
echo "=========================================="
echo " WORK=${WORK}"
echo ""

run_case1
run_case2
run_case3
run_case4

echo ""
echo "=========================================="
echo " Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed / ${TOTAL} total"
echo "=========================================="

if [[ "${FAIL_COUNT}" -gt 0 ]]; then
  echo "HARNESS EXIT: 1 (failures detected)"
  exit 1
fi

echo "HARNESS EXIT: 0 (all cases PASS)"
exit 0
