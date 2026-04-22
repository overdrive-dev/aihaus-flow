#!/usr/bin/env bash
# aihaus install script (Unix)
# Copies .aihaus/ into target repo and links .claude/{skills,agents,hooks}.
# Flags:
#   --target <path>   Install into <path> instead of $PWD
#   --copy            Copy files instead of creating symlinks
#   --update          Re-sync package dirs only; preserve local data
#   -h, --help        Show usage
set -euo pipefail

# Minimum Claude Code version supporting --dangerously-skip-permissions (DSP).
# TODO: Update this floor if the Claude Code changelog confirms a stricter minimum.
# Conservative default: 2.0.0 (DSP flag was present well before this release).
DSP_MIN_CLAUDE_VERSION="2.0.0"

usage() {
  cat <<'EOF'
Usage: install.sh [--target <path>] [--copy] [--update] [--platform <target>]

Installs aihaus into a target git repository.

Options:
  --target <path>      Target directory (default: current working directory)
  --copy               Copy files instead of symlinking (fallback for
                       locked-down environments)
  --update             Re-sync package dirs only; preserve local data
  --platform <name>    Install target: claude only.
                       cursor and both are rejected (M014+: DSP flag is
                       Claude-Code-CLI-only). See ADR-M014-A.
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
      PLATFORM="$2"
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

# Reject Cursor platform (M014+: DSP is Claude-Code-CLI-only per ADR-M014-A)
case "${PLATFORM}" in
  cursor|both)
    echo "ERROR: aihaus M014+ uses claude --dangerously-skip-permissions which is Claude-Code-CLI-only." >&2
    echo "Cursor install path is rejected. See ADR-M014-A and pkg/.aihaus/rules/COMPAT-MATRIX.md." >&2
    exit 1
    ;;
  claude)
    : ;;
  *)
    echo "ERROR: --platform must be one of: claude, cursor, both" >&2
    exit 2
    ;;
esac

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
  # Restore per-agent effort from sidecar after agents/ wipe -- pinned
  # between the refresh loop above and the .claude/ link_or_copy loop below,
  # mirroring update.sh's call site so both .aihaus/agents/ (physical) and
  # .claude/agents/ (symlink or copy) pick up restored frontmatter.
  # shellcheck source=lib/restore-effort.sh
  source "$(dirname "$0")/lib/restore-effort.sh"
  restore_effort "${TARGET}/.aihaus"
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

mkdir -p "${TARGET}/.claude"
for name in skills agents hooks; do
  link_or_copy "${name}"
done

# Step 6.5: create auto.sh wrapper symlink / copy (M014/S05)
WRAPPER_SRC="${SCRIPT_DIR}/launch-aihaus.sh"
WRAPPER_LINK="${TARGET}/.aihaus/auto.sh"
if [[ -f "${WRAPPER_SRC}" ]]; then
  if [[ "${MODE}" == "link" ]]; then
    if ln -sf "${WRAPPER_SRC}" "${WRAPPER_LINK}" 2>/dev/null; then
      echo "  link: .aihaus/auto.sh -> ${WRAPPER_SRC}"
    else
      echo "  warn: symlink failed for auto.sh, falling back to copy"
      cp -f "${WRAPPER_SRC}" "${WRAPPER_LINK}"
      chmod +x "${WRAPPER_LINK}" 2>/dev/null || true
      echo "  copy: .aihaus/auto.sh"
    fi
  else
    cp -f "${WRAPPER_SRC}" "${WRAPPER_LINK}"
    chmod +x "${WRAPPER_LINK}" 2>/dev/null || true
    echo "  copy: .aihaus/auto.sh"
  fi
else
  echo "  warn: launch-aihaus.sh not found at ${WRAPPER_SRC}, skipping auto.sh creation"
fi

# Step 7: merge settings template into .claude/settings.local.json (Claude target only)
SETTINGS_SRC="${PKG_TEMPLATES}/settings.local.json"
SETTINGS_DST="${TARGET}/.claude/settings.local.json"

# shellcheck source=lib/merge-settings.sh
source "$(dirname "$0")/lib/merge-settings.sh"
merge_settings "${SETTINGS_DST}" "${SETTINGS_SRC}"

# Step 8: write install mode marker
echo "${MODE}" > "${TARGET}/.aihaus/.install-mode"
echo "${PLATFORM}" > "${TARGET}/.aihaus/.install-platform"

# Step 9: DSP version-gate soft warning (LD-3: soft only, never exit non-zero)
if command -v claude >/dev/null 2>&1; then
  _claude_ver_raw="$(claude --version 2>/dev/null || true)"
  # Extract version number (e.g. "2.1.117 (Claude Code)" -> "2.1.117")
  _claude_ver="$(echo "${_claude_ver_raw}" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true)"
  if [[ -n "${_claude_ver}" ]]; then
    # Compare using sort -V (version sort)
    _lower="$(printf '%s\n%s\n' "${DSP_MIN_CLAUDE_VERSION}" "${_claude_ver}" | sort -V | head -1)"
    if [[ "${_lower}" != "${DSP_MIN_CLAUDE_VERSION}" ]] && [[ "${_claude_ver}" != "${DSP_MIN_CLAUDE_VERSION}" ]]; then
      echo ""
      echo "  !! WARNING: claude --version reports ${_claude_ver}."
      echo "  !! aihaus requires Claude Code >= ${DSP_MIN_CLAUDE_VERSION} for --dangerously-skip-permissions."
      echo "  !! Update Claude Code if you encounter permission errors when launching via auto.sh."
      echo "  !! (This is a soft warning -- install continues regardless.)"
    fi
  fi
fi

# Step 10: success message
echo ""
if [[ "${UPDATE}" == "1" ]]; then
  echo "aihaus updated (${MODE} mode, platform: ${PLATFORM})."
  echo "Launch with: bash .aihaus/auto.sh"
else
  echo "aihaus installed (${MODE} mode, platform: ${PLATFORM})."
  echo "Launch with: bash .aihaus/auto.sh"
  echo "Run /aih-init inside the launched session to bootstrap project.md"
fi
