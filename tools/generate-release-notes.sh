#!/usr/bin/env bash
# aihaus release-note generator (maintainer-only).
#
# Reads .aihaus/milestones/M0XX-*/execution/MILESTONE-SUMMARY.md and the
# corresponding milestone branch, then emits a user-facing release-note
# draft to stdout (or to -o <file>).
#
# Filtering rule (load-bearing): drop a commit from the "What changed"
# section if and only if EVERY changed path in that commit starts with
# `tools/`. Any non-tools/ path retains the commit.
#
# Hardcoded omissions: no "Validation" section. Maintainer-only script
# names (smoke-test, purity-check, dogfood-brainstorm) must not appear
# in the output. A grep assertion fires before emit; a warning is
# printed to stderr if any are found, so the maintainer can fix the
# template before publishing.
#
# SUMMARY FILE RESOLUTION (dual-path tolerance):
#   Canonical path:  <milestone>/execution/MILESTONE-SUMMARY.md
#   Fallback path:   <milestone>/MILESTONE-SUMMARY.md  (non-canonical — WARN)
#   non-canonical accepted with WARN; will be removed in M020 — pin canonical
#   shape via the MILESTONE-SUMMARY.md template under pkg/.aihaus/templates/
#
# SECTION NAME TOLERANCE:
#   Canonical section:  ## Stories Completed
#   Alternative:        ## Commits shipped  (non-canonical — WARN)
#   non-canonical accepted with WARN; will be removed in M020 — pin canonical
#   shape via the MILESTONE-SUMMARY.md template under pkg/.aihaus/templates/
#
# USAGE:
#   bash tools/generate-release-notes.sh M0XX [-o tools/.out/release-notes-M0XX.md] [--strict]
#
# EXIT CODES:
#   0 = success
#   1 = strict mode: one or more WARN conditions triggered
#   2 = preconditions unmet (missing milestone summary, missing branch
#       header, no merge-base, etc.)

set -euo pipefail

# ---- Args ------------------------------------------------------------------
MILESTONE_ID=""
OUT_FILE=""
STRICT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) OUT_FILE="${2:-}"; shift 2 ;;
    --strict) STRICT=1; shift ;;
    -h|--help)
      sed -n '1,40p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      if [[ -z "$MILESTONE_ID" ]]; then
        MILESTONE_ID="$1"; shift
      else
        printf "unknown argument: %s\n" "$1" >&2
        exit 2
      fi
      ;;
  esac
done

if [[ -z "$MILESTONE_ID" ]]; then
  printf "usage: %s M0XX [-o output-file]\n" "$(basename "$0")" >&2
  exit 2
fi

# Validate milestone id shape (M followed by 3+ digits, optionally with -slug)
if [[ ! "$MILESTONE_ID" =~ ^M[0-9]{3,}$ ]]; then
  printf "invalid milestone id: %s (expected M0XX, e.g. M001)\n" "$MILESTONE_ID" >&2
  exit 2
fi

# ---- Resolve repo root + milestone dir -------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Find the milestone dir matching M0XX-<slug>
MILESTONE_DIR=""
for candidate in "${REPO_ROOT}/.aihaus/milestones/${MILESTONE_ID}"-*; do
  if [[ -d "$candidate" ]]; then
    MILESTONE_DIR="$candidate"
    break
  fi
done

if [[ -z "$MILESTONE_DIR" || ! -d "$MILESTONE_DIR" ]]; then
  printf "milestone dir not found: .aihaus/milestones/%s-*\n" "$MILESTONE_ID" >&2
  exit 2
fi

# ---- WARN accumulator (--strict converts WARNs to exit 1) -----------------
WARN_COUNT=0
emit_warn() {
  printf "WARN: %s\n" "$1" >&2
  WARN_COUNT=$((WARN_COUNT + 1))
}

# ---- Resolve MILESTONE-SUMMARY.md (dual-path tolerance) --------------------
# Canonical:  <milestone>/execution/MILESTONE-SUMMARY.md
# Fallback:   <milestone>/MILESTONE-SUMMARY.md   (non-canonical — WARN)
SUMMARY="${MILESTONE_DIR}/execution/MILESTONE-SUMMARY.md"
SUMMARY_PATH_WARN=0
if [[ ! -f "$SUMMARY" ]]; then
  FALLBACK_SUMMARY="${MILESTONE_DIR}/MILESTONE-SUMMARY.md"
  if [[ -f "$FALLBACK_SUMMARY" ]]; then
    emit_warn "non-canonical path: MILESTONE-SUMMARY.md found at milestone root (not execution/). non-canonical accepted with WARN; will be removed in M020 — pin canonical shape via the MILESTONE-SUMMARY.md template under pkg/.aihaus/templates/"
    SUMMARY="$FALLBACK_SUMMARY"
    SUMMARY_PATH_WARN=1
  else
    printf "MILESTONE-SUMMARY.md not found: %s (also checked %s)\n" "$SUMMARY" "$FALLBACK_SUMMARY" >&2
    exit 2
  fi
fi

# ---- Extract Branch: header from MILESTONE-SUMMARY.md ----------------------
# Match `**Branch:** ... milestone/M0XX-...` (allowing surrounding markdown).
BRANCH_LINE="$(grep -E '^\*\*Branch:\*\*' "$SUMMARY" | head -1 || true)"
if [[ -z "$BRANCH_LINE" ]]; then
  printf "MILESTONE-SUMMARY.md missing required '**Branch:**' header line\n" >&2
  exit 2
fi

# Pull out the branch name — strip backticks, leading text.
BRANCH_NAME="$(printf '%s' "$BRANCH_LINE" | sed -E 's/^\*\*Branch:\*\*[[:space:]]*//' | tr -d '`' | awk '{print $1}')"
if [[ -z "$BRANCH_NAME" || "$BRANCH_NAME" != milestone/${MILESTONE_ID}-* ]]; then
  printf "Branch name in MILESTONE-SUMMARY.md doesn't match milestone/%s-*: '%s'\n" "$MILESTONE_ID" "$BRANCH_NAME" >&2
  exit 2
fi

# ---- Compute commit range: merge-base main..HEAD-of-branch -----------------
# Use git -C "$REPO_ROOT" so this works from any cwd.
MERGE_BASE="$(git -C "$REPO_ROOT" merge-base main "$BRANCH_NAME" 2>/dev/null || true)"
if [[ -z "$MERGE_BASE" ]]; then
  # Branch may already be merged; try merge-base against the branch's tip.
  MERGE_BASE="$(git -C "$REPO_ROOT" merge-base main "$BRANCH_NAME" 2>/dev/null || true)"
fi
if [[ -z "$MERGE_BASE" ]]; then
  printf "git merge-base main %s returned no commit (branch may not exist locally)\n" "$BRANCH_NAME" >&2
  exit 2
fi

# Resolve branch tip (works whether branch is merged or live).
BRANCH_TIP="$(git -C "$REPO_ROOT" rev-parse "$BRANCH_NAME" 2>/dev/null || true)"
if [[ -z "$BRANCH_TIP" ]]; then
  printf "could not resolve branch tip: %s\n" "$BRANCH_NAME" >&2
  exit 2
fi

# ---- Read version from pkg/VERSION -----------------------------------------
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/pkg/VERSION" 2>/dev/null || echo unknown)"

# ---- Extract milestone title from H1 of MILESTONE-SUMMARY.md ---------------
MILESTONE_TITLE="$(head -1 "$SUMMARY" | sed -E 's/^# *//')"

# ---- Build "What changed" section ------------------------------------------
# For each commit in range, list paths. Drop commit if all paths are tools/-only.
COMMITS="$(git -C "$REPO_ROOT" log --reverse --pretty=format:'%H' "${MERGE_BASE}..${BRANCH_TIP}" 2>/dev/null || true)"

CHANGED_BULLETS=""
while IFS= read -r sha; do
  [[ -z "$sha" ]] && continue
  paths="$(git -C "$REPO_ROOT" diff-tree --no-commit-id --name-only -r "$sha" 2>/dev/null || true)"
  [[ -z "$paths" ]] && continue
  # Determine: are ALL paths under tools/?
  all_tools=1
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    if [[ "$p" != tools/* ]]; then
      all_tools=0
      break
    fi
  done <<<"$paths"
  if [[ "$all_tools" -eq 1 ]]; then
    continue  # drop tools-only commit
  fi
  subject="$(git -C "$REPO_ROOT" log -1 --pretty=format:'%s' "$sha")"
  CHANGED_BULLETS="${CHANGED_BULLETS}- ${subject}"$'\n'
done <<<"$COMMITS"

# ---- Pull "Stories Completed" rows from MILESTONE-SUMMARY.md ---------------
# Canonical section header:  ## Stories Completed
# Alternative section header: ## Commits shipped  (non-canonical — WARN)
STORIES_BULLETS=""
in_stories=0
section_matched=""
while IFS= read -r line; do
  if [[ "$line" =~ ^##[[:space:]]+Stories[[:space:]]+Completed ]]; then
    in_stories=1; section_matched="canonical"; continue
  fi
  if [[ "$line" =~ ^##[[:space:]]+Commits[[:space:]]+shipped ]]; then
    in_stories=1; section_matched="non-canonical"; continue
  fi
  if [[ "$in_stories" -eq 1 ]]; then
    if [[ "$line" =~ ^##[[:space:]] ]]; then
      break
    fi
    # Match data rows of the table: | N | story title | status | files | commit |
    if [[ "$line" =~ ^\|[[:space:]]*[0-9]+[[:space:]]*\|[[:space:]]*([^\|]+)[[:space:]]*\| ]]; then
      story_title="${BASH_REMATCH[1]}"
      story_title="$(printf '%s' "$story_title" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
      # Hardcoded omission: drop story rows that mention maintainer-only
      # script names. Those are validation/regression chores and don't
      # belong in user-facing notes (see plan step 4).
      skip=0
      for forbidden in "smoke-test" "purity-check" "dogfood-brainstorm"; do
        case "$story_title" in
          *"$forbidden"*) skip=1; break ;;
        esac
      done
      [[ "$skip" -eq 1 ]] && continue
      STORIES_BULLETS="${STORIES_BULLETS}- ${story_title}"$'\n'
    fi
  fi
done < "$SUMMARY"

# Emit WARN if non-canonical section was used
if [[ "$section_matched" == "non-canonical" ]]; then
  emit_warn "non-canonical section: '## Commits shipped' found (expected '## Stories Completed'). non-canonical accepted with WARN; will be removed in M020 — pin canonical shape via the MILESTONE-SUMMARY.md template under pkg/.aihaus/templates/"
fi

# ---- Compose the release notes ---------------------------------------------
NOTES=""
NOTES+="# v${VERSION} — ${MILESTONE_TITLE}"$'\n\n'
NOTES+="## Summary"$'\n\n'
NOTES+="${MILESTONE_TITLE}"$'\n\n'
NOTES+="## What changed"$'\n\n'

if [[ -n "$STORIES_BULLETS" ]]; then
  NOTES+="${STORIES_BULLETS}"
fi
if [[ -n "$CHANGED_BULLETS" ]]; then
  NOTES+="${CHANGED_BULLETS}"
fi
if [[ -z "$STORIES_BULLETS" && -z "$CHANGED_BULLETS" ]]; then
  NOTES+="_(no user-facing changes detected)_"$'\n'
fi

# ---- Pre-emit assertion: no maintainer-only leakage ------------------------
LEAK_HITS=""
for forbidden in "smoke-test" "purity-check" "dogfood-brainstorm"; do
  if printf '%s' "$NOTES" | grep -Fq "$forbidden"; then
    LEAK_HITS="${LEAK_HITS} ${forbidden}"
  fi
done
if [[ -n "$LEAK_HITS" ]]; then
  printf "WARNING: generated notes contain maintainer-only string(s):%s\n" "$LEAK_HITS" >&2
  printf "         Edit MILESTONE-SUMMARY.md or filter rule before publishing.\n" >&2
fi

# ---- Emit -----------------------------------------------------------------
if [[ -n "$OUT_FILE" ]]; then
  mkdir -p "$(dirname "$OUT_FILE")"
  printf '%s' "$NOTES" > "$OUT_FILE"
  printf "wrote release notes to %s\n" "$OUT_FILE" >&2
else
  printf '%s' "$NOTES"
fi

# ---- Strict mode: any WARN → exit 1 ----------------------------------------
if [[ "$STRICT" -eq 1 && "$WARN_COUNT" -gt 0 ]]; then
  printf "strict mode: %d WARN(s) treated as errors\n" "$WARN_COUNT" >&2
  exit 1
fi

exit 0
