#!/usr/bin/env bash
# manifest-append.sh — single writer for RUN-MANIFEST.md Story Records + Invoke stack.
# ADR-004 amendment to ADR-001. Append-only; mkdir-mutex with 30s stale reclaim;
# trap release; worktree-refusal guard; OneDrive/cloud-sync advisory.
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

# --- helpers ---

ts_iso() { date -u +%FT%TZ; }

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

# --- lock (mkdir mutex with 30s stale reclaim + trap release) ---

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
  trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT INT TERM
}

# --- section manipulators (in-memory transforms) ---

# Count rows in Invoke stack (non-empty content lines)
stack_depth() {
  awk '/^## Invoke stack$/ {on=1; next} /^## / {on=0} on && /[^[:space:]]/' "$MANIFEST_PATH" | wc -l | tr -d ' '
}

# Append a raw line to a target section, in-place, via tmp + replace.
# For "## Invoke stack" and "## Story Records" append mode.
append_to_section() {
  local section_header="$1" new_line="$2" mode="${3:-append}"
  local tmp="$MANIFEST_PATH.tmp"
  local in_section=0 done_append=0
  awk -v header="$section_header" -v line="$new_line" -v mode="$mode" -v out_tmp="$tmp" '
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

# Pop last non-empty line from Invoke stack
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

# Update a Metadata key: value (phase|status|last_updated)
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

append_progress_log() {
  local line="$1"
  append_to_section "## Progress Log" "- $(ts_iso) — $line" append
}

# --- main dispatch ---

onedrive_advisory
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
