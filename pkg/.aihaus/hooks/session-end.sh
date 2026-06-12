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

# --- stale-manifest advisory (non-blocking, NFR-05 / R-3) ---
AUTOCLOSE_HOOK="$CLAUDE_PROJECT_DIR/.aihaus/hooks/manifest-auto-close.sh"
if [ -x "$AUTOCLOSE_HOOK" ]; then
  count=$(bash "$AUTOCLOSE_HOOK" --dry-run 2>/dev/null | wc -l | tr -d ' ' || echo 0)
  if [ "${count:-0}" -gt 0 ] 2>/dev/null; then
    printf 'advisory: %s manifest(s) eligible for auto-close — run /aih-close --bulk\n' "$count" >&2
  fi
fi

# --- M050/S08 (F12): native-scratch harvest — CANDIDATES ONLY (BR-P6) -------
# Diffs each .claude/agent-memory/<name>/MEMORY.md (native CC subagent scratch)
# against a last-seen snapshot and appends the changed content to
# .aihaus/runtime/memory-candidates/<name>.md. The ORCHESTRATOR promotes
# candidates via the memory-promotion ritual (protocols/kanban/
# memory-promotion.md routes); NO hook writes tier-B committed memory.
# .aihaus/runtime/ is gitignored — candidates never land in the repo history
# from here. Fail-open on every path. Opt-out: AIHAUS_MEMORY_HARVEST=0.
if [ "${AIHAUS_MEMORY_HARVEST:-1}" != "0" ]; then
  AGENT_MEM_ROOT="$CLAUDE_PROJECT_DIR/.claude/agent-memory"
  CAND_DIR="$CLAUDE_PROJECT_DIR/.aihaus/runtime/memory-candidates"
  SNAP_DIR="$CAND_DIR/.last-seen"
  if [ -d "$AGENT_MEM_ROOT" ] && [ -d "$CLAUDE_PROJECT_DIR/.aihaus" ]; then
    mkdir -p "$CAND_DIR" "$SNAP_DIR" 2>/dev/null || true
    for mem_file in "$AGENT_MEM_ROOT"/*/MEMORY.md; do
      [ -f "$mem_file" ] || continue
      agent_name="$(basename "$(dirname "$mem_file")")"
      snap_file="$SNAP_DIR/${agent_name}.md"
      cand_file="$CAND_DIR/${agent_name}.md"
      # Unchanged since last harvest — skip.
      if [ -f "$snap_file" ] && cmp -s "$mem_file" "$snap_file" 2>/dev/null; then
        continue
      fi
      # Changed content: added lines vs the snapshot; whole file on first sight.
      if [ -f "$snap_file" ]; then
        changed="$(diff "$snap_file" "$mem_file" 2>/dev/null | sed -n 's/^> //p' || true)"
      else
        changed="$(cat "$mem_file" 2>/dev/null || true)"
      fi
      if [ -n "$(printf '%s' "$changed" | tr -d '[:space:]')" ]; then
        {
          printf '\n## Candidate %s (session %s)\n\n' "$(ts_iso)" "$SESSION_ID"
          printf 'Source: .claude/agent-memory/%s/MEMORY.md — changed lines since last harvest. Promote via the memory-promotion ritual; hooks never write tier-B memory (F12 / BR-P6).\n\n' "$agent_name"
          printf '%s\n' "$changed"
        } >> "$cand_file" 2>/dev/null || true
      fi
      # Refresh the snapshot regardless (deletions also advance last-seen).
      cp -f "$mem_file" "$snap_file" 2>/dev/null || true
    done
  fi
fi

exit 0
