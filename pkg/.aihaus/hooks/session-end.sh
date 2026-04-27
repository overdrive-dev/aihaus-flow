#!/bin/bash
# session-end.sh — safe stash on dirty tree exit (M018/S5-aligned).
#
# Aligned with M018/S5 §Stash Recovery (completion-protocol.md:6-37) +
# ADR-260427-A: stash on dirty tree with slug-validated label, attempt
# auto-pop only on a clean tree post-push, surface STASH PENDING via
# the audit log on dirty-tree / label-mismatch / pop-failure.
#
# SHA-stable reference (git rev-parse stash@{0}) is invariant across
# concurrent stash mutations — the index-ref name is fragile.
#
# Audit log: .claude/audit/session-end-stash-pending.jsonl
#   schema: ts, session_id, branch, stash_sha, reason, label
#
# Reasons: dirty-tree-after-stash | label-mismatch | pop-failed-on-clean-tree
#
# Out-of-scope: this hook never auto-resolves conflicts, never force-pops,
# never drops user stashes. Only the labels it created are eligible for
# auto-pop / auto-reap; other stashes are left untouched.

set -euo pipefail

cd "$CLAUDE_PROJECT_DIR" 2>/dev/null || exit 0

LOG_DIR="$CLAUDE_PROJECT_DIR/.claude/audit"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).jsonl"
PENDING_LOG="$LOG_DIR/session-end-stash-pending.jsonl"
mkdir -p "$LOG_DIR" 2>/dev/null || true

ts_iso() { date -u +%FT%TZ 2>/dev/null || echo ""; }

SESSION_ID="${CLAUDE_SESSION_ID:-$(date +%s 2>/dev/null || echo unknown)}"
STASH_LABEL="aihaus session-end ${SESSION_ID}"
BRANCH="$(git branch --show-current 2>/dev/null || echo "")"

_record_pending() {
  local sha="$1" reason="$2"
  local sha_q reason_q label_q branch_q
  sha_q=$(printf '%s' "$sha" | sed 's/\\/\\\\/g; s/"/\\"/g')
  reason_q=$(printf '%s' "$reason" | sed 's/\\/\\\\/g; s/"/\\"/g')
  label_q=$(printf '%s' "$STASH_LABEL" | sed 's/\\/\\\\/g; s/"/\\"/g')
  branch_q=$(printf '%s' "$BRANCH" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '{"ts":"%s","session_id":"%s","branch":"%s","stash_sha":"%s","reason":"%s","label":"%s"}\n' \
    "$(ts_iso)" "$SESSION_ID" "$branch_q" "$sha_q" "$reason_q" "$label_q" \
    >> "$PENDING_LOG" 2>/dev/null || true
}

# Stash only if working tree or index is dirty.
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  if git stash push -m "$STASH_LABEL" --include-untracked --quiet 2>/dev/null; then
    STASH_SHA="$(git rev-parse stash@{0} 2>/dev/null || echo "")"
    if [ -z "$STASH_SHA" ]; then
      # Stash exists but SHA could not be resolved (e.g., concurrent stash race).
      # Surface anyway so the next session-start banner makes the user aware.
      _record_pending "" "rev-parse-failed"
    fi
    if [ -n "$STASH_SHA" ]; then
      # Auto-pop only when working tree is clean post-push (i.e., nothing else
      # accumulated between push and pop) AND label cross-validates the SHA.
      if [ -z "$(git status --porcelain 2>/dev/null)" ]; then
        STASH_MSG="$(git stash show -s --format=%B "$STASH_SHA" 2>/dev/null || echo "")"
        if echo "$STASH_MSG" | grep -qF "$STASH_LABEL"; then
          if ! git stash pop --quiet "$STASH_SHA" 2>/dev/null; then
            _record_pending "$STASH_SHA" "pop-failed-on-clean-tree"
          fi
        else
          _record_pending "$STASH_SHA" "label-mismatch"
        fi
      else
        _record_pending "$STASH_SHA" "dirty-tree-after-stash"
      fi
    fi
  fi
fi

jq -n --arg ts "$(ts_iso)" \
  '{ts: $ts, event: "session_end"}' >> "$LOG_FILE" 2>/dev/null || true

exit 0
