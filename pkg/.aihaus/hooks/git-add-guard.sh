#!/usr/bin/env bash
# git-add-guard.sh — PreToolUse hook denying destructive git stage on milestone/feature branches
# (M017/S04 / ADR-M017-A companion defense)
#
# Catches git add -A / git add <dir>/ / git commit -am class via regex before it
# reaches merge-back.sh. Orthogonal to merge-back.sh — two independent defense layers.
#
# Denied patterns (exit 2):
#   git add -A | --all | . | -u | --update | :/ | --interactive | -p
#   git add <dir>/ (trailing slash)
#   git add <arg> where arg resolves to an existing directory (F-6 guard)
#   git commit -a | --all | -am | -a -m | --all -m
#
# Allowed (exit 0):
#   git add <explicit-file-path>
#   git commit -m | git commit (no staging flag)
#
# Active ONLY on milestone/* or feature/* branches. All other branches → exit 0 silently.
#
# Env:
#   AIHAUS_GIT_ADD_GUARD=0   — disable (warn + allow; exit 0)
#   AIHAUS_AUDIT_LOG         — override audit log path (default .claude/audit/hook.jsonl)
#
# Refs: ADR-M017-A, M017/S04, CHECK F-5 (commit-side bypass), CHECK F-6 (dir-without-slash).

set -euo pipefail

# ---- env bypass (Rollback matrix §AIHAUS_GIT_ADD_GUARD=0) -------------------
if [ "${AIHAUS_GIT_ADD_GUARD:-}" = "0" ]; then
  echo "git-add-guard.sh: DISABLED via AIHAUS_GIT_ADD_GUARD=0 — allowing all git add/commit" >&2
  # audit skipped-opt-out
  AUDIT_LOG="${AIHAUS_AUDIT_LOG:-.claude/audit/hook.jsonl}"
  mkdir -p "$(dirname "${AUDIT_LOG}")" 2>/dev/null || true
  printf '{"ts":"%s","hook":"git-add-guard","event":"git-add-guard","result":"skipped-opt-out","branch":"","command":""}\n' \
    "$(date -u +%FT%TZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z")" \
    >> "${AUDIT_LOG}" 2>/dev/null || true
  exit 0
fi

# ---- config ------------------------------------------------------------------
AUDIT_LOG="${AIHAUS_AUDIT_LOG:-.claude/audit/hook.jsonl}"

ts_iso() { date -u +%FT%TZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z"; }

# ---- audit helper ------------------------------------------------------------
# log_audit <result> <branch> <command>
log_audit() {
  local result="${1:-allowed}"
  local branch="${2:-}"
  local command="${3:-}"
  mkdir -p "$(dirname "${AUDIT_LOG}")" 2>/dev/null || true
  # Escape double-quotes in command for JSON safety
  local cmd_safe="${command//\"/\\\"}"
  local branch_safe="${branch//\"/\\\"}"
  printf '{"ts":"%s","hook":"git-add-guard","event":"git-add-guard","result":"%s","branch":"%s","command":"%s"}\n' \
    "$(ts_iso)" "${result}" "${branch_safe}" "${cmd_safe}" \
    >> "${AUDIT_LOG}" 2>/dev/null || true
}

# ---- parse PreToolUse stdin JSON ---------------------------------------------
# Input shape: {"tool_name":"Bash","tool_input":{"command":"git add ..."}}
PAYLOAD="$(cat)"

TOOL_NAME=""
COMMAND=""

if command -v jq >/dev/null 2>&1; then
  TOOL_NAME="$(printf '%s' "${PAYLOAD}" | jq -r '.tool_name // empty' 2>/dev/null || echo "")"
  COMMAND="$(printf '%s' "${PAYLOAD}" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")"
else
  # Fallback: grep without jq (K-002 defensive pattern)
  TOOL_NAME="$(printf '%s' "${PAYLOAD}" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo "")"
  COMMAND="$(printf '%s' "${PAYLOAD}" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo "")"
fi

# ---- guard: only act on Bash tool -------------------------------------------
[ "${TOOL_NAME}" = "Bash" ] || exit 0
[ -n "${COMMAND}" ] || exit 0

# ---- check current branch ---------------------------------------------------
BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo "")"

case "${BRANCH}" in
  milestone/*|feature/*)
    : # proceed to checks
    ;;
  *)
    # Not a milestone or feature branch — off-milestone, silent pass
    log_audit "off-milestone" "${BRANCH}" "${COMMAND}"
    exit 0
    ;;
esac

# ---- deny: git add destructive patterns (CHECK F-5 + F-6 regex layer) ------
# Split command on &&, ||, ; to check each segment independently
deny_detected=0
deny_reason=""

OLD_IFS="${IFS}"
IFS=$'\n'
segments="$(printf '%s' "${COMMAND}" | sed -E 's/[[:space:]]*(&&|\|\||;)[[:space:]]*/\n/g')"
for seg in ${segments}; do
  # Trim leading/trailing whitespace
  trimmed="${seg#"${seg%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
  [ -z "${trimmed}" ] && continue

  # Pattern 1: git add with destructive flags
  if printf '%s' "${trimmed}" | grep -qE 'git[[:space:]]+add[[:space:]]+(-A\b|--all\b|\.[[:space:]]|\.(\s|$)|-u\b|--update\b|:/\b|--interactive\b|-p\b)' 2>/dev/null; then
    deny_detected=1
    deny_reason="${trimmed}"
    break
  fi
  # Handle 'git add .' at end of string (no trailing char)
  if printf '%s' "${trimmed}" | grep -qE 'git[[:space:]]+add[[:space:]]+\.$' 2>/dev/null; then
    deny_detected=1
    deny_reason="${trimmed}"
    break
  fi

  # Pattern 2: git add <dir>/ (trailing slash on any argument)
  if printf '%s' "${trimmed}" | grep -qE 'git[[:space:]]+add[[:space:]]+[^[:space:]]+/([[:space:]]|$)' 2>/dev/null; then
    deny_detected=1
    deny_reason="${trimmed}"
    break
  fi

  # Pattern 3: git commit -a / --all / -am / -a -m / --all -m (CHECK F-5)
  if printf '%s' "${trimmed}" | grep -qE 'git[[:space:]]+commit[[:space:]]+(-a\b|--all\b|-am\b|-a[[:space:]]+-m\b|--all[[:space:]]+-m\b)' 2>/dev/null; then
    deny_detected=1
    deny_reason="${trimmed}"
    break
  fi
done
IFS="${OLD_IFS}"

if [ "${deny_detected}" -eq 1 ]; then
  echo "git-add-guard.sh: DENIED — ${deny_reason}" >&2
  echo "Use 'bash .aihaus/hooks/merge-back.sh --story S<NN>' instead (M017 ADR-M017-A)." >&2
  log_audit "denied" "${BRANCH}" "${deny_reason}"
  exit 2
fi

# ---- deny: directory-without-slash guard (CHECK F-6 / E3 plan-check F-6) ---
# For each `git add <arg>`, check if the arg (even without trailing slash)
# resolves to an existing directory on disk.
if printf '%s' "${COMMAND}" | grep -qE 'git[[:space:]]+add[[:space:]]' 2>/dev/null; then
  # Extract the portion after 'git add'
  ADD_ARGS_STR="$(printf '%s' "${COMMAND}" | sed -E 's/.*git[[:space:]]+add[[:space:]]+//')"
  # Read args one per line, splitting on spaces
  while IFS= read -r arg; do
    [ -z "${arg}" ] && continue
    # Skip flags (start with -)
    case "${arg}" in
      -*) continue ;;
    esac
    # test -d: if arg is an existing directory → deny (catches git add frontend, etc.)
    if [ -d "${arg}" ] 2>/dev/null; then
      echo "git-add-guard.sh: DENIED — directory add: ${arg}" >&2
      echo "Use 'bash .aihaus/hooks/merge-back.sh --story S<NN>' instead (M017 ADR-M017-A)." >&2
      log_audit "denied" "${BRANCH}" "git add ${arg} (directory)"
      exit 2
    fi
  done < <(printf '%s' "${ADD_ARGS_STR}" | tr ' ' '\n' | grep -v '^[[:space:]]*$' || true)
fi

# ---- allowed -----------------------------------------------------------------
log_audit "allowed" "${BRANCH}" "${COMMAND}"
exit 0
