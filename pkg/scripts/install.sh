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
Usage: install.sh [--target <path>] [--copy] [--update]

Installs aihaus into a target git repository.

Options:
  --target <path>   Target directory (default: current working directory)
  --copy            Copy files instead of symlinking (fallback for
                    locked-down environments)
  --update          Re-sync package dirs only; preserve local data
  -h, --help        Show this message
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
echo "  package: ${PKG_ROOT}"
echo "  target:  ${TARGET}"
echo "  mode:    ${MODE}"

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

# Step 5+6: create .claude/{skills,agents,hooks} as links or copies
mkdir -p "${TARGET}/.claude"

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

for name in skills agents hooks; do
  link_or_copy "${name}"
done

# Step 7: merge settings template into .claude/settings.local.json
SETTINGS_SRC="${PKG_TEMPLATES}/settings.local.json"
SETTINGS_DST="${TARGET}/.claude/settings.local.json"

if [[ ! -f "${SETTINGS_SRC}" ]]; then
  echo "  warn: settings template missing at ${SETTINGS_SRC}, skipping merge"
else
  if [[ ! -f "${SETTINGS_DST}" ]]; then
    cp "${SETTINGS_SRC}" "${SETTINGS_DST}"
    echo "  settings: copied template"
  else
    # Merge: preserve user keys, add package required keys
    if command -v jq >/dev/null 2>&1; then
      tmp="$(mktemp)"
      jq -s '.[0] * .[1]' "${SETTINGS_DST}" "${SETTINGS_SRC}" > "${tmp}"
      mv "${tmp}" "${SETTINGS_DST}"
      echo "  settings: merged via jq"
    elif command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 || command -v py >/dev/null 2>&1; then
      py_bin="$(command -v python3 || command -v python || command -v py)"
      "${py_bin}" - "${SETTINGS_DST}" "${SETTINGS_SRC}" <<'PY'
import json, sys

dst_path, src_path = sys.argv[1], sys.argv[2]
with open(dst_path, "r", encoding="utf-8") as fh:
    dst = json.load(fh)
with open(src_path, "r", encoding="utf-8") as fh:
    src = json.load(fh)

def deep_merge(base, overlay):
    if isinstance(base, dict) and isinstance(overlay, dict):
        out = dict(base)
        for k, v in overlay.items():
            out[k] = deep_merge(base.get(k), v) if k in base else v
        return out
    return overlay if overlay is not None else base

merged = deep_merge(dst, src)
with open(dst_path, "w", encoding="utf-8") as fh:
    json.dump(merged, fh, indent=2)
PY
      echo "  settings: merged via python"
    else
      echo "  warn: neither jq nor python available; leaving settings.local.json untouched"
    fi
  fi
fi

# Step 8: write install mode marker
echo "${MODE}" > "${TARGET}/.aihaus/.install-mode"

# Step 9: success message
echo ""
if [[ "${UPDATE}" == "1" ]]; then
  echo "aihaus updated (${MODE} mode)."
else
  echo "aihaus installed (${MODE} mode)."
  echo "Run /aih-init to bootstrap project.md"
fi
