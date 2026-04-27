#!/usr/bin/env bash
# worktree-reconcile.sh — classify and act on each git worktree.
#
# For each non-main worktree:
#   Category A (clean + HEAD reachable from main): prune silently via
#               git worktree remove --force; log to stderr.
#   Category B (clean + commits not on main): emit cherry-pick recipe
#               to stdout; NEVER auto-execute.
#   Category C (dirty): preserve untouched; emit 1-line summary to stdout.
#
# Usage:
#   bash worktree-reconcile.sh [--main-branch <name>] [--dry-run]
#   bash worktree-reconcile.sh --reap-locked [--age-days N] [--confirm]
#
# Env:
#   AIHAUS_MAIN_BRANCH        — override main-branch detection (before flag parsing)
#   AIHAUS_RECONCILE_DRY_RUN=1 — emit Category A action as echo, do not prune
#   AIHAUS_REAP_DRY_RUN=1     — for --reap-locked mode: print would-delete list only
#
# Exit codes: 0 ok (including no-worktrees + non-git-dir cases)
#
# Functions exported for sourcing:
#   classify_only <worktree-path>  — returns A/B/C to stdout; exit 0 on recognised path,
#                                    non-zero on unrecognised path.
#
# --reap-locked mode (S02a M017 / S02d-reusable):
#   Iterates locked worktrees. Checks mtime of .git/worktrees/<name>/locked sentinel.
#   Prunes entries older than --age-days (default 14) when --confirm is passed.
#   Respects AIHAUS_REAP_DRY_RUN=1 (print would-delete list, no deletion).
#   Emits [REAPED] marker on success. Windows path-lock → Category-C fallthrough.
#
# Called standalone or by /aih-resume (S09), or sourced by worktree-release.sh.
# Refs: M014/S08, M017/S02a, K-002, ADR-M014-B §F, ADR-M017-B.

set -euo pipefail

# ---- argument parsing -------------------------------------------------------
MAIN_BRANCH="${AIHAUS_MAIN_BRANCH:-}"
DRY_RUN="${AIHAUS_RECONCILE_DRY_RUN:-0}"
REAP_DRY_RUN="${AIHAUS_REAP_DRY_RUN:-0}"
REAP_MODE=0
REAP_AGE_DAYS=14
REAP_CONFIRM=0

while [ $# -gt 0 ]; do
  case "$1" in
    --main-branch)  MAIN_BRANCH="$2"; shift 2 ;;
    --dry-run)      DRY_RUN=1; shift ;;
    --reap-locked)  REAP_MODE=1; shift ;;
    --age-days)     REAP_AGE_DAYS="$2"; shift 2 ;;
    --confirm)      REAP_CONFIRM=1; shift ;;
    *) echo "worktree-reconcile.sh: unknown arg $1" >&2; exit 0 ;;
  esac
done

# ---- non-git-dir guard ------------------------------------------------------
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "worktree-reconcile.sh: not a git repo; skipping" >&2
  exit 0
fi

# ---- detect main branch -----------------------------------------------------
# Priority: env/flag > symbolic-ref origin/HEAD > "main" > "pi-port"
if [ -z "$MAIN_BRANCH" ]; then
  _sym="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [ -n "$_sym" ]; then
    # refs/remotes/origin/main → main
    MAIN_BRANCH="${_sym##*/}"
  elif git show-ref --verify --quiet refs/heads/main 2>/dev/null; then
    MAIN_BRANCH="main"
  else
    MAIN_BRANCH="pi-port"
  fi
fi

# Resolve main branch HEAD sha (used for reachability check)
MAIN_HEAD="$(git rev-parse "${MAIN_BRANCH}" 2>/dev/null || true)"
if [ -z "$MAIN_HEAD" ]; then
  echo "worktree-reconcile.sh: cannot resolve ${MAIN_BRANCH} HEAD; skipping reconcile" >&2
  exit 0
fi

# ---- classify_only function -------------------------------------------------
# Classifies a single worktree path as A, B, or C.
# Returns via stdout + exit 0 on recognised path.
# Returns exit 1 on unrecognised or error (path doesn't exist, not a worktree, etc.).
# Does NOT prune or act — read-only assessment only.
classify_only() {
  local wt_path="$1"

  # Validate the path exists
  if [ -z "$wt_path" ] || [ ! -d "$wt_path" ]; then
    echo "worktree-reconcile.sh: classify_only: path not found: ${wt_path}" >&2
    return 1
  fi

  # Check it's a known worktree (appears in git worktree list)
  if ! git worktree list --porcelain 2>/dev/null | grep -q "^worktree ${wt_path}$"; then
    echo "worktree-reconcile.sh: classify_only: path is not a git worktree: ${wt_path}" >&2
    return 1
  fi

  # Get SHA for this worktree
  local wt_sha
  wt_sha="$(git worktree list --porcelain 2>/dev/null | awk -v p="${wt_path}" '
    /^worktree / { if ($0 == "worktree " p) { found=1; next } else { found=0 } }
    found && /^HEAD / { sub(/^HEAD /, ""); print; exit }
  ')"

  if [ -z "$wt_sha" ]; then
    echo "worktree-reconcile.sh: classify_only: cannot resolve HEAD for: ${wt_path}" >&2
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

# ---- --reap-locked mode -----------------------------------------------------
# When called with --reap-locked: iterate locked worktrees, check lock sentinel
# mtime, and prune those older than REAP_AGE_DAYS when --confirm is given.
if [ "${REAP_MODE}" = "1" ]; then
  GIT_DIR="$(git rev-parse --git-dir 2>/dev/null || true)"
  if [ -z "${GIT_DIR}" ]; then
    echo "worktree-reconcile.sh: --reap-locked: cannot resolve .git dir" >&2
    exit 0
  fi
  WORKTREES_DIR="${GIT_DIR}/worktrees"
  if [ ! -d "${WORKTREES_DIR}" ]; then
    # No worktrees registered at all — silent exit
    exit 0
  fi

  NOW_EPOCH="$(date +%s)"
  AGE_CUTOFF_SEC=$(( REAP_AGE_DAYS * 86400 ))

  # Iterate each entry under .git/worktrees/
  for wt_name_dir in "${WORKTREES_DIR}"/*/; do
    [ -d "${wt_name_dir}" ] || continue
    LOCK_FILE="${wt_name_dir}locked"
    [ -f "${LOCK_FILE}" ] || continue

    # Resolve worktree path from .git/worktrees/<name>/gitdir
    GITDIR_FILE="${wt_name_dir}gitdir"
    if [ ! -f "${GITDIR_FILE}" ]; then
      continue
    fi
    # gitdir contains either a relative path (../../.claude/worktrees/agent-xxxx/.git)
    # OR an absolute path (C:/Users/.../wt/.git on Windows; /home/user/wt/.git on Unix).
    # M018-S1 K-001: Windows/Git Bash writes absolute paths here, so unconditional
    # prepend of GIT_DIR produced invalid concatenations like '.git/C:/...' →
    # WT_PATH_CANDIDATE always empty on Windows. Detect absolute vs relative.
    WT_GITDIR_VAL="$(cat "${GITDIR_FILE}")"
    case "${WT_GITDIR_VAL}" in
      /*|[A-Za-z]:[/\\]*)
        # Absolute path (Unix /... or Windows C:/...) — use as-is
        WT_GITDIR_FULL="${WT_GITDIR_VAL}"
        ;;
      *)
        # Relative path — resolve against GIT_DIR
        WT_GITDIR_FULL="${GIT_DIR}/${WT_GITDIR_VAL}"
        ;;
    esac
    # gitdir points at the worktree's .git FILE (e.g., /path/to/wt/.git).
    # The worktree path is its parent (single dirname). M017's original 'dirname dirname'
    # stripped one segment too many — only "worked" because K-001's path-resolution
    # bug made WT_PATH_CANDIDATE always empty on Windows, masking this regression.
    WT_PATH_CANDIDATE="$(dirname "${WT_GITDIR_FULL}")"
    # Normalize
    WT_PATH_CANDIDATE="$(cd "${WT_PATH_CANDIDATE}" 2>/dev/null && pwd -P 2>/dev/null || echo "")"

    # Check lock sentinel mtime
    LOCK_MTIME="$(stat -c %Y "${LOCK_FILE}" 2>/dev/null || stat -f %m "${LOCK_FILE}" 2>/dev/null || echo "${NOW_EPOCH}")"
    LOCK_AGE=$(( NOW_EPOCH - LOCK_MTIME ))

    if [ "${LOCK_AGE}" -lt "${AGE_CUTOFF_SEC}" ]; then
      # Live lock, skip
      continue
    fi

    if [ "${REAP_DRY_RUN}" = "1" ] || [ "${REAP_CONFIRM}" = "0" ]; then
      # Dry-run or no --confirm: report only
      printf '[REAP-CANDIDATE] %s — lock age %d days (sentinel: %s)\n' \
        "${WT_PATH_CANDIDATE:-${wt_name_dir}}" "$(( LOCK_AGE / 86400 ))" "${LOCK_FILE}"
      continue
    fi

    # --confirm is set and lock is old enough — attempt reap
    if [ -n "${WT_PATH_CANDIDATE}" ] && [ -d "${WT_PATH_CANDIDATE}" ]; then
      # Attempt unlock + remove
      if git worktree unlock "${WT_PATH_CANDIDATE}" 2>/dev/null; then
        if git worktree remove --force "${WT_PATH_CANDIDATE}" 2>/dev/null; then
          printf '[REAPED] %s — pruned (lock age %d days).\n' \
            "${WT_PATH_CANDIDATE}" "$(( LOCK_AGE / 86400 ))" >&2
        else
          # Windows path-lock Category-C fallthrough (reconcile.sh:146-147 pattern)
          printf '[CATEGORY C] %s — remove failed after unlock; preserved as safety fallback.\n' \
            "${WT_PATH_CANDIDATE}"
          # Re-lock to restore state
          git worktree lock "${WT_PATH_CANDIDATE}" 2>/dev/null || true
        fi
      else
        printf '[CATEGORY C] %s — unlock failed; preserved (Windows path-lock or active use).\n' \
          "${WT_PATH_CANDIDATE:-${wt_name_dir}}"
      fi
    else
      # Path empty or not on disk — guard pattern from classify_only (lines 92-96).
      # Do NOT use || true masking (SC2015 antipattern — CHECK C1).
      # git worktree prune does NOT remove locked entries per git-worktree(1);
      # rm -rf "${wt_name_dir}" is the only path that clears M010-M012 backlog (CHECK H4).
      printf '[REAP-CANDIDATE] %s — path resolution failed; manual cleanup required\n' \
        "${wt_name_dir}" >&2
      # Attempt unlock only if path is non-empty (avoids git error on empty arg).
      # Capture exit code without || true (set -e safe: assignment captures failure).
      _u=0
      if [ -n "${WT_PATH_CANDIDATE}" ]; then
        git worktree unlock "${WT_PATH_CANDIDATE}" 2>/dev/null || _u=$?
      fi
      # Wipe the .git/worktrees/<name>/ registration.
      # git worktree prune does NOT clear locked entries, so rm -rf is required.
      # NEVER emit [REAPED] for path-empty entries — only [REAP-CANDIDATE] above.
      rm -rf "${wt_name_dir}"
    fi
  done

  exit 0
fi

# ---- parse git worktree list --porcelain ------------------------------------
# Porcelain format: blank-line-separated blocks.
# Each block has: worktree <path>, HEAD <sha>, branch <ref> | bare | detached
parse_worktrees() {
  local path="" sha="" branch="" locked=0
  while IFS= read -r line; do
    case "$line" in
      "worktree "*)
        # Emit previous block if we have one
        if [ -n "$path" ]; then
          printf '%s\t%s\t%s\t%s\n' "$path" "$sha" "$branch" "$locked"
        fi
        path="${line#worktree }"
        sha=""; branch=""; locked=0
        ;;
      "HEAD "*)     sha="${line#HEAD }" ;;
      "branch "*)   branch="${line#branch }" ;;
      "locked"*)    locked=1 ;;
      "")
        if [ -n "$path" ]; then
          printf '%s\t%s\t%s\t%s\n' "$path" "$sha" "$branch" "$locked"
          path=""; sha=""; branch=""; locked=0
        fi
        ;;
    esac
  done
  # Emit final block if no trailing blank line
  if [ -n "$path" ]; then
    printf '%s\t%s\t%s\t%s\n' "$path" "$sha" "$branch" "$locked"
  fi
}

# ---- collect worktrees -------------------------------------------------------
worktree_data="$(git worktree list --porcelain | parse_worktrees)"

if [ -z "$worktree_data" ]; then
  # No worktrees (besides main, or truly empty) — exit 0 silently
  exit 0
fi

# ---- resolve main worktree path (first entry in list) -----------------------
MAIN_WORKTREE_PATH="$(git worktree list --porcelain | awk '/^worktree /{print substr($0,10); exit}')"

# ---- main reconcile loop ----------------------------------------------------
found_non_main=0

while IFS=$'\t' read -r wt_path wt_sha wt_branch wt_locked; do
  # Skip the main checkout (never touch it)
  if [ "$wt_path" = "$MAIN_WORKTREE_PATH" ]; then
    continue
  fi

  # Skip locked worktrees — they are in active use
  if [ "$wt_locked" = "1" ]; then
    echo "[LOCKED] ${wt_path} — skipped (locked worktree, in active use)." >&2
    continue
  fi

  found_non_main=1

  # ---- dirty / clean detection ---------------------------------------------
  dirty_files="$(git -C "${wt_path}" status --porcelain 2>/dev/null | wc -l | tr -d ' ')" || dirty_files="1"

  if [ "$dirty_files" -gt 0 ]; then
    # ---- Category C: dirty → preserve + surface summary --------------------
    printf '[CATEGORY C] %s — %s uncommitted file(s); preserved.\n' \
      "${wt_path}" "${dirty_files}"
    continue
  fi

  # ---- clean: check reachability from main --------------------------------
  # Count commits in worktree HEAD not reachable from main.
  commits_not_on_main="$(git rev-list --count "${MAIN_BRANCH}..${wt_sha}" 2>/dev/null || echo "1")"

  if [ "$commits_not_on_main" -eq 0 ]; then
    # ---- Category A: clean + merged → prune ---------------------------------
    if [ "$DRY_RUN" = "1" ]; then
      echo "[CATEGORY A] ${wt_path} — clean, merged (DRY-RUN: would prune)." >&2
    else
      if git worktree remove --force "${wt_path}" 2>/dev/null; then
        echo "[CATEGORY A] ${wt_path} — pruned (clean, merged)." >&2
      else
        # Fallback: if remove fails (e.g. Windows path locks), report as C
        printf '[CATEGORY C] %s — remove failed; preserved as safety fallback.\n' "${wt_path}"
      fi
    fi
  else
    # ---- Category B: clean + unmerged commits → emit recipe ----------------
    # Collect commit shas oldest-first (rev-list outputs newest-first by default)
    commit_range="$(git rev-list --reverse "${MAIN_BRANCH}..${wt_sha}" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
    branch_label="${wt_branch:-${wt_sha:0:8}}"
    # Strip refs/heads/ prefix for readability
    branch_label="${branch_label#refs/heads/}"

    printf '[CATEGORY B] %s — clean but %s commit(s) not on %s.\n' \
      "${wt_path}" "${commits_not_on_main}" "${MAIN_BRANCH}"
    printf 'Cherry-pick recipe:\n'
    printf '```bash\n'
    printf '# Cherry-pick %s commits from %s onto %s:\n' \
      "${commits_not_on_main}" "${branch_label}" "${MAIN_BRANCH}"
    printf 'git cherry-pick %s\n' "${commit_range}"
    printf '# Then prune the worktree:\n'
    printf 'git worktree remove --force %s\n' "${wt_path}"
    printf '```\n'
    printf '\n'
  fi

done <<EOF
${worktree_data}
EOF

# If there were no non-main worktrees, exit silently
if [ "$found_non_main" -eq 0 ]; then
  exit 0
fi

exit 0
