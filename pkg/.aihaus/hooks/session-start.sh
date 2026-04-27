#!/bin/bash
# session-start.sh — inject aihaus project status + surface pending stashes.
#
# ADR-260427-A: surfaces session-end-stash-pending.jsonl entries via the
# additionalContext JSON payload so the user sees stranded stashes from
# prior sessions on next launch (instead of silently inheriting them).
#
# Also runs a stash reaper: drops `aihaus session-end *` stashes older than
# 14 days, capped at 50 most-recent regardless of age. User-driven stashes
# (anything not matching the label prefix) are never touched.

set -euo pipefail

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export AIHAUS_PROJECT_DIR=\"$CLAUDE_PROJECT_DIR\"" >> "$CLAUDE_ENV_FILE"
fi

# Inject project status context from .aihaus/ artifacts
PLANNING_STATUS=""

# .aihaus/ artifact detection
AIHAUS_MS=$(ls -d "$CLAUDE_PROJECT_DIR/.aihaus/milestones"/M0* 2>/dev/null | wc -l || true)
[ "$AIHAUS_MS" -gt 0 ] 2>/dev/null && PLANNING_STATUS="${PLANNING_STATUS}milestones:${AIHAUS_MS} "
AIHAUS_FT=$(ls -d "$CLAUDE_PROJECT_DIR/.aihaus/features"/*/ 2>/dev/null | wc -l || true)
[ "$AIHAUS_FT" -gt 0 ] 2>/dev/null && PLANNING_STATUS="${PLANNING_STATUS}features:${AIHAUS_FT} "
AIHAUS_PL=$(ls -d "$CLAUDE_PROJECT_DIR/.aihaus/plans"/*/ 2>/dev/null | wc -l || true)
[ "$AIHAUS_PL" -gt 0 ] 2>/dev/null && PLANNING_STATUS="${PLANNING_STATUS}plans:${AIHAUS_PL} "

# project.md presence
[ -f "$CLAUDE_PROJECT_DIR/.aihaus/project.md" ] && PLANNING_STATUS="${PLANNING_STATUS}project.md:ready "

# --- ADR-260427-A: stash reaper + pending-stash surface --------------------
PENDING_LOG="$CLAUDE_PROJECT_DIR/.claude/audit/session-end-stash-pending.jsonl"
STASH_NOTICE=""

# Reaper: drop labels older than 14 days; cap at 50 most-recent labels.
# Operates only on `aihaus session-end *` labeled stashes.
if cd "$CLAUDE_PROJECT_DIR" 2>/dev/null && git rev-parse --git-dir >/dev/null 2>&1; then
  NOW_EPOCH="$(date +%s 2>/dev/null || echo 0)"
  CUTOFF=$(( NOW_EPOCH - 14 * 86400 ))

  # Iterate stash list; collect drop candidates oldest-first.
  # Format: <ref> <unix-ts> <message>
  CANDIDATES="$(git stash list --format='%gd %ct %gs' 2>/dev/null \
    | awk -v cutoff="$CUTOFF" '
      /aihaus session-end / {
        if ($2 + 0 < cutoff) print $1
      }')"

  if [ -n "$CANDIDATES" ]; then
    # Drop oldest-first (highest stash@{N} index first to keep lower indices stable).
    # Reverse-sort by index numeric.
    echo "$CANDIDATES" | sort -t '{' -k2 -n -r | while IFS= read -r ref; do
      [ -z "$ref" ] && continue
      git stash drop --quiet "$ref" 2>/dev/null || true
    done
  fi

  # 50-cap: count remaining aihaus session-end stashes; drop oldest beyond 50.
  REMAINING="$(git stash list --format='%gd %gs' 2>/dev/null | grep -c 'aihaus session-end ' || echo 0)"
  if [ "$REMAINING" -gt 50 ] 2>/dev/null; then
    OVER=$(( REMAINING - 50 ))
    git stash list --format='%gd %gs' 2>/dev/null \
      | grep 'aihaus session-end ' \
      | tail -n "$OVER" \
      | awk '{print $1}' \
      | sort -t '{' -k2 -n -r \
      | while IFS= read -r ref; do
          [ -z "$ref" ] && continue
          git stash drop --quiet "$ref" 2>/dev/null || true
        done
  fi
fi

# Surface pending-stash entries written by session-end.sh.
if [ -f "$PENDING_LOG" ]; then
  PENDING_COUNT="$(wc -l < "$PENDING_LOG" 2>/dev/null | tr -d ' ' || echo 0)"
  if [ "${PENDING_COUNT:-0}" -gt 0 ] 2>/dev/null; then
    LAST_ENTRY="$(tail -n1 "$PENDING_LOG" 2>/dev/null || echo "")"
    if command -v jq >/dev/null 2>&1; then
      LAST_SHA="$(printf '%s' "$LAST_ENTRY" | jq -r '.stash_sha // empty' 2>/dev/null || echo "")"
      LAST_REASON="$(printf '%s' "$LAST_ENTRY" | jq -r '.reason // empty' 2>/dev/null || echo "")"
    else
      # jq-optional fallback (mirrors bash-guard.sh:68-73 pattern).
      LAST_SHA="$(printf '%s' "$LAST_ENTRY" | grep -oE '"stash_sha"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"stash_sha"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' || echo "")"
      LAST_REASON="$(printf '%s' "$LAST_ENTRY" | grep -oE '"reason"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"reason"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' || echo "")"
    fi
    if [ -n "$LAST_SHA" ]; then
      STASH_NOTICE=" Pending session-end stash: ${LAST_SHA:0:7} (${LAST_REASON}); ${PENDING_COUNT} total. Run 'git stash list' / 'git stash pop ${LAST_SHA}' to recover."
    fi
  fi
fi
# --------------------------------------------------------------------------

jq -n --arg status "${PLANNING_STATUS:-no artifacts yet}" --arg notice "$STASH_NOTICE" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: ("aihaus status: " + $status + ". Use /aih-init to bootstrap project.md, /aih-plan to scope work, /aih-milestone to build, /aih-help for all commands." + $notice)
  }
}'
