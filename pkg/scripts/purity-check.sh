#!/usr/bin/env bash
# AIhaus framework purity check
#
# Scans the entire aihaus-package/ tree for references to foreign frameworks
# or prior tool names. AIhaus ships as a standalone, original product and must
# not contain attribution to any prior tooling.
#
# Exits 0 if no matches are found.
# Exits 1 (and prints file:line:term) if any match is found.
#
# ---------------------------------------------------------------------------
# DENYLIST
# ---------------------------------------------------------------------------
# Future maintainers: append new forbidden terms to the array below.
# Entries are matched case-insensitively with explicit boundaries so that
# short tokens do not false-positive inside unrelated longer words.
#
# NOTE: This script intentionally contains the forbidden terms in the array
# below. The scan explicitly excludes this file from its own results.
FORBIDDEN_TERMS=("gsd" "bmad" "sparc" "claude-flow" "ruv-swarm" "agentic-flow" "domus" "nora")

set -u

# ---- Resolve package root relative to this script --------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SELF_NAME="$(basename "$0")"

# ---- Build the regex -------------------------------------------------------
# Escape regex metacharacters. Only "-" matters in our list.
_escape_term() {
  # Escape each char that is a BRE/ERE metacharacter.
  printf '%s' "$1" | sed -e 's/[][\\.^$*+?(){}|/-]/\\&/g'
}

ALTERNATION=""
for term in "${FORBIDDEN_TERMS[@]}"; do
  escaped=$(_escape_term "$term")
  if [[ -z "$ALTERNATION" ]]; then
    ALTERNATION="$escaped"
  else
    ALTERNATION="${ALTERNATION}|${escaped}"
  fi
done

# Explicit boundary via a character class rather than \b, because several
# terms contain hyphens which break GNU grep's word-character definition.
# A "boundary" here = start of line, end of line, or any non-[A-Za-z0-9_] char.
BOUNDARY_REGEX="(^|[^A-Za-z0-9_])(${ALTERNATION})([^A-Za-z0-9_]|\$)"

# ---- Run grep --------------------------------------------------------------
printf "AIhaus framework purity check\n"
printf "Scanning: %s\n" "$PACKAGE_ROOT"
printf "Forbidden terms: %s\n\n" "${FORBIDDEN_TERMS[*]}"

# --include patterns limit the scan to text formats we ship.
# --exclude-dir skips the local git metadata.
# -I skips binary files.
# -E enables extended regex.
# -i case-insensitive.
# -n prints line numbers.
# -H prints filenames even for single-file matches.
TMP_OUT=$(mktemp 2>/dev/null || mktemp -t purity)
trap 'rm -f "$TMP_OUT"' EXIT

grep -rIEHin \
  --include='*.md' \
  --include='*.sh' \
  --include='*.ps1' \
  --include='*.json' \
  --include='*.yml' \
  --include='*.yaml' \
  --exclude="$SELF_NAME" \
  --exclude-dir='.git' \
  --exclude-dir='.claude' \
  --exclude-dir='plans' \
  --exclude-dir='milestones' \
  --exclude-dir='features' \
  --exclude-dir='bugfixes' \
  --regexp="$BOUNDARY_REGEX" \
  "$PACKAGE_ROOT" > "$TMP_OUT" 2>/dev/null || true

# Exit status of grep: 0=match, 1=no match, 2=error. We ignore errors above
# because they usually mean "no files matched the include globs".

MATCH_COUNT=$(wc -l < "$TMP_OUT" | tr -d ' ')

if [[ "$MATCH_COUNT" -eq 0 ]]; then
  printf "Framework purity: PASSED (zero foreign framework references)\n"
  exit 0
fi

printf "Framework purity: FAILED (%d matches)\n" "$MATCH_COUNT"
printf -- "----------------------------------------\n"
# Reformat matches as file:line:term where possible. grep already prints
# file:line:content; append which term(s) matched on that line.
while IFS= read -r hit; do
  if [[ -z "$hit" ]]; then
    continue
  fi
  matched_terms=""
  lower_hit=$(printf '%s' "$hit" | tr '[:upper:]' '[:lower:]')
  for term in "${FORBIDDEN_TERMS[@]}"; do
    lower_term=$(printf '%s' "$term" | tr '[:upper:]' '[:lower:]')
    case "$lower_hit" in
      *"$lower_term"*)
        if [[ -z "$matched_terms" ]]; then
          matched_terms="$term"
        else
          matched_terms="${matched_terms},${term}"
        fi
        ;;
    esac
  done
  printf "%s  [term(s): %s]\n" "$hit" "$matched_terms"
done < "$TMP_OUT"

exit 1
