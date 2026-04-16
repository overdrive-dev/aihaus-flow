#!/usr/bin/env bash
# aihaus update — re-syncs local .aihaus/ from pkg/ package source.
# Usage: bash pkg/scripts/update.sh [--target <path>]
#
# Re-links (or re-copies) skills, agents, hooks, templates from pkg/.aihaus/
# Preserves ALL local data: project.md, plans/, milestones/, memory/, etc.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: update.sh [--target <path>]

Re-syncs package-managed files in .aihaus/ from the aihaus package source.
Local data (project.md, plans/, milestones/, memory/, etc.) is preserved.

Options:
  --target <path>   Target directory (default: current working directory)
  -h, --help        Show this message
EOF
}

# Resolve package root (the directory containing this script's parent)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PKG_AIHAUS="${PKG_ROOT}/.aihaus"
PKG_TEMPLATES="${PKG_ROOT}/templates"

TARGET="${PWD}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      [[ $# -ge 2 ]] || { echo "ERROR: --target requires a path" >&2; exit 2; }
      TARGET="$2"
      shift 2
      ;;
    -h|--help)
      usage; exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# Absolute path for target
TARGET="$(cd "${TARGET}" 2>/dev/null && pwd)" || {
  echo "ERROR: target directory does not exist: ${TARGET}" >&2
  exit 1
}

AIHAUS="${TARGET}/.aihaus"
CLAUDE="${TARGET}/.claude"

# ---- Preflight checks -------------------------------------------------------

if [[ ! -d "${AIHAUS}" ]]; then
  echo "ERROR: No .aihaus/ directory found at ${TARGET}." >&2
  echo "  Run install.sh first." >&2
  exit 1
fi

# Read install mode from marker file
MODE_FILE="${AIHAUS}/.install-mode"
if [[ -f "${MODE_FILE}" ]]; then
  MODE="$(cat "${MODE_FILE}" | tr -d '[:space:]')"
else
  # Default to copy if no marker exists (legacy installs)
  MODE="copy"
  echo "  warn: .install-mode not found; defaulting to copy mode"
fi

echo "aihaus updater"
echo "  package: ${PKG_ROOT}"
echo "  target:  ${TARGET}"
echo "  mode:    ${MODE}"

# ---- Counters for summary ----------------------------------------------------
count_skills=0
count_agents=0
count_hooks=0

# ---- Update package directories in .aihaus/ ---------------------------------
# These are the package-owned directories that get refreshed.
# Local data directories (plans/, milestones/, features/, bugfixes/, memory/,
# rules/, notion/, debug/) are NEVER touched.

update_aihaus_dir() {
  local name="$1"
  local src="${PKG_AIHAUS}/${name}"
  local dst="${AIHAUS}/${name}"

  if [[ ! -e "${src}" ]]; then
    echo "  skip: ${name} not found in package"
    return 0
  fi

  # Remove old directory contents and replace with fresh copy from package
  if [[ -e "${dst}" ]]; then
    rm -rf "${dst}"
  fi
  cp -R "${src}" "${dst}"
  echo "  refreshed: .aihaus/${name}"
}

for name in skills agents hooks templates; do
  update_aihaus_dir "${name}"
done

# ---- Restore per-agent calibration from sidecar ------------------------------
# Reads .aihaus/.calibration (schema v1) and re-applies recorded effort tiers
# to refreshed agent frontmatters. Call site is pinned between the refresh
# loop above and the link_or_copy loop below so both .aihaus/agents/ (physical)
# and .claude/agents/ (symlink or copy) pick up restored frontmatter.
# Missing sidecar = silent no-op. Schema contract: pkg/.aihaus/skills/
# aih-calibrate/annexes/state-file.md.
restore_calibration() {
  local state_file="${AIHAUS}/.calibration"
  [[ -f "$state_file" ]] || return 0

  # Schema gate — unknown versions bail with a loud warning, leave defaults.
  local schema
  schema=$(grep -E '^schema=' "$state_file" | head -1 | cut -d= -f2 | tr -d '[:space:]\r')
  if [[ "$schema" != "1" ]]; then
    echo "  warn: unknown .calibration schema='${schema}' — skipping restore"
    return 0
  fi

  local restored=0 skipped=0
  while IFS='=' read -r key value; do
    # Skip blank lines and comments.
    [[ -z "$key" || "$key" =~ ^# ]] && continue
    # Skip metadata keys — only per-agent lines past this point.
    [[ "$key" =~ ^(schema|permission_mode|last_preset|last_commit)$ ]] && continue
    # CRLF normalization — Windows-authored sidecars (F-008).
    value="${value%$'\r'}"
    # Defensive: whitespace-only values skip.
    [[ -z "$value" || "$value" =~ ^[[:space:]]+$ ]] && continue

    local agent_file="${AIHAUS}/agents/${key}.md"
    if [[ -f "$agent_file" ]]; then
      sed -i.bak "s/^effort: .*/effort: ${value}/" "$agent_file" && rm -f "${agent_file}.bak"
      restored=$((restored + 1))
    else
      skipped=$((skipped + 1))
      echo "  warn: .calibration references missing agent '${key}' — skipped"
    fi
  done < "$state_file"

  if [[ "$skipped" -gt 0 ]]; then
    echo "  restored ${restored} per-agent effort override(s) from .aihaus/.calibration (${skipped} skipped — missing agents)"
  else
    echo "  restored ${restored} per-agent effort override(s) from .aihaus/.calibration"
  fi

  # Loud warning when auto-mode-safe was the last preset — side effects
  # (auto-approve-bash.sh SAFE_PATTERNS widening + worktree agents'
  # permissionMode removal) are NOT auto-restored and must be re-applied
  # by re-running the preset.
  local last_preset
  last_preset=$(grep -E '^last_preset=' "$state_file" | head -1 | cut -d= -f2 | tr -d '[:space:]\r')
  if [[ "$last_preset" == "auto-mode-safe" ]]; then
    echo ""
    echo "  !!  Your last preset was auto-mode-safe, but side effects"
    echo "  !!  (auto-approve-bash.sh SAFE_PATTERNS widening + worktree"
    echo "  !!  agents' permissionMode removal) are NOT auto-restored."
    echo "  !!  Classifier pauses may occur until you re-run:"
    echo "  !!    /aih-calibrate --preset auto-mode-safe"
    echo ""
  fi
}

restore_calibration

# Count what was updated
if [[ -d "${AIHAUS}/skills" ]]; then
  count_skills=$(find "${AIHAUS}/skills" -type f -name 'SKILL.md' 2>/dev/null | wc -l | tr -d ' ')
fi
if [[ -d "${AIHAUS}/agents" ]]; then
  count_agents=$(find "${AIHAUS}/agents" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
fi
if [[ -d "${AIHAUS}/hooks" ]]; then
  count_hooks=$(find "${AIHAUS}/hooks" -maxdepth 1 -type f -name '*.sh' 2>/dev/null | wc -l | tr -d ' ')
fi

# ---- Re-link / re-copy .claude/{skills,agents,hooks} ------------------------

link_or_copy() {
  local name="$1"
  local src="${AIHAUS}/${name}"
  local dst="${CLAUDE}/${name}"

  if [[ ! -e "${src}" ]]; then
    echo "  skip: ${src} does not exist"
    return 0
  fi

  # Remove stale destination
  if [[ -L "${dst}" || -e "${dst}" ]]; then
    rm -rf "${dst}"
  fi

  if [[ "${MODE}" == "link" ]]; then
    if ln -s "${src}" "${dst}" 2>/dev/null; then
      echo "  link: .claude/${name} -> .aihaus/${name}"
      return 0
    fi
    echo "  warn: symlink failed for ${name}, falling back to copy"
    MODE="copy"
  fi
  cp -R "${src}" "${dst}"
  echo "  copy: .claude/${name}"
}

mkdir -p "${CLAUDE}"
for name in skills agents hooks; do
  link_or_copy "${name}"
done

# ---- Deep-merge settings template -------------------------------------------
SETTINGS_SRC="${PKG_TEMPLATES}/settings.local.json"
SETTINGS_DST="${CLAUDE}/settings.local.json"

# shellcheck source=lib/merge-settings.sh
source "$(dirname "$0")/lib/merge-settings.sh"
merge_settings "${SETTINGS_DST}" "${SETTINGS_SRC}"

# ---- Update install mode marker ----------------------------------------------
echo "${MODE}" > "${AIHAUS}/.install-mode"

# ---- Summary -----------------------------------------------------------------
echo ""
echo "Updated ${count_skills} skills, ${count_agents} agents, ${count_hooks} hooks"
echo "aihaus updated (${MODE} mode)."
exit 0
