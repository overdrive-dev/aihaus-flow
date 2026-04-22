#!/usr/bin/env bash
# manifest-helpers.sh — shared library sourced by manifest-append.sh and
# phase-advance.sh. Hosts RUN-MANIFEST.md read-modify-write primitives and
# the cross-platform coarse-lock helper.
#
# Exports:
#   update_metadata_kv <key> <value>
#   append_to_section <header> <line> [mode]
#   append_progress_log <line>
#   detect_platform                  # sets AIH_USE_MKDIR_LOCK=0|1
#   acquire_coarse_lock <path>       # flock -w 2 on POSIX, mkdir-atomic on Windows
#   stack_depth                      # count Invoke stack rows (uses $MANIFEST_PATH)
#
# This library is hook-level only — NOT a top-level hook. Check 3's hook count
# globs `pkg/.aihaus/hooks/*.sh` with maxdepth 1, so lib/ subdir is excluded.
#
# Reference: M011 architecture § 2.0 (F-01 extraction). Called from both
# manifest-append.sh (all six --field dispatches) and phase-advance.sh
# (--to paused + metadata writes added by S04).

# shellcheck disable=SC2034  # caller may or may not use these

# --- ISO 8601 UTC timestamp ---
ts_iso() { date -u +%FT%TZ; }

# --- Metadata key/value upsert ---
# Updates an existing `key: value` line in the ## Metadata block, or appends
# a new line if the key is absent. Caller must have set $MANIFEST_PATH and
# held a write lock before calling.
update_metadata_kv() {
  local key="$1" value="$2"
  local tmp="$MANIFEST_PATH.tmp"
  awk -v k="$key" -v v="$value" '
    BEGIN { in_meta=0; updated=0 }
    /^## Metadata$/ { in_meta=1; print; next }
    /^## / && in_meta==1 { in_meta=0; if (!updated) print k ": " v; print; next }
    in_meta==1 && $1 == k":" { print k ": " v; updated=1; next }
    { print }
    END { if (in_meta==1 && !updated) print k ": " v }
  ' "$MANIFEST_PATH" > "$tmp"
  mv -f "$tmp" "$MANIFEST_PATH"
}

# --- Append a line to a ## section body ---
# mode defaults to "append". $MANIFEST_PATH required.
append_to_section() {
  local section_header="$1" new_line="$2" mode="${3:-append}"
  local tmp="$MANIFEST_PATH.tmp"
  awk -v header="$section_header" -v line="$new_line" -v mode="$mode" '
    BEGIN { in_sec=0; done=0 }
    {
      if ($0 == header) { in_sec=1; print; next }
      if (/^## / && in_sec==1) {
        if (done==0 && mode=="append") { print line; done=1 }
        in_sec=0; print; next
      }
      print
    }
    END {
      if (in_sec==1 && done==0 && mode=="append") { print line }
    }
  ' "$MANIFEST_PATH" > "$tmp"
  mv -f "$tmp" "$MANIFEST_PATH"
}

# --- Append a timestamped entry to ## Progress Log ---
append_progress_log() {
  local line="$1"
  append_to_section "## Progress Log" "- $(ts_iso) — $line" append
}

# --- Count non-empty Invoke stack rows ---
stack_depth() {
  awk '/^## Invoke stack$/ {on=1; next} /^## / {on=0} on && /[^[:space:]]/' "$MANIFEST_PATH" | wc -l | tr -d ' '
}

# --- Platform probe (F-03 / S02) ---
# Sets AIH_USE_MKDIR_LOCK=1 when flock is unavailable OR we are on MSYS/Cygwin
# (where flock advisory semantics are unreliable on host NTFS). Runtime only —
# no file persistence (in-memory only).
detect_platform() {
  if [[ "${OSTYPE:-}" == "msys" || "${OSTYPE:-}" == "cygwin" ]] || ! command -v flock >/dev/null 2>&1; then
    AIH_USE_MKDIR_LOCK=1
  else
    AIH_USE_MKDIR_LOCK=0
  fi
}

# --- Fractional-sleep probe (F-16) ---
# Sets AIH_SLEEP_FRACTIONAL=1 when `sleep 0.05` works; else 0 (old MSYS bash 3.x
# fallback uses `sleep 1` with fewer iterations to stay inside 2s budget).
detect_fractional_sleep() {
  if sleep 0.05 2>/dev/null; then
    AIH_SLEEP_FRACTIONAL=1
  else
    AIH_SLEEP_FRACTIONAL=0
  fi
}

# --- Acquire coarse outer lock on a RUN-MANIFEST target (F-01 + F-03) ---
# Arg 1: manifest path. Opens fd 200 on <path>.lock (POSIX) or mkdir's
# <path>.lock.d (Windows). Bounded 2s wait on both paths. On timeout:
# caller should emit an audit entry + exit 6.
#
# Caller responsibilities:
#   - Call `detect_platform` before this (or rely on the built-in fallback).
#   - Register trap 'release_coarse_lock "$MANIFEST_PATH"' EXIT INT TERM
#     for Windows path (POSIX auto-releases on process exit via fd 200).
#
# Returns 0 on success; 6 on timeout.
acquire_coarse_lock() {
  local target="$1"
  [ -n "${AIH_USE_MKDIR_LOCK:-}" ] || detect_platform
  if [ "${AIH_USE_MKDIR_LOCK:-0}" = "0" ]; then
    # POSIX path — flock -w 2 on fd 200
    exec 200>"$target.lock" 2>/dev/null || return 6
    if ! flock -w 2 200; then
      return 6
    fi
    return 0
  else
    # Windows path — mkdir-atomic with bounded retry
    [ -n "${AIH_SLEEP_FRACTIONAL:-}" ] || detect_fractional_sleep
    local max_iters sleep_cmd i
    if [ "${AIH_SLEEP_FRACTIONAL:-0}" = "1" ]; then
      max_iters=40; sleep_cmd="sleep 0.05"
    else
      max_iters=2;  sleep_cmd="sleep 1"
    fi
    i=0
    while ! mkdir "$target.lock.d" 2>/dev/null; do
      i=$((i+1))
      if [ "$i" -ge "$max_iters" ]; then
        return 6
      fi
      $sleep_cmd 2>/dev/null || true
    done
    return 0
  fi
}

# --- Release the coarse outer lock (Windows path only; POSIX auto-releases) ---
release_coarse_lock() {
  local target="$1"
  if [ "${AIH_USE_MKDIR_LOCK:-0}" = "1" ]; then
    rmdir "$target.lock.d" 2>/dev/null || true
  fi
  # POSIX: fd 200 released on process exit; nothing to do here.
}
