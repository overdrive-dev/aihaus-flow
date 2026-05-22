#!/usr/bin/env bash
# manifest-auto-close.sh — deterministic enforcement hook for closing stale manifests.
#
# Purpose:
#   Flips a feature/bugfix/milestone manifest's Status to "completed" IFF five
#   provable-done conditions hold simultaneously (ADR-260502-A):
#     1. Status ∈ {running, awaiting-approval, awaiting-merge}
#     2. Branch field exists locally OR remotely
#     3. Branch is ancestor of at least one integration ref (lib/integration-refs.sh)
#     4. SUMMARY.md exists OR last Story Records row has verified=true
#     5. Crash-resume guard: no unmatched event=enter in ## Checkpoints
#
# Usage:
#   manifest-auto-close.sh [--dry-run] [--manifest <path>]
#   manifest-auto-close.sh --help
#
# Modes:
#   (default)         Full sweep: .aihaus/{milestones,features,bugfixes}/*/RUN-MANIFEST.md
#   --manifest <path> Single-target mode (used by merge-back.sh after release-before-spawn).
#   --dry-run         Report candidate count to stdout; zero mutation, zero audit.
#
# Exit codes:
#   0   OK (one or more mutations OR full sweep with no-mutations)
#   2   Bad arguments
#   3   Nothing to close (no eligible manifests; idempotent re-invocation)
#   4   Partial failure (some closed, some refused/erred)
#
# Audit log: .claude/audit/hook.jsonl — one JSON line per decision.
# ADR: ADR-260502-A in pkg/.aihaus/decisions.md
# Invariants: I-01 .. I-13 in architecture.md §3
set -euo pipefail

# ---- resolve script directory (for sourcing helpers) --------------------------
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- source shared library ---------------------------------------------------
# shellcheck source=lib/manifest-helpers.sh
. "${HOOK_DIR}/lib/manifest-helpers.sh"
# shellcheck source=lib/path-helpers.sh
. "${HOOK_DIR}/lib/path-helpers.sh"

# ---- source integration-ref helper (S01) -------------------------------------
# shellcheck source=lib/integration-refs.sh
. "${HOOK_DIR}/lib/integration-refs.sh"

# ---- configuration -----------------------------------------------------------
AUDIT_LOG="$(aihaus_project_path "${AIHAUS_AUDIT_LOG:-.claude/audit/hook.jsonl}")"

# ---- argument parsing --------------------------------------------------------
DRY_RUN=0
SINGLE_MANIFEST=""

_usage() {
  printf 'Usage: manifest-auto-close.sh [--dry-run] [--manifest <path>]\n'
  printf '       manifest-auto-close.sh --help\n'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --manifest)
      [[ $# -ge 2 ]] || { printf 'manifest-auto-close.sh: --manifest requires a path\n' >&2; exit 2; }
      SINGLE_MANIFEST="$2"
      shift 2
      ;;
    --help)
      _usage
      exit 0
      ;;
    *)
      printf 'manifest-auto-close.sh: unknown argument: %s\n' "$1" >&2
      _usage >&2
      exit 2
      ;;
  esac
done

# ---- locate git root (for relative path reporting) ---------------------------
GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"

# ---- ISO timestamp -----------------------------------------------------------
ts_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# ---- emit one audit line -----------------------------------------------------
# Args: manifest_path branch integration_ref result reason
emit_audit() {
  local mp="$1" br="$2" ir="$3" res="$4" rsn="$5"
  mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true
  # JSON-encode: replace backslash then double-quote (minimal encoding for path/branch).
  local mp_esc br_json ir_json
  mp_esc="${mp//\\/\\\\}"; mp_esc="${mp_esc//\"/\\\"}"
  if [[ -z "$br" ]]; then
    br_json="null"
  else
    local br_esc="${br//\\/\\\\}"; br_esc="${br_esc//\"/\\\"}"; br_json="\"${br_esc}\""
  fi
  if [[ -z "$ir" ]]; then
    ir_json="null"
  else
    local ir_esc="${ir//\\/\\\\}"; ir_esc="${ir_esc//\"/\\\"}"; ir_json="\"${ir_esc}\""
  fi
  printf '{"ts":"%s","hook":"manifest-auto-close","manifest_path":"%s","branch":%s,"integration_ref":%s,"result":"%s","reason":"%s"}\n' \
    "$(ts_now)" "$mp_esc" "$br_json" "$ir_json" "$res" "$rsn" \
    >> "$AUDIT_LOG" 2>/dev/null || true
}

# ---- parse a metadata key from a v3/v4 manifest (simple awk, no shell-isms) --
# Args: key path
# Stdout: value (stripped), or empty if absent
read_metadata_kv() {
  local k="$1" f="$2"
  awk -v k="$k" '
    /^## Metadata$/ { on=1; next }
    /^## /          { on=0 }
    on && $1 == k":" {
      sub(/^[^:]*:[[:space:]]*/,"")
      gsub(/[[:space:]]*$/,"")
      print; exit
    }
  ' "$f" 2>/dev/null || true
}

# Read either v3/v4 "## Metadata" blocks or legacy YAML frontmatter without
# mutating the manifest. Session-start sweeps must inspect stale files without
# bumping schemas as a side effect.
read_manifest_kv() {
  local k="$1" f="$2" val
  val="$(read_metadata_kv "$k" "$f")"
  if [[ -n "$val" ]]; then
    printf '%s\n' "$val"
    return 0
  fi
  awk -v k="$k" '
    BEGIN { want = tolower(k) ":" }
    {
      key = tolower($1)
      if (key == want) {
        sub(/^[^:]*:[[:space:]]*/, "")
        gsub(/[[:space:]]*$/, "")
        print
        exit
      }
    }
  ' "$f" 2>/dev/null || true
}

# ---- condition 1: eligibility filter -----------------------------------------
# Returns 0 if status is in the promotable set; prints reason if terminal.
# Eligible: running | awaiting-approval | awaiting-merge (F6 absorption from S07)
# Per Q-4: the full v4 vocabulary is recognized from day one; only the promotable
# subset changes between PR1 and PR2.
check_status_eligible() {
  local status="$1"
  case "$status" in
    running|awaiting-approval|awaiting-merge)
      return 0
      ;;
    completed|cancelled|deferred|paused|paused-user-input)
      return 1
      ;;
    "")
      return 1
      ;;
    *)
      # Unknown value — treat as ineligible (fail safe).
      return 1
      ;;
  esac
}

# Determine the skip/refused reason for a non-eligible status
status_skip_reason() {
  local status="$1"
  case "$status" in
    completed|cancelled|deferred)
      printf 'already-terminal'
      ;;
    paused|paused-user-input)
      printf 'paused-explicit'
      ;;
    *)
      printf 'already-terminal'
      ;;
  esac
}

# ---- condition 2: branch field exists locally or remotely -------------------
# Args: branch_name
# Returns 0 if branch resolves; 1 otherwise
check_branch_exists() {
  local branch="$1"
  git rev-parse --verify "$branch" >/dev/null 2>&1 && return 0
  git rev-parse --verify "origin/$branch" >/dev/null 2>&1 && return 0
  # Also try remote with refs/remotes prefix stripped already
  git rev-parse --verify "refs/remotes/$branch" >/dev/null 2>&1 && return 0
  return 1
}

# ---- condition 4: SUMMARY.md present OR last Story Records row verified=true --
# Args: manifest_path
# Returns 0 if evidence found; 1 otherwise
check_completion_evidence() {
  local manifest="$1"
  local run_dir
  run_dir="$(dirname "$manifest")"

  # SUMMARY.md present?
  if [[ -f "${run_dir}/SUMMARY.md" ]]; then
    return 0
  fi

  # Fallback: awk-parse last ## Story Records data row column 5 (verified)
  # Table format: | S01 | name | phase | status | verified |
  # We look for the last non-header, non-separator table row and check col 5.
  local last_verified
  last_verified="$(awk '
    /^## Story Records/ { in_sec=1; next }
    /^## /              { in_sec=0 }
    in_sec && /^\|/ && !/^\|[-: ]*$/ && !/^\| *#/ && !/^\| *story/ && !/^\| *S[[:space:]]/ {
      # Last data row — overwrite each time
      last=$0
    }
    END {
      if (last == "") exit 1
      # Split on | and get the 5th field (verified column)
      n = split(last, cols, "|")
      # cols[1] is empty (leading |), cols[2]=story, cols[3]=name, cols[4]=phase, cols[5]=status, cols[6]=verified
      # But table column order depends on manifest version; try to find verified
      for (i=2; i<=n; i++) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", cols[i])
        if (cols[i] == "true") { found=1 }
      }
      if (found) exit 0
      exit 1
    }
  ' "$manifest" 2>/dev/null)"
  local rc=$?
  [[ $rc -eq 0 ]] && return 0

  # More targeted: look specifically for column 5 = "true" in Story Records
  local verified_found
  verified_found="$(awk '
    /^## Story Records/ { in_sec=1; header_count=0; next }
    /^## /              { in_sec=0 }
    in_sec && /^\|/ {
      if (/^\|[-: ]*$/) next          # separator row
      # Count as data row if it has non-header content
      if (header_count == 0) { header_count=1; next }  # skip first row (header)
      last=$0
    }
    END {
      if (last == "") exit 1
      n = split(last, cols, "|")
      # Look for "true" in any column
      for (i=2; i<=n; i++) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", cols[i])
        if (cols[i] == "true") exit 0
      }
      exit 1
    }
  ' "$manifest" 2>/dev/null)" || true

  local awk_exit=$?
  # The above awk approach doesn't cleanly return — use a different approach
  # Simply check if any data row in Story Records has a "true" in column 5 (verified)
  local has_verified
  has_verified="$(awk '
    BEGIN { in_sec=0; rows=0; found=0 }
    /^## Story Records/ { in_sec=1; next }
    /^## /              { in_sec=0 }
    in_sec && /^\|/ {
      if (/^\|[- :]*\|/) next
      rows++
      if (rows == 1) next  # header row
      # Extract columns - split by |
      row = $0
      n = split(row, cols, "|")
      for (i=2; i<=n; i++) {
        v = cols[i]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        if (v == "true") { found=1 }
      }
    }
    END { if (found) print "yes" }
  ' "$manifest" 2>/dev/null || true)"

  if [[ "$has_verified" == "yes" ]]; then
    return 0
  fi

  return 1
}

# ---- condition 5: crash-resume guard ----------------------------------------
# Scans ## Checkpoints for unmatched enter rows.
# An "enter" row is unmatched if no "exit" row exists for the same (story,agent,substep).
# Args: manifest_path
# Returns 0 if no unmatched enters (safe to close); 1 if unmatched enters exist
check_crash_resume_guard() {
  local manifest="$1"
  # Parse ## Checkpoints section.
  # Row format: | ts | story | agent | substep | event | result | sha |
  # We collect all (story,agent,substep) triples from enter rows and exit rows.
  # If any enter triple has no matching exit triple -> refuse.
  local result
  result="$(awk '
    BEGIN { in_cp=0 }
    /^## Checkpoints$/ { in_cp=1; next }
    /^## /             { in_cp=0 }
    in_cp && /^\|/ {
      if (/^\|[- :]*\|/) next     # separator
      if (/^\| *ts *\|/)  next    # header
      # Split row into cols
      n = split($0, cols, "|")
      # cols: [1]empty [2]ts [3]story [4]agent [5]substep [6]event [7]result [8]sha
      if (n < 7) next
      story   = cols[3]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", story)
      agent   = cols[4]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", agent)
      substep = cols[5]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", substep)
      event   = cols[6]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", event)
      key = story SUBSEP agent SUBSEP substep
      if (event == "enter") {
        enters[key] = 1
      } else if (event == "exit") {
        exits[key] = 1
      }
    }
    END {
      for (k in enters) {
        if (!(k in exits)) {
          print "unmatched:" k
        }
      }
    }
  ' "$manifest" 2>/dev/null || true)"

  if [[ -n "$result" ]]; then
    return 1
  fi
  return 0
}

# ---- process a single manifest -----------------------------------------------
# Args: manifest_path
# Side-effects: may mutate manifest, always emits audit (unless dry-run)
# Returns:
#   0 = closed (mutation happened)
#   3 = skipped or refused (no mutation)
#   4 = error
process_manifest() {
  local manifest="$1"

  # --- Step 1: Parse metadata without mutation -------------------------------
  local status branch
  status="$(read_manifest_kv "status" "$manifest")"
  branch="$(read_manifest_kv "branch" "$manifest")"

  local mp_disp="$manifest"
  [[ -n "$GIT_ROOT" ]] && mp_disp="${manifest#${GIT_ROOT}/}"

  # --- Step 3: Eligibility filter (condition 1) -------------------------------
  if ! check_status_eligible "$status"; then
    local skip_rsn
    skip_rsn="$(status_skip_reason "$status")"
    [[ $DRY_RUN -eq 0 ]] && emit_audit "$mp_disp" "$branch" "" "skipped" "$skip_rsn"
    return 3
  fi

  # --- Step 4: Branch field check (condition 2) --------------------------------
  if [[ -z "$branch" ]]; then
    [[ $DRY_RUN -eq 0 ]] && emit_audit "$mp_disp" "" "" "refused" "branch-missing"
    return 3
  fi
  if ! check_branch_exists "$branch"; then
    [[ $DRY_RUN -eq 0 ]] && emit_audit "$mp_disp" "$branch" "" "refused" "branch-missing"
    return 3
  fi

  # --- Step 5: Integration-ref ancestry (condition 3) -------------------------
  # Override mechanism for testing: AIHAUS_INTEGRATION_REFS_OVERRIDE
  local int_refs_list
  if [[ -n "${AIHAUS_INTEGRATION_REFS_OVERRIDE+x}" ]]; then
    # Allow empty override (means no refs — simulates F-NO-INTEGRATION-REF)
    int_refs_list="$AIHAUS_INTEGRATION_REFS_OVERRIDE"
  else
    int_refs_list="$(detect_integration_refs)"
  fi

  if [[ -z "$int_refs_list" ]]; then
    [[ $DRY_RUN -eq 0 ]] && emit_audit "$mp_disp" "$branch" "" "skipped" "no-integration-ref"
    return 3
  fi

  # Try each integration ref
  local matched_ref=""
  while IFS= read -r iref; do
    [[ -z "$iref" ]] && continue
    if is_branch_merged_into_any "$branch" "$iref"; then
      matched_ref="$iref"
      break
    fi
  done <<< "$int_refs_list"

  if [[ -z "$matched_ref" ]]; then
    [[ $DRY_RUN -eq 0 ]] && emit_audit "$mp_disp" "$branch" "" "skipped" "branch-not-merged"
    return 3
  fi

  # --- Step 6: SUMMARY-or-verified (condition 4) -------------------------------
  if ! check_completion_evidence "$manifest"; then
    [[ $DRY_RUN -eq 0 ]] && emit_audit "$mp_disp" "$branch" "$matched_ref" "refused" "no-completion-evidence"
    return 3
  fi

  # --- Step 7: Crash-resume guard (condition 5) --------------------------------
  if ! check_crash_resume_guard "$manifest"; then
    [[ $DRY_RUN -eq 0 ]] && emit_audit "$mp_disp" "$branch" "$matched_ref" "refused" "unmatched-enter"
    return 3
  fi

  # --- All five conditions hold: promote to completed -------------------------
  if [[ $DRY_RUN -eq 1 ]]; then
    return 0
  fi

  # Only migrate after every close condition holds. Session-start sweeps must
  # not churn skipped/refused historical manifests just to inspect them.
  if ! MANIFEST_PATH="$manifest" bash "${HOOK_DIR}/manifest-migrate.sh" >/dev/null 2>&1; then
    emit_audit "$mp_disp" "$branch" "$matched_ref" "refused" "migration-failed"
    return 3
  fi
  status="$(read_manifest_kv "status" "$manifest")"
  branch="$(read_manifest_kv "branch" "$manifest")"

  # Determine reason text based on source status
  local close_reason
  case "$status" in
    running)             close_reason="running-promotion" ;;
    awaiting-approval)   close_reason="awaiting-approval-promotion" ;;
    awaiting-merge)      close_reason="awaiting-merge-promotion" ;;
    *)                   close_reason="running-promotion" ;;
  esac

  # Acquire coarse lock (I-01 / AC-05 / I-03)
  detect_platform
  detect_fractional_sleep
  export MANIFEST_PATH="$manifest"
  if ! acquire_coarse_lock "$manifest"; then
    emit_audit "$mp_disp" "$branch" "$matched_ref" "refused" "lock-timeout"
    return 3
  fi

  # Mutate: update_metadata_kv + last_updated (AC-05 / I-01)
  update_metadata_kv "status" "completed"
  update_metadata_kv "last_updated" "$(ts_now)"

  # Release lock (Windows explicit release; POSIX auto-releases on fd close)
  release_coarse_lock "$manifest"

  emit_audit "$mp_disp" "$branch" "$matched_ref" "closed" "$close_reason"
  return 0
}

# ---- collect manifests -------------------------------------------------------
declare -a MANIFESTS=()

if [[ -n "$SINGLE_MANIFEST" ]]; then
  if [[ ! -f "$SINGLE_MANIFEST" ]]; then
    printf 'manifest-auto-close.sh: manifest not found: %s\n' "$SINGLE_MANIFEST" >&2
    exit 2
  fi
  MANIFESTS=("$SINGLE_MANIFEST")
else
  # Full sweep: glob .aihaus/{milestones,features,bugfixes}/*/RUN-MANIFEST.md
  # Resolve from git root (preferred) or cwd
  sweep_root="${GIT_ROOT:-.}"
  for subdir in milestones features bugfixes; do
    sweep_pattern="${sweep_root}/.aihaus/${subdir}/*/RUN-MANIFEST.md"
    for f in $sweep_pattern; do
      [[ -f "$f" ]] && MANIFESTS+=("$f")
    done
  done
fi

# ---- dry-run mode: just count eligible candidates ---------------------------
if [[ $DRY_RUN -eq 1 ]]; then
  count=0
  for m in "${MANIFESTS[@]+"${MANIFESTS[@]}"}"; do
    # Quick status check (no migration in dry-run)
    s="$(read_manifest_kv "status" "$m")"
    check_status_eligible "$s" && count=$((count + 1)) || true
  done
  printf 'manifest-auto-close: %d candidate(s) eligible for auto-close\n' "$count"
  exit 0
fi

# ---- full processing ---------------------------------------------------------
closed=0
refused=0
errors=0

for m in "${MANIFESTS[@]+"${MANIFESTS[@]}"}"; do
  rc=0
  process_manifest "$m" || rc=$?
  case $rc in
    0) closed=$((closed + 1)) ;;
    3) ;;   # skipped / refused — audit already written
    4) errors=$((errors + 1)) ;;
    *) errors=$((errors + 1)) ;;
  esac
done

# ---- determine exit code -----------------------------------------------------
total=$((${#MANIFESTS[@]}))
if [[ $total -eq 0 || ($closed -eq 0 && $errors -eq 0) ]]; then
  exit 3   # nothing eligible / nothing closed
fi

if [[ $errors -gt 0 && $closed -gt 0 ]]; then
  exit 4   # partial failure
fi

if [[ $errors -gt 0 && $closed -eq 0 ]]; then
  exit 4   # all failed
fi

exit 0   # all good; at least one closed
