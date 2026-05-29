#!/usr/bin/env bash
# audit-skill-enforcement.sh — SKILL enforcement-layer audit tooling (M021/S01)
#
# Usage:
#   bash tools/audit-skill-enforcement.sh --compute-expected
#       Print integer: total rubric-matched steps across all 13 SKILL.md + annexes +
#       _shared/*-protocol.md files.
#
#   bash tools/audit-skill-enforcement.sh --coverage
#       Exit 0 if every rubric-matched step appears as >=1 row in canonical.
#       If canonical not yet created (pre-S08), exit 0 with advisory on stderr.
#
#   bash tools/audit-skill-enforcement.sh --validate-fragments
#       For each fragment file in _shared/enforcement-audit/, verify >=3 data rows
#       + canonical 13-column header. Pre-S02, fragment dir is empty -> exit 0.
#
# Architecture: M021 architecture.md §7.2-7.4, ADR-260503-A

set -euo pipefail

# ---- Resolve repo root relative to this script --------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PKG_ROOT="${REPO_ROOT}/pkg"

# ---- Ensure grep -P works (PCRE requires a UTF-8/unibyte locale) --------------
# On minimal Git Bash / POSIX-"C" environments the inherited locale makes
# `grep -P` abort ("supports only unibyte and UTF-8 locales"), which silently
# zeroes every step count (compute-expected -> 0) and falsely fails Check 62.
# Only override the locale when -P is actually broken, so working envs (Linux/CI
# with a UTF-8 locale already set) are left untouched.
if ! printf 'a\n' | grep -qP 'a' 2>/dev/null; then
  for _loc in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
    if LC_ALL="$_loc" sh -c "printf 'a\n' | grep -qP 'a'" 2>/dev/null; then
      export LC_ALL="$_loc"
      break
    fi
  done
fi

# ---- Per-format regex constants (architecture.md §7.2 + B3 fix) ---------------
# H3 colon/dash format: aih-feature, aih-milestone/annexes/execution.md
RE_H3_STEP='^### Step [0-9]+(\.[0-9]+)?[ —:]'
# H2 step format: aih-milestone/SKILL.md, aih-milestone/annexes/promotion.md
RE_H2_STEP='^## Step [0-9]+(\.[0-9]+)?[ —:]'
# Numbered H3: aih-bugfix, aih-init, aih-resume, aih-update
RE_H3_NUMBERED='^### [0-9]+(\.[0-9]+)?\. '
# D2 fallback: H2 mode/phase headers (for SKILLs with zero numbered-H3)
RE_H2_MODE_PHASE='^## [A-Za-z]'
# Named-section exclusions for D2 fallback (H6 fix: no $ end-anchor)
EXCLUDED_H2='^## (Task|Modes|Autonomy|Guardrails|Annexes|Inputs|Required output|Constraints|Acceptance criteria|Hard rules)\b'
# Phase-grouping exclusion (B4 fix: phases are groupings, not steps)
RE_H2_PHASE_GROUP='^## Phase [0-9]+'

# ---- Canonical + fragment paths -----------------------------------------------
CANONICAL="${PKG_ROOT}/.aihaus/skills/_shared/enforcement-audit.md"
FRAGMENT_DIR="${PKG_ROOT}/.aihaus/skills/_shared/enforcement-audit"
SKILLS_ROOT="${PKG_ROOT}/.aihaus/skills"

# ---- Expected 13-column header ------------------------------------------------
EXPECTED_HEADER="| SKILL | Location | Step | Label | Primary | Actor | Gate | Escape | Leverage | Reversibility | Drift Risk | Eligibility | Notes |"

# ---- Count steps in a single file --------------------------------------------
count_steps_in_file() {
  local file="$1"
  local n=0

  # Count numbered H3 (H3-step + H3-numbered) to decide format
  local numbered_h3
  numbered_h3=$(grep -cP "$RE_H3_STEP|$RE_H3_NUMBERED" "$file" 2>/dev/null) || numbered_h3=0

  if [ "$numbered_h3" -eq 0 ]; then
    # D2 fallback: count H2 mode/phase headers, excluding named sections
    # and Phase N groupings (B4 fix)
    n=$(grep -P "$RE_H2_MODE_PHASE" "$file" 2>/dev/null \
        | grep -vP "$EXCLUDED_H2" \
        | grep -cvP "$RE_H2_PHASE_GROUP") || n=0
  else
    # Count H3-step + H3-numbered + H2-step
    # RE_H2_PHASE_GROUP never matches RE_H2_STEP (which requires "Step N") so
    # no subtraction needed — but exclude it explicitly for future safety.
    n=$(grep -P "$RE_H3_STEP|$RE_H3_NUMBERED|$RE_H2_STEP" "$file" 2>/dev/null \
        | grep -cvP "$RE_H2_PHASE_GROUP") || n=0
  fi

  echo "$n"
}

# ---- compute_expected_rows ---------------------------------------------------
compute_expected_rows() {
  local total=0

  # Sweep all 13 SKILL.md files
  for skill_dir in "${SKILLS_ROOT}"/aih-*/; do
    local skill_file="${skill_dir}SKILL.md"
    [ -f "$skill_file" ] || continue
    local rows
    rows=$(count_steps_in_file "$skill_file")
    total=$((total + rows))
  done

  # Sweep _shared/*-protocol.md files
  for proto_file in "${SKILLS_ROOT}/_shared/"*-protocol.md; do
    [ -f "$proto_file" ] || continue
    local rows
    rows=$(count_steps_in_file "$proto_file")
    total=$((total + rows))
  done

  # Sweep annexes (all *.md in skills/*/annexes/ and skills/*/*/)
  for annex_file in "${SKILLS_ROOT}"/aih-*/annexes/*.md \
                    "${SKILLS_ROOT}"/aih-*/*.md; do
    [ -f "$annex_file" ] || continue
    # Skip SKILL.md (already counted above)
    case "$annex_file" in
      */SKILL.md) continue ;;
    esac
    local rows
    rows=$(count_steps_in_file "$annex_file")
    total=$((total + rows))
  done

  # Sweep nested annexes (e.g., aih-milestone/annexes/milestone-scoped/)
  for annex_file in "${SKILLS_ROOT}"/aih-*/annexes/**/*.md; do
    [ -f "$annex_file" ] || continue
    local rows
    rows=$(count_steps_in_file "$annex_file")
    total=$((total + rows))
  done

  echo "$total"
}

# ---- --coverage mode ---------------------------------------------------------
cmd_coverage() {
  if [ ! -f "$CANONICAL" ]; then
    echo "audit-skill-enforcement.sh: canonical not yet created (S08 deliverable)" >&2
    exit 0
  fi

  local expected
  expected=$(compute_expected_rows)

  # Count canonical rows (lines starting with "| aih-")
  local actual
  actual=$(grep -c '^| aih-' "$CANONICAL" 2>/dev/null || echo 0)

  if [ "$actual" -ge "$expected" ]; then
    exit 0
  else
    echo "audit-skill-enforcement.sh: coverage miss — canonical has $actual rows, expected >= $expected" >&2
    exit 1
  fi
}

# ---- --validate-fragments mode -----------------------------------------------
cmd_validate_fragments() {
  # Pre-S02: fragment dir is empty -> exit 0 silently
  local frag_count
  frag_count=$(find "$FRAGMENT_DIR" -maxdepth 1 -name "aih-*.md" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$frag_count" -eq 0 ]; then
    exit 0
  fi

  local failures=0
  while IFS= read -r -d '' frag_file; do
    # Check header line
    if ! head -5 "$frag_file" | grep -qF "$EXPECTED_HEADER"; then
      echo "audit-skill-enforcement.sh: fragment missing 13-column header: $frag_file" >&2
      failures=$((failures + 1))
    fi
    # Check >= 3 data rows (lines starting with "| aih-")
    local row_count
    row_count=$(grep -c '^| aih-' "$frag_file" 2>/dev/null || echo 0)
    if [ "$row_count" -lt 3 ]; then
      echo "audit-skill-enforcement.sh: fragment has <3 data rows ($row_count): $frag_file" >&2
      failures=$((failures + 1))
    fi
  done < <(find "$FRAGMENT_DIR" -maxdepth 1 -name "aih-*.md" -print0)

  if [ "$failures" -gt 0 ]; then
    exit 1
  fi
  exit 0
}

# ---- Dispatch ----------------------------------------------------------------
if [ $# -eq 0 ]; then
  echo "Usage: $0 --compute-expected | --coverage | --validate-fragments" >&2
  exit 1
fi

case "$1" in
  --compute-expected)
    compute_expected_rows
    ;;
  --coverage)
    cmd_coverage
    ;;
  --validate-fragments)
    cmd_validate_fragments
    ;;
  *)
    echo "Unknown flag: $1" >&2
    echo "Usage: $0 --compute-expected | --coverage | --validate-fragments" >&2
    exit 1
    ;;
esac
