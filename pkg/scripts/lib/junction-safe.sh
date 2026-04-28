#!/usr/bin/env bash
# junction-safe.sh — Windows-aware directory link/unlink helpers.
#
# Why this exists:
#   On Windows + Git Bash, `rm -rf` on a directory junction can follow the
#   junction and delete the TARGET's contents. And `ln -s` cannot create
#   real directory junctions — it produces a plain-file stub. The combo
#   wipes .claude/{skills,agents,hooks} junctions AND nukes their targets
#   in .aihaus/ (see fix/aih-update-windows-junction-wipe / 2026-04-28).
#
#   These helpers route via PowerShell on Windows (reparse-point-aware
#   detection + `New-Item -ItemType Junction` creation; not subject to
#   MSYS argv quote-mangling that breaks `cmd //c "mklink /J ..."`) and
#   fall back to POSIX `rm -rf` / `ln -s` on non-Windows hosts.
#
# Public API:
#   safe_remove_dir <path>     -- junction-aware directory removal
#   make_dir_link <src> <dst>  -- create dir junction (Windows) or symlink
#                                  Sets LINK_ERR on failure; reset to "" on success.

# Detect Windows-native bash (Git Bash / MSYS / Cygwin). Excludes WSL —
# WSL has powershell.exe via interop but native paths and POSIX symlinks
# work correctly there, so the bash branch is the right path.
_is_windows_native() {
  case "${OSTYPE:-}" in
    msys*|cygwin*|win32) return 0 ;;
    *) return 1 ;;
  esac
}

# Convert a POSIX path to a Windows path for native tools. Falls back to
# the input unchanged if cygpath isn't available.
_to_win_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
  else
    printf '%s' "$1"
  fi
}

# safe_remove_dir <path>
# Removes <path> safely. On Windows-native bash, uses PowerShell to
# detect a reparse point (junction); junctions are removed via
# `(Get-Item).Delete()` which removes only the link entry, never recurses
# into the target. Non-junction directories use `Remove-Item -Recurse`.
# Non-Windows hosts use `rm -rf`. Empty/missing path is a no-op.
safe_remove_dir() {
  local path="${1:-}"
  if [[ -z "${path}" ]]; then return 0; fi
  if [[ ! -e "${path}" && ! -L "${path}" ]]; then return 0; fi

  if _is_windows_native; then
    local win
    win="$(_to_win_path "${path}")"
    # Single-quote the Windows path inside PowerShell — escape any literal
    # single quotes by doubling them (PowerShell single-quote rule).
    local ps_path="${win//\'/\'\'}"
    if powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "
      \$ErrorActionPreference = 'Stop'
      \$p = '${ps_path}'
      \$i = Get-Item -LiteralPath \$p -Force -ErrorAction SilentlyContinue
      if (\$null -eq \$i) { exit 0 }
      if (\$i.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        \$i.Delete()
      } else {
        Remove-Item -LiteralPath \$p -Recurse -Force
      }
    " >/dev/null 2>&1; then
      return 0
    fi
    # PowerShell route failed — fall through to rm -rf as last resort.
  fi
  rm -rf "${path}"
}

# make_dir_link <src> <dst>
# Creates a directory link from <src> to <dst>. Returns 0 on success.
# On failure, populates LINK_ERR with stderr (do not silently swallow).
# Windows uses PowerShell `New-Item -ItemType Junction` (no admin needed,
# no MSYS quote-mangling); POSIX uses `ln -s`.
make_dir_link() {
  local src="${1:-}" dst="${2:-}" out
  LINK_ERR=""
  if [[ -z "${src}" || -z "${dst}" ]]; then
    LINK_ERR="missing src or dst argument"
    return 1
  fi

  if _is_windows_native; then
    local win_src win_dst
    win_src="$(_to_win_path "${src}")"
    win_dst="$(_to_win_path "${dst}")"
    local ps_src="${win_src//\'/\'\'}"
    local ps_dst="${win_dst//\'/\'\'}"
    if out="$(powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "
      \$ErrorActionPreference = 'Stop'
      New-Item -ItemType Junction -Path '${ps_dst}' -Target '${ps_src}' | Out-Null
    " 2>&1)"; then
      return 0
    fi
    LINK_ERR="${out}"
    return 1
  fi

  if out="$(ln -s "${src}" "${dst}" 2>&1)"; then
    return 0
  fi
  LINK_ERR="${out}"
  return 1
}
