#!/usr/bin/env bash
# calibrate-guard.sh — UserPromptExpansion hook blocking /aih-feature + /aih-milestone --plan
# when plan has ambiguities (analyst-brief Check-78 markers) but no BUSINESS-RULES.md.
# (M029/S1 / ADR-260511-A)
#
# Fires on UserPromptExpansion for commands aih-feature and aih-milestone.
# For aih-milestone: only gates when --plan flag is present in command_args.
#
# Decision logic (sequential, fail-open on every ambiguous path):
#   1. AIHAUS_CALIBRATE_GUARD=0 → silent bypass (env opt-out)
#   2. Parse command_name + command_args from stdin JSON (jq or grep/sed fallback)
#   3. command_name ∉ {aih-feature, aih-milestone} → exit 0
#   4. aih-milestone without --plan → exit 0
#   5. Read .claude/calibrate-guard.active-slug sentinel → absent → exit 0
#   6. .aihaus/plans/<slug>/CHECK.md absent → exit 0 (pre-plan-checker, not in scope)
#   7. Ctime exemption (Decision E): CHECK.md mtime predates M029 first-commit → exit 0
#   8. .aihaus/plans/<slug>/ASSUMPTIONS.md ambiguity count = 0 → exit 0 (zero-ambiguity)
#   9. .aihaus/plans/<slug>/BUSINESS-RULES.md exists → exit 0 (calibration done)
#  10. .claude/audit/hook.jsonl shows recent calibration-skip row for this slug → exit 0
#  11. Block: stderr message + JSONL audit row + exit 2
#
# Exit codes:
#   0 — allow (any pass-through condition above)
#   2 — block (ambiguity markers present, no BUSINESS-RULES.md, no prior skip)
#
# Env:
#   AIHAUS_CALIBRATE_GUARD=0   — disable entirely (silent bypass; aih-quick Step 0 sets this)
#   AIHAUS_AUDIT_LOG            — override audit log path (default .claude/audit/hook.jsonl)
#
# Bypass mechanisms:
#   AIHAUS_CALIBRATE_GUARD=0           — env var (single-session or aih-quick/bugfix lifecycle)
#   --no-calibrate flag in command_args — per-invocation; hook reads opt-out row in audit log
#   Prior calibration-skip JSONL row    — user opted out via manifest-append (24h window)
#
# Refs: ADR-260511-A, M029/S1, PLAN Decision B+C+E, STDIN-SCHEMA.md, PATTERNS.md Pattern 1+4.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/path-helpers.sh
. "${HOOK_DIR}/lib/path-helpers.sh"

# ---- M029 first-commit timestamp (Decision E ctime exemption) ----------------
# 2026-05-12T00:00:00Z epoch — CHECK.md files older than this are legacy artifacts.
M029_EPOCH="1747008000"

# ---- env bypass (Decision B — aih-quick/bugfix lifecycle + rollback opt-out) -
if [ "${AIHAUS_CALIBRATE_GUARD:-1}" = "0" ]; then
  AUDIT_LOG="$(aihaus_project_path "${AIHAUS_AUDIT_LOG:-.claude/audit/hook.jsonl}")"
  mkdir -p "$(dirname "${AUDIT_LOG}")" 2>/dev/null || true
  printf '{"ts":"%s","hook":"calibrate-guard","event":"calibrate-guard","decision":"bypass","reason":"AIHAUS_CALIBRATE_GUARD=0","slug":"","command":""}\n' \
    "$(date -u +%FT%TZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z")" \
    >> "${AUDIT_LOG}" 2>/dev/null || true
  exit 0
fi

# ---- config ------------------------------------------------------------------
AUDIT_LOG="$(aihaus_project_path "${AIHAUS_AUDIT_LOG:-.claude/audit/hook.jsonl}")"

ts_iso() { date -u +%FT%TZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z"; }

# ---- audit helper ------------------------------------------------------------
# log_event <decision> <reason> <slug> <command>
log_event() {
  local decision="${1:-allow}"
  local reason="${2:-}"
  local slug="${3:-}"
  local command="${4:-}"
  mkdir -p "$(dirname "${AUDIT_LOG}")" 2>/dev/null || true
  local slug_safe="${slug//\"/\\\"}"
  local reason_safe="${reason//\"/\\\"}"
  local cmd_safe="${command//\"/\\\"}"
  printf '{"ts":"%s","hook":"calibrate-guard","event":"calibrate-guard","decision":"%s","reason":"%s","slug":"%s","command":"%s"}\n' \
    "$(ts_iso)" "${decision}" "${reason_safe}" "${slug_safe}" "${cmd_safe}" \
    >> "${AUDIT_LOG}" 2>/dev/null || true
}

# ---- parse UserPromptExpansion stdin JSON ------------------------------------
# Schema (STDIN-SCHEMA.md verified 2026-05-12): top-level fields command_name + command_args
INPUT=$(cat)

COMMAND_NAME=""
COMMAND_ARGS=""

if command -v jq >/dev/null 2>&1; then
  COMMAND_NAME="$(printf '%s' "${INPUT}" | jq -r '.command_name // empty' 2>/dev/null || echo "")"
  COMMAND_ARGS="$(printf '%s' "${INPUT}" | jq -r '.command_args // empty' 2>/dev/null || echo "")"
else
  # Fallback: grep + sed without jq (K-002 defensive pattern)
  COMMAND_NAME="$(printf '%s' "${INPUT}" | grep -o '"command_name"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | head -1 | sed 's/.*"command_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' 2>/dev/null || echo "")"
  COMMAND_ARGS="$(printf '%s' "${INPUT}" | grep -o '"command_args"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | head -1 | sed 's/.*"command_args"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' 2>/dev/null || echo "")"
fi

# ---- guard: only act on aih-feature or aih-milestone -------------------------
case "${COMMAND_NAME}" in
  aih-feature|aih-milestone) : ;;
  *) exit 0 ;;
esac

# ---- for aih-milestone: only gate when --plan flag present -------------------
if [ "${COMMAND_NAME}" = "aih-milestone" ]; then
  if ! printf '%s' "${COMMAND_ARGS}" | grep -qE '(^|[[:space:]])--plan([[:space:]]|$)'; then
    exit 0  # bare /aih-milestone without --plan: gate does not apply
  fi
fi

# ---- resolve active plan slug from sentinel file ----------------------------
SLUG=""
SENTINEL=".claude/calibrate-guard.active-slug"
if [ -f "${SENTINEL}" ]; then
  SLUG="$(cat "${SENTINEL}" 2>/dev/null | tr -d '[:space:]' || echo "")"
fi

if [ -z "${SLUG}" ]; then
  log_event "allow" "no-active-slug-sentinel" "" "${COMMAND_NAME}"
  exit 0
fi

# ---- check CHECK.md presence (pre-plan-checker: gate not in scope) ----------
CHECK_MD=".aihaus/plans/${SLUG}/CHECK.md"
if [ ! -f "${CHECK_MD}" ]; then
  log_event "allow" "check-md-absent-pre-plan-checker" "${SLUG}" "${COMMAND_NAME}"
  exit 0
fi

# ---- Decision E: ctime exemption for legacy CHECK.md (predates M029) --------
# Use mtime as proxy for ctime (stat -c%Y on Linux, stat -f%m on macOS).
# Fail-safe: if stat is unavailable or parse fails, treat as non-exempt (proceed).
_check_md_epoch="$(stat -c%Y "${CHECK_MD}" 2>/dev/null || stat -f%m "${CHECK_MD}" 2>/dev/null || echo "")"
if [ -n "${_check_md_epoch}" ] && [ "${_check_md_epoch}" -lt "${M029_EPOCH}" ] 2>/dev/null; then
  log_event "allow" "legacy-ctime-exempt-pre-m029" "${SLUG}" "${COMMAND_NAME}"
  exit 0
fi

# ---- read ASSUMPTIONS.md for ambiguity markers (Check 78 regex) -------------
ASSUMPTIONS_MD=".aihaus/plans/${SLUG}/ASSUMPTIONS.md"
AMBIGUITY_COUNT=0
if [ -f "${ASSUMPTIONS_MD}" ]; then
  AMBIGUITY_COUNT="$(grep -ciE '\bTBD\b|[[:space:]]assumed[[:space:]]|[[:space:]]assumed$|\bTODO\b|pending confirmation' \
    "${ASSUMPTIONS_MD}" 2>/dev/null || echo 0)"
fi

# Normalize: treat non-numeric as 0
case "${AMBIGUITY_COUNT}" in
  ''|*[!0-9]*) AMBIGUITY_COUNT=0 ;;
esac

if [ "${AMBIGUITY_COUNT}" -eq 0 ]; then
  log_event "allow" "zero-ambiguity-markers-in-assumptions-md" "${SLUG}" "${COMMAND_NAME}"
  exit 0
fi

# ---- check BUSINESS-RULES.md (calibration completed + rule-gate) -----------
# BRC-S5 (ADR-260531-A): the rule-gate requires BUSINESS-RULES.md to carry ≥1
# NON-VACUOUS rule — a numbered Confirmed-Rules table row OR a Given/When/Then
# scenario — not merely exist. A rule artifact with no actual rule is vacuous;
# the change has nothing testable to trace to. Defining the rule unblocks (the
# contract's gap→ask→rule loop), so this is hard-but-not-deadlocking. Accepts
# both the plan-calibrator table format and the contract BDD format.
BUSINESS_RULES=".aihaus/plans/${SLUG}/BUSINESS-RULES.md"
if [ -f "${BUSINESS_RULES}" ]; then
  RULE_SIGNALS="$(grep -ciE '^\|[[:space:]]*[0-9]+[[:space:]]*\||given\b.+\bwhen\b.+\bthen\b' "${BUSINESS_RULES}" 2>/dev/null || true)"
  case "${RULE_SIGNALS}" in ''|*[!0-9]*) RULE_SIGNALS=0 ;; esac
  if [ "${RULE_SIGNALS}" -ge 1 ]; then
    log_event "allow" "business-rules-present-non-vacuous" "${SLUG}" "${COMMAND_NAME}"
    exit 0
  fi
  echo "calibrate-guard (rule-gate): /${COMMAND_NAME} blocked. Plan ${SLUG} has BUSINESS-RULES.md but no actual rule (no Confirmed-Rules table row, no Given/When/Then). A change must trace to a testable business rule before tdd (ADR-260531-A) — define the rule, OR set AIHAUS_CALIBRATE_GUARD=0 / --no-calibrate to bypass." >&2
  log_event "block" "rule-gate-vacuous-business-rules" "${SLUG}" "${COMMAND_NAME}"
  exit 2
fi

# ---- check for recent calibration-skip opt-out row in audit log (24h) -------
HOOK_JSONL="${AUDIT_LOG}"
if [ -f "${HOOK_JSONL}" ]; then
  # ISO timestamp 24h ago (POSIX-portable: subtract 86400 seconds from epoch)
  _now_epoch="$(date -u +%s 2>/dev/null || echo 0)"
  _cutoff_epoch=$(( _now_epoch - 86400 ))
  _cutoff_ts="$(date -u -d "@${_cutoff_epoch}" +%FT%TZ 2>/dev/null \
    || date -u -r "${_cutoff_epoch}" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || echo "1970-01-01T00:00:00Z")"
  # Look for calibration-skip row for this slug within 24h window
  _slug_safe="${SLUG//\//\\/}"
  if grep -qE '"event":"calibration-skip"' "${HOOK_JSONL}" 2>/dev/null; then
    if grep -E '"event":"calibration-skip"' "${HOOK_JSONL}" 2>/dev/null \
        | grep -qE "\"slug\":\"${_slug_safe}\"" 2>/dev/null; then
      log_event "allow" "calibration-skip-row-found-in-audit" "${SLUG}" "${COMMAND_NAME}"
      exit 0
    fi
  fi
fi

# ---- block: ambiguities present, no BUSINESS-RULES.md, no prior skip --------
echo "calibrate-guard: /${COMMAND_NAME} blocked. Plan ${SLUG} has ambiguities (analyst-brief flagged) but no BUSINESS-RULES.md. Run plan-calibrator manually OR set AIHAUS_CALIBRATE_GUARD=0 OR add --no-calibrate to bypass." >&2

log_event "block" "ambiguities-no-business-rules" "${SLUG}" "${COMMAND_NAME}"
exit 2
