#!/usr/bin/env bash
# tdd-guard.sh — PreToolUse hook enforcing test-first on Write|Edit when testing_discipline=tdd
# (M028/S2 / ADR-260510-C)
#
# Fires on Write and Edit tool events. Checks project.md testing_discipline field.
# When tdd: blocks edits on non-test files unless a test file was written first in session.
#
# Session state tracked via .claude/audit/tdd-guard.session.{id}.json (marker file per session).
# First invocation per session reads project.md; subsequent reads use AIHAUS_TESTING_DISCIPLINE env
# (performance optimization R4 from PLAN risk table).
#
# Exit codes:
#   0 — allow (discipline != tdd, file is a test file, or test file already written this session)
#   2 — block (tdd + non-test file + no prior test file in session)
#
# Env:
#   AIHAUS_TDD_GUARD=0               — disable entirely (silent bypass; aih-quick Step 0 sets this)
#   AIHAUS_TESTING_DISCIPLINE=<val>  — override project.md read (cached by parent skill Step 0)
#   AIHAUS_AUDIT_LOG                 — override audit log path (default .claude/audit/hook.jsonl)
#   TDD_SESSION_TTL_MINUTES          — minutes before session marker expires (default 120)
#
# Refs: ADR-260510-C, M028/S2, PLAN Decision B (aih-quick bypass), PLAN Decision D (enum).

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/path-helpers.sh
. "${HOOK_DIR}/lib/path-helpers.sh"

# ---- env bypass (Decision B — aih-quick lifecycle + rollback opt-out) --------
if [ "${AIHAUS_TDD_GUARD:-1}" = "0" ]; then
  # Audit the bypass silently (fail-open on audit write)
  AUDIT_LOG="$(aihaus_project_path "${AIHAUS_AUDIT_LOG:-.claude/audit/hook.jsonl}")"
  mkdir -p "$(dirname "${AUDIT_LOG}")" 2>/dev/null || true
  printf '{"ts":"%s","hook":"tdd-guard","event":"tdd-guard","decision":"bypass","reason":"AIHAUS_TDD_GUARD=0","file_path":"","testing_discipline":""}\n' \
    "$(date -u +%FT%TZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z")" \
    >> "${AUDIT_LOG}" 2>/dev/null || true
  exit 0
fi

# ---- config ------------------------------------------------------------------
AUDIT_LOG="$(aihaus_project_path "${AIHAUS_AUDIT_LOG:-.claude/audit/hook.jsonl}")"
SESSION_MARKER_DIR="$(aihaus_project_path "${AIHAUS_SESSION_MARKER_DIR:-.claude/audit}")"
SESSION_TTL_MINUTES="${TDD_SESSION_TTL_MINUTES:-120}"

ts_iso() { date -u +%FT%TZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z"; }

# ---- audit helper ------------------------------------------------------------
# log_event <decision> <reason> <file_path> <discipline>
log_event() {
  local decision="${1:-allow}"
  local reason="${2:-}"
  local file_path="${3:-}"
  local discipline="${4:-}"
  mkdir -p "$(dirname "${AUDIT_LOG}")" 2>/dev/null || true
  local fp_safe="${file_path//\"/\\\"}"
  local reason_safe="${reason//\"/\\\"}"
  printf '{"ts":"%s","hook":"tdd-guard","event":"tdd-guard","decision":"%s","reason":"%s","file_path":"%s","testing_discipline":"%s"}\n' \
    "$(ts_iso)" "${decision}" "${reason_safe}" "${fp_safe}" "${discipline}" \
    >> "${AUDIT_LOG}" 2>/dev/null || true
}

# ---- session marker helpers (defined before use) ----------------------------
# Detect a stable session identifier. Use CLAUDE_SESSION_ID if set, else PID.
_session_id() {
  echo "${CLAUDE_SESSION_ID:-$$}"
}

_marker_path() {
  echo "${SESSION_MARKER_DIR}/tdd-guard.session.$(_session_id).json"
}

_mark_test_file_written() {
  local marker
  marker="$(_marker_path)"
  mkdir -p "${SESSION_MARKER_DIR}" 2>/dev/null || true
  local escaped_fp
  escaped_fp="${FILE_PATH//\"/\\\"}"
  printf '{"session_id":"%s","ts":"%s","test_files":["%s"]}\n' \
    "$(_session_id)" "$(ts_iso)" "${escaped_fp}" \
    > "${marker}" 2>/dev/null || true
}

_session_has_test_file() {
  local marker
  marker="$(_marker_path)"
  if [ ! -f "${marker}" ]; then
    return 1
  fi
  # Check TTL (file mtime-based age check via find -mmin).
  # find returns the file if it is NEWER than -TTL_MINUTES (i.e., still valid).
  # Fail-safe: if find -mmin is unsupported (Windows), skip expiry check (marker is valid).
  if command -v find >/dev/null 2>&1; then
    local recent
    recent="$(find "${marker}" -mmin "-${SESSION_TTL_MINUTES}" 2>/dev/null || echo "skip-ttl")"
    if [ -z "${recent}" ]; then
      return 1  # Expired (find returned no match)
    fi
    # "skip-ttl" means find failed; treat marker as valid (fail-safe)
  fi
  # Marker exists and is within TTL — check that test_files array is non-empty
  if command -v jq >/dev/null 2>&1; then
    local count
    count="$(jq -r '.test_files | length' "${marker}" 2>/dev/null || echo "0")"
    [ "${count}" -gt 0 ]
  else
    # Fallback: grep for a non-empty test_files array value
    grep -qE '"test_files":\s*\[".+"\]' "${marker}" 2>/dev/null
  fi
}

# ---- parse PreToolUse stdin JSON --------------------------------------------
# Write/Edit events carry .tool_input.file_path (per file-guard.sh pattern)
INPUT=$(cat)

TOOL_NAME=""
FILE_PATH=""

if command -v jq >/dev/null 2>&1; then
  TOOL_NAME="$(printf '%s' "${INPUT}" | jq -r '.tool_name // empty' 2>/dev/null || echo "")"
  FILE_PATH="$(printf '%s' "${INPUT}" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")"
else
  # Fallback: grep without jq (K-002 defensive pattern)
  TOOL_NAME="$(printf '%s' "${INPUT}" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' 2>/dev/null || echo "")"
  FILE_PATH="$(printf '%s' "${INPUT}" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' 2>/dev/null || echo "")"
fi

# ---- guard: only act on Write or Edit tool ----------------------------------
case "${TOOL_NAME}" in
  Write|Edit) : ;;
  *) exit 0 ;;
esac

# ---- resolve testing_discipline (R4: use env cache if set) ------------------
DISCIPLINE="${AIHAUS_TESTING_DISCIPLINE:-}"

if [ -z "${DISCIPLINE}" ]; then
  # First invocation per session: read project.md
  PROJECT_MD=".aihaus/project.md"
  if [ -f "${PROJECT_MD}" ]; then
    DISCIPLINE="$(grep -E '^testing_discipline:' "${PROJECT_MD}" | head -1 | sed 's/testing_discipline:[[:space:]]*//' | tr -d '[:space:]' 2>/dev/null || echo "")"
  fi
  # Default to none if not found or empty
  : "${DISCIPLINE:=none}"
fi

# ---- only enforce when discipline=tdd ---------------------------------------
if [ "${DISCIPLINE}" != "tdd" ]; then
  log_event "allow" "testing_discipline=${DISCIPLINE} (not tdd)" "${FILE_PATH}" "${DISCIPLINE}"
  exit 0
fi

# ---- test-file allowlist regex (R5 mitigation) ------------------------------
# Edits ON test files are ALWAYS allowed. This prevents false-positives when
# the user is writing the test themselves (the very act tdd-guard wants to see).
#
# Allowlist patterns (extensible per OQ-9):
#   tests/           Python/generic test dirs
#   __tests__/       Jest convention
#   test/            Ruby/Go/many langs
#   spec/            RSpec/Jasmine
#   e2e/             End-to-end test dirs
#   cypress/integration/  Cypress e2e
#   __specs__/       alternate spec dir
#   *_test.*         Go/Python: foo_test.go, foo_test.py
#   *.test.*         JS/TS: foo.test.js, foo.test.ts
#   *.spec.*         JS/TS: foo.spec.ts
#   _test.go         Go: trailing _test.go suffix
is_test_file() {
  local fp="$1"
  # Normalize to forward slashes for cross-platform matching
  local normalized
  normalized="$(printf '%s' "$fp" | tr '\\' '/')"
  if printf '%s' "${normalized}" | grep -qE \
    '(^|/)tests/|(^|/)__tests__/|(^|/)test/|(^|/)spec/|(^|/)e2e/|(^|/)cypress/integration/|(^|/)__specs__/|_test\.[^/]+$|\.test\.[^/]+$|\.spec\.[^/]+$'; then
    return 0
  fi
  return 1
}

if is_test_file "${FILE_PATH}"; then
  # Record that a test file was touched in this session (enables future non-test edits)
  _mark_test_file_written
  log_event "allow" "test-file-allowlist match" "${FILE_PATH}" "${DISCIPLINE}"
  exit 0
fi

# ---- check session state for test file pairing ------------------------------
if _session_has_test_file; then
  log_event "allow" "session-marker: test file edited in session" "${FILE_PATH}" "${DISCIPLINE}"
  exit 0
fi

# ---- block: tdd + non-test file + no prior test file in session -------------
fp_display="${FILE_PATH:-<unknown>}"
echo "tdd-guard: Write|Edit on ${fp_display} blocked. testing_discipline=tdd requires a test file edit/create in the same session before implementation. Allowlist regex matched paths bypass this check. Set AIHAUS_TDD_GUARD=0 to opt out." >&2

log_event "block" "no-test-file-in-session" "${FILE_PATH}" "${DISCIPLINE}"
exit 2
