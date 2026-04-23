#!/usr/bin/env bash
# aihaus update — re-syncs local .aihaus/ from pkg/ package source.
# Usage: bash pkg/scripts/update.sh [--target <path>]
#
# Re-links (or re-copies) skills, agents, hooks, templates from pkg/.aihaus/
# Preserves ALL local data: project.md, plans/, milestones/, memory/, etc.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: update.sh [--target <path>] [--migrate-memory] [--no-gitignore]

Re-syncs package-managed files in .aihaus/ from the aihaus package source.
Local data (project.md, plans/, milestones/, memory/, etc.) is preserved.

Options:
  --target <path>   Target directory (default: current working directory)
  --migrate-memory  Seed missing memory/*/README.md files from package source.
                    Existing files are NEVER overwritten (idempotent, opt-in).
                    Does NOT run as part of the default refresh loop.
  --no-gitignore    Skip the .gitignore backfill prompt entirely (non-interactive
                    CI runs, or users who have already declined and don't want
                    to be asked again).
  -h, --help        Show this message
EOF
}

# Resolve package root (the directory containing this script's parent)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PKG_AIHAUS="${PKG_ROOT}/.aihaus"
PKG_TEMPLATES="${PKG_ROOT}/templates"

TARGET="${PWD}"
MIGRATE_MEMORY=0
NO_GITIGNORE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      [[ $# -ge 2 ]] || { echo "ERROR: --target requires a path" >&2; exit 2; }
      TARGET="$2"
      shift 2
      ;;
    --migrate-memory)
      MIGRATE_MEMORY=1
      shift
      ;;
    --no-gitignore)
      NO_GITIGNORE=1
      shift
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

# ---- Restore per-agent effort from sidecar -----------------------------------
# Dispatch order (binding per architecture.md):
#   1. restore_effort   -- migrates v2 .calibration -> v3 .effort (if needed)
#                          or idempotent v3 restore.
# Call site pinned between refresh loop and link_or_copy so both .aihaus/agents/
# (physical) and .claude/agents/ (symlink or copy) pick up restored frontmatter.
# Missing sidecar = silent no-op. Schema contract: pkg/.aihaus/skills/
# aih-effort/annexes/state-file.md.
# shellcheck source=lib/restore-effort.sh
source "$(dirname "$0")/lib/restore-effort.sh"
restore_effort "${AIHAUS}"

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

# ---- Migrate memory README seeds (opt-in, ADR-M009-A safe) ------------------
# Only runs when --migrate-memory is passed. NEVER part of the default loop.
# For each memory sub-bucket, copies the package README.md if and only if the
# target file does not already exist. Existing content is never overwritten.
migrate_memory() {
  local count_created=0
  local count_skipped=0
  local subdirs=(global backend frontend reviews)

  echo ""
  echo "[migrate-memory] seeding memory README files (opt-in, non-destructive)"

  for subdir in "${subdirs[@]}"; do
    local src="${PKG_AIHAUS}/memory/${subdir}/README.md"
    local dst="${AIHAUS}/memory/${subdir}/README.md"

    if [[ ! -f "${src}" ]]; then
      echo "[migrate-memory]   SKIP  memory/${subdir}/README.md (source not found in package)"
      count_skipped=$((count_skipped + 1))
      continue
    fi

    if [[ -f "${dst}" ]]; then
      echo "[migrate-memory]   SKIP  memory/${subdir}/README.md (exists)"
      count_skipped=$((count_skipped + 1))
    else
      mkdir -p "${AIHAUS}/memory/${subdir}"
      cp "${src}" "${dst}"
      echo "[migrate-memory]   CREATE memory/${subdir}/README.md"
      count_created=$((count_created + 1))
    fi
  done

  echo "[migrate-memory] done: ${count_created} created, ${count_skipped} skipped"
}

if [[ "${MIGRATE_MEMORY}" -eq 1 ]]; then
  migrate_memory
fi

# ---- Gitignore backfill (existing-install gate) ------------------------------
# TODO: Document this carve-out prominently in v0.19.2 release notes —
#       update.sh scope expanded to write repo-root .gitignore behind explicit
#       user prompt gate. First time update.sh writes to repo root.
#
# Design: prompt fires once when the guard block is absent and --no-gitignore
# is not set. Idempotent: guard present → skip silently. Non-interactive CI:
# pass --no-gitignore to suppress. Per ADR-M015-B R3 mitigation.
_backfill_gitignore() {
  local target="$1"
  local gitignore="${target}/.gitignore"

  # Step 1: idempotency — guard-comment block already present?
  if grep -q "^# AIHAUS:GITIGNORE-START" "${gitignore}" 2>/dev/null; then
    # Already present — no prompt, no write.
    return 0
  fi
  # Secondary idempotency: hand-edited variant without the full guard comment?
  if grep -q "\.aihaus/audit" "${gitignore}" 2>/dev/null; then
    # Already has the relevant entries — skip to avoid duplication.
    return 0
  fi

  # Step 2: --no-gitignore flag bypasses prompt entirely
  if [[ "${NO_GITIGNORE}" -eq 1 ]]; then
    return 0
  fi

  # Step 3: prompt user (explicit gate — existing users may have intentional choices)
  echo ""
  printf 'aihaus v0.19.2+ recommends adding .aihaus/audit/ and .claude/audit/ to your .gitignore. Add now? [y/N] (skip with --no-gitignore): '
  read -r _answer </dev/tty 2>/dev/null || _answer=""

  # Step 4: on y/Y → inject guard block (idempotent write)
  if [[ "${_answer}" == "y" || "${_answer}" == "Y" ]]; then
    {
      printf '\n'
      printf '# AIHAUS:GITIGNORE-START -- managed by install.sh / update.sh; do not edit between markers\n'
      printf '/.aihaus/audit/\n'
      printf '/.claude/audit/\n'
      printf '/.aihaus/.context-budgets\n'
      printf '/.aihaus/.effort\n'
      printf '/.aihaus/.calibration\n'
      printf '/.aihaus/.install-mode\n'
      printf '/.aihaus/.install-source\n'
      printf '/.aihaus/.install-platform\n'
      printf '/.aihaus/.version\n'
      printf '/.aihaus/.enforcement\n'
      printf '/.aihaus/.automode\n'
      printf '# AIHAUS:GITIGNORE-END\n'
    } >> "${gitignore}" 2>/dev/null || {
      echo "  !! WARNING: could not write .gitignore at ${gitignore}" >&2
      echo "  !!          Apply manually from pkg/.aihaus/templates/gitignore-fragment" >&2
      return 0
    }
    echo "  .gitignore: aihaus block injected"
    return 0
  fi

  # Step 5: on N / empty → skip silently with one-line note
  echo "  Skipped — re-run with --no-gitignore to suppress this prompt next time, or rerun update.sh and answer y to add later."
}
_backfill_gitignore "${TARGET}"

# ---- Summary -----------------------------------------------------------------
echo ""
echo "Updated ${count_skills} skills, ${count_agents} agents, ${count_hooks} hooks"
echo "aihaus updated (${MODE} mode)."
exit 0
