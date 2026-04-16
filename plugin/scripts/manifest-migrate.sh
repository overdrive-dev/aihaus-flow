#!/usr/bin/env bash
# manifest-migrate.sh — detect v1 RUN-MANIFEST.md and convert to v2 in place.
# ADR-004 migration hook. Idempotent; backs up to .v1.bak before first mutation.
# Coordinates with manifest-append.sh via the same $MANIFEST_PATH.lock mutex.
#
# Usage: MANIFEST_PATH=<path> manifest-migrate.sh
#
# Exit codes: 0 ok (migrated or already-v2), 2 invalid args, 3 worktree-refuse,
#             4 backup-failed, 5 write-failed, 6 lock-timeout, 7 manifest-missing.
set -euo pipefail

STALE_LOCK_SEC=30
AUDIT_LOG="${AIHAUS_AUDIT_LOG:-.claude/audit/hook.jsonl}"

MANIFEST_PATH="${MANIFEST_PATH:-}"
[ -n "$MANIFEST_PATH" ] || { echo "manifest-migrate.sh: MANIFEST_PATH env required" >&2; exit 2; }
[ -f "$MANIFEST_PATH" ] || { echo "manifest-migrate.sh: manifest not found: $MANIFEST_PATH" >&2; exit 7; }

# --- worktree refusal (ADR-004) ---
if command -v git >/dev/null 2>&1; then
  SUPER="$(git rev-parse --show-superproject-working-tree 2>/dev/null || true)"
  if [ -n "$SUPER" ]; then
    echo "manifest-migrate.sh: refused — running inside a git worktree." >&2
    exit 3
  fi
fi

ts_iso() { date -u +%FT%TZ; }

log_audit() {
  local result="$1" detail="${2:-null}"
  mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true
  local detail_json="null"
  [ "$detail" != "null" ] && detail_json="\"$detail\""
  printf '{"ts":"%s","hook":"manifest-migrate","manifest_path":"%s","result":"%s","detail":%s}\n' \
    "$(ts_iso)" "$MANIFEST_PATH" "$result" "$detail_json" \
    >> "$AUDIT_LOG" 2>/dev/null || true
}

# OneDrive advisory (same pattern as manifest-append.sh)
case "$MANIFEST_PATH" in
  *OneDrive*|*"One Drive"*|*Dropbox*|*iCloud*)
    marker="$(dirname "$AUDIT_LOG")/.onedrive-advised-$(date -u +%F)"
    if [ ! -f "$marker" ]; then
      mkdir -p "$(dirname "$marker")" 2>/dev/null || true
      touch "$marker" 2>/dev/null || true
      printf '{"ts":"%s","hook":"manifest-migrate","advisory":"cloud-sync-path","path":"%s"}\n' \
        "$(ts_iso)" "$MANIFEST_PATH" >> "$AUDIT_LOG" 2>/dev/null || true
    fi
    ;;
esac

# --- detect v2 (idempotent no-op) ---
if grep -qE '^schema:\s*v2\s*$' "$MANIFEST_PATH"; then
  echo "manifest-migrate.sh: already-v2 (no-op)"
  log_audit "already-v2"
  exit 0
fi

# --- acquire lock (shared protocol with manifest-append.sh) ---
LOCK="$MANIFEST_PATH.lock"
tries=0
while ! mkdir "$LOCK" 2>/dev/null; do
  if [ -d "$LOCK" ]; then
    age=$(( $(date +%s) - $(stat -c %Y "$LOCK" 2>/dev/null || stat -f %m "$LOCK" 2>/dev/null || echo 0) ))
    if [ "$age" -gt "$STALE_LOCK_SEC" ]; then
      rmdir "$LOCK" 2>/dev/null || true
      continue
    fi
  fi
  tries=$((tries + 1))
  [ "$tries" -lt 100 ] || { echo "manifest-migrate.sh: lock timeout" >&2; log_audit "fail" "lock-timeout"; exit 6; }
  sleep 0.1 2>/dev/null || sleep 1
done
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT INT TERM

# --- backup v1 ---
BAK="${MANIFEST_PATH}.v1.bak"
if ! cp -f "$MANIFEST_PATH" "$BAK"; then
  log_audit "fail" "backup-failed"
  exit 4
fi

# --- extract v1 fields (best-effort) ---
# v1 shape (free-form): header "# Run Manifest: ..." then YAML-ish lines like
# "**Run ID:**", "**Command:**", "**Started:**", "**Phase:**", "**Status:**",
# "**Branch:**", "**Last updated:**", followed by "## Progress Log" + bullets.

get_v1_field() {
  local label="$1"
  grep -iE "^\*\*${label}:\*\*" "$MANIFEST_PATH" | head -1 | sed -E "s/^\*\*${label}:\*\*[[:space:]]*//i" | sed -E 's/[[:space:]]*$//'
}

MILESTONE="$(get_v1_field 'Run ID')"
BRANCH="$(get_v1_field 'Branch')"
STARTED="$(get_v1_field 'Started')"
PHASE="$(get_v1_field 'Phase')"
STATUS_V1="$(get_v1_field 'Status')"
LAST_UPDATED="$(get_v1_field 'Last updated')"

# Derive milestone ID from Run ID or file path if empty
if [ -z "$MILESTONE" ]; then
  MILESTONE="$(basename "$(dirname "$MANIFEST_PATH")")"
fi
[ -n "$STARTED" ] || STARTED="$(ts_iso)"
[ -n "$LAST_UPDATED" ] || LAST_UPDATED="$(ts_iso)"
[ -n "$PHASE" ] || PHASE="unknown"
[ -n "$STATUS_V1" ] || STATUS_V1="unknown"
[ -n "$BRANCH" ] || BRANCH="unknown"

# Extract Progress Log lines → best-effort story records
# v1 Progress Log: "- [ts] — <text>" style bullets
TMP="$(mktemp)"
trap 'rmdir "$LOCK" 2>/dev/null || true; rm -f "$TMP"' EXIT INT TERM

PRESERVED=0
BEST_EFFORT=0
awk '/^## Progress Log$/ {on=1; next} /^## / {on=0} on && /^- /' "$MANIFEST_PATH" > "$TMP" || true

# --- write v2 ---
{
  echo "## Metadata"
  echo "milestone: $MILESTONE"
  echo "branch: $BRANCH"
  echo "started: $STARTED"
  echo "schema: v2"
  echo "phase: $PHASE"
  echo "status: $STATUS_V1"
  echo "last_updated: $LAST_UPDATED"
  echo ""
  echo "## Invoke stack"
  echo ""
  echo "## Story Records"
  echo "story_id|status|started_at|commit_sha|verified|notes"
  # best-effort: one row per v1 progress bullet, story_id=unknown, notes=raw bullet text
  while IFS= read -r bullet; do
    [ -n "$bullet" ] || continue
    clean="$(printf '%s' "$bullet" | sed -E 's/^-[[:space:]]*//' | sed -E 's/\|/\\|/g')"
    echo "unknown|complete|$STARTED||false|$clean"
    BEST_EFFORT=$((BEST_EFFORT + 1))
  done < "$TMP"
  echo ""
  echo "## Progress Log (legacy — migrated)"
  cat "$TMP" 2>/dev/null || true
} > "$MANIFEST_PATH.new"

if ! mv -f "$MANIFEST_PATH.new" "$MANIFEST_PATH"; then
  echo "manifest-migrate.sh: write failed" >&2
  log_audit "fail" "write-failed"
  exit 5
fi

echo "manifest-migrate.sh: v1 → v2 OK, 0 story rows preserved, ${BEST_EFFORT} rows required best-effort parse"
log_audit "migrated" "best-effort:$BEST_EFFORT"
