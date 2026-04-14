#!/usr/bin/env bash
# aihaus uninstall script (Unix)
# Removes package-installed files while preserving user data.
# Flags:
#   --target <path>   Uninstall from <path> instead of $PWD
#   --purge           Remove EVERYTHING under .aihaus/ (including project.md)
#   -h, --help        Show usage
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: uninstall.sh [--target <path>] [--purge] [--platform <target>]

Removes aihaus files from a target repository while preserving user data.

Options:
  --target <path>      Target directory (default: current working directory)
  --purge              Delete ALL .aihaus/ data including project.md (prompts)
  --platform <name>    Uninstall from: claude | cursor | both (default: both)
  -h, --help           Show this message
EOF
}

TARGET="${PWD}"
PURGE="0"
PLATFORM="both"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      [[ $# -ge 2 ]] || { echo "ERROR: --target requires a path" >&2; exit 2; }
      TARGET="$2"; shift 2 ;;
    --purge) PURGE="1"; shift ;;
    --platform)
      [[ $# -ge 2 ]] || { echo "ERROR: --platform requires a value" >&2; exit 2; }
      case "$2" in
        claude|cursor|both) PLATFORM="$2" ;;
        *) echo "ERROR: --platform must be one of: claude, cursor, both" >&2; exit 2 ;;
      esac
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

TARGET="$(cd "${TARGET}" 2>/dev/null && pwd)" || {
  echo "ERROR: target directory does not exist: ${TARGET}" >&2; exit 1;
}

CLAUDE="${TARGET}/.claude"
AIHAUS="${TARGET}/.aihaus"
touched="0"

remove_claude_entry() {
  local name="$1"
  local path="${CLAUDE}/${name}"
  if [[ -L "${path}" ]]; then
    rm -f "${path}"; echo "  removed link: .claude/${name}"; touched="1"
  elif [[ -d "${path}" ]]; then
    rm -rf "${path}"; echo "  removed dir:  .claude/${name}"; touched="1"
  fi
}

remove_aihaus_sub() {
  local name="$1"
  local path="${AIHAUS}/${name}"
  if [[ -e "${path}" ]]; then
    rm -rf "${path}"; echo "  removed:      .aihaus/${name}"; touched="1"
  fi
}

# Purge mode: nuke everything after confirmation
if [[ "${PURGE}" == "1" ]]; then
  if [[ ! -e "${AIHAUS}" && ! -e "${CLAUDE}/skills" && ! -e "${CLAUDE}/agents" && ! -e "${CLAUDE}/hooks" ]]; then
    echo "Nothing to uninstall"
    exit 0
  fi
  echo "This will delete ALL .aihaus/ data including project.md."
  printf "Type 'yes' to confirm: "
  read -r reply
  if [[ "${reply}" != "yes" ]]; then
    echo "Aborted."
    exit 0
  fi
  if [[ "${PLATFORM}" == "claude" || "${PLATFORM}" == "both" ]]; then
    for name in skills agents hooks; do remove_claude_entry "${name}"; done
  fi
  if [[ -e "${AIHAUS}" ]]; then
    rm -rf "${AIHAUS}"; echo "  removed:      .aihaus/ (purged)"; touched="1"
  fi
else
  # Normal mode: remove package-installed parts only
  if [[ "${PLATFORM}" == "claude" || "${PLATFORM}" == "both" ]]; then
    for name in skills agents hooks; do remove_claude_entry "${name}"; done
  fi
  for name in skills agents hooks memory; do remove_aihaus_sub "${name}"; done
  # Remove install-mode markers (created by installer)
  if [[ -f "${AIHAUS}/.install-mode" ]]; then
    rm -f "${AIHAUS}/.install-mode"; touched="1"
  fi
  if [[ -f "${AIHAUS}/.install-platform" ]]; then
    rm -f "${AIHAUS}/.install-platform"; touched="1"
  fi
fi

# Cursor plugin cleanup (platform in {cursor, both})
if [[ "${PLATFORM}" == "cursor" || "${PLATFORM}" == "both" ]]; then
  CURSOR_LINK="${HOME}/.cursor/plugins/local/aihaus"
  if [[ -L "${CURSOR_LINK}" || -e "${CURSOR_LINK}" ]]; then
    rm -rf "${CURSOR_LINK}"
    echo "  removed:      ~/.cursor/plugins/local/aihaus"
    touched="1"
  fi
fi

# Settings cleanup: only remove keys listed in _aihaus_managed marker
SETTINGS="${CLAUDE}/settings.local.json"
if [[ -f "${SETTINGS}" ]]; then
  py_bin=""
  if command -v python3 >/dev/null 2>&1; then py_bin="$(command -v python3)"
  elif command -v python  >/dev/null 2>&1; then py_bin="$(command -v python)"
  elif command -v py      >/dev/null 2>&1; then py_bin="$(command -v py)"
  fi
  if [[ -n "${py_bin}" ]]; then
    if "${py_bin}" - "${SETTINGS}" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
managed = data.get("_aihaus_managed")
if not managed:
    sys.exit(2)  # no marker — leave file alone
for key_path in managed:
    parts = key_path.split(".")
    node = data
    for p in parts[:-1]:
        if not isinstance(node, dict) or p not in node:
            node = None; break
        node = node[p]
    if isinstance(node, dict):
        node.pop(parts[-1], None)
data.pop("_aihaus_managed", None)
with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2)
sys.exit(0)
PY
    then
      echo "  settings: cleaned aihaus-managed keys"; touched="1"
    fi
  else
    echo "  warn: no python available; leaving .claude/settings.local.json untouched"
  fi
fi

if [[ "${touched}" == "0" ]]; then
  echo "Nothing to uninstall"
  exit 0
fi

if [[ "${PURGE}" != "1" ]]; then
  echo ""
  echo "User data preserved at .aihaus/{milestones,features,bugfixes,plans}/"
fi
