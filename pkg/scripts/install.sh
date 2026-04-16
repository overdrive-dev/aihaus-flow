#!/usr/bin/env bash
# aihaus install script (Unix)
# Copies .aihaus/ into target repo and links .claude/{skills,agents,hooks}.
# Flags:
#   --target <path>   Install into <path> instead of $PWD
#   --copy            Copy files instead of creating symlinks
#   --update          Re-sync package dirs only; preserve local data
#   -h, --help        Show usage
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: install.sh [--target <path>] [--copy] [--update] [--platform <target>]

Installs aihaus into a target git repository.

Options:
  --target <path>      Target directory (default: current working directory)
  --copy               Copy files instead of symlinking (fallback for
                       locked-down environments)
  --update             Re-sync package dirs only; preserve local data
  --platform <name>    Install target: claude | cursor | both
                       Default: claude (preserves pre-v0.10.0 behavior).
                       cursor: also link ~/.cursor/plugins/local/aihaus.
                       both:   install for Claude Code AND Cursor.
  -h, --help           Show this message
EOF
}

# Resolve package root (the directory containing this script's parent)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PKG_AIHAUS="${PKG_ROOT}/.aihaus"
PKG_TEMPLATES="${PKG_ROOT}/templates"

TARGET="${PWD}"
MODE="link"
UPDATE="0"
PLATFORM="claude"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      [[ $# -ge 2 ]] || { echo "ERROR: --target requires a path" >&2; exit 2; }
      TARGET="$2"
      shift 2
      ;;
    --copy)
      MODE="copy"
      shift
      ;;
    --update)
      UPDATE="1"
      shift
      ;;
    --platform)
      [[ $# -ge 2 ]] || { echo "ERROR: --platform requires a value (claude|cursor|both)" >&2; exit 2; }
      case "$2" in
        claude|cursor|both) PLATFORM="$2" ;;
        *) echo "ERROR: --platform must be one of: claude, cursor, both" >&2; exit 2 ;;
      esac
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

if [[ "${UPDATE}" == "1" ]]; then
  echo "aihaus updater (via --update)"
else
  echo "aihaus installer"
fi
echo "  package:  ${PKG_ROOT}"
echo "  target:   ${TARGET}"
echo "  mode:     ${MODE}"
echo "  platform: ${PLATFORM}"

# Step 2: require a git repo
if [[ ! -d "${TARGET}/.git" ]] && ! git -C "${TARGET}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: Target must be a git repository. Run git init first." >&2
  exit 1
fi

if [[ "${UPDATE}" == "1" ]]; then
  # Update mode: require existing installation, refresh package dirs only
  if [[ ! -d "${TARGET}/.aihaus" ]]; then
    echo "ERROR: No .aihaus/ directory found. Run install.sh first (without --update)." >&2
    exit 1
  fi
  # Read install mode from marker if not explicitly overridden
  MODE_FILE="${TARGET}/.aihaus/.install-mode"
  if [[ -f "${MODE_FILE}" ]] && [[ "${MODE}" == "link" ]]; then
    SAVED_MODE="$(cat "${MODE_FILE}" | tr -d '[:space:]')"
    if [[ -n "${SAVED_MODE}" ]]; then
      MODE="${SAVED_MODE}"
    fi
  fi
  # Refresh only package-owned directories inside .aihaus/
  for name in skills agents hooks templates; do
    src="${PKG_AIHAUS}/${name}"
    dst="${TARGET}/.aihaus/${name}"
    if [[ ! -e "${src}" ]]; then
      echo "  skip: ${name} not found in package"
      continue
    fi
    if [[ -e "${dst}" ]]; then
      rm -rf "${dst}"
    fi
    cp -R "${src}" "${dst}"
    echo "  refreshed: .aihaus/${name}"
  done
  # Restore per-agent calibration from sidecar after agents/ wipe — pinned
  # between the refresh loop above and the .claude/ link_or_copy loop below,
  # mirroring update.sh's call site so both .aihaus/agents/ (physical) and
  # .claude/agents/ (symlink or copy) pick up restored frontmatter.
  # shellcheck source=lib/restore-calibration.sh
  source "$(dirname "$0")/lib/restore-calibration.sh"
  restore_calibration "${TARGET}/.aihaus"
else
  # Step 3: existing .aihaus/ prompt
  if [[ -e "${TARGET}/.aihaus" ]]; then
    printf "Existing .aihaus/ found. Overwrite? [y/N] "
    read -r reply
    case "${reply}" in
      y|Y|yes|YES) ;;
      *) echo "Aborted."; exit 0 ;;
    esac
    rm -rf "${TARGET}/.aihaus"
  fi

  # Step 4: copy package .aihaus/ into target
  mkdir -p "${TARGET}/.aihaus"
  cp -R "${PKG_AIHAUS}/." "${TARGET}/.aihaus/"
fi

# Step 5+6: create .claude/{skills,agents,hooks} as links or copies (Claude Code target)
link_or_copy() {
  local name="$1"
  local src="${TARGET}/.aihaus/${name}"
  local dst="${TARGET}/.claude/${name}"

  if [[ ! -e "${src}" ]]; then
    echo "  skip: ${src} does not exist in package"
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

if [[ "${PLATFORM}" == "claude" || "${PLATFORM}" == "both" ]]; then
  mkdir -p "${TARGET}/.claude"
  for name in skills agents hooks; do
    link_or_copy "${name}"
  done
fi

# Step 7: merge settings template into .claude/settings.local.json (Claude target only)
SETTINGS_SRC="${PKG_TEMPLATES}/settings.local.json"
SETTINGS_DST="${TARGET}/.claude/settings.local.json"

if [[ "${PLATFORM}" == "cursor" ]]; then
  : # skip settings merge on Cursor-only install
else
  # shellcheck source=lib/merge-settings.sh
  source "$(dirname "$0")/lib/merge-settings.sh"
  merge_settings "${SETTINGS_DST}" "${SETTINGS_SRC}"
fi

# Step 7.5: Cursor plugin setup (platform in {cursor, both})
if [[ "${PLATFORM}" == "cursor" || "${PLATFORM}" == "both" ]]; then
  CURSOR_PLUGINS_DIR="${HOME}/.cursor/plugins/local"
  CURSOR_LINK="${CURSOR_PLUGINS_DIR}/aihaus"
  PLUGIN_ROOT="${TARGET}/.aihaus"
  mkdir -p "${CURSOR_PLUGINS_DIR}"
  if [[ -L "${CURSOR_LINK}" || -e "${CURSOR_LINK}" ]]; then
    rm -rf "${CURSOR_LINK}"
  fi
  if [[ "${MODE}" == "link" ]]; then
    if ln -s "${PLUGIN_ROOT}" "${CURSOR_LINK}" 2>/dev/null; then
      echo "  link: ~/.cursor/plugins/local/aihaus -> ${PLUGIN_ROOT}"
    else
      echo "  warn: cursor symlink failed, falling back to copy"
      cp -R "${PLUGIN_ROOT}" "${CURSOR_LINK}"
      echo "  copy: ~/.cursor/plugins/local/aihaus"
    fi
  else
    cp -R "${PLUGIN_ROOT}" "${CURSOR_LINK}"
    echo "  copy: ~/.cursor/plugins/local/aihaus"
  fi
fi

# Step 8: write install mode marker
echo "${MODE}" > "${TARGET}/.aihaus/.install-mode"
echo "${PLATFORM}" > "${TARGET}/.aihaus/.install-platform"

# Step 9: success message
echo ""
if [[ "${UPDATE}" == "1" ]]; then
  echo "aihaus updated (${MODE} mode, platform: ${PLATFORM})."
else
  echo "aihaus installed (${MODE} mode, platform: ${PLATFORM})."
  if [[ "${PLATFORM}" == "cursor" || "${PLATFORM}" == "both" ]]; then
    echo "Restart Cursor to pick up the aihaus plugin."
  fi
  echo "Run /aih-init to bootstrap project.md"
fi
