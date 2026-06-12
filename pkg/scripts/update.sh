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
  --migrate-memory  Legacy compatibility flag. Missing memory starter files are
                    now seeded by the default refresh loop without overwrites.
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

warn_if_synced_target() {
  local target_path="$1"
  local normalized
  normalized="$(printf '%s' "$target_path" | tr '\\' '/')"
  case "$normalized" in
    *OneDrive*|*Dropbox*|*"Google Drive"*|*iCloudDrive*|*"/Box/"*)
      echo "  warn: target is on a synced path; worktree churn may be slow/lock-prone. Pause sync before cleanup if needed."
      ;;
  esac
}

warn_if_copy_mode() {
  if [[ "${MODE}" == "copy" ]]; then
    echo "  warn: copy mode overwrites package-managed .aihaus/.claude files on update; keep custom edits in project memory/workflows, not managed skills/agents/hooks."
  fi
}

# Resolve package root (the directory containing this script's parent)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PKG_AIHAUS="${PKG_ROOT}/.aihaus"
PKG_TEMPLATES="${PKG_AIHAUS}/templates"

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
    PKG_TEMPLATES="${PKG_AIHAUS}/templates"
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
warn_if_synced_target "${TARGET}"
warn_if_copy_mode

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

  # Remove old managed contents before copying. This is copy-mode orphan
  # pruning: the shipped package tree is the manifest for managed files.
  if [[ -e "${dst}" ]]; then
    rm -rf "${dst}"
  fi
  cp -R "${src}" "${dst}"
  echo "  refreshed: .aihaus/${name} (managed copy pruned)"
}

for name in skills agents hooks templates; do
  update_aihaus_dir "${name}"
done

# Repo-local runtime layout. Do not overwrite protocol profiles on update; only
# seed missing defaults for existing installs.
mkdir -p \
  "${AIHAUS}/bin" \
  "${AIHAUS}/state" \
  "${AIHAUS}/runtime" \
  "${AIHAUS}/backups" \
  "${AIHAUS}/protocols" \
  "${AIHAUS}/memory/workflows" \
  "${AIHAUS}/memory/agents" \
  "${AIHAUS}/memory/reviews" \
  "${AIHAUS}/memory/global" \
  "${AIHAUS}/memory/backend" \
  "${AIHAUS}/memory/frontend"

migrate_legacy_workflows_dir() {
  local old_dir="${AIHAUS}/workflows"
  local new_dir="${AIHAUS}/protocols"
  local runtime_runs="${AIHAUS}/runtime/runs"
  [[ -d "${old_dir}" ]] || return 0

  mkdir -p "${new_dir}" "${AIHAUS}/runtime"
  local rel src dst
  for rel in default.md agents.md artifacts.md business-rules.md fan-out.md parallelism.md roles.md routing.md kanban; do
    src="${old_dir}/${rel}"
    dst="${new_dir}/${rel}"
    [[ -e "${src}" ]] || continue
    if [[ ! -e "${dst}" ]]; then
      mv "${src}" "${dst}"
      echo "  migrate: .aihaus/workflows/${rel} -> .aihaus/protocols/${rel}"
    else
      echo "  warn: legacy .aihaus/workflows/${rel} left in place; .aihaus/protocols/${rel} already exists"
    fi
  done
  if [[ -d "${old_dir}/runs" && ! -e "${runtime_runs}" ]]; then
    mv "${old_dir}/runs" "${runtime_runs}"
    echo "  migrate: .aihaus/workflows/runs -> .aihaus/runtime/runs"
  elif [[ -d "${old_dir}/runs" ]]; then
    echo "  warn: legacy .aihaus/workflows/runs left in place; .aihaus/runtime/runs already exists"
  fi
  rmdir "${old_dir}" 2>/dev/null || true
}
migrate_legacy_workflows_dir
mkdir -p "${AIHAUS}/runtime/runs"

for protocol_file in default.md agents.md artifacts.md business-rules.md fan-out.md harness.md parallelism.md roles.md routing.md; do
  if [[ ! -f "${AIHAUS}/protocols/${protocol_file}" && -f "${PKG_AIHAUS}/protocols/${protocol_file}" ]]; then
    cp "${PKG_AIHAUS}/protocols/${protocol_file}" "${AIHAUS}/protocols/${protocol_file}"
    echo "  protocol: created .aihaus/protocols/${protocol_file}"
  fi
done
for rel in \
  "memory/MEMORY.md" \
  "memory/workflows/README.md" \
  "memory/workflows/environment.md" \
  "memory/workflows/business-rules.md" \
  "memory/workflows/user-preferences.md" \
  "memory/workflows/rules.md" \
  "memory/workflows/gotchas.md" \
  "memory/agents/README.md" \
  "memory/reviews/README.md" \
  "memory/reviews/common-findings.md" \
  "memory/global/README.md" \
  "memory/global/gotchas.md" \
  "memory/backend/README.md" \
  "memory/frontend/README.md"; do
  if [[ ! -f "${AIHAUS}/${rel}" && -f "${PKG_AIHAUS}/${rel}" ]]; then
    mkdir -p "$(dirname "${AIHAUS}/${rel}")"
    cp "${PKG_AIHAUS}/${rel}" "${AIHAUS}/${rel}"
  fi
done
if [[ ! -f "${AIHAUS}/decisions.md" && -f "${PKG_TEMPLATES}/decisions.md" ]]; then
  cp "${PKG_TEMPLATES}/decisions.md" "${AIHAUS}/decisions.md"
  echo "  memory: created .aihaus/decisions.md"
fi
if [[ ! -f "${AIHAUS}/knowledge.md" && -f "${PKG_TEMPLATES}/knowledge.md" ]]; then
  cp "${PKG_TEMPLATES}/knowledge.md" "${AIHAUS}/knowledge.md"
  echo "  memory: created .aihaus/knowledge.md"
fi

ensure_workflow_environment_prompts() {
  local env_file="$1"
  [[ -f "${env_file}" ]] || return 0
  if grep -Fq "AIHAUS:WORKFLOW-ENVIRONMENT-PROMPTS-START" "${env_file}" 2>/dev/null; then
    return 0
  fi
  if grep -Fq "## Runtime and Deployment" "${env_file}" 2>/dev/null; then
    return 0
  fi
  cat >> "${env_file}" <<'EOF'

<!-- AIHAUS:WORKFLOW-ENVIRONMENT-PROMPTS-START -->
## Runtime and Deployment

- **Where code runs:** _local dev / container / CodeBuild / ECS / Lambda / other_
- **Default dev URL:** _fill in if browser validation uses a stable URL_
- **Deploy path:** _command, pipeline, CodeBuild project, or human-owned release path_
- **Promotion gates:** _what must pass before dev, staging, or production_

## Credentials and Test Accounts

- **Credential location:** _Secrets Manager, Parameter Store, .env vault, password manager, or other approved source_
- **Test users/roles:** _named roles only; do not store passwords or tokens_
- **Auth protocol:** _how an agent should authenticate for Playwright or API smoke checks_

## Validation Commands

- **Unit/integration:** _repo command or CI job_
- **Playwright/browser:** _repo command, dev URL, required seed data_
- **CodeBuild/CI:** _project names or commands used to check builds_
- **Smoke evidence:** _screenshots, traces, URLs, logs, or release artifacts expected_

## Source System Hints

- **External kanban:** _source system, project/view/board identifiers, or none_
- **Stage sync:** _which statuses/views mirror local aihaus stages_
- **Question protocol:** _how business-rule gaps are recorded and answered_
<!-- AIHAUS:WORKFLOW-ENVIRONMENT-PROMPTS-END -->
EOF
  echo "  memory: appended workflow environment prompts"
}
ensure_workflow_environment_prompts "${AIHAUS}/memory/workflows/environment.md"

sync_output_styles() {
  local src_dir="${PKG_AIHAUS}/output-styles"
  local dst_dir="${CLAUDE}/output-styles"
  [[ -d "${src_dir}" ]] || return 0

  mkdir -p "${dst_dir}"
  local src dst name
  for src in "${src_dir}/"*.md; do
    [[ -f "${src}" ]] || continue
    name="$(basename "${src}")"
    dst="${dst_dir}/${name}"
    if [[ ! -f "${dst}" ]] || ! cmp -s "${src}" "${dst}" 2>/dev/null; then
      cp "${src}" "${dst}"
      echo "  output-style: refreshed .claude/output-styles/${name}"
    fi
  done
}
sync_output_styles

seed_claude_context_bridge() {
  local claude_dir="$1"
  local context_src="${PKG_TEMPLATES}/claude/CLAUDE.md"
  local context_dst="${claude_dir}/CLAUDE.md"
  local rule_src="${PKG_TEMPLATES}/claude/rules/aihaus-project-memory.md"
  local rule_dst="${claude_dir}/rules/aihaus-project-memory.md"

  mkdir -p "${claude_dir}/rules"

  _scrub_large_claude_imports() {
    local file="$1" tmp
    [[ -f "${file}" ]] || return 0
    if ! grep -Eq '^@\.\./\.aihaus/(decisions|knowledge)\.md[[:space:]]*$' "${file}" 2>/dev/null; then
      return 0
    fi
    tmp="${file}.tmp.$$"
    if awk '{
      line=$0
      sub(/\r$/, "", line)
      if (line != "@../.aihaus/decisions.md" && line != "@../.aihaus/knowledge.md") print $0
    }' "${file}" > "${tmp}" 2>/dev/null; then
      mv "${tmp}" "${file}"
      echo "  claude-context: removed large ledger startup imports"
    else
      rm -f "${tmp}" 2>/dev/null || true
    fi
  }

  if [[ -f "${context_src}" ]]; then
    if [[ ! -f "${context_dst}" ]]; then
      cp "${context_src}" "${context_dst}"
      echo "  claude-context: created .claude/CLAUDE.md"
    elif ! grep -Fq "AIHAUS:CLAUDE-CONTEXT-START" "${context_dst}"; then
      { printf '\n\n'; cat "${context_src}"; } >> "${context_dst}"
      echo "  claude-context: appended aihaus imports to .claude/CLAUDE.md"
    fi
  else
    echo "  warn: Claude context template missing at ${context_src}"
  fi
  _scrub_large_claude_imports "${context_dst}"

  if [[ -f "${rule_src}" ]]; then
    if [[ ! -f "${rule_dst}" ]]; then
      cp "${rule_src}" "${rule_dst}"
      echo "  claude-context: created .claude/rules/aihaus-project-memory.md"
    elif ! grep -Fq "AIHAUS:CLAUDE-RULES-START" "${rule_dst}"; then
      { printf '\n\n'; cat "${rule_src}"; } >> "${rule_dst}"
      echo "  claude-context: appended aihaus rule to .claude/rules/aihaus-project-memory.md"
    fi
  else
    echo "  warn: Claude rule template missing at ${rule_src}"
  fi
}

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
  echo "  copy: .claude/${name} (managed copy pruned)"
}

mkdir -p "${CLAUDE}"
seed_claude_context_bridge "${CLAUDE}"
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
      # Re-drop .aihaus-managed marker via temp-file + cp (avoids bash
      # redirect error noise when Windows junction FS-cache hasn't synced
      # yet; cp failure is silent and catchable; retry once after 0.5s;
      # next update re-attempts if both retries fail). See M041/dogfood.
      local _marker_tmp
      _marker_tmp="$(mktemp 2>/dev/null)" || _marker_tmp="/tmp/.aihaus-marker.$$"
      {
        printf 'managed_by=aihaus\n'
        printf 'source=%s\n' "${pkg_skill_dir}"
      } > "${_marker_tmp}"
      cp "${_marker_tmp}" "${target_dir}/.aihaus-managed" 2>/dev/null || {
        sleep 0.5 || true
        cp "${_marker_tmp}" "${target_dir}/.aihaus-managed" 2>/dev/null || \
          echo "  warn: marker write skipped for ${skill_name} (junction FS-cache; non-fatal)" >&2
      }
      rm -f "${_marker_tmp}"
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

    # Best-effort marker write via temp-file + cp (see Pass 1 above).
    local _marker_tmp
    _marker_tmp="$(mktemp 2>/dev/null)" || _marker_tmp="/tmp/.aihaus-marker.$$"
    {
      printf 'managed_by=aihaus\n'
      printf 'source=%s\n' "${pkg_skill_dir}"
    } > "${_marker_tmp}"
    cp "${_marker_tmp}" "${target_dir}/.aihaus-managed" 2>/dev/null || {
      sleep 0.5 || true
      cp "${_marker_tmp}" "${target_dir}/.aihaus-managed" 2>/dev/null || \
        echo "  warn: marker write skipped for ${skill_name} (junction FS-cache; non-fatal)" >&2
    }
    rm -f "${_marker_tmp}"

    echo "  user-global new: ${skill_name}"
    refreshed_count=$((refreshed_count + 1))
  done

  echo "  user-global skills: ${refreshed_count} refreshed, ${skipped_count} skipped (unmanaged), ${orphan_count} orphans removed"
}

_refresh_user_global_skills

# ---- ~/.aihaus/.targets enrollment (M050/S08, hole 8 / F9) -------------------
# Pre-existing installs enroll on their next update: append-dedupe this repo's
# absolute path to ~/.aihaus/.targets (format consumed by `aihaus update --all`).
# Honors AIHAUS_SKIP_GLOBAL_HARNESS=1 (BR-U1).
# shellcheck source=lib/global-harness.sh
source "$(dirname "$0")/lib/global-harness.sh"
register_aihaus_target "${TARGET}"

# ---- Migrate memory README seeds (legacy compatibility) ----------------------
# Default update now seeds memory starter files non-destructively. Keep this
# flag as a narrow README-only alias for older workflows that still pass it.
migrate_memory() {
  local count_created=0
  local count_skipped=0
  local subdirs=(global backend frontend reviews agents workflows)

  echo ""
  echo "[migrate-memory] seeding memory README files (legacy, non-destructive)"

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
  local entries=(
    '/.aihaus/audit/'
    '/.claude/audit/'
    '*/.aihaus/'
    '*/.claude/'
    '/.aihaus/agents/'
    '/.aihaus/skills/'
    '/.aihaus/hooks/'
    '/.aihaus/templates/'
    '/.aihaus/bin/'
    '/.aihaus/state/'
    '/.aihaus/runtime/'
    '/.aihaus/backups/'
    '/.aihaus/roles/'
    '/.aihaus/memory/local/'
    '/.claude/agents/'
    '/.claude/hooks/'
    '/.claude/skills/'
    '/.claude/worktrees/'
    '/.claude/settings.local.json'
    '/.claude/backups/'
    '/.claude/agent-memory/'
    '/.claude/agent-memory-local/'
    '/.bg-shell/'
    '/.worktrees/'
    '/.gsd/'
    '/.gsd-id'
    '/.hermes/'
    '/.aihaus/.context-budgets'
    '/.aihaus/.effort'
    '/.aihaus/.calibration'
    '/.aihaus/.install-mode'
    '/.aihaus/.install-source'
    '/.aihaus/.install-platform'
    '/.aihaus/.version'
    '/.aihaus/.enforcement'
    '/.aihaus/.automode'
  )
  _patch_guard_block() {
    local tmp missing
    tmp="$(mktemp)" || return 0
    missing="$(mktemp)" || { rm -f "$tmp"; return 0; }
    local entry
    for entry in "${entries[@]}"; do
      grep -Fxq "$entry" "${gitignore}" 2>/dev/null || printf '%s\n' "$entry" >> "$missing"
    done
    if [[ ! -s "$missing" ]]; then
      rm -f "$tmp" "$missing"
      return 0
    fi
    if ! grep -q '^# AIHAUS:GITIGNORE-END' "$gitignore" 2>/dev/null; then
      cat "$missing" >> "$gitignore"
      rm -f "$tmp" "$missing"
      echo "  .gitignore: aihaus block updated"
      return 0
    fi
    awk -v missing_file="$missing" '
      BEGIN { while ((getline line < missing_file) > 0) miss[++n] = line }
      /^# AIHAUS:GITIGNORE-END/ { for (i = 1; i <= n; i++) print miss[i] }
      { print }
    ' "$gitignore" > "$tmp" && mv "$tmp" "$gitignore"
    rm -f "$missing"
    echo "  .gitignore: aihaus block updated"
  }

  # Step 1: idempotency — guard-comment block already present?
  if grep -q "^# AIHAUS:GITIGNORE-START" "${gitignore}" 2>/dev/null; then
    # Already present — no prompt, no write.
    _patch_guard_block
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
      local entry
      for entry in "${entries[@]}"; do
        printf '%s\n' "$entry"
      done
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

# ---- aih-graph binary refresh (M041/S4) --------------------------------------
# Mirror of install.sh Step 13: ensure .aihaus/bin/aih-graph exists.
# Non-fatal — update completes even if download fails. Idempotent when binary
# already present (silent skip). Opt-out: AIHAUS_SKIP_GRAPH_BINARY=1.
if [[ -z "${AIHAUS_SKIP_GRAPH_BINARY:-}" ]]; then
  _aih_graph_bin="${AIHAUS}/bin/aih-graph"
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) _aih_graph_bin="${_aih_graph_bin}.exe" ;;
  esac
  if [[ ! -x "${_aih_graph_bin}" ]]; then
    _aih_graph_installer="${SCRIPT_DIR}/install-aih-graph-binary.sh"
    if [[ -f "${_aih_graph_installer}" ]]; then
      echo ""
      echo "  installing aih-graph memory engine..."
      if bash "${_aih_graph_installer}" --bin "${_aih_graph_bin}" >/dev/null 2>&1; then
        echo "  ok: aih-graph at ${_aih_graph_bin}"
      else
        echo "  warn: aih-graph download failed (memory engine optional; /aih-init retries)"
      fi
    fi
  fi
fi

refresh_claude_context_bridge() {
  local refresh_hook="${AIHAUS}/hooks/project-context-refresh.sh"
  [[ -f "${refresh_hook}" ]] || return 0

  echo ""
  echo "  refreshing Claude context bridge..."
  if CLAUDE_PROJECT_DIR="${TARGET}" \
    AIHAUS_CONTEXT_REFRESH_QUIET=1 \
    AIHAUS_CONTEXT_REFRESH_DISCOVERY=0 \
    bash "${refresh_hook}" --reason update >/dev/null 2>&1; then
    echo "  ok: Claude context bridge refreshed"
  else
    echo "  warn: Claude context bridge refresh failed (run .aihaus/hooks/project-context-refresh.sh manually)"
  fi
}
refresh_claude_context_bridge

# ---- Summary -----------------------------------------------------------------
echo ""
echo "Updated ${count_skills} skills, ${count_agents} agents, ${count_hooks} hooks"
echo "aihaus updated (${MODE} mode)."
exit 0
