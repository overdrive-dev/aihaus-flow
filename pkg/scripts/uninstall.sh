#!/usr/bin/env bash
# aihaus uninstall script (Unix)
# Removes package-installed files while preserving user data.
# Flags:
#   --target <path>        Uninstall from <path> instead of $PWD
#   --purge                Remove EVERYTHING under .aihaus/ (including project.md)
#   --purge-user-global    Remove user-global aih-* skills from ~/.claude/skills/
#                          Only removes entries carrying the .aihaus-managed marker AND
#                          whose symlink target resolves under registered AIHAUS_HOME
#                          (R4 readlink validation — ADR-260504-A FR-06 + FR-21).
#                          Also purges tier-C global user preferences (M050/S06 /
#                          ADR-260611-E): ~/.aihaus/memory/user/ + prefs-audit JSONL.
#   -h, --help             Show usage
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: uninstall.sh [--target <path>] [--purge] [--purge-user-global]

Removes aihaus files from a target repository while preserving user data.

Options:
  --target <path>      Target directory (default: current working directory)
  --purge              Delete ALL .aihaus/ data including project.md (prompts)
  --purge-user-global  Remove user-global aih-* skills from ~/.claude/skills/
                       Only removes entries marked aihaus-owned AND whose symlink
                       target resolves under registered AIHAUS_HOME (R4 guard).
                       Also purges tier-C global user preferences (M050/S06,
                       ADR-260611-E): ~/.aihaus/memory/user/ and the prefs
                       audit JSONL ~/.aihaus/state/prefs-audit.jsonl.
  -h, --help           Show this message
EOF
}

TARGET="${PWD}"
PURGE="0"
PURGE_USER_GLOBAL="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      [[ $# -ge 2 ]] || { echo "ERROR: --target requires a path" >&2; exit 2; }
      TARGET="$2"; shift 2 ;;
    --purge) PURGE="1"; shift ;;
    --purge-user-global) PURGE_USER_GLOBAL="1"; shift ;;
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

# ---------------------------------------------------------------------------
# --purge-user-global: remove user-global aih-* skill dirs from ~/.claude/skills/
# Security boundary (ADR-260504-A FR-06 + FR-21 R4):
#   - Only removes dirs carrying a .aihaus-managed marker (aihaus-owned signal).
#   - readlink resolves symlink target; refuses if outside registered AIHAUS_HOME.
#   - Removes ~/.aihaus/.install-source registry after successful purge.
#   - Removes ~/.claude/hooks/session-start.sh if aihaus-managed marker present.
# ---------------------------------------------------------------------------
purge_user_global() {
  local user_skills_dir="$HOME/.claude/skills"
  local registry="$HOME/.aihaus/.install-source"
  local purge_touched="0"

  # Resolve registered AIHAUS_HOME from the install-source registry.
  if [[ ! -f "${registry}" ]]; then
    echo "  warn: ~/.aihaus/.install-source not found; no registered AIHAUS_HOME to validate against" >&2
    echo "  warn: user-global purge aborted (cannot perform R4 readlink validation without registry)" >&2
    return 1
  fi
  local aihaus_home
  aihaus_home="$(cat "${registry}" | tr -d '[:space:]')"
  if [[ -z "${aihaus_home}" ]]; then
    echo "  warn: ~/.aihaus/.install-source is empty; cannot resolve AIHAUS_HOME" >&2
    return 1
  fi
  # Resolve to canonical absolute path (guard against relative paths in registry).
  aihaus_home="$(cd "${aihaus_home}" 2>/dev/null && pwd)" || {
    echo "  warn: AIHAUS_HOME '${aihaus_home}' from registry does not exist on disk; R4 validation skipped" >&2
    return 1
  }

  echo "  user-global purge: AIHAUS_HOME=${aihaus_home}"

  # Iterate over every aih-* entry in the user-global skills dir.
  if [[ -d "${user_skills_dir}" ]]; then
    for entry in "${user_skills_dir}"/aih-*; do
      # glob may expand to literal string if no matches
      [[ -e "${entry}" || -L "${entry}" ]] || continue
      local entry_name
      entry_name="$(basename "${entry}")"

      # --- Marker check (FR-06) ---
      if [[ ! -f "${entry}/.aihaus-managed" ]]; then
        echo "skipping ~/.claude/skills/${entry_name}: no .aihaus-managed marker (not aihaus-owned)" >&2
        continue
      fi

      # --- R4 readlink validation (FR-21) ---
      # Resolve the symlink target. If it's not a symlink, use the dir itself.
      local resolved_target
      if [[ -L "${entry}" ]]; then
        resolved_target="$(readlink -f "${entry}" 2>/dev/null || true)"
      else
        # Copied dir: check .aihaus-managed source= line for origin path.
        # The marker file contains "source=<orig_path>" (ADR-260504-A §6.3).
        local src_line
        src_line="$(grep '^source=' "${entry}/.aihaus-managed" 2>/dev/null | head -1 | sed 's/^source=//' || true)"
        resolved_target="${src_line}"
      fi

      if [[ -z "${resolved_target}" ]]; then
        echo "skipping ~/.claude/skills/${entry_name}: symlink target outside registered AIHAUS_HOME (R4 guard)" >&2
        continue
      fi

      # Normalize: strip any trailing slash from aihaus_home for prefix comparison.
      local home_prefix="${aihaus_home%/}"
      case "${resolved_target}" in
        "${home_prefix}"/*|"${home_prefix}")
          : ;;  # target is under AIHAUS_HOME — safe to remove
        *)
          echo "skipping ~/.claude/skills/${entry_name}: symlink target outside registered AIHAUS_HOME (R4 guard)" >&2
          continue
          ;;
      esac

      # Both checks passed — remove the entry.
      rm -rf "${entry}"
      echo "  removed user-global: ~/.claude/skills/${entry_name}"
      purge_touched="1"
    done
  fi

  # --- Hook fragment cleanup (Z7 outcome — gate on marker existence) ---
  # If install.sh dropped a user-global hook fragment at ~/.claude/hooks/session-start.sh
  # and that file carries an .aihaus-managed marker line, remove it.
  local user_hook="$HOME/.claude/hooks/session-start.sh"
  if [[ -f "${user_hook}" ]] && grep -q "managed_by=aihaus" "${user_hook}" 2>/dev/null; then
    rm -f "${user_hook}"
    echo "  removed user-global: ~/.claude/hooks/session-start.sh"
    purge_touched="1"
    # Also remove now-empty hooks dir if empty.
    rmdir "$HOME/.claude/hooks" 2>/dev/null || true
  fi

  # --- Remove install-source registry after successful purge ---
  if [[ -f "${registry}" ]]; then
    rm -f "${registry}"
    echo "  removed: ~/.aihaus/.install-source"
    purge_touched="1"
  fi

  if [[ "${purge_touched}" == "0" ]]; then
    echo "  user-global: nothing to remove"
  fi
}

# ---------------------------------------------------------------------------
# Tier-C purge (M050/S06, ADR-260611-E standing checklist): remove the global
# user-preferences store (~/.aihaus/memory/user/) and the prefs-audit JSONL
# (~/.aihaus/state/prefs-audit.jsonl). Independent of the R4 registry guard
# above — these are plain aihaus-owned files, not symlinked skill dirs.
# ---------------------------------------------------------------------------
purge_tier_c() {
  local user_memory_dir="$HOME/.aihaus/memory/user"
  local prefs_audit="$HOME/.aihaus/state/prefs-audit.jsonl"
  local tier_c_touched="0"
  if [[ -d "${user_memory_dir}" ]]; then
    rm -rf "${user_memory_dir}"
    echo "  removed user-global: ~/.aihaus/memory/user/ (tier-C preferences)"
    tier_c_touched="1"
  fi
  if [[ -f "${prefs_audit}" ]]; then
    rm -f "${prefs_audit}"
    echo "  removed user-global: ~/.aihaus/state/prefs-audit.jsonl"
    tier_c_touched="1"
  fi
  if [[ "${tier_c_touched}" == "0" ]]; then
    echo "  tier-c: nothing to remove"
  fi
}

# Invoke user-global purge if flag was set.
if [[ "${PURGE_USER_GLOBAL}" == "1" ]]; then
  purge_user_global || true
  purge_tier_c || true
  touched="1"
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
