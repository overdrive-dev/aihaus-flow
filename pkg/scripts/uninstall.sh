#!/usr/bin/env bash
# AIhaus uninstall script (Unix)
# Removes package-installed files while preserving user data.
# Flags:
#   --target <path>   Uninstall from <path> instead of $PWD
#   --purge           Remove EVERYTHING under .aihaus/ (including project.md)
#   -h, --help        Show usage
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: uninstall.sh [--target <path>] [--purge]

Removes AIhaus files from a target repository while preserving user data.

Options:
  --target <path>   Target directory (default: current working directory)
  --purge           Delete ALL .aihaus/ data including project.md (prompts)
  -h, --help        Show this message
EOF
}

TARGET="${PWD}"
PURGE="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      [[ $# -ge 2 ]] || { echo "ERROR: --target requires a path" >&2; exit 2; }
      TARGET="$2"; shift 2 ;;
    --purge) PURGE="1"; shift ;;
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
  for name in skills agents hooks; do remove_claude_entry "${name}"; done
  if [[ -e "${AIHAUS}" ]]; then
    rm -rf "${AIHAUS}"; echo "  removed:      .aihaus/ (purged)"; touched="1"
  fi
else
  # Normal mode: remove package-installed parts only
  for name in skills agents hooks; do remove_claude_entry "${name}"; done
  for name in skills agents hooks memory; do remove_aihaus_sub "${name}"; done
  # Remove install-mode marker (created by installer)
  if [[ -f "${AIHAUS}/.install-mode" ]]; then
    rm -f "${AIHAUS}/.install-mode"; touched="1"
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
      echo "  settings: cleaned AIhaus-managed keys"; touched="1"
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
