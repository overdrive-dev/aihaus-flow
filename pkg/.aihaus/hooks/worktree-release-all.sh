#!/usr/bin/env bash
# worktree-release-all.sh — L2 SessionEnd sweep (M017/S02b / ADR-M017-B)
#
# Reads .claude/worktrees/.session-<pid>.owned sentinel (one worktree path per line,
# written at skill entry by S02d wiring). On SessionEnd, classifies + releases each
# listed worktree, then removes the sentinel on full success or retains it on partial
# failure for retry.
#
# Idempotent: missing or already-removed sentinel = exit 0 silently.
# PID-suffixed sentinels prevent concurrent-session collision.
# Exit 0 ALWAYS — never blocks session teardown.
#
# Trigger:   Claude Code SessionEnd event (registered in settings.local.json).
# Inputs:    .claude/worktrees/.session-<pid>.owned — newline-separated worktree paths.
# Outputs:   audit rows in .claude/audit/hook.jsonl  event:"worktree-release-session"
#            result ∈ {pruned, preserved-for-merge, preserved-dirty, warn}
#            PENDING-MERGE.md entry (Category B only)
#            Sentinel removed on full success; retained on partial failure for retry.
#
# Env:
#   AIHAUS_RELEASE_L2=0        — top-of-body no-op short-circuit (ADR-M017-B Rollback)
#   AIHAUS_SESSION_PID         — override PID for sentinel lookup (default: $$)
#   AIHAUS_AUDIT_LOG           — override audit log path (default .claude/audit/hook.jsonl)
#   AIHAUS_MAIN_BRANCH         — override main branch name (default: auto-detect)
#
# classify_only is inlined here (not sourced from worktree-reconcile.sh).
# Rationale (D-002 + K-003): worktree-reconcile.sh has set -euo + exit 0 at the end.
# Sourcing it directly terminates the parent regardless of set +e workarounds; the
# declare -f subshell pattern also fails because exit 0 fires before declare -f runs.
# Inline avoids all sourcing pitfalls. 46-line function is identical to reconcile.sh
# classify_only — keep in sync with worktree-reconcile.sh:88-134 on future edits.
#
# Act logic inlined (not extracted to lib): Category B _emit_pending_merge in L1
# references AGENT_ID from stdin payload; L2 has no agent context, so inlining with
# agent_id:"session-sweep" is cleaner. See D-002 in DECISIONS-LOG.md.
#
# Refs: ADR-M017-B, ADR-004, ADR-001, M017/S02b, K-001, K-003.
# S05 note: Path B (no AIHAUS_PREWORKTREE_PATH injection); classify logic is path-agnostic.

set -euo pipefail

# ---- L2 env bypass (ADR-M017-B Rollback) ------------------------------------
if [ "${AIHAUS_RELEASE_L2:-}" = "0" ]; then exit 0; fi

# ---- config ------------------------------------------------------------------
AUDIT_LOG="${AIHAUS_AUDIT_LOG:-.claude/audit/hook.jsonl}"
MAIN_BRANCH="${AIHAUS_MAIN_BRANCH:-}"

ts_iso() { date -u +%FT%TZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z"; }

# ---- audit helper ------------------------------------------------------------
# log_audit <result> [<reason>] [<worktree_path>] [<category>]
log_audit() {
  local result="${1:-warn}"
  local reason="${2:-null}"
  local wt_path="${3:-}"
  local category="${4:-}"
  mkdir -p "$(dirname "${AUDIT_LOG}")" 2>/dev/null || true
  local reason_json="null"
  [ "${reason}" != "null" ] && reason_json="\"${reason}\""
  local path_json="null"
  [ -n "${wt_path}" ] && path_json="\"${wt_path//\"/\\\"}\""
  local cat_json="null"
  [ -n "${category}" ] && cat_json="\"${category}\""
  printf '{"ts":"%s","hook":"worktree-release-all","event":"worktree-release-session","result":"%s","reason":%s,"worktree_path":%s,"category":%s}\n' \
    "$(ts_iso)" "${result}" "${reason_json}" "${path_json}" "${cat_json}" \
    >> "${AUDIT_LOG}" 2>/dev/null || true
}

# ---- sentinel lookup ---------------------------------------------------------
PID="${AIHAUS_SESSION_PID:-$$}"
SENTINEL=".claude/worktrees/.session-${PID}.owned"

if [ ! -f "${SENTINEL}" ]; then
  # Nothing to sweep — idempotent exit (no audit noise on missing/already-removed sentinel)
  exit 0
fi

# ---- resolve main branch (for classify_only + emit_pending) -----------------
if [ -z "${MAIN_BRANCH}" ]; then
  _sym="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [ -n "${_sym}" ]; then
    MAIN_BRANCH="${_sym##*/}"
  elif git show-ref --verify --quiet refs/heads/main 2>/dev/null; then
    MAIN_BRANCH="main"
  else
    MAIN_BRANCH="pi-port"
  fi
fi

# ---- classify_only: inlined from worktree-reconcile.sh:88-134 (K-001/K-003) -
# Classifies a single worktree path as A, B, or C.
# Returns via stdout + exit 0 on recognised path; non-zero on error.
# Does NOT prune or act — read-only assessment only.
# KEEP IN SYNC with worktree-reconcile.sh classify_only function.
classify_only() {
  local wt_path="$1"

  # Validate the path exists
  if [ -z "$wt_path" ] || [ ! -d "$wt_path" ]; then
    echo "worktree-release-all.sh: classify_only: path not found: ${wt_path}" >&2
    return 1
  fi

  # Check it's a known worktree (appears in git worktree list)
  if ! git worktree list --porcelain 2>/dev/null | grep -q "^worktree ${wt_path}$"; then
    echo "worktree-release-all.sh: classify_only: path is not a git worktree: ${wt_path}" >&2
    return 1
  fi

  # Get SHA for this worktree
  local wt_sha
  wt_sha="$(git worktree list --porcelain 2>/dev/null | awk -v p="${wt_path}" '
    /^worktree / { if ($0 == "worktree " p) { found=1; next } else { found=0 } }
    found && /^HEAD / { sub(/^HEAD /, ""); print; exit }
  ')"

  if [ -z "$wt_sha" ]; then
    echo "worktree-release-all.sh: classify_only: cannot resolve HEAD for: ${wt_path}" >&2
    return 1
  fi

  # Dirty / clean detection
  local dirty_files
  dirty_files="$(git -C "${wt_path}" status --porcelain 2>/dev/null | wc -l | tr -d ' ')" || dirty_files="1"

  if [ "${dirty_files}" -gt 0 ]; then
    echo "C"
    return 0
  fi

  # Clean: check reachability from main
  local commits_not_on_main
  commits_not_on_main="$(git rev-list --count "${MAIN_BRANCH}..${wt_sha}" 2>/dev/null || echo "1")"

  if [ "${commits_not_on_main}" -eq 0 ]; then
    echo "A"
  else
    echo "B"
  fi
  return 0
}

# ---- Category B helper: emit PENDING-MERGE.md entry (mirrors S02a logic) ----
# agent_id is "session-sweep" because L2 has no per-agent context from payload.
_emit_pending_merge_session() {
  local wt_path="$1"

  # Resolve milestone dir from MANIFEST_PATH env or glob
  local milestone_dir=""
  if [ -n "${MANIFEST_PATH:-}" ] && [ -f "${MANIFEST_PATH}" ]; then
    milestone_dir="$(dirname "${MANIFEST_PATH}")"
  else
    for cand in .aihaus/milestones/M0*/RUN-MANIFEST.md; do
      [ -f "${cand}" ] || continue
      if awk '/^## Metadata$/{on=1;next} /^## /{on=0} on && /^status:[[:space:]]*(running|paused)[[:space:]]*$/{found=1;exit} END{exit !found}' "${cand}" 2>/dev/null; then
        milestone_dir="$(dirname "${cand}")"
        break
      fi
    done
  fi

  local pending_file=""
  if [ -n "${milestone_dir}" ]; then
    local exec_dir="${milestone_dir}/execution"
    mkdir -p "${exec_dir}" 2>/dev/null || true
    pending_file="${exec_dir}/PENDING-MERGE.md"
  else
    pending_file=".claude/audit/PENDING-MERGE.md"
    mkdir -p "$(dirname "${pending_file}")" 2>/dev/null || true
  fi

  # Gather branch + commits for cherry-pick recipe
  local wt_sha wt_branch commit_range commits_count
  wt_sha="$(git worktree list --porcelain 2>/dev/null | awk -v p="${wt_path}" '
    /^worktree / { if ($0 == "worktree " p) { found=1; next } else { found=0 } }
    found && /^HEAD / { sub(/^HEAD /, ""); print; exit }
  ' || echo "")"
  wt_branch="$(git worktree list --porcelain 2>/dev/null | awk -v p="${wt_path}" '
    /^worktree / { if ($0 == "worktree " p) { found=1; next } else { found=0 } }
    found && /^branch / { sub(/^branch /, ""); print; exit }
  ' | sed 's|refs/heads/||' || echo "")"
  commit_range="$(git rev-list --reverse "${MAIN_BRANCH}..${wt_sha}" 2>/dev/null | tr '\n' ' ' | sed 's/ $//' || echo "")"
  commits_count="$(git rev-list --count "${MAIN_BRANCH}..${wt_sha}" 2>/dev/null || echo "?")"

  {
    printf '\n## %s — %s\n\n' "$(ts_iso)" "${wt_path}"
    printf '**Agent:** session-sweep (L2 SessionEnd)\n'
    printf '**Branch:** %s\n' "${wt_branch:-detached}"
    printf '**Commits not on %s:** %s\n\n' "${MAIN_BRANCH}" "${commits_count}"
    printf 'Cherry-pick recipe:\n'
    printf '```bash\n'
    printf '# Cherry-pick %s commits from %s onto %s:\n' "${commits_count}" "${wt_branch:-${wt_sha:0:8}}" "${MAIN_BRANCH}"
    [ -n "${commit_range}" ] && printf 'git cherry-pick %s\n' "${commit_range}"
    printf '# Then prune the worktree:\n'
    printf 'git worktree remove --force %s\n' "${wt_path}"
    printf '```\n'
  } >> "${pending_file}" 2>/dev/null || true
}

# ---- sweep loop: release each worktree listed in sentinel -------------------
PARTIAL_FAIL=0

while IFS= read -r worktree_path; do
  # Skip blank lines (tolerant parse)
  [ -z "${worktree_path}" ] && continue

  # ---- guard: path must exist on disk ---------------------------------------
  if [ ! -d "${worktree_path}" ]; then
    log_audit "warn" "worktree-path-missing" "${worktree_path}" ""
    echo "worktree-release-all.sh: WARN worktree path not found (stale sentinel entry): ${worktree_path}" >&2
    # Treat stale paths as already-released — don't block sentinel removal
    continue
  fi

  # ---- classify the worktree ------------------------------------------------
  CATEGORY=""
  if ! CATEGORY="$(classify_only "${worktree_path}" 2>/dev/null)"; then
    log_audit "warn" "classify-failed" "${worktree_path}" ""
    echo "worktree-release-all.sh: WARN classify_only failed for ${worktree_path}; preserving for L4" >&2
    # Leave lock intact for L4 reap — this is a partial failure
    PARTIAL_FAIL=1
    continue
  fi

  # ---- act on category BEFORE releasing lock --------------------------------
  case "${CATEGORY}" in

    A)
      # Clean + merged → prune
      if git worktree remove --force "${worktree_path}" 2>/dev/null; then
        log_audit "pruned" "null" "${worktree_path}" "A"
      else
        # Windows path-lock Category-C fallthrough (reconcile.sh:146-147 pattern)
        log_audit "preserved-dirty" "remove-failed-windows-path-lock" "${worktree_path}" "A→C"
        echo "worktree-release-all.sh: WARN git worktree remove failed for ${worktree_path}; preserved (Windows path-lock?)" >&2
        PARTIAL_FAIL=1
      fi
      ;;

    B)
      # Clean + unmerged commits → emit PENDING-MERGE.md entry, preserve worktree
      if _emit_pending_merge_session "${worktree_path}" 2>/dev/null; then
        log_audit "preserved-for-merge" "null" "${worktree_path}" "B"
      else
        log_audit "preserved-for-merge" "pending-merge-write-failed" "${worktree_path}" "B"
        echo "worktree-release-all.sh: WARN failed to write PENDING-MERGE entry for ${worktree_path}" >&2
      fi
      ;;

    C)
      # Dirty → preserve + flag
      log_audit "preserved-dirty" "null" "${worktree_path}" "C"
      echo "worktree-release-all.sh: [CATEGORY C] ${worktree_path} — dirty; preserved for manual review." >&2
      ;;

    *)
      # Unknown category — warn + preserve
      log_audit "warn" "unknown-category:${CATEGORY}" "${worktree_path}" "${CATEGORY}"
      echo "worktree-release-all.sh: WARN unknown category '${CATEGORY}' for ${worktree_path}" >&2
      PARTIAL_FAIL=1
      ;;
  esac

  # ---- release lock LAST (partial failure above leaves lock for L4) ---------
  # For Category A (pruned), worktree is already gone — unlock is a no-op (silenced).
  # For B and C, unlock allows L4 reap to operate on the worktree later.
  git worktree unlock "${worktree_path}" 2>/dev/null || true

done < "${SENTINEL}"

# ---- sentinel cleanup -------------------------------------------------------
if [ "${PARTIAL_FAIL}" = "0" ]; then
  # Full success — remove sentinel so re-run is a silent no-op
  rm -f "${SENTINEL}"
fi
# On partial failure, sentinel is retained for next-boot retry (L4 reap catches remnants).

exit 0
