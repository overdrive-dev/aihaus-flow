#!/usr/bin/env bash
# manifest-append.sh — single writer for RUN-MANIFEST.md Story Records + Invoke stack
#                       + Checkpoints (schema v3, M014/ADR-M014-B).
# ADR-004 amendment to ADR-001. Append-only; mkdir-mutex with 30s stale reclaim;
# trap release; worktree-refusal guard; OneDrive/cloud-sync advisory.
#
# M011/S01: wraps read-modify-write path in a coarse outer lock (POSIX flock -w 2
# via manifest-helpers.sh; Windows mkdir-atomic fallback per S02). Existing
# mkdir-mutex + 30s stale-reclaim preserved as the inner lock.
#
# Usage:
#   manifest-append.sh --field story-record|invoke-push|invoke-pop|progress-log|phase|status \
#                      --payload "<value>"
#   manifest-append.sh --checkpoint-enter <story> <agent> <substep>
#   manifest-append.sh --checkpoint-exit  <story> <agent> <substep> <result> [<sha>]
#     result must be one of: OK ERR SKIP
#     sha is optional 7-char short git sha (omit or pass "" if no commit)
#
# Env: MANIFEST_PATH (required; path to RUN-MANIFEST.md)
#      AIHAUS_AUDIT_LOG (optional; default .claude/audit/hook.jsonl)
#
# Exit codes: 0 ok, 2 invalid args, 3 worktree-refuse, 4 stack-full,
#             5 stack-empty, 6 lock-timeout, 7 manifest-missing, 8 payload-malformed,
#             9 result-invalid (--checkpoint-exit with bad result enum).
set -euo pipefail

MAX_DEPTH=3
STALE_LOCK_SEC=30
AUDIT_LOG="${AIHAUS_AUDIT_LOG:-.claude/audit/hook.jsonl}"

# --- source shared helpers (F-01 extraction; see architecture § 2.0) ---
# shellcheck source=lib/manifest-helpers.sh
. "$(dirname "$0")/lib/manifest-helpers.sh"

# --- runtime platform detect (M011/S02; F-03 no-persistence) ---
# Probes `command -v flock` at invocation. POSIX path uses flock -w 2 on a
# fd-backed lock file; Windows path (MSYS/Cygwin/no-flock) falls through to
# mkdir-atomic with bounded 2s retry. AIH_USE_MKDIR_LOCK caches the choice
# for the hook process lifetime — no disk state, zero ADR-005 collision
# (.aihaus/.install-platform remains reserved for claude|cursor|both).
detect_platform
detect_fractional_sleep

# --- argument parsing ---

FIELD=""
PAYLOAD=""
CHECKPOINT_MODE=""   # "enter" or "exit"
CP_STORY=""
CP_AGENT=""
CP_SUBSTEP=""
CP_RESULT=""
CP_SHA=""

# Detect checkpoint modes first (positional args, not --field/--payload)
case "${1:-}" in
  --checkpoint-enter)
    CHECKPOINT_MODE="enter"
    [ $# -ge 4 ] || { echo "manifest-append.sh: --checkpoint-enter requires <story> <agent> <substep>" >&2; exit 2; }
    CP_STORY="$2"; CP_AGENT="$3"; CP_SUBSTEP="$4"
    shift 4
    ;;
  --checkpoint-exit)
    CHECKPOINT_MODE="exit"
    [ $# -ge 5 ] || { echo "manifest-append.sh: --checkpoint-exit requires <story> <agent> <substep> <result> [<sha>]" >&2; exit 2; }
    CP_STORY="$2"; CP_AGENT="$3"; CP_SUBSTEP="$4"; CP_RESULT="$5"
    CP_SHA="${6:-}"
    shift; shift; shift; shift; shift; shift 2>/dev/null || true
    ;;
  *)
    while [ $# -gt 0 ]; do
      case "$1" in
        --field) FIELD="$2"; shift 2 ;;
        --payload) PAYLOAD="$2"; shift 2 ;;
        *) echo "manifest-append.sh: unknown arg $1" >&2; exit 2 ;;
      esac
    done
    ;;
esac

if [ -z "$CHECKPOINT_MODE" ]; then
  [ -n "$FIELD" ] || { echo "manifest-append.sh: --field required" >&2; exit 2; }
  case "$FIELD" in
    story-record|invoke-push|invoke-pop|progress-log|phase|status) ;;
    *) echo "manifest-append.sh: invalid --field $FIELD" >&2; exit 2 ;;
  esac
fi

MANIFEST_PATH="${MANIFEST_PATH:-}"
[ -n "$MANIFEST_PATH" ] || { echo "manifest-append.sh: MANIFEST_PATH env required" >&2; exit 2; }
[ -f "$MANIFEST_PATH" ] || { echo "manifest-append.sh: manifest not found: $MANIFEST_PATH" >&2; exit 7; }

# --- worktree refusal (ADR-004: writes only from orchestrator, not implementer worktree) ---

if command -v git >/dev/null 2>&1; then
  SUPER="$(git rev-parse --show-superproject-working-tree 2>/dev/null || true)"
  if [ -n "$SUPER" ]; then
    echo "manifest-append.sh: refused — running inside a git worktree. Writes must occur on orchestrator checkout." >&2
    exit 3
  fi
fi

# --- helpers (ts_iso + shared RW primitives sourced from lib above) ---

log_audit() {
  local result="$1" reason="${2:-null}"
  mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true
  local reason_json="null"
  [ "$reason" != "null" ] && reason_json="\"$reason\""
  local field_label="${FIELD:-checkpoint-${CHECKPOINT_MODE}}"
  local payload_summary
  if [ -n "$CHECKPOINT_MODE" ]; then
    payload_summary="${CP_STORY}|${CP_AGENT}|${CP_SUBSTEP}|${CP_RESULT}"
  else
    payload_summary="${PAYLOAD:0:60}"
  fi
  printf '{"ts":"%s","hook":"manifest-append","field":"%s","payload_summary":"%s","result":"%s","reason":%s}\n' \
    "$(ts_iso)" "$field_label" "${payload_summary//\"/\\\"}" "$result" "$reason_json" \
    >> "$AUDIT_LOG" 2>/dev/null || true
}

onedrive_advisory() {
  # one-time per day, marker file under audit dir
  local marker
  marker="$(dirname "$AUDIT_LOG")/.onedrive-advised-$(date -u +%F)"
  case "$MANIFEST_PATH" in
    *OneDrive*|*"One Drive"*|*Dropbox*|*iCloud*)
      if [ ! -f "$marker" ]; then
        mkdir -p "$(dirname "$marker")" 2>/dev/null || true
        touch "$marker" 2>/dev/null || true
        printf '{"ts":"%s","hook":"manifest-append","advisory":"cloud-sync-path","path":"%s"}\n' \
          "$(ts_iso)" "$MANIFEST_PATH" >> "$AUDIT_LOG" 2>/dev/null || true
      fi
      ;;
  esac
}

# --- coarse outer lock (M011/S01 + S02) ---

acquire_coarse() {
  # detect_platform already called at hook startup; lib re-probes safely.
  if ! acquire_coarse_lock "$MANIFEST_PATH"; then
    echo "manifest-append.sh: coarse lock timeout after 2s on $MANIFEST_PATH.lock" >&2
    log_audit "fail" "flock-timeout"
    exit 6
  fi
  # Windows path needs explicit release; POSIX fd 200 auto-releases on exit.
  if [ "${AIH_USE_MKDIR_LOCK:-0}" = "1" ]; then
    trap 'release_coarse_lock "$MANIFEST_PATH"; rmdir "$LOCK" 2>/dev/null || true' EXIT INT TERM
  fi
}

# --- inner lock (mkdir mutex with 30s stale reclaim + trap release) ---

LOCK="$MANIFEST_PATH.lock"

acquire_lock() {
  local tries=0
  while ! mkdir "$LOCK" 2>/dev/null; do
    if [ -d "$LOCK" ]; then
      local age
      age=$(( $(date +%s) - $(stat -c %Y "$LOCK" 2>/dev/null || stat -f %m "$LOCK" 2>/dev/null || echo 0) ))
      if [ "$age" -gt "$STALE_LOCK_SEC" ]; then
        rmdir "$LOCK" 2>/dev/null || true
        log_audit "lock-reclaimed" "stale-${age}s"
        continue
      fi
    fi
    tries=$((tries + 1))
    if [ "$tries" -ge 100 ]; then
      echo "manifest-append.sh: lock timeout after 100 tries on $LOCK" >&2
      log_audit "fail" "lock-timeout"
      exit 6
    fi
    sleep 0.1 2>/dev/null || sleep 1
  done
  # Compose trap: if coarse-lock trap already set (Windows path), replace with combined.
  if [ "${AIH_USE_MKDIR_LOCK:-0}" = "1" ]; then
    trap 'rmdir "$LOCK" 2>/dev/null || true; release_coarse_lock "$MANIFEST_PATH"' EXIT INT TERM
  else
    trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT INT TERM
  fi
}

# --- section manipulators extracted to manifest-helpers.sh (F-01) ---
# update_metadata_kv, append_to_section, append_progress_log, stack_depth
# are all sourced from lib/manifest-helpers.sh at the top of this file.

# Pop last non-empty line from Invoke stack — local-only variant (not used by
# phase-advance), so it stays here rather than moving to the shared lib.
pop_invoke_stack() {
  local tmp="$MANIFEST_PATH.tmp"
  awk '
    BEGIN { in_sec=0 }
    /^## Invoke stack$/ { in_sec=1; print; next }
    /^## / && in_sec==1 {
      # print buffered lines except the last non-empty
      if (buf_n > 0) {
        for (i=1; i<last_nonempty; i++) print buf[i]
        for (i=last_nonempty+1; i<=buf_n; i++) print buf[i]
      }
      buf_n=0; last_nonempty=0
      in_sec=0; print; next
    }
    in_sec==1 {
      buf_n++; buf[buf_n]=$0
      if ($0 ~ /[^[:space:]]/) last_nonempty=buf_n
      next
    }
    { print }
    END {
      if (in_sec==1 && buf_n > 0) {
        for (i=1; i<last_nonempty; i++) print buf[i]
        for (i=last_nonempty+1; i<=buf_n; i++) print buf[i]
      }
    }
  ' "$MANIFEST_PATH" > "$tmp"
  mv -f "$tmp" "$MANIFEST_PATH"
}

# --- checkpoint helpers (schema v3, M014/ADR-M014-B) ---

# Ensure ## Checkpoints section exists. Called inside the lock.
# Per ADR-M014-B C.3: auto-creates via the existing mkdir lock (defense-in-depth).
_ensure_checkpoints_section() {
  if ! grep -q '^## Checkpoints$' "$MANIFEST_PATH"; then
    printf '\n## Checkpoints\n\n| ts | story | agent | substep | event | result | sha |\n|---|---|---|---|---|---|---|\n' \
      >> "$MANIFEST_PATH"
  fi
}

# Append a checkpoint row to ## Checkpoints.
# Args: ts story agent substep event result sha
_append_checkpoint_row() {
  local ts="$1" story="$2" agent="$3" substep="$4" event="$5" result="$6" sha="$7"
  local row="| ${ts} | ${story} | ${agent} | ${substep} | ${event} | ${result} | ${sha} |"
  local tmp="$MANIFEST_PATH.tmp"
  awk -v header="## Checkpoints" -v line="$row" '
    BEGIN { in_sec=0; done=0 }
    {
      if ($0 == header) { in_sec=1; print; next }
      if (/^## / && in_sec==1) {
        if (done==0) { print line; done=1 }
        in_sec=0; print; next
      }
      print
    }
    END {
      if (in_sec==1 && done==0) { print line }
    }
  ' "$MANIFEST_PATH" > "$tmp"
  mv -f "$tmp" "$MANIFEST_PATH"
}

# Rate-limit guard: return 0 (allow) or 1 (drop) for duplicate enter events.
# Drops if an identical (story, agent, substep) enter row exists with a ts
# within the last 1 second.
_checkpoint_rate_limit() {
  local story="$1" agent="$2" substep="$3"
  local now_epoch; now_epoch="$(date +%s)"
  local cutoff=$(( now_epoch - 1 ))
  # Search for recent enter rows with same tuple
  while IFS='|' read -r _ ts_col story_col agent_col substep_col event_col _rest; do
    # Strip whitespace
    ts_col="${ts_col// /}"; story_col="${story_col// /}"; agent_col="${agent_col// /}"
    substep_col="${substep_col// /}"; event_col="${event_col// /}"
    [ "$event_col" = "enter" ] || continue
    [ "$story_col" = "$story" ] || continue
    [ "$agent_col" = "$agent" ] || continue
    [ "$substep_col" = "$substep" ] || continue
    # Parse ts to epoch for comparison (strip Z, replace T with space)
    local ts_plain="${ts_col%Z}"; ts_plain="${ts_plain/T/ }"
    local row_epoch; row_epoch="$(date -u -d "$ts_plain" +%s 2>/dev/null || date -u -j -f "%Y-%m-%d %H:%M:%S" "$ts_plain" +%s 2>/dev/null || echo 0)"
    if [ "$row_epoch" -ge "$cutoff" ] 2>/dev/null; then
      return 1  # duplicate within 1s → drop
    fi
  done < <(grep '^|' "$MANIFEST_PATH" 2>/dev/null || true)
  return 0  # allow
}

# --- main dispatch ---

onedrive_advisory
acquire_coarse
acquire_lock

# Checkpoint modes bypass the normal --field/--payload dispatch
if [ -n "$CHECKPOINT_MODE" ]; then
  case "$CHECKPOINT_MODE" in
    enter)
      _ensure_checkpoints_section
      if ! _checkpoint_rate_limit "$CP_STORY" "$CP_AGENT" "$CP_SUBSTEP"; then
        log_audit "rate-limited" "duplicate-enter-within-1s"
        exit 0
      fi
      _append_checkpoint_row "$(ts_iso)" "$CP_STORY" "$CP_AGENT" "$CP_SUBSTEP" "enter" "" ""
      update_metadata_kv "last_updated" "$(ts_iso)"
      log_audit "ok"
      exit 0
      ;;
    exit)
      case "$CP_RESULT" in
        OK|ERR|SKIP) ;;
        *) echo "manifest-append.sh: --checkpoint-exit result must be OK, ERR, or SKIP; got '${CP_RESULT}'" >&2
           log_audit "fail" "result-invalid"
           exit 9 ;;
      esac
      _ensure_checkpoints_section
      _append_checkpoint_row "$(ts_iso)" "$CP_STORY" "$CP_AGENT" "$CP_SUBSTEP" "exit" "$CP_RESULT" "$CP_SHA"
      update_metadata_kv "last_updated" "$(ts_iso)"
      log_audit "ok"
      exit 0
      ;;
  esac
fi

case "$FIELD" in
  story-record)
    [ -n "$PAYLOAD" ] || { log_audit "fail" "payload-empty"; exit 8; }
    # payload is a pre-formed pipe-delimited row
    append_to_section "## Story Records" "$PAYLOAD" append
    update_metadata_kv "last_updated" "$(ts_iso)"
    ;;
  invoke-push)
    [ -n "$PAYLOAD" ] || { log_audit "fail" "payload-empty"; exit 8; }
    depth=$(stack_depth)
    if [ "$depth" -ge "$MAX_DEPTH" ]; then
      log_audit "fail" "stack-full"
      exit 4
    fi
    append_to_section "## Invoke stack" "$PAYLOAD" append
    update_metadata_kv "last_updated" "$(ts_iso)"
    ;;
  invoke-pop)
    depth=$(stack_depth)
    if [ "$depth" -le 0 ]; then
      log_audit "fail" "stack-empty"
      exit 5
    fi
    pop_invoke_stack
    update_metadata_kv "last_updated" "$(ts_iso)"
    ;;
  progress-log)
    [ -n "$PAYLOAD" ] || { log_audit "fail" "payload-empty"; exit 8; }
    append_progress_log "$PAYLOAD"
    update_metadata_kv "last_updated" "$(ts_iso)"
    ;;
  phase)
    [ -n "$PAYLOAD" ] || { log_audit "fail" "payload-empty"; exit 8; }
    update_metadata_kv "phase" "$PAYLOAD"
    update_metadata_kv "last_updated" "$(ts_iso)"
    ;;
  status)
    [ -n "$PAYLOAD" ] || { log_audit "fail" "payload-empty"; exit 8; }
    update_metadata_kv "status" "$PAYLOAD"
    update_metadata_kv "last_updated" "$(ts_iso)"
    ;;
esac

log_audit "ok"
