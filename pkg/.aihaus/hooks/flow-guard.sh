#!/bin/bash
set -euo pipefail

# flow-guard.sh — PreToolUse hook (aihaus 3.0 / BRC-S4, ADR-260531-A BR-F2).
#
# Promotion-boundary determinism. An online-action (deploy / promotion) command
# may run ONLY inside an active flow. Offline/dev work is unrestricted; the moment
# work promotes to an online environment it must be part of a tracked sub-flow, so
# nothing reaches prod ad-hoc and every promoted change traces back to a rule.
#
# This is the SOLE online-boundary gate (ADR-260612-A): the question is never
# WHO is deploying, only whether the deploy happens WITHIN a tracked flow. The
# deploy-command patterns live in lib/online-actions.sh (single source — the
# M030 drift lesson).
#
# "Active flow" = any sentinel present:
#   .claude/_state/active-flow              (feature / bugfix / milestone)
#   .claude/calibrate-guard.active-slug     (plan)
# Absent → ad-hoc promotion → block.
#
# Early-exit when the aihaus overlay is not installed (no .aihaus/ directory),
# so this is a no-op on repos that have not opted in. Opt-out: AIHAUS_FLOW_GUARD=0.
# Audit: .claude/audit/flow-guard.jsonl.

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/path-helpers.sh
. "${HOOK_DIR}/lib/path-helpers.sh"
# shellcheck source=lib/online-actions.sh
. "${HOOK_DIR}/lib/online-actions.sh"

[ "${AIHAUS_FLOW_GUARD:-1}" = "0" ] && exit 0

ROOT="$(aihaus_project_root)"

# aihaus overlay not installed → out of scope (no-op).
[ -d "${ROOT}/.aihaus" ] || exit 0

INPUT=$(cat)

# jq-optional command extraction (mirror bash-guard).
if command -v jq >/dev/null 2>&1; then
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
else
  COMMAND=$(echo "$INPUT" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"command"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' || echo "")
fi
[ -z "$COMMAND" ] && exit 0

ONLINE_REGEX="$(aihaus_online_action_regex "$ROOT")"

# Segment on && || ; and test each segment (mirror bash-guard).
matched=0
MATCHED_SEG=""
OLD_IFS="$IFS"
IFS=$'\n'
segments=$(printf '%s' "$COMMAND" | sed -E 's/[[:space:]]*(&&|\|\||;)[[:space:]]*/\n/g')
for seg in $segments; do
  trimmed="${seg#"${seg%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
  [ -z "$trimmed" ] && continue
  if echo "$trimmed" | grep -qiE "$ONLINE_REGEX"; then
    matched=1
    MATCHED_SEG="$trimmed"
    break
  fi
done
IFS="$OLD_IFS"

# Not an online action → out of scope.
[ "$matched" -eq 0 ] && exit 0

# Online action detected. Inside an active flow? → allow.
if [ -f "${ROOT}/.claude/_state/active-flow" ] || [ -f "${ROOT}/.claude/calibrate-guard.active-slug" ]; then
  exit 0
fi

# No active flow → ad-hoc promotion → block + audit.
_fg_ts() { date -u +%FT%TZ 2>/dev/null || echo ""; }
AUDIT_LOG="${ROOT}/.claude/audit/flow-guard.jsonl"
mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true
CMD_HASH="$(printf '%s' "$COMMAND" | sha256sum 2>/dev/null | cut -c1-12 || printf 'nohash')"
printf '{"ts":"%s","session_id":"%s","decision":"block-no-flow","command_hash":"%s"}\n' \
  "$(_fg_ts)" "${CLAUDE_SESSION_ID:-unknown}" "$CMD_HASH" >> "$AUDIT_LOG" 2>/dev/null || true

echo "BLOCKED (flow-guard): this looks like a promotion to an online environment ('${MATCHED_SEG}'), but no active aihaus flow is in progress. Promotions must run inside a tracked sub-flow so the change traces to a business rule + its tests — start or resume a flow first. Override with AIHAUS_FLOW_GUARD=0." >&2
exit 2
