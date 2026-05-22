#!/usr/bin/env bash
# aihaus install script (Unix)
# Copies .aihaus/ into target repo and links .claude/{skills,agents,hooks}.
# V5 (M022/Z3): user-global skill bootstrap + 8-tier discovery priority chain
#               + dogfood-mode branch + zero-prompt happy path.
# Flags:
#   --target <path>   Install into <path> instead of $PWD
#   --copy            Copy files instead of creating symlinks
#   --update          Re-sync package dirs only; preserve local data
#   --package <path>  Override package source location (tier 1 of discovery chain)
#   --force           Overwrite existing .aihaus/ without prompting
#   -h, --help        Show usage
set -euo pipefail

# Minimum Claude Code version supporting --dangerously-skip-permissions (DSP).
# TODO: Update this floor if the Claude Code changelog confirms a stricter minimum.
# 2.1.126: fixed idle-timeout edge cases (CLI-005 defense-in-depth; M019/S02).
DSP_MIN_CLAUDE_VERSION="2.1.126"

usage() {
  cat <<'EOF'
Usage: install.sh [--target <path>] [--copy] [--update] [--package <path>] [--force] [--force-project-skills]

Installs aihaus into a target git repository (Claude Code only).

Options:
  --target <path>         Target directory (default: current working directory)
  --copy                  Copy files instead of symlinking (fallback for
                          locked-down environments)
  --update                Re-sync package dirs only; preserve local data
  --package <path>        Override AIHAUS_HOME discovery; use this path as package root
  --force                 Overwrite existing .aihaus/ without prompting
  --force-project-skills  Always create .claude/skills junction even when
                          user-global skills (~/.claude/skills/aih-init) exist
                          (env: FORCE_PROJECT_SKILLS=1)
  -h, --help              Show this message
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
FORCE="0"
PACKAGE_FLAG=""  # V5: --package <path> override (tier 1 of discovery chain)
FORCE_PROJECT_SKILLS="${FORCE_PROJECT_SKILLS:-0}"  # M024/S02: env-var opt-out for skill-junction conditional

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
    --package)
      [[ $# -ge 2 ]] || { echo "ERROR: --package requires a path" >&2; exit 2; }
      PACKAGE_FLAG="$(cd "$2" 2>/dev/null && pwd)" || {
        echo "ERROR: --package path does not exist: $2" >&2
        exit 2
      }
      shift 2
      ;;
    --force)
      FORCE="1"
      shift
      ;;
    --force-project-skills)
      FORCE_PROJECT_SKILLS="1"
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

# ---------------------------------------------------------------------------
# V5 (M022/Z3): 8-tier discovery priority chain — ADR-260504-A §6.1
# Returns the canonical AIHAUS_HOME path (parent directory containing
# pkg/.aihaus/skills/) via stdout, or exits non-zero if not found.
# Tier 1: --package <path> CLI flag (already resolved above into PACKAGE_FLAG)
# Tier 2: $AIHAUS_HOME env var
# Tier 3: ~/.aihaus/.install-source registry (written on first successful run)
# Tier 4: $XDG_DATA_HOME/aihaus (Unix default: $HOME/.local/share/aihaus)
# Tier 5: $HOME/tools/aihaus (legacy README path)
# Tier 6: $HOME/Documents/GitHub/aihaus-flow (friend's auto-clone path)
# Tier 7: $HOME/Documents/GitHub/aihaus (variant)
# Tier 8: $HOME/code/aihaus (variant)
# Multiple tiers populated -> pick newest by git log -1 --format=%ct HEAD.
# Winning path written to ~/.aihaus/.install-source for subsequent runs.
# ---------------------------------------------------------------------------
resolve_aihaus_home() {
  # tier 1: explicit --package flag wins immediately
  if [[ -n "${PACKAGE_FLAG:-}" ]]; then
    if [[ -d "${PACKAGE_FLAG}/pkg/.aihaus/skills" ]]; then
      printf '%s' "${PACKAGE_FLAG}"
      return 0
    else
      echo "ERROR: --package path does not contain pkg/.aihaus/skills: ${PACKAGE_FLAG}" >&2
      return 1
    fi
  fi

  # tier 2: env override
  if [[ -n "${AIHAUS_HOME:-}" ]] && [[ -d "${AIHAUS_HOME}/pkg/.aihaus/skills" ]]; then
    printf '%s' "${AIHAUS_HOME}"
    return 0
  fi

  # tier 3: registry written on first install
  local registry="$HOME/.aihaus/.install-source"
  if [[ -f "${registry}" ]]; then
    local recorded
    recorded="$(head -n1 "${registry}" | tr -d '[:space:]')"
    if [[ -n "${recorded}" ]] && [[ -d "${recorded}/pkg/.aihaus/skills" ]]; then
      printf '%s' "${recorded}"
      return 0
    fi
  fi

  # tiers 4-8: scan candidates, arbitrate by newest HEAD commit timestamp
  local xdg_data="${XDG_DATA_HOME:-$HOME/.local/share}"
  local candidates=(
    "${xdg_data}/aihaus"
    "$HOME/tools/aihaus"
    "$HOME/Documents/GitHub/aihaus-flow"
    "$HOME/Documents/GitHub/aihaus"
    "$HOME/code/aihaus"
  )

  local best="" best_ts=0
  for c in "${candidates[@]}"; do
    if [[ -d "${c}/pkg/.aihaus/skills" ]] && [[ -d "${c}/.git" ]]; then
      local ts
      ts="$(git -C "${c}" log -1 --format=%ct 2>/dev/null || echo 0)"
      if [[ "${ts}" -gt "${best_ts}" ]]; then
        best="${c}"
        best_ts="${ts}"
      fi
    fi
  done

  if [[ -n "${best}" ]]; then
    # record pick to registry for next time (tier 3 read on subsequent runs)
    mkdir -p "$HOME/.aihaus"
    printf '%s\n' "${best}" > "${registry}"
    printf '%s' "${best}"
    return 0
  fi

  # nothing found — caller must handle
  return 1
}

# ---------------------------------------------------------------------------
# V5 (M022/Z3): Dogfood detection — I-04
# Returns 0 (true) when cwd IS the central aihaus clone.
# Predicate: pkg/scripts/install.sh + pkg/.aihaus/skills/ both exist in cwd.
# ---------------------------------------------------------------------------
is_dogfood_cwd() {
  [[ -f "${PWD}/pkg/scripts/install.sh" ]] && [[ -d "${PWD}/pkg/.aihaus/skills" ]]
}

# ---------------------------------------------------------------------------
# V5 (M022/Z3): User-global skill install loop — ADR-260504-A FR-01/FR-06
# Installs symlinks for every pkg/.aihaus/skills/aih-* directory
# into ~/.claude/skills/aih-* (user-global Claude Code skill resolution layer).
# Each created dir carries a .aihaus-managed marker (R1 collision defense).
# WSL2 detection via WSL_DISTRO_NAME env var (D-Z0-A from Z0 verification):
#   - In WSL2 sessions, ~/resolves to Linux home (/home/<user>/) — correct.
#   - In Git Bash on Windows, ~/resolves to USERPROFILE — correct.
#   Both paths write to the appropriate ~/.claude/skills/ for the running environment.
#   If WSL_DISTRO_NAME is set, we emit an informational hint: skills installed
#   here are for the Linux-side claude binary. Users who invoke claude.exe from
#   Windows must also run install.sh from a Windows shell to populate the Windows
#   USERPROFILE skills directory. We do NOT block — just inform.
# ---------------------------------------------------------------------------
install_user_global_skills() {
  local aihaus_home="$1"

  # Determine user-global skills directory. In WSL2, $HOME is the Linux home.
  # In Git Bash on Windows, $HOME is /c/Users/<user> (maps to USERPROFILE).
  # In both cases $HOME/.claude/skills/ is the correct target for the active shell.
  local user_global_skills="$HOME/.claude/skills"

  # WSL2 detection (D-Z0-A): inform only — do not block.
  if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
    echo "  info: WSL2 detected (distro=${WSL_DISTRO_NAME}); installing skills to Linux-side ${user_global_skills}" >&2
    echo "  note: skills installed here are for the Linux-side claude binary." >&2
    echo "        If you also use claude.exe from Windows, run install.sh from a" >&2
    echo "        Windows Git Bash or PowerShell session to populate the Windows" >&2
    echo "        %USERPROFILE%\\.claude\\skills\\ directory." >&2
  fi

  mkdir -p "${user_global_skills}"

  # Detect Windows native (not WSL2): use cmd.exe /c mklink /J for junctions.
  # On WSL2 or Unix, use ln -s (symlinks).
  local use_junction=0
  if [[ "${OS:-}" == "Windows_NT" ]] && [[ -z "${WSL_DISTRO_NAME:-}" ]]; then
    use_junction=1
  fi

  local installed_count=0
  local skipped_count=0

  for skill_dir in "${aihaus_home}/pkg/.aihaus/skills"/aih-*; do
    [[ -d "${skill_dir}" ]] || continue
    local skill_name
    skill_name="$(basename "${skill_dir}")"
    local target="${user_global_skills}/${skill_name}"

    # R1 collision defense: refuse to overwrite a dir not managed by aihaus.
    # A .aihaus-managed marker (created by us) is the ownership signal.
    if [[ -e "${target}" ]] && [[ ! -f "${target}/.aihaus-managed" ]]; then
      echo "  warn: ${target} exists but is not aihaus-managed; skipping (manual cleanup required)" >&2
      skipped_count=$((skipped_count + 1))
      continue
    fi

    # Remove stale or prior-version symlink/junction.
    if [[ -e "${target}" ]] || [[ -L "${target}" ]]; then
      rm -rf "${target}" 2>/dev/null || true
    fi

    # Create symlink or junction.
    if [[ "${use_junction}" == "1" ]]; then
      # Windows native junction via cmd.exe (no UAC required for junctions to dirs)
      local win_target win_skill
      win_target="$(cygpath -w "${target}" 2>/dev/null || echo "${target}")"
      win_skill="$(cygpath -w "${skill_dir}" 2>/dev/null || echo "${skill_dir}")"
      if ! cmd.exe /c "mklink /J \"${win_target}\" \"${win_skill}\"" >/dev/null 2>&1; then
        # Junction failed (e.g. cross-volume) — fall back to copy.
        echo "  warn: junction failed for ${skill_name}; falling back to copy" >&2
        cp -R "${skill_dir}" "${target}"
      fi
    else
      if ! ln -s "${skill_dir}" "${target}" 2>/dev/null; then
        # Symlink failed (locked-down filesystem) — fall back to copy.
        echo "  warn: symlink failed for ${skill_name}; falling back to copy" >&2
        cp -R "${skill_dir}" "${target}"
      fi
    fi

    # Drop .aihaus-managed marker inside the skill directory (R1 defense, I-02).
    # Content: two lines — managed_by + source path (ADR-260504-A §6.3).
    # Best-effort write via temp-file + cp: Windows junctions have a brief
    # FS-cache delay where direct bash `> path` redirects fail with bash
    # error noise; cp on the same path fails silently and is catchable via
    # `||`. Retry once after 0.5s; next install/update re-attempts on miss.
    _aihaus_marker_tmp="$(mktemp 2>/dev/null)" || _aihaus_marker_tmp="/tmp/.aihaus-marker.$$"
    {
      printf 'managed_by=aihaus\n'
      printf 'source=%s\n' "${skill_dir}"
    } > "${_aihaus_marker_tmp}"
    cp "${_aihaus_marker_tmp}" "${target}/.aihaus-managed" 2>/dev/null || {
      sleep 0.5 || true
      cp "${_aihaus_marker_tmp}" "${target}/.aihaus-managed" 2>/dev/null || \
        echo "  warn: marker write skipped (junction FS-cache; non-fatal)" >&2
    }
    rm -f "${_aihaus_marker_tmp}"

    echo "  user-global: ${target}"
    installed_count=$((installed_count + 1))
  done

  echo "  user-global skills: ${installed_count} installed, ${skipped_count} skipped (collision)"
}

# ---------------------------------------------------------------------------
# V5 (M022/Z3): Dogfood mode check — I-04, L9
# Must run BEFORE per-repo install logic. If we are inside the aihaus package
# directory, emit a one-liner and exit 0. Never git-pull. Never self-symlink.
# ---------------------------------------------------------------------------
if is_dogfood_cwd; then
  echo "info: you are inside the aihaus package; run 'aihaus self-update' to refresh from origin"
  # Still attempt user-global skill install if aihaus_home resolves (cwd IS the pkg).
  # The per-repo overlay is skipped; only user-global symlinks are created.
  RESOLVED_HOME="${PKG_ROOT}"
  install_user_global_skills "${RESOLVED_HOME}"
  # Write registry so future invocations use this clone directly (tier 3).
  mkdir -p "$HOME/.aihaus"
  printf '%s\n' "${RESOLVED_HOME}" > "$HOME/.aihaus/.install-source"
  echo "  registry: ~/.aihaus/.install-source -> ${RESOLVED_HOME}"
  echo ""
  echo "aihaus user-global skills installed (dogfood mode; per-repo overlay skipped)."
  exit 0
fi

# ---------------------------------------------------------------------------
# Resolve AIHAUS_HOME for non-dogfood installs.
# If the script is being run from the package directory directly (e.g.
# bash pkg/scripts/install.sh --target /some/other/repo), use the resolved
# PKG_ROOT as the canonical AIHAUS_HOME.
# ---------------------------------------------------------------------------
if [[ -d "${PKG_ROOT}/pkg/.aihaus/skills" ]]; then
  # Running from within a clone of the aihaus repo targeting another directory.
  AIHAUS_RESOLVED="${PKG_ROOT}"
elif AIHAUS_RESOLVED="$(resolve_aihaus_home 2>&1)"; then
  : # resolved via priority chain
else
  # Could not locate package — inform user.
  echo "ERROR: could not locate aihaus package. Set AIHAUS_HOME or pass --package <path>." >&2
  exit 1
fi

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
  # Step 3: existing .aihaus/ handling (V5: zero-prompt happy path — I-13, L8)
  # Replace interactive prompt: dead symlink -> silent overwrite;
  # live .aihaus/ -> require --force opt-in; default -> abort with stderr.
  if [[ -e "${TARGET}/.aihaus" ]] || [[ -L "${TARGET}/.aihaus" ]]; then
    if [[ -L "${TARGET}/.aihaus" ]] && [[ ! -e "${TARGET}/.aihaus" ]]; then
      # Dead symlink — silently remove and continue.
      rm -f "${TARGET}/.aihaus"
    elif [[ "${FORCE}" == "1" ]]; then
      # --force opt-in: destructive overwrite.
      rm -rf "${TARGET}/.aihaus"
    else
      echo "error: .aihaus/ already exists; pass --force to overwrite" >&2
      exit 1
    fi
  fi

  # Step 4: copy package .aihaus/ into target
  mkdir -p "${TARGET}/.aihaus"
  cp -R "${PKG_AIHAUS}/." "${TARGET}/.aihaus/"
fi

# Repo-local runtime layout. Package-owned source stays in AIHAUS_HOME; target
# repos receive only runtime/state defaults and editable workflow profiles.
mkdir -p \
  "${TARGET}/.aihaus/bin" \
  "${TARGET}/.aihaus/state" \
  "${TARGET}/.aihaus/runtime" \
  "${TARGET}/.aihaus/backups" \
  "${TARGET}/.aihaus/workflows" \
  "${TARGET}/.aihaus/memory/workflows"
if [[ ! -f "${TARGET}/.aihaus/workflows/default.md" && -f "${PKG_AIHAUS}/workflows/default.md" ]]; then
  cp "${PKG_AIHAUS}/workflows/default.md" "${TARGET}/.aihaus/workflows/default.md"
  echo "  workflow: created .aihaus/workflows/default.md"
fi
if [[ ! -f "${TARGET}/.aihaus/workflows/agents.md" && -f "${PKG_AIHAUS}/workflows/agents.md" ]]; then
  cp "${PKG_AIHAUS}/workflows/agents.md" "${TARGET}/.aihaus/workflows/agents.md"
  echo "  workflow: created .aihaus/workflows/agents.md"
fi
if [[ ! -f "${TARGET}/.aihaus/memory/workflows/README.md" && -f "${PKG_AIHAUS}/memory/workflows/README.md" ]]; then
  cp "${PKG_AIHAUS}/memory/workflows/README.md" "${TARGET}/.aihaus/memory/workflows/README.md"
fi

# Step 5+6: create .claude/{skills,agents,hooks} as links or copies (Claude Code target)
# shellcheck source=lib/junction-safe.sh
source "$(dirname "$0")/lib/junction-safe.sh"

link_or_copy() {
  local name="$1"
  local src="${TARGET}/.aihaus/${name}"
  local dst="${TARGET}/.claude/${name}"

  if [[ ! -e "${src}" ]]; then
    echo "  skip: ${src} does not exist in package"
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

mkdir -p "${TARGET}/.claude"

# ---------------------------------------------------------------------------
# M024/S02: Skill-junction conditional (Concern C) — ADR-260507-A #5
# Skip per-repo .claude/skills junction when user-global skills already exist
# (detected by sentinel directory ~/.claude/skills/aih-init, present in every
# aihaus install). Opt-out: --force-project-skills flag OR FORCE_PROJECT_SKILLS=1.
# Note: dogfood mode returns before reaching this block (I-04 / install.sh:274),
# so the conditional here only applies to non-dogfood --target invocations.
# ---------------------------------------------------------------------------
_has_user_global_skills() {
  [[ -d "$HOME/.claude/skills/aih-init" ]]   # aih-init is sentinel — exists in every aihaus install
}

for name in skills agents hooks; do
  if [[ "${name}" == "skills" ]]; then
    if ! _has_user_global_skills || [[ "${FORCE_PROJECT_SKILLS:-0}" == "1" ]]; then
      link_or_copy "skills"
    else
      echo "  skip: .claude/skills -- user-global skills present (pass --force-project-skills to override)"
    fi
  else
    link_or_copy "${name}"
  fi
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

# Step 10: V5 user-global skill install — ADR-260504-A FR-01/FR-06
# Install each aih-* skill into ~/.claude/skills/ (user-global Claude Code resolution layer).
# This runs on every non-dogfood non-update invocation (idempotent per I-02).
# M024/S02 (Concern B fix): pass AIHAUS_RESOLVED (repo root containing pkg/) not PKG_ROOT
# (which is repo-root/pkg — would resolve to repo-root/pkg/pkg/.aihaus/skills, never exists).
echo ""
echo "  installing user-global skills..."
install_user_global_skills "${AIHAUS_RESOLVED}"

# Step 11: write ~/.aihaus/.install-source registry (FR-04, I-01)
# Written here (after per-repo overlay + user-global skills succeed) so a partial
# failure never pins a broken path. Using AIHAUS_RESOLVED as the canonical AIHAUS_HOME.
# M024/S02 (Concern B fix): use AIHAUS_RESOLVED (repo root) not PKG_ROOT (repo-root/pkg).
mkdir -p "$HOME/.aihaus"
printf '%s\n' "${AIHAUS_RESOLVED}" > "$HOME/.aihaus/.install-source"
echo "  registry: ~/.aihaus/.install-source -> ${AIHAUS_RESOLVED}"

# Step 12: idempotent .gitignore injection (soft-fail per LD-3)
# Manual fallback: pkg/.aihaus/templates/gitignore-fragment
_inject_gitignore() {
  local target="$1"
  local gitignore="${target}/.gitignore"
  # Primary idempotency check: guard-comment anchor already present?
  if grep -q "^# AIHAUS:GITIGNORE-START" "${gitignore}" 2>/dev/null; then
    echo "  .gitignore: aihaus block already present (no-op)"
    return 0
  fi
  # Secondary idempotency check: hand-edited variant without the full guard comment?
  if grep -q "\.aihaus/audit" "${gitignore}" 2>/dev/null; then
    echo "  .gitignore: .aihaus/audit entry detected (skipping injection to avoid duplication)"
    return 0
  fi
  # Append guard block (create .gitignore if absent)
  {
    printf '\n'
    printf '# AIHAUS:GITIGNORE-START -- managed by install.sh / update.sh; do not edit between markers\n'
    printf '/.aihaus/audit/\n'
    printf '/.claude/audit/\n'
    printf '/.aihaus/bin/\n'
    printf '/.aihaus/state/\n'
    printf '/.aihaus/runtime/\n'
    printf '/.aihaus/backups/\n'
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
}
_inject_gitignore "${TARGET}"

# Step 13: aih-graph memory engine binary bootstrap (M041/S3)
# Downloads the aih-graph binary to .aihaus/bin/ if not already present.
# Non-fatal — install completes even if download fails (e.g. offline,
# rate-limited, platform not in v0.1 matrix). /aih-init Phase 3 retries
# the same download on its own if the binary is still missing at run time.
# Opt-out: AIHAUS_SKIP_GRAPH_BINARY=1.
if [[ -z "${AIHAUS_SKIP_GRAPH_BINARY:-}" ]] && [[ "${UPDATE}" != "1" ]]; then
  _aih_graph_bin="${TARGET}/.aihaus/bin/aih-graph"
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
  else
    echo "  aih-graph: already installed at ${_aih_graph_bin}"
  fi
fi

# Step 14: success message
echo ""
if [[ "${UPDATE}" == "1" ]]; then
  echo "aihaus updated (${MODE} mode)."
  echo "Launch with: bash .aihaus/auto.sh"
else
  echo "aihaus installed (${MODE} mode)."
  echo "Launch with: bash .aihaus/auto.sh"
  echo "Run /aih-init inside the launched session to bootstrap project.md + aih-graph"
fi
