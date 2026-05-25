#!/usr/bin/env bash
# Verifies Claude Code project context bridge files for /aih-init.
set -u

TARGET="${PWD}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: claude-context-verify.sh [--target <repo>]"; exit 0 ;;
    *)
      echo "warn: unknown argument ignored: $1" >&2; shift ;;
  esac
done

ROOT="$(cd "$TARGET" 2>/dev/null && pwd)" || {
  echo "error: target not found: $TARGET" >&2
  exit 1
}

CLAUDE_DIR="${ROOT}/.claude"
REPORT_DIR="${ROOT}/.aihaus/audit"
REPORT="${REPORT_DIR}/claude-context-verify.md"
mkdir -p "${REPORT_DIR}" 2>/dev/null || true

issues=0
rows=""
add_row() {
  local status="$1" item="$2" detail="$3"
  rows="${rows}| ${status} | ${item} | ${detail} |"$'\n'
  [[ "${status}" == "WARN" ]] && issues=$((issues + 1))
}

check_file() {
  local rel="$1" label="$2"
  if [[ -f "${ROOT}/${rel}" ]]; then
    add_row "OK" "${label}" "${rel}"
  else
    add_row "WARN" "${label}" "missing: ${rel}"
  fi
}

check_file ".claude/CLAUDE.md" "Claude project memory"
check_file ".claude/rules/aihaus-project-memory.md" "Claude project rule"
check_file ".claude/settings.local.json" "Claude local settings"
check_file ".aihaus/project.md" "aihaus project context"
check_file ".aihaus/memory/workflows/environment.md" "workflow environment memory"

if [[ -f "${CLAUDE_DIR}/CLAUDE.md" ]]; then
  if grep -Fq "AIHAUS:CLAUDE-CONTEXT-START" "${CLAUDE_DIR}/CLAUDE.md"; then
    add_row "OK" "Managed aihaus block" "marker present"
  else
    add_row "WARN" "Managed aihaus block" "marker missing"
  fi

  while IFS= read -r import_line; do
    rel="${import_line#@}"
    rel="${rel%%[$'\r' ]*}"
    [[ -z "${rel}" ]] && continue
    if [[ -f "${CLAUDE_DIR}/${rel}" || -d "${CLAUDE_DIR}/${rel}" ]]; then
      add_row "OK" "Import ${import_line}" "resolved"
    else
      add_row "WARN" "Import ${import_line}" "target missing"
    fi
  done < <(grep -E '^@' "${CLAUDE_DIR}/CLAUDE.md" 2>/dev/null || true)
fi

if [[ -f "${ROOT}/CLAUDE.md" ]]; then
  add_row "OK" "Root CLAUDE.md" "present; Claude Code may also load root project memory"
else
  add_row "OK" "Root CLAUDE.md" "absent; .claude/CLAUDE.md is the aihaus bridge"
fi

verdict="PASS"
[[ "${issues}" -gt 0 ]] && verdict="WARN"
cat > "${REPORT}" <<EOF
# Claude Context Verification

Verdict: ${verdict}

| Status | Item | Detail |
|---|---|---|
${rows}
EOF

echo "claude context verification: ${verdict} (${issues} warning(s))"
echo "report: .aihaus/audit/claude-context-verify.md"
exit 0
