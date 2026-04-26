#!/usr/bin/env bash
# worktree-release.sh — L1 SubagentStop hook (M017/S02a / ADR-M017-B)
#
# Classifies the exiting agent's worktree (A/B/C) via classify_only from
# worktree-reconcile.sh, acts (A=prune, B=emit PENDING-MERGE entry, C=preserve+flag),
# then releases the lock LAST so partial failures leave locks for L4 reap.
#
# Exit 0 ALWAYS — never blocks subsequent Agent spawns.
# Failures emit WARN to stderr + audit row with result:"warn".
#
# Trigger:   Claude Code SubagentStop event (registered in settings.local.json).
# Stdin:     JSON payload: { session_id, agent_id, agent_name, worktree_path?,
#                            exit_status, task_description, last_assistant_message, ... }
# Outputs:   audit row in .claude/audit/hook.jsonl  event:"worktree-release"
#            result ∈ {pruned, preserved-for-merge, preserved-dirty, warn}
#            PENDING-MERGE.md entry (Category B only)
#
# Env:
#   AIHAUS_RELEASE_L1=0        — top-of-body no-op short-circuit (ADR-M017-B Rollback)
#   AIHAUS_AUDIT_LOG           — override audit log path (default .claude/audit/hook.jsonl)
#
# Covers all 5 isolation:worktree agents (implementer, frontend-dev, code-fixer,
# executor, nyquist-auditor) — identity-agnostic via worktree_path in payload.
#
# Windows path-lock: if git worktree remove fails after classify Category A,
# falls through to Category C (preserved) per reconcile.sh:146-147 pattern.
#
# Refs: ADR-M017-B, ADR-004, ADR-001, M017/S02a.
# S01 note: P1 verified that git worktree unlock works externally (RESEARCH-harness.md).
# S05 note: P2+P3 are VERIFIED-no → NON-UNANIMOUS → Path B (no AIHAUS_PREWORKTREE_PATH
#           injection). This hook does NOT branch on AIHAUS_PREWORKTREE_PATH; S05 ships
#           Path B only. The classify_only logic is path-agnostic regardless.

set -euo pipefail

# ---- L1 env bypass (ADR-M017-B Rollback) ------------------------------------
if [ "${AIHAUS_RELEASE_L1:-}" = "0" ]; then exit 0; fi

# ---- config -----------------------------------------------------------------
AUDIT_LOG="${AIHAUS_AUDIT_LOG:-.claude/audit/hook.jsonl}"

ts_iso() { date -u +%FT%TZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z"; }

# ---- audit helper -----------------------------------------------------------
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
  printf '{"ts":"%s","hook":"worktree-release","event":"worktree-release","result":"%s","reason":%s,"worktree_path":%s,"category":%s}\n' \
    "$(ts_iso)" "${result}" "${reason_json}" "${path_json}" "${cat_json}" \
    >> "${AUDIT_LOG}" 2>/dev/null || true
}

# ---- parse SubagentStop stdin JSON ------------------------------------------
PAYLOAD="$(cat)"

WORKTREE_PATH=""
AGENT_ID=""

if command -v jq >/dev/null 2>&1; then
  # Try common field names from the SubagentStop schema
  WORKTREE_PATH="$(printf '%s' "${PAYLOAD}" | jq -r '.worktree_path // empty' 2>/dev/null || true)"
  AGENT_ID="$(printf '%s' "${PAYLOAD}" | jq -r '.agent_id // .agent_name // .name // empty' 2>/dev/null || true)"
else
  # Fallback: grep for worktree_path without jq
  WORKTREE_PATH="$(printf '%s' "${PAYLOAD}" | grep -o '"worktree_path"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"worktree_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)"
  AGENT_ID="$(printf '%s' "${PAYLOAD}" | grep -o '"agent_id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"agent_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)"
fi

# ---- guard: no worktree_path in payload → no-op exit 0 ---------------------
if [ -z "${WORKTREE_PATH}" ]; then
  # Not an isolation:worktree agent (path absent from payload) — silent no-op
  exit 0
fi

# ---- guard: worktree path must exist on disk --------------------------------
if [ ! -d "${WORKTREE_PATH}" ]; then
  # Path gone — stale reference; emit warn audit but don't fail
  log_audit "warn" "worktree-path-missing" "${WORKTREE_PATH}" ""
  echo "worktree-release.sh: WARN worktree path not found: ${WORKTREE_PATH}" >&2
  exit 0
fi

# ---- guard: non-git-dir -----------------------------------------------------
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  log_audit "warn" "not-a-git-repo" "${WORKTREE_PATH}" ""
  exit 0
fi

# ---- source classify_only from worktree-reconcile.sh -----------------------
# shellcheck source=./worktree-reconcile.sh
RECONCILE_SH="$(dirname "$0")/worktree-reconcile.sh"
if [ ! -f "${RECONCILE_SH}" ]; then
  log_audit "warn" "reconcile-sh-missing" "${WORKTREE_PATH}" ""
  echo "worktree-release.sh: WARN worktree-reconcile.sh not found at ${RECONCILE_SH}" >&2
  # Cannot classify — preserve + flag for L4, then release lock
  git worktree unlock "${WORKTREE_PATH}" 2>/dev/null || true
  exit 0
fi
# Source to import classify_only function (script guards set -euo internally; reset after)
set +euo 2>/dev/null || true
# shellcheck disable=SC1090
. "${RECONCILE_SH}" 2>/dev/null || true
set -euo pipefail

# ---- classify the worktree --------------------------------------------------
CATEGORY=""
if ! CATEGORY="$(classify_only "${WORKTREE_PATH}" 2>/dev/null)"; then
  log_audit "warn" "classify-failed" "${WORKTREE_PATH}" ""
  echo "worktree-release.sh: WARN classify_only failed for ${WORKTREE_PATH}; preserving for L4" >&2
  # Leave lock intact for L4 reap — do NOT unlock on classify failure
  exit 0
fi

# ---- act on category BEFORE releasing lock ----------------------------------
case "${CATEGORY}" in

  A)
    # Clean + merged → prune
    if git worktree remove --force "${WORKTREE_PATH}" 2>/dev/null; then
      log_audit "pruned" "null" "${WORKTREE_PATH}" "A"
    else
      # Windows path-lock Category-C fallthrough (reconcile.sh:146-147 pattern)
      log_audit "preserved-dirty" "remove-failed-windows-path-lock" "${WORKTREE_PATH}" "A→C"
      echo "worktree-release.sh: WARN git worktree remove failed for ${WORKTREE_PATH}; preserved (Windows path-lock?)" >&2
    fi
    ;;

  B)
    # Clean + unmerged commits → emit PENDING-MERGE.md entry, preserve worktree
    _emit_pending_merge() {
      # Resolve milestone dir from MANIFEST_PATH or glob
      local milestone_dir=""
      if [ -n "${MANIFEST_PATH:-}" ] && [ -f "${MANIFEST_PATH}" ]; then
        milestone_dir="$(dirname "${MANIFEST_PATH}")"
      else
        # Best-effort glob for running milestone
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

      # Get worktree branch + commits-not-on-main for recipe
      local wt_sha wt_branch commit_range main_br commits_count
      # Detect main branch (quick version — env override or default "main")
      main_br="${AIHAUS_MAIN_BRANCH:-main}"
      wt_sha="$(git worktree list --porcelain 2>/dev/null | awk -v p="${WORKTREE_PATH}" '
        /^worktree / { if ($0 == "worktree " p) { found=1; next } else { found=0 } }
        found && /^HEAD / { sub(/^HEAD /, ""); print; exit }
      ' || echo "")"
      wt_branch="$(git worktree list --porcelain 2>/dev/null | awk -v p="${WORKTREE_PATH}" '
        /^worktree / { if ($0 == "worktree " p) { found=1; next } else { found=0 } }
        found && /^branch / { sub(/^branch /, ""); print; exit }
      ' | sed 's|refs/heads/||' || echo "")"
      commit_range="$(git rev-list --reverse "${main_br}..${wt_sha}" 2>/dev/null | tr '\n' ' ' | sed 's/ $//' || echo "")"
      commits_count="$(git rev-list --count "${main_br}..${wt_sha}" 2>/dev/null || echo "?")"

      {
        printf '\n## %s — %s\n\n' "$(ts_iso)" "${WORKTREE_PATH}"
        printf '**Agent:** %s\n' "${AGENT_ID:-unknown}"
        printf '**Branch:** %s\n' "${wt_branch:-detached}"
        printf '**Commits not on %s:** %s\n\n' "${main_br}" "${commits_count}"
        printf 'Cherry-pick recipe:\n'
        printf '```bash\n'
        printf '# Cherry-pick %s commits from %s onto %s:\n' "${commits_count}" "${wt_branch:-${wt_sha:0:8}}" "${main_br}"
        [ -n "${commit_range}" ] && printf 'git cherry-pick %s\n' "${commit_range}"
        printf '# Then prune the worktree:\n'
        printf 'git worktree remove --force %s\n' "${WORKTREE_PATH}"
        printf '```\n'
      } >> "${pending_file}" 2>/dev/null || true
    }

    if _emit_pending_merge 2>/dev/null; then
      log_audit "preserved-for-merge" "null" "${WORKTREE_PATH}" "B"
    else
      log_audit "preserved-for-merge" "pending-merge-write-failed" "${WORKTREE_PATH}" "B"
      echo "worktree-release.sh: WARN failed to write PENDING-MERGE entry for ${WORKTREE_PATH}" >&2
    fi
    ;;

  C)
    # Dirty → preserve + flag
    log_audit "preserved-dirty" "null" "${WORKTREE_PATH}" "C"
    echo "worktree-release.sh: [CATEGORY C] ${WORKTREE_PATH} — dirty; preserved for manual review." >&2
    ;;

  *)
    # Unknown category — shouldn't happen; warn + preserve
    log_audit "warn" "unknown-category:${CATEGORY}" "${WORKTREE_PATH}" "${CATEGORY}"
    echo "worktree-release.sh: WARN unknown category '${CATEGORY}' for ${WORKTREE_PATH}" >&2
    ;;
esac

# ---- release lock LAST (partial failure above leaves lock for L4) -----------
# Lock release is intentionally the FINAL step. If act branch above failed or
# returned early (classify failure path), lock is NOT released here.
git worktree unlock "${WORKTREE_PATH}" 2>/dev/null || true

exit 0
