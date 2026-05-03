#!/usr/bin/env sh
# lib/integration-refs.sh — shared helper: integration-ref detection + branch-ancestry test
#
# Purpose:
#   Single source of truth for resolving which refs count as "integration ancestors"
#   and testing whether a branch has been merged into any of them.
#   Consumed by manifest-auto-close.sh (S02), aih-resume step 4b (S05),
#   and worktree-reconcile.sh (S09).
#
# Contract:
#   - POSIX sh only. No bash-isms ([[ ]], arrays, +=, <<<).
#   - Sourceable without side effects. No top-level cd, set -e, or git mutations.
#   - All diagnostic output guarded by AIHAUS_DEBUG=1; silent by default.
#   - Every emitted ref passes `git rev-parse --verify` before emission.
#   - Empty stdout from detect_integration_refs is valid; callers treat as
#     result=skipped reason=no-integration-ref (NFR-06 / I-05).
#
# References:
#   - ADR-260502-B in pkg/.aihaus/decisions.md (integration-branch awareness)
#   - architecture.md §6.3 (API spec)
#   - analysis-brief.md Appendix (R-4: origin/HEAD fragility)

# ---- internal diagnostic logger -----------------------------------------------
# Writes to stderr only when AIHAUS_DEBUG=1. Silent in normal operation (AC-06).
_int_log() {
  if [ "${AIHAUS_DEBUG:-0}" = "1" ]; then
    printf '[integration-refs] %s\n' "$*" >&2
  fi
}

# ---- detect_integration_refs --------------------------------------------------
# Emits one ref per line on stdout in priority order:
#   (1) integration_branches: field from .aihaus/project.md MANUAL section
#   (2) target of git symbolic-ref refs/remotes/origin/HEAD
#   (3) fallback list: origin/staging origin/main origin/develop origin/dev
#
# Every candidate is filtered through git rev-parse --verify before emission.
# Duplicates are dropped (first occurrence wins).
# Always exits 0 — empty output is a valid result.
#
# Args: none
# Returns: 0 always
# Stdout: verified refs, one per line, highest priority first
# Stderr: silent unless AIHAUS_DEBUG=1
detect_integration_refs() {
  _int_log "detect_integration_refs: start"

  # Accumulate candidates in a newline-separated string (POSIX, no arrays).
  _candidates=""

  # --- Priority 1: integration_branches: from project.md MANUAL block ---------
  # Locate project.md relative to git root (handles being called from any subdir).
  _git_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  _project_md=""
  if [ -n "$_git_root" ] && [ -f "${_git_root}/.aihaus/project.md" ]; then
    _project_md="${_git_root}/.aihaus/project.md"
  fi

  if [ -n "$_project_md" ]; then
    # Extract the MANUAL block content and look for integration_branches: within it.
    # We read line-by-line: once inside the MANUAL block, capture until MANUAL-END.
    _in_manual=0
    _branch_line=""
    while IFS= read -r _line; do
      case "$_line" in
        *'AIHAUS:MANUAL-START'*)
          _in_manual=1
          ;;
        *'AIHAUS:MANUAL-END'*)
          _in_manual=0
          ;;
        *)
          if [ "$_in_manual" = "1" ]; then
            case "$_line" in
              integration_branches:*)
                _branch_line="$_line"
                ;;
            esac
          fi
          ;;
      esac
    done < "$_project_md"

    if [ -n "$_branch_line" ]; then
      _int_log "detect_integration_refs: found integration_branches line: $_branch_line"
      # Extract the list inside [...] or bare after the colon.
      # Format: integration_branches: [origin/staging, origin/main, origin/release/2026]
      # Strip key, brackets, and split on comma or whitespace.
      _list="${_branch_line#integration_branches:}"
      # Remove leading/trailing brackets and spaces.
      _list="$(printf '%s' "$_list" | tr -d '[]' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')"
      # Split on comma or whitespace; process each token.
      # Use tr to normalize separators to newlines.
      _old_IFS="$IFS"
      IFS=','
      for _entry in $_list; do
        # Trim surrounding whitespace from each entry.
        _ref="$(printf '%s' "$_entry" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')"
        if [ -n "$_ref" ]; then
          _candidates="${_candidates}${_ref}
"
        fi
      done
      IFS="$_old_IFS"
    fi
  fi

  # --- Priority 2: git symbolic-ref refs/remotes/origin/HEAD ------------------
  _sym_ref="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [ -n "$_sym_ref" ]; then
    # symbolic-ref returns refs/remotes/origin/main — convert to remote tracking form.
    # Strip leading refs/remotes/ to get origin/main.
    _sym_ref_short="${_sym_ref#refs/remotes/}"
    _int_log "detect_integration_refs: symbolic-ref -> $_sym_ref_short"
    _candidates="${_candidates}${_sym_ref_short}
"
  else
    _int_log "detect_integration_refs: no symbolic-ref origin/HEAD"
  fi

  # --- Priority 3: static fallback list ----------------------------------------
  for _fallback in origin/staging origin/main origin/develop origin/dev; do
    _candidates="${_candidates}${_fallback}
"
  done

  # --- Verify + deduplicate (first occurrence wins) ----------------------------
  _seen=""
  _output=""
  # Process candidates line by line.
  _old_IFS2="$IFS"
  IFS='
'
  for _cand in $_candidates; do
    # Skip empty lines.
    if [ -z "$_cand" ]; then
      continue
    fi
    # Deduplication check: skip if already seen.
    _dup=0
    _old_IFS3="$IFS"
    IFS='
'
    for _s in $_seen; do
      if [ "$_s" = "$_cand" ]; then
        _dup=1
        break
      fi
    done
    IFS="$_old_IFS3"
    if [ "$_dup" = "1" ]; then
      _int_log "detect_integration_refs: skip duplicate $_cand"
      continue
    fi
    # Record as seen.
    _seen="${_seen}${_cand}
"
    # Verify ref exists.
    if git rev-parse --verify "$_cand" >/dev/null 2>&1; then
      _int_log "detect_integration_refs: verified $_cand"
      _output="${_output}${_cand}
"
    else
      _int_log "detect_integration_refs: drop unverified $_cand"
    fi
  done
  IFS="$_old_IFS2"

  # Emit verified refs (strip trailing newline via printf).
  if [ -n "$_output" ]; then
    printf '%s' "$_output"
  fi
  # Always exit 0 (AC-04).
  return 0
}

# ---- is_branch_merged_into_any ------------------------------------------------
# Tests whether <branch> is an ancestor of any of the provided refs.
# Iterates refs in argument order; first match wins.
#
# Args: <branch-or-sha> <ref1> [<ref2> ...]
# Returns: 0 if any ref contains <branch>; prints matching ref to stdout.
#          1 if no ref contains <branch>; empty stdout.
# Stderr: silent unless AIHAUS_DEBUG=1
is_branch_merged_into_any() {
  _imb_branch="$1"
  shift
  _int_log "is_branch_merged_into_any: branch=$_imb_branch refs=$*"
  for _imb_ref in "$@"; do
    if git merge-base --is-ancestor "$_imb_branch" "$_imb_ref" 2>/dev/null; then
      _int_log "is_branch_merged_into_any: match on $_imb_ref"
      printf '%s\n' "$_imb_ref"
      return 0
    fi
  done
  _int_log "is_branch_merged_into_any: no match"
  return 1
}
