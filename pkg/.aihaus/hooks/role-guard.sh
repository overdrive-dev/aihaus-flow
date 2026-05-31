#!/bin/bash
set -euo pipefail

# role-guard.sh — PreToolUse hook (aihaus 3.0 / S1).
#
# Enforces the role capability boundary: the "online" boundary (staging→prod) IS
# the capability boundary. Only an online-capable role (default: devops) may run
# an action that touches an online environment. builder/dev/qa operate 100%
# offline-local. Roles are ADDITIVE — the active profile is a set of roles in
# .aihaus/.profile (comma/space separated, e.g. "builder,devops").
#
# NOTE: this PRODUCT role (builder/dev/qa/devops/pm) is distinct from the agent
# COHORT roles (:planner/:doer/...) in lib/role-defaults.json. Decision surface:
# pkg/.aihaus/workflows/roles.md.
#
# Opt-out: AIHAUS_ROLE_GUARD=0. Audit: .claude/audit/role-guard.jsonl.

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/path-helpers.sh
. "${HOOK_DIR}/lib/path-helpers.sh"
# shellcheck source=lib/online-actions.sh
. "${HOOK_DIR}/lib/online-actions.sh"

if [ "${AIHAUS_ROLE_GUARD:-1}" = "0" ]; then
  exit 0
fi

# Roles allowed to cross the staging→prod boundary.
ONLINE_CAPABLE_ROLES="devops"

# Online-action patterns (ERE) live in lib/online-actions.sh — the single source
# shared with flow-guard.sh. Project patterns extend via
# .aihaus/roles/online-actions.conf. Conservative by design: a missed pattern
# fails open (allowed), never destructively.

INPUT=$(cat)

# jq-optional: extract .tool_input.command with bash fallback (mirror bash-guard).
if command -v jq >/dev/null 2>&1; then
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
else
  COMMAND=$(echo "$INPUT" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"command"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' || echo "")
fi

# No command (non-Bash tool or empty) → not in scope for the bash boundary.
[ -z "$COMMAND" ] && exit 0

# Resolve active profile. Absent/empty → gate not in scope (non-role install).
PROFILE_FILE="$(aihaus_project_path ".aihaus/.profile")"
[ -f "$PROFILE_FILE" ] || exit 0
PROFILE="$(tr ',' ' ' < "$PROFILE_FILE" 2>/dev/null | tr -s '[:space:]' ' ' | sed 's/^ *//; s/ *$//')"
[ -z "$PROFILE" ] && exit 0

# If the profile holds an online-capable role, allow immediately.
for role in $PROFILE; do
  for cap in $ONLINE_CAPABLE_ROLES; do
    [ "$role" = "$cap" ] && exit 0
  done
done

ONLINE_REGEX="$(aihaus_online_action_regex "$(aihaus_project_root)")"

# Segment on && || ; (mirror bash-guard) and test each segment.
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

[ "$matched" -eq 0 ] && exit 0

# Audit + block.
_rg_ts() { date -u +%FT%TZ 2>/dev/null || echo ""; }
AUDIT_LOG="$(aihaus_project_path ".claude/audit/role-guard.jsonl")"
mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true
CMD_HASH="$(printf '%s' "$COMMAND" | sha256sum 2>/dev/null | cut -c1-12 || printf 'nohash')"
printf '{"ts":"%s","session_id":"%s","profile":"%s","decision":"block-online","command_hash":"%s"}\n' \
  "$(_rg_ts)" "${CLAUDE_SESSION_ID:-unknown}" \
  "$(printf '%s' "$PROFILE" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
  "$CMD_HASH" >> "$AUDIT_LOG" 2>/dev/null || true

echo "BLOCKED (role-guard): profile [${PROFILE}] is offline-local and cannot run an action that touches an online environment (staging/prod). Matched: '${MATCHED_SEG}'. Only a profile with an online-capable role (${ONLINE_CAPABLE_ROLES}) may cross — hand off to devops, or set AIHAUS_ROLE_GUARD=0 to override." >&2
exit 2
