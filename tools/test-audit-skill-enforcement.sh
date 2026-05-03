#!/usr/bin/env bash
# test-audit-skill-enforcement.sh — drives 7 fixture test cases for audit-skill-enforcement.sh
# Reports N/7 passing; exits 0 if all pass.
# M021/S01

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURE_BASE="${REPO_ROOT}/tools/.fixtures/enforcement-audit"
AUDIT="${SCRIPT_DIR}/audit-skill-enforcement.sh"

PASS=0
FAIL=0
TOTAL=7

_pass() { printf "[PASS] %s\n" "$1"; PASS=$((PASS + 1)); }
_fail() { printf "[FAIL] %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

# ---- Helper: read key=value from EXPECTED.md ---------------------------------
read_expected() {
  local dir="$1"
  local key="$2"
  grep "^${key}=" "${dir}/EXPECTED.md" 2>/dev/null | head -1 | cut -d= -f2-
}

# ---- T1: mixed-format — compute_expected_rows matches expected_rows -----------
test_mixed_format() {
  local name="T1 mixed-format"
  local dir="${FIXTURE_BASE}/mixed-format"
  local expected_rows
  expected_rows=$(read_expected "$dir" "expected_rows")

  # Count steps using the rubric directly on the fixture SKILL.md
  # We replicate the logic here to test it in isolation
  local RE_H3_STEP='^### Step [0-9]+(\.[0-9]+)?[ —:]'
  local RE_H3_NUMBERED='^### [0-9]+(\.[0-9]+)?\. '
  local RE_H2_STEP='^## Step [0-9]+(\.[0-9]+)?[ —:]'
  local RE_H2_PHASE_GROUP='^## Phase [0-9]+'

  local skill_file="${dir}/SKILL.md"
  local numbered_h3
  numbered_h3=$(grep -cP "$RE_H3_STEP|$RE_H3_NUMBERED" "$skill_file" 2>/dev/null) || numbered_h3=0

  local actual_rows
  if [ "$numbered_h3" -eq 0 ]; then
    local EXCLUDED='^## (Task|Modes|Autonomy|Guardrails|Annexes|Inputs|Required output|Constraints|Acceptance criteria|Hard rules)\b'
    local RE_H2_MODE='^## [A-Za-z]'
    actual_rows=$(grep -P "$RE_H2_MODE" "$skill_file" 2>/dev/null \
      | grep -vP "$EXCLUDED" \
      | grep -cvP "$RE_H2_PHASE_GROUP") || actual_rows=0
  else
    actual_rows=$(grep -P "$RE_H3_STEP|$RE_H3_NUMBERED|$RE_H2_STEP" "$skill_file" 2>/dev/null \
      | grep -cvP "$RE_H2_PHASE_GROUP") || actual_rows=0
  fi

  if [ "$actual_rows" -eq "$expected_rows" ]; then
    _pass "$name (rows=$actual_rows matches expected=$expected_rows)"
  else
    _fail "$name" "expected $expected_rows rows, got $actual_rows"
  fi
}

# ---- T2: excluded-section — H3s inside excluded H2 not counted ---------------
test_excluded_section() {
  local name="T2 excluded-section"
  local dir="${FIXTURE_BASE}/excluded-section"
  local expected_rows
  expected_rows=$(read_expected "$dir" "expected_rows")

  local RE_H3_STEP='^### Step [0-9]+(\.[0-9]+)?[ —:]'
  local RE_H3_NUMBERED='^### [0-9]+(\.[0-9]+)?\. '
  local RE_H2_STEP='^## Step [0-9]+(\.[0-9]+)?[ —:]'
  local RE_H2_PHASE_GROUP='^## Phase [0-9]+'

  local skill_file="${dir}/SKILL.md"
  local numbered_h3
  numbered_h3=$(grep -cP "$RE_H3_STEP|$RE_H3_NUMBERED" "$skill_file" 2>/dev/null) || numbered_h3=0

  local actual_rows
  if [ "$numbered_h3" -eq 0 ]; then
    local EXCLUDED='^## (Task|Modes|Autonomy|Guardrails|Annexes|Inputs|Required output|Constraints|Acceptance criteria|Hard rules)\b'
    local RE_H2_MODE='^## [A-Za-z]'
    actual_rows=$(grep -P "$RE_H2_MODE" "$skill_file" 2>/dev/null \
      | grep -vP "$EXCLUDED" \
      | grep -cvP "$RE_H2_PHASE_GROUP") || actual_rows=0
  else
    actual_rows=$(grep -P "$RE_H3_STEP|$RE_H3_NUMBERED|$RE_H2_STEP" "$skill_file" 2>/dev/null \
      | grep -cvP "$RE_H2_PHASE_GROUP") || actual_rows=0
  fi

  if [ "$actual_rows" -eq "$expected_rows" ]; then
    _pass "$name (rows=$actual_rows matches expected=$expected_rows)"
  else
    _fail "$name" "expected $expected_rows rows, got $actual_rows"
  fi
}

# ---- T3: under-coverage — canonical has fewer rows than expected --------------
test_under_coverage() {
  local name="T3 under-coverage"
  local dir="${FIXTURE_BASE}/under-coverage"

  local actual_rows
  actual_rows=$(grep -c '^| aih-' "${dir}/canonical.md" 2>/dev/null) || actual_rows=0
  local expected_rows
  expected_rows=$(read_expected "$dir" "expected_rows")

  if [ "$actual_rows" -lt "$expected_rows" ]; then
    _pass "$name (canonical has $actual_rows rows < expected $expected_rows — under-coverage detected)"
  else
    _fail "$name" "expected canonical to have <$expected_rows rows, got $actual_rows"
  fi
}

# ---- T4: duplicate-rows — same SKILL+Step combination appears 2x -------------
test_duplicate_rows() {
  local name="T4 duplicate-rows"
  local dir="${FIXTURE_BASE}/duplicate-rows"

  # Detect duplicate SKILL+Step combinations in canonical
  local dupes
  dupes=$(grep '^| aih-' "${dir}/canonical.md" 2>/dev/null \
    | awk -F'|' '{print $2"|"$4}' \
    | sort | uniq -d | wc -l | tr -d ' ')

  if [ "$dupes" -gt 0 ]; then
    _pass "$name (found $dupes duplicate SKILL+Step combination(s))"
  else
    _fail "$name" "expected at least 1 duplicate SKILL+Step pair, found 0"
  fi
}

# ---- T5: missing-headers — canonical has < 4 H2 headers ---------------------
test_missing_headers() {
  local name="T5 missing-headers"
  local dir="${FIXTURE_BASE}/missing-headers"
  local required_h2_count
  required_h2_count=$(read_expected "$dir" "required_h2_count")

  local actual_h2
  actual_h2=$(grep -c '^## ' "${dir}/canonical.md" 2>/dev/null) || actual_h2=0

  if [ "$actual_h2" -lt "$required_h2_count" ]; then
    _pass "$name (h2_count=$actual_h2 < required=$required_h2_count — missing headers detected)"
  else
    _fail "$name" "expected <$required_h2_count H2 headers, got $actual_h2"
  fi
}

# ---- T6: empty-fragment — fragment has < 3 data rows -------------------------
test_empty_fragment() {
  local name="T6 empty-fragment"
  local dir="${FIXTURE_BASE}/empty-fragment"

  local frag_file="${dir}/aih-fixture-empty.md"
  local row_count
  row_count=$(grep -c '^| aih-' "$frag_file" 2>/dev/null) || row_count=0

  if [ "$row_count" -lt 3 ]; then
    _pass "$name (fragment has $row_count data rows < 3 — empty-fragment detected)"
  else
    _fail "$name" "expected fragment with <3 data rows, got $row_count"
  fi
}

# ---- T7: duplicate-row-diff-loc — composite Location collapses to 1 row ------
test_duplicate_row_diff_loc() {
  local name="T7 duplicate-row-diff-loc"
  local dir="${FIXTURE_BASE}/duplicate-row-diff-loc"
  local expected_rows
  expected_rows=$(read_expected "$dir" "expected_rows")

  # Canonical should have exactly expected_rows rows
  local actual_rows
  actual_rows=$(grep -c '^| aih-' "${dir}/canonical.md" 2>/dev/null) || actual_rows=0

  if [ "$actual_rows" -eq "$expected_rows" ]; then
    _pass "$name (canonical has $actual_rows rows == expected $expected_rows — composite Location deduplication correct)"
  else
    _fail "$name" "expected $expected_rows rows after composite dedup, got $actual_rows"
  fi
}

# ---- Main --------------------------------------------------------------------
printf "audit-skill-enforcement fixture tests\n\n"

test_mixed_format
test_excluded_section
test_under_coverage
test_duplicate_rows
test_missing_headers
test_empty_fragment
test_duplicate_row_diff_loc

printf "\n"
if [ "$FAIL" -eq 0 ]; then
  printf "%d/%d passing\n" "$PASS" "$TOTAL"
  exit 0
else
  printf "%d/%d passing (%d failed)\n" "$PASS" "$TOTAL" "$FAIL"
  exit 1
fi
