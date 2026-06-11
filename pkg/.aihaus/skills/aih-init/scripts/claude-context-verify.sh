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
check_file ".aihaus/memory/workflows/business-rules.md" "workflow business rules"
check_file ".aihaus/memory/workflows/rules.md" "workflow rules memory"
check_file ".aihaus/memory/workflows/user-preferences.md" "workflow user preferences"
check_file ".aihaus/memory/workflows/gotchas.md" "workflow gotchas"

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

  for required_import in \
    "../.aihaus/project.md" \
    "../.aihaus/protocols/default.md" \
    "../.aihaus/protocols/agents.md" \
    "../.aihaus/protocols/routing.md" \
    "../.aihaus/memory/workflows/environment.md" \
    "../.aihaus/memory/workflows/business-rules.md" \
    "../.aihaus/memory/workflows/rules.md" \
    "../.aihaus/memory/workflows/user-preferences.md" \
    "../.aihaus/memory/workflows/gotchas.md"; do
    if grep -Fxq "@${required_import}" "${CLAUDE_DIR}/CLAUDE.md" 2>/dev/null; then
      add_row "OK" "Required import ${required_import}" "present"
    else
      add_row "WARN" "Required import ${required_import}" "missing from .claude/CLAUDE.md"
    fi
  done
fi

RULE_FILE="${CLAUDE_DIR}/rules/aihaus-project-memory.md"
if [[ -f "${RULE_FILE}" ]]; then
  rule_hits="$(grep -F '.aihaus/memory/workflows/business-rules.md' "${RULE_FILE}" 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "${rule_hits:-0}" -gt 1 ]]; then
    add_row "WARN" "Duplicate business-rules rule" "${rule_hits} entries; run project-context-refresh to resync managed block"
  else
    add_row "OK" "Business-rules rule" "deduplicated"
  fi
fi

FRESHNESS_REPORT="${ROOT}/.aihaus/audit/project-context-freshness.md"
if [[ -f "${FRESHNESS_REPORT}" ]]; then
  if grep -Eq '^Status:[[:space:]]*STALE' "${FRESHNESS_REPORT}" 2>/dev/null; then
    add_row "WARN" "Project context freshness" "STALE; run /aih-init to refresh generated project inventory"
  else
    add_row "OK" "Project context freshness" "not stale"
  fi
fi

AGENT_MEMORY_DIR="${CLAUDE_DIR}/agent-memory"
if [[ -d "${AGENT_MEMORY_DIR}" ]]; then
  aux_without_native=0
  checked_agent_dirs=0
  while IFS= read -r agent_dir; do
    checked_agent_dirs=$((checked_agent_dirs + 1))
    md_count="$(find "${agent_dir}" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "${md_count:-0}" -gt 0 && ! -f "${agent_dir}/MEMORY.md" ]]; then
      aux_without_native=$((aux_without_native + 1))
    fi
  done < <(find "${AGENT_MEMORY_DIR}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true)
  if [[ "${aux_without_native}" -gt 0 ]]; then
    add_row "WARN" "Agent native MEMORY.md coverage" "${aux_without_native}/${checked_agent_dirs} agent-memory dirs contain md files but no native MEMORY.md"
  else
    add_row "OK" "Agent native MEMORY.md coverage" "${checked_agent_dirs} agent-memory dirs checked"
  fi
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
