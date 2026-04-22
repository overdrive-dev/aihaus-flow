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
#
# Env:
#   AIHAUS_MAIN_BRANCH  — override main-branch detection (before flag parsing)
#   AIHAUS_RECONCILE_DRY_RUN=1 — emit Category A action as echo, do not prune
#
# Exit codes: 0 ok (including no-worktrees + non-git-dir cases)
#
# Called standalone or by /aih-resume (S09).
# Refs: M014/S08, K-002, ADR-M014-B §F.

set -euo pipefail

# ---- argument parsing -------------------------------------------------------
MAIN_BRANCH="${AIHAUS_MAIN_BRANCH:-}"
DRY_RUN="${AIHAUS_RECONCILE_DRY_RUN:-0}"

while [ $# -gt 0 ]; do
  case "$1" in
    --main-branch) MAIN_BRANCH="$2"; shift 2 ;;
    --dry-run)     DRY_RUN=1; shift ;;
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
