#!/usr/bin/env bash
# aihaus dogfood regression: /aih-brainstorm shape validation.
# Asserts file layout, headers, and turn structure from a completed run.
# See .aihaus/milestones/M001-aih-brainstorm/stories/08-dogfood-validation.md.
#
# USAGE:
#   Panel mode (--deep regression, default):
#     1. /aih-brainstorm "what makes a good morning routine?" --deep
#     2. bash pkg/scripts/dogfood-brainstorm.sh --slug <slug>
#   Conversational-default mode (v0.6.0+):
#     1. /aih-brainstorm "some lightweight question"
#        (no --deep; optionally end with synthesis-escalation consent)
#     2. bash pkg/scripts/dogfood-brainstorm.sh --slug <slug> --mode conversational
#
# Slug is explicit (no mtime-fallback) because /aih-brainstorm is a slash
# command and concurrent brainstorms would cause silent false passes.
#
# EXIT CODES: 0=all pass, 1=assertion failed, 2=usage/setup error.

set -euo pipefail

TICK="[PASS]"; CROSS="[FAIL]"; FAILURES=0
_pass() { printf "%s %s\n" "$TICK" "$1"; }
_fail() {
  printf "%s %s\n" "$CROSS" "$1"; shift
  for line in "$@"; do printf "        %s\n" "$line"; done
  FAILURES=$((FAILURES + 1))
}
usage() {
  cat <<'EOF'
Usage: dogfood-brainstorm.sh --slug <slug> [--mode panel-deep|conversational]

Modes:
  panel-deep (default)   Asserts full panel + --deep run (R1 == R2 >= 1,
                         PERSPECTIVE files, CHALLENGES.md, BRIEF.md).
  conversational         Asserts conversational-default run (zero panelists,
                         no CHALLENGES.md; BRIEF.md optional — only if user
                         consented to synthesis-escalation).

Assumes /aih-brainstorm has already been run. Then re-run this script
with the emitted slug and the matching mode.
EOF
}

# ---- Args -------------------------------------------------------------------
SLUG=""
MODE="panel-deep"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --slug) SLUG="${2:-}"; shift 2 ;;
    --mode) MODE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf "unknown argument: %s\n" "$1" >&2; usage >&2; exit 2 ;;
  esac
done
if [[ -z "$SLUG" ]]; then usage >&2; exit 2; fi
case "$MODE" in
  panel-deep|conversational) ;;
  *) printf "unknown mode: %s\n" "$MODE" >&2; usage >&2; exit 2 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BDIR="${REPO_ROOT}/.aihaus/brainstorm/${SLUG}"
CONV="${BDIR}/CONVERSATION.md"
BRIEF="${BDIR}/BRIEF.md"
CHALL="${BDIR}/CHALLENGES.md"

printf "aihaus dogfood regression: /aih-brainstorm\nSlug: %s\nMode: %s\nDir:  %s\n\n" "$SLUG" "$MODE" "$BDIR"

# ---- 1: dir exists ----------------------------------------------------------
if [[ -d "$BDIR" ]]; then
  _pass "1. brainstorm dir exists"
else
  _fail "1. brainstorm dir exists" "not a directory: $BDIR"
  printf "\nDOGFOOD-BRAINSTORM: FAIL (cannot continue)\n"; exit 2
fi

# ---- 2: CONVERSATION.md H1 --------------------------------------------------
if [[ -f "$CONV" ]] && head -1 "$CONV" | grep -Eq '^# Conversation:'; then
  _pass "2. CONVERSATION.md first line matches '^# Conversation:'"
elif [[ -f "$CONV" ]]; then
  _fail "2. CONVERSATION.md first line" "got: $(head -1 "$CONV")" "file: $CONV"
else
  _fail "2. CONVERSATION.md first line" "file missing: $CONV"
fi

# ---- conversational-mode early path ----------------------------------------
if [[ "$MODE" == "conversational" ]]; then
  R1=$(find "$BDIR" -maxdepth 1 -type f -name 'PERSPECTIVE-*.md' ! -name 'PERSPECTIVE-*-r2.md' | wc -l | tr -d ' ')
  if [[ "$R1" -eq 0 ]]; then
    _pass "3c. conversational mode: zero PERSPECTIVE-*.md files (no panel spawned)"
  else
    _fail "3c. conversational mode: PERSPECTIVE files present" "R1=$R1 (expected 0)" "dir: $BDIR"
  fi
  if [[ ! -f "$CHALL" ]]; then
    _pass "4c. conversational mode: no CHALLENGES.md (no contrarian spawned)"
  else
    _fail "4c. conversational mode: CHALLENGES.md present" "file should not exist: $CHALL"
  fi
  if [[ -f "$BRIEF" ]]; then
    # BRIEF.md is optional in conversational mode — only present if user consented to synthesis.
    # If present, it MUST still pass the 8-header schema (Phase 7.5 runs in lightweight mode too).
    REQ=(
      "## Problem Statement" "## Perspectives Summary" "## Key Disagreements"
      "## Challenges" "## Research Evidence" "## Synthesis"
      "## Open Questions" "## Suggested Next Command"
    )
    miss=()
    for h in "${REQ[@]}"; do
      grep -Fxq "$h" "$BRIEF" || miss+=("$h")
    done
    if [[ ${#miss[@]} -eq 0 ]]; then
      _pass "5c. BRIEF.md (optional in conversational mode) present and passes 8-header schema"
    else
      _fail "5c. BRIEF.md 8-header schema" "missing: ${miss[*]}" "file: $BRIEF"
    fi
  else
    _pass "5c. BRIEF.md absent (no synthesis-escalation consent) — OK for conversational mode"
  fi
  printf "\n"
  if [[ "$FAILURES" -eq 0 ]]; then
    printf "DOGFOOD-BRAINSTORM: PASS (conversational mode)\n"; exit 0
  else
    printf "DOGFOOD-BRAINSTORM: FAIL (%d assertion(s) failed)\n" "$FAILURES"; exit 1
  fi
fi

# ---- 4-prep: count panelist files (needed for assertion 3's expected turns) -
R1=$(find "$BDIR" -maxdepth 1 -type f -name 'PERSPECTIVE-*.md' ! -name 'PERSPECTIVE-*-r2.md' | wc -l | tr -d ' ')
R2=$(find "$BDIR" -maxdepth 1 -type f -name 'PERSPECTIVE-*-r2.md' | wc -l | tr -d ' ')

# ---- 3: turn count ----------------------------------------------------------
TURNS=0
[[ -f "$CONV" ]] && TURNS=$(grep -c '^## Turn ' "$CONV" || true)
EXPECTED=$((1 + R1 + R2 + 1 + 1))
if [[ "$TURNS" -eq "$EXPECTED" && "$R1" -ge 1 ]]; then
  _pass "3. CONVERSATION.md has $TURNS turns (expected $EXPECTED = 1+${R1}+${R2}+1+1)"
else
  _fail "3. CONVERSATION.md turn count" \
    "got $TURNS; expected $EXPECTED (1 user + $R1 R1 + $R2 R2 + 1 contrarian + 1 synthesis)" \
    "file: $CONV"
fi

# ---- 4: R1 == R2 count ------------------------------------------------------
if [[ "$R1" -ge 1 && "$R1" -eq "$R2" ]]; then
  _pass "4. PERSPECTIVE R1=$R1 matches R2=$R2"
else
  _fail "4. PERSPECTIVE counts" "R1=$R1 R2=$R2 (must be equal and >=1)" "dir: $BDIR"
fi

# ---- 5: CHALLENGES.md coverage or NO-FINDINGS-JUSTIFIED ---------------------
if [[ -f "$CHALL" ]]; then
  hp=0; hf=0; hs=0; hj=0
  grep -Eiq 'premise'     "$CHALL" && hp=1 || true
  grep -Eiq 'framing'     "$CHALL" && hf=1 || true
  grep -Eiq 'stakeholder' "$CHALL" && hs=1 || true
  grep -Eq  'NO-FINDINGS-JUSTIFIED' "$CHALL" && hj=1 || true
  if [[ "$hj" -eq 1 ]] || [[ "$hp" -eq 1 && "$hf" -eq 1 && "$hs" -eq 1 ]]; then
    _pass "5. CHALLENGES.md covers premise/framing/stakeholder or has NO-FINDINGS-JUSTIFIED"
  else
    _fail "5. CHALLENGES.md deliverable coverage" \
      "premise=$hp framing=$hf stakeholder=$hs justified=$hj" "file: $CHALL"
  fi
else
  _fail "5. CHALLENGES.md" "file missing: $CHALL"
fi

# ---- 6: BRIEF.md 8 required H2 headers --------------------------------------
REQ=(
  "## Problem Statement" "## Perspectives Summary" "## Key Disagreements"
  "## Challenges" "## Research Evidence" "## Synthesis"
  "## Open Questions" "## Suggested Next Command"
)
if [[ -f "$BRIEF" ]]; then
  miss=()
  for h in "${REQ[@]}"; do
    grep -Fxq "$h" "$BRIEF" || miss+=("$h")
  done
  if [[ ${#miss[@]} -eq 0 ]]; then
    _pass "6. BRIEF.md contains all 8 required H2 headers"
  else
    _fail "6. BRIEF.md H2 headers" "missing: ${miss[*]}" "file: $BRIEF"
  fi
else
  _fail "6. BRIEF.md" "file missing: $BRIEF"
fi

# ---- 7: CONVERSATION.md mtime is latest among peers -------------------------
if [[ -f "$CONV" ]]; then
  cm=$(stat -c %Y "$CONV" 2>/dev/null || stat -f %m "$CONV")
  issues=()
  while IFS= read -r -d '' peer; do
    [[ "$peer" == "$CONV" ]] && continue
    pm=$(stat -c %Y "$peer" 2>/dev/null || stat -f %m "$peer")
    if [[ "$pm" -gt "$cm" ]]; then
      issues+=("${peer#${BDIR}/} mtime=$pm > CONVERSATION.md mtime=$cm")
    fi
  done < <(find "$BDIR" -maxdepth 1 -type f \
    \( -name 'PERSPECTIVE-*.md' -o -name 'CHALLENGES.md' \
       -o -name 'RESEARCH.md' -o -name 'BRIEF.md' \) -print0)
  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "7. CONVERSATION.md mtime latest (single-writer invariant)"
  else
    _fail "7. CONVERSATION.md mtime audit" "${issues[@]}"
  fi
else
  _fail "7. CONVERSATION.md mtime audit" "file missing: $CONV"
fi

# ---- 8: Suggested Next Command in allowed set ------------------------------
if [[ -f "$BRIEF" ]]; then
  block=$(awk '/^## Suggested Next Command$/{f=1;next} /^## /{f=0} f' "$BRIEF")
  if printf '%s' "$block" | grep -Eq '(aih-plan --from-brainstorm|aih-milestone --from-brainstorm|aih-quick|aih-brainstorm)'; then
    _pass "8. Suggested Next Command matches allowed set"
  else
    _fail "8. Suggested Next Command whitelist" \
      "no match for /aih-plan|/aih-milestone|/aih-quick|/aih-brainstorm" "file: $BRIEF"
  fi
else
  _fail "8. Suggested Next Command whitelist" "file missing: $BRIEF"
fi

printf "\n"
if [[ "$FAILURES" -eq 0 ]]; then
  printf "DOGFOOD-BRAINSTORM: PASS (8/8)\n"; exit 0
else
  printf "DOGFOOD-BRAINSTORM: FAIL (%d assertion(s) failed)\n" "$FAILURES"; exit 1
fi
