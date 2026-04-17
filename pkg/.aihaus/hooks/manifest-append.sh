#!/usr/bin/env bash
# manifest-append.sh — single writer for RUN-MANIFEST.md Story Records + Invoke stack.
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
#
# Env: MANIFEST_PATH (required; path to RUN-MANIFEST.md)
#      AIHAUS_AUDIT_LOG (optional; default .claude/audit/hook.jsonl)
#
# Exit codes: 0 ok, 2 invalid args, 3 worktree-refuse, 4 stack-full,
#             5 stack-empty, 6 lock-timeout, 7 manifest-missing, 8 payload-malformed.
set -euo pipefail

MAX_DEPTH=3
STALE_LOCK_SEC=30
AUDIT_LOG="${AIHAUS_AUDIT_LOG:-.claude/audit/hook.jsonl}"

# --- source shared helpers (F-01 extraction; see architecture § 2.0) ---
# shellcheck source=lib/manifest-helpers.sh
. "$(dirname "$0")/lib/manifest-helpers.sh"

# --- argument parsing ---

FIELD=""
PAYLOAD=""
while [ $# -gt 0 ]; do
  case "$1" in
    --field) FIELD="$2"; shift 2 ;;
    --payload) PAYLOAD="$2"; shift 2 ;;
    *) echo "manifest-append.sh: unknown arg $1" >&2; exit 2 ;;
  esac
done

[ -n "$FIELD" ] || { echo "manifest-append.sh: --field required" >&2; exit 2; }
case "$FIELD" in
  story-record|invoke-push|invoke-pop|progress-log|phase|status) ;;
  *) echo "manifest-append.sh: invalid --field $FIELD" >&2; exit 2 ;;
esac

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
  local payload_summary="${PAYLOAD:0:60}"
  printf '{"ts":"%s","hook":"manifest-append","field":"%s","payload_summary":"%s","result":"%s","reason":%s}\n' \
    "$(ts_iso)" "$FIELD" "${payload_summary//\"/\\\"}" "$result" "$reason_json" \
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
  detect_platform
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

# --- main dispatch ---

onedrive_advisory
acquire_coarse
acquire_lock

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
