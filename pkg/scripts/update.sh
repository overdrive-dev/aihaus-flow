#!/usr/bin/env bash
# aihaus update — re-syncs local .aihaus/ from pkg/ package source.
# Usage: bash pkg/scripts/update.sh [--target <path>] [--self]
#
# Re-links (or re-copies) skills, agents, hooks, templates from pkg/.aihaus/
# Preserves ALL local data: project.md, plans/, milestones/, memory/, etc.
#
# V5 (M022/Z9): user-global skill refresh + R3 dogfood guard + --self + R9 copy-mode
# FR-23: user-global refresh on every update
# FR-24: R4 marker invariant — never touch unmarked entries
# FR-25: R3 dogfood guard — skip git pull on dogfood cwd
# FR-26: R9 copy-mode user-global refresh
# ADR-260504-A §6.4
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: update.sh [--target <path>] [--migrate-memory] [--no-gitignore] [--self]

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
  --self            Pull from origin before refreshing. Used by 'aihaus self-update'.
                    Aborts with exit 3 if cwd is dogfood and has uncommitted changes.
  -h, --help        Show this message
EOF
}

# ---------------------------------------------------------------------------
# V5 (M022/Z9): Dogfood detection — matches Z3's is_dogfood_cwd exactly.
# Returns 0 (true) when the current working directory IS the central aihaus clone.
# Predicate: pkg/scripts/install.sh + pkg/.aihaus/skills/ both exist in PWD.
# ---------------------------------------------------------------------------
is_dogfood_cwd() {
  [[ -f "${PWD}/pkg/scripts/install.sh" ]] && [[ -d "${PWD}/pkg/.aihaus/skills" ]]
}

# Resolve package root (the directory containing this script's parent)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PKG_AIHAUS="${PKG_ROOT}/.aihaus"
PKG_TEMPLATES="${PKG_ROOT}/templates"

TARGET="${PWD}"
MIGRATE_MEMORY=0
NO_GITIGNORE=0
SELF_MODE=0

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
    --self)
      SELF_MODE=1
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

# ---------------------------------------------------------------------------
# V5 (M022/Z9): R3 dogfood guard + --self / R8 dirty-dogfood abort
# Must run BEFORE preflight checks that require .aihaus/ to exist.
# ---------------------------------------------------------------------------
if is_dogfood_cwd; then
  if [[ "${SELF_MODE}" -eq 1 ]]; then
    # R8: --self on dogfood — abort if dirty
    if [[ -n "$(git -C "${PWD}" status --porcelain 2>/dev/null)" ]]; then
      echo "aihaus self-update: uncommitted changes — aborting (commit or stash manually first)" >&2
      exit 3
    fi
    echo "  dogfood mode + --self: pulling from origin..."
    git -C "${PWD}" pull
    # After git pull, PKG_ROOT may have shifted; recalculate derived paths.
    PKG_AIHAUS="${PKG_ROOT}/.aihaus"
    PKG_TEMPLATES="${PKG_ROOT}/templates"
  else
    # R3: dogfood cwd without --self — skip git pull, continue with skill refresh
    echo "  dogfood mode — git pull skipped; commit local changes before self-update"
  fi
fi

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

# ---- Refresh auto.sh from launch-aihaus.sh on hash change (M019/S02 F-C3 fix) --
# Previously update.sh only refreshed skills/agents/hooks/templates; this block
# closes the gap so CLI-005 env defaults (and any future launch-aihaus.sh edits)
# reach existing installs automatically. SHA comparison avoids needless writes.
_LAUNCH_SRC="${SCRIPT_DIR}/launch-aihaus.sh"
_AUTO_DST="${AIHAUS}/auto.sh"
if [[ -f "${_LAUNCH_SRC}" ]]; then
  if [[ -f "${_AUTO_DST}" ]]; then
    _src_sha="$(sha256sum "${_LAUNCH_SRC}" 2>/dev/null | awk '{print $1}' || shasum -a 256 "${_LAUNCH_SRC}" 2>/dev/null | awk '{print $1}')"
    _dst_sha="$(sha256sum "${_AUTO_DST}"   2>/dev/null | awk '{print $1}' || shasum -a 256 "${_AUTO_DST}"   2>/dev/null | awk '{print $1}')"
    if [[ "${_src_sha}" != "${_dst_sha}" ]]; then
      cp -f "${_LAUNCH_SRC}" "${_AUTO_DST}"
      chmod +x "${_AUTO_DST}" 2>/dev/null || true
      echo "  auto.sh refreshed from launch-aihaus.sh"
    fi
  else
    cp -f "${_LAUNCH_SRC}" "${_AUTO_DST}"
    chmod +x "${_AUTO_DST}" 2>/dev/null || true
    echo "  auto.sh created from launch-aihaus.sh"
  fi
else
  echo "  warn: launch-aihaus.sh not found at ${_LAUNCH_SRC}, skipping auto.sh refresh"
fi

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
# shellcheck source=lib/junction-safe.sh
source "$(dirname "$0")/lib/junction-safe.sh"

link_or_copy() {
  local name="$1"
  local src="${AIHAUS}/${name}"
  local dst="${CLAUDE}/${name}"

  if [[ ! -e "${src}" ]]; then
    echo "  skip: ${src} does not exist"
    return 0
  fi

  # Remove stale destination (junction-safe on Windows — see lib/junction-safe.sh)
  safe_remove_dir "${dst}"

  if [[ "${MODE}" == "link" ]]; then
    if make_dir_link "${src}" "${dst}"; then
      echo "  link: .claude/${name} -> .aihaus/${name}"
      return 0
    fi
    echo "  warn: link failed for ${name} (${LINK_ERR}), falling back to copy"
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

# ---- Drift-detect: prompt recompute if hook count fell behind template ------
# ADR-260514-B Half B rollout closure. Compares template hook count vs user's
# merged settings hook count for each .hooks.<Event>[]. If any Event has
# template_count - user_count >= AIHAUS_DRIFT_THRESHOLD (default 2), prompt user
# to recompute with AIHAUS_RECOMPUTE_MERGE=1 (which re-merges with template-wins
# at outer level, preserving user-customs at inner .command level).
# Non-interactive opt-out: AIHAUS_DRIFT_PROMPT=0 (CI-safe).
# Sentinel: .aihaus/.recompute-skipped-260514 (written on N answer; suppresses
# future prompts until user deletes the sentinel).
if [[ "${AIHAUS_DRIFT_PROMPT:-}" != "0" ]] && [[ -f "${SETTINGS_DST}" ]] && [[ -f "${SETTINGS_SRC}" ]]; then
  _sentinel_path="${AIHAUS}/.recompute-skipped-260514"
  if [[ -f "${_sentinel_path}" ]]; then
    echo "  drift-detect: recompute skipped (sentinel present)" >&2
  else
    _py_bin_drift="$(command -v python3 || command -v python || command -v py || true)"
    if [[ -n "${_py_bin_drift}" ]]; then
      _drift_settings_src="${SETTINGS_SRC}"
      _drift_settings_dst="${SETTINGS_DST}"
      if command -v cygpath >/dev/null 2>&1; then
        _drift_settings_src="$(cygpath -w "${SETTINGS_SRC}" 2>/dev/null || echo "${SETTINGS_SRC}")"
        _drift_settings_dst="$(cygpath -w "${SETTINGS_DST}" 2>/dev/null || echo "${SETTINGS_DST}")"
      fi
      _drift_result=$("${_py_bin_drift}" -c "
import json, sys
threshold = int(sys.argv[3])
with open(sys.argv[1]) as f: tmpl = json.load(f)
with open(sys.argv[2]) as f: user = json.load(f)
tmpl_hooks = tmpl.get('hooks', {})
user_hooks = user.get('hooks', {})
max_delta = 0
max_event = ''
for event, entries in tmpl_hooks.items():
    tmpl_count = sum(len(e.get('hooks', [])) for e in entries)
    user_count = sum(len(e.get('hooks', [])) for e in user_hooks.get(event, []))
    delta = tmpl_count - user_count
    if delta > max_delta:
        max_delta = delta
        max_event = event
if max_delta >= threshold:
    print('drift:' + str(max_delta) + ':' + max_event)
else:
    print('no-drift')
" "${_drift_settings_src}" "${_drift_settings_dst}" "${AIHAUS_DRIFT_THRESHOLD:-2}" 2>/dev/null || echo "no-drift")

      if [[ "${_drift_result}" == drift:* ]]; then
        _drift_n="${_drift_result#drift:}"
        _drift_event="${_drift_n#*:}"
        _drift_n="${_drift_n%%:*}"
        if [[ -t 0 ]]; then
          printf "  Detected %s missing canonical hook entries from %s. Recompute merged settings now? [Y/n] " \
            "${_drift_n}" "${_drift_event}"
          read -r _drift_answer </dev/tty 2>/dev/null || _drift_answer="n"
        else
          _drift_answer="n"
        fi
        if [[ "${_drift_answer}" =~ ^[Yy]$ ]] || [[ -z "${_drift_answer}" ]]; then
          echo "  drift-detect: recomputing merged settings..."
          AIHAUS_RECOMPUTE_MERGE=1 merge_settings "${SETTINGS_DST}" "${SETTINGS_SRC}"
        else
          touch "${_sentinel_path}"
          echo "  drift-detect: skipped; sentinel written to suppress future prompts" >&2
        fi
      fi
    fi
  fi
fi

# ---- Update install mode marker ----------------------------------------------
echo "${MODE}" > "${AIHAUS}/.install-mode"

# ---------------------------------------------------------------------------
# V5 (M022/Z9): User-global skill refresh — FR-23/FR-24/FR-26; ADR-260504-A §6.3
# Refreshes ~/.claude/skills/aih-* entries that carry the .aihaus-managed marker.
# R4 invariant: never touch entries without the marker.
# R9 copy-mode: if user-global entries are copies (no symlink), re-copy SKILL.md.
# Orphan removal: remove entries for skills no longer in pkg/.aihaus/skills/ (marker required).
# ---------------------------------------------------------------------------
_refresh_user_global_skills() {
  local pkg_skills_dir="${PKG_ROOT}/.aihaus/skills"
  local user_global_skills="${HOME}/.claude/skills"

  # No user-global skills dir at all — nothing to refresh.
  if [[ ! -d "${user_global_skills}" ]]; then
    return 0
  fi

  # Detect whether to use Windows native junctions (Git Bash on Windows, not WSL2).
  local use_junction=0
  if [[ "${OS:-}" == "Windows_NT" ]] && [[ -z "${WSL_DISTRO_NAME:-}" ]]; then
    use_junction=1
  fi

  local refreshed_count=0
  local skipped_count=0
  local orphan_count=0

  # ---- Pass 1: refresh existing user-global entries that carry the marker ----
  for target_dir in "${user_global_skills}"/aih-*; do
    [[ -d "${target_dir}" ]] || [[ -L "${target_dir}" ]] || continue

    local skill_name
    skill_name="$(basename "${target_dir}")"

    # R4: only touch marker-owned entries.
    if [[ ! -f "${target_dir}/.aihaus-managed" ]]; then
      skipped_count=$((skipped_count + 1))
      continue
    fi

    local pkg_skill_dir="${pkg_skills_dir}/${skill_name}"

    # Orphan removal: skill no longer in package AND carries marker.
    if [[ ! -d "${pkg_skill_dir}" ]]; then
      rm -rf "${target_dir}" 2>/dev/null || true
      echo "  user-global orphan removed: ${skill_name}"
      orphan_count=$((orphan_count + 1))
      continue
    fi

    # Detect copy-mode for this entry:
    # copy-mode = entry is a real directory (not a symlink/junction) OR
    #             .aihaus-copy-mode marker exists at user-global level.
    local entry_is_copy=0
    if [[ -f "${HOME}/.claude/.aihaus-copy-mode" ]]; then
      entry_is_copy=1
    elif [[ -L "${target_dir}" ]]; then
      entry_is_copy=0  # symlink — link mode
    elif [[ "${use_junction}" == "1" ]]; then
      # On Windows: junctions show as directories without -L; check reparse point
      # by testing if readlink has output (Git Bash exposes junction as symlink).
      if readlink "${target_dir}" >/dev/null 2>&1; then
        entry_is_copy=0  # junction treated as link
      else
        entry_is_copy=1  # real copy
      fi
    else
      entry_is_copy=1  # real directory on Unix — was a copy
    fi

    if [[ "${entry_is_copy}" == "1" ]]; then
      # R9 copy-mode: re-copy SKILL.md (and the whole skill dir) from package.
      rm -rf "${target_dir}" 2>/dev/null || true
      cp -R "${pkg_skill_dir}" "${target_dir}"
      # Restore the .aihaus-managed marker (cp preserved it, but be explicit).
      {
        printf 'managed_by=aihaus\n'
        printf 'source=%s\n' "${pkg_skill_dir}"
      } > "${target_dir}/.aihaus-managed"
      echo "  user-global refreshed (copy): ${skill_name}"
    else
      # Link mode: update the symlink/junction to the latest pkg path.
      rm -rf "${target_dir}" 2>/dev/null || true
      if [[ "${use_junction}" == "1" ]]; then
        local win_target win_skill
        win_target="$(cygpath -w "${target_dir}" 2>/dev/null || echo "${target_dir}")"
        win_skill="$(cygpath -w "${pkg_skill_dir}" 2>/dev/null || echo "${pkg_skill_dir}")"
        if ! cmd.exe /c "mklink /J \"${win_target}\" \"${win_skill}\"" >/dev/null 2>&1; then
          echo "  warn: junction refresh failed for ${skill_name}; falling back to copy" >&2
          cp -R "${pkg_skill_dir}" "${target_dir}"
        fi
      else
        if ! ln -s "${pkg_skill_dir}" "${target_dir}" 2>/dev/null; then
          echo "  warn: symlink refresh failed for ${skill_name}; falling back to copy" >&2
          cp -R "${pkg_skill_dir}" "${target_dir}"
        fi
      fi
      # Re-drop .aihaus-managed marker (symlink target may have moved; always write).
      {
        printf 'managed_by=aihaus\n'
        printf 'source=%s\n' "${pkg_skill_dir}"
      } > "${target_dir}/.aihaus-managed"
      echo "  user-global refreshed (link): ${skill_name}"
    fi
    refreshed_count=$((refreshed_count + 1))
  done

  # ---- Pass 2: install user-global entries for new skills not yet present ----
  for pkg_skill_dir in "${pkg_skills_dir}"/aih-*; do
    [[ -d "${pkg_skill_dir}" ]] || continue
    local skill_name
    skill_name="$(basename "${pkg_skill_dir}")"
    local target_dir="${user_global_skills}/${skill_name}"

    # Already handled in Pass 1 (exists and has marker) or collision-protected.
    if [[ -e "${target_dir}" ]] || [[ -L "${target_dir}" ]]; then
      continue
    fi

    # Install new skill entry.
    if [[ -f "${HOME}/.claude/.aihaus-copy-mode" ]]; then
      cp -R "${pkg_skill_dir}" "${target_dir}"
    elif [[ "${use_junction}" == "1" ]]; then
      local win_target win_skill
      win_target="$(cygpath -w "${target_dir}" 2>/dev/null || echo "${target_dir}")"
      win_skill="$(cygpath -w "${pkg_skill_dir}" 2>/dev/null || echo "${pkg_skill_dir}")"
      if ! cmd.exe /c "mklink /J \"${win_target}\" \"${win_skill}\"" >/dev/null 2>&1; then
        cp -R "${pkg_skill_dir}" "${target_dir}"
      fi
    else
      if ! ln -s "${pkg_skill_dir}" "${target_dir}" 2>/dev/null; then
        cp -R "${pkg_skill_dir}" "${target_dir}"
      fi
    fi

    {
      printf 'managed_by=aihaus\n'
      printf 'source=%s\n' "${pkg_skill_dir}"
    } > "${target_dir}/.aihaus-managed"

    echo "  user-global new: ${skill_name}"
    refreshed_count=$((refreshed_count + 1))
  done

  echo "  user-global skills: ${refreshed_count} refreshed, ${skipped_count} skipped (unmanaged), ${orphan_count} orphans removed"
}

_refresh_user_global_skills

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
# pass --no-gitignore to suppress. Per ADR-M016-B R3 mitigation.
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
