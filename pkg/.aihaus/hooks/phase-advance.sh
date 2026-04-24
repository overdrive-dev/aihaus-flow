#!/usr/bin/env bash
# phase-advance.sh — atomic STATUS.md writer + PLAN.md/CONTEXT.md frontmatter Status update.
# ADR-004 projection of Metadata.phase from RUN-MANIFEST.md. Sole writer of STATUS.md post-M003.
#
# Usage: phase-advance.sh --to <phase> --dir <milestone_or_plan_dir>
#   <phase> ∈ gathering | planning | ready | running | complete | paused
#
# M011/S01: wraps the STATUS.md + metadata writes in a coarse flock-w-2 on
# $DIR/RUN-MANIFEST.md.lock (POSIX) or mkdir-atomic fallback (Windows) so
# concurrent writers from manifest-append.sh and phase-advance.sh serialize
# on the same lock target.
#
# Env: AIHAUS_AUDIT_LOG (optional; default .claude/audit/hook.jsonl)
#
# Exit codes: 0 ok, 2 invalid args, 3 worktree-refuse, 6 lock-timeout,
#             10 invoke-stack-non-empty, 11 atomic-replace-failed,
#             12 target-dir-missing.
set -euo pipefail

AUDIT_LOG="${AIHAUS_AUDIT_LOG:-.claude/audit/hook.jsonl}"

# --- source shared helpers (F-01 extraction; see architecture § 2.0) ---
# shellcheck source=lib/manifest-helpers.sh
. "$(dirname "$0")/lib/manifest-helpers.sh"

# --- runtime platform detect (M011/S02; F-03 no-persistence) ---
# Probes `command -v flock` at invocation. POSIX → flock -w 2; Windows → mkdir
# atomic fallback. AIH_USE_MKDIR_LOCK caches the choice for the hook process
# lifetime — no disk state.
detect_platform
detect_fractional_sleep

TO=""
DIR=""
REASON=""
while [ $# -gt 0 ]; do
  case "$1" in
    --to) TO="$2"; shift 2 ;;
    --dir) DIR="$2"; shift 2 ;;
    --reason) REASON="$2"; shift 2 ;;
    *) echo "phase-advance.sh: unknown arg $1" >&2; exit 2 ;;
  esac
done

[ -n "$TO" ]  || { echo "phase-advance.sh: --to required" >&2; exit 2; }
[ -n "$DIR" ] || { echo "phase-advance.sh: --dir required" >&2; exit 2; }
[ -d "$DIR" ] || { echo "phase-advance.sh: dir not found: $DIR" >&2; exit 12; }

case "$TO" in
  gathering|planning|ready|running|complete|paused) ;;
  *) echo "phase-advance.sh: invalid phase $TO" >&2; exit 2 ;;
esac

# --- --reason required when --to paused (M011/S04) ---
if [ "$TO" = "paused" ] && [ -z "$REASON" ]; then
  echo "phase-advance.sh: --reason required when --to paused" >&2
  exit 2
fi

# --- sanitize REASON payload (trim, collapse newlines, quote→apostrophe, truncate@200) ---
if [ -n "$REASON" ]; then
  REASON="$(printf '%s' "$REASON" \
    | tr '\n\r\t' '   ' \
    | sed -e 's/^[[:space:]]\+//' -e 's/[[:space:]]\+$//' -e 's/  */ /g' -e 's/"/'"'"'/g')"
  if [ "${#REASON}" -gt 200 ]; then
    REASON="${REASON:0:200}…"
  fi
fi

# --- worktree refusal (M011/S04 F-02 bypass for --to paused) ---
# paused IS the escape hatch worktree-isolated agents must be able to emit
# when hitting a TRUE blocker — the paused write targets the absolute
# $MANIFEST_PATH in the main repo, not the worktree tree. Bypass applies
# ONLY to paused; gathering|planning|ready|running|complete keep exit 3.
if [ "$TO" = "paused" ]; then
  : # skip worktree refusal — paused is the escape hatch (F-02 / ADR-M011-A)
else
  if command -v git >/dev/null 2>&1; then
    SUPER="$(git rev-parse --show-superproject-working-tree 2>/dev/null || true)"
    if [ -n "$SUPER" ]; then
      echo "phase-advance.sh: refused — inside a git worktree." >&2
      exit 3
    fi
  fi
fi

ts_iso() { date -u +%FT%TZ; }

log_audit() {
  local result="$1" from_phase="${2:-unknown}" fallback="${3:-false}" backup="${4:-false}"
  mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true
  printf '{"ts":"%s","hook":"phase-advance","from_phase":"%s","to_phase":"%s","target_dir":"%s","result":"%s","fallback_used":%s,"backup_created":%s}\n' \
    "$(ts_iso)" "$from_phase" "$TO" "$DIR" "$result" "$fallback" "$backup" \
    >> "$AUDIT_LOG" 2>/dev/null || true
}

# --- coarse outer lock (M011/S01 + S02) ---
# Lock sibling file $DIR/RUN-MANIFEST.md so concurrent writers from
# manifest-append.sh serialize against phase-advance on the SAME target.
COARSE_LOCK_TARGET="$DIR/RUN-MANIFEST.md"
# detect_platform already called at hook startup; lib re-probes safely.
if ! acquire_coarse_lock "$COARSE_LOCK_TARGET"; then
  echo "phase-advance.sh: coarse lock timeout after 2s on $COARSE_LOCK_TARGET.lock" >&2
  log_audit "fail-flock-timeout" "unknown" "false" "false"
  exit 6
fi
if [ "${AIH_USE_MKDIR_LOCK:-0}" = "1" ]; then
  trap 'release_coarse_lock "$COARSE_LOCK_TARGET"' EXIT INT TERM
fi

# --- detect existing STATUS.md state ---
STATUS_FILE="$DIR/STATUS.md"
FROM_PHASE="none"
if [ -f "$STATUS_FILE" ]; then
  FROM_PHASE="$(head -1 "$STATUS_FILE" | tr -d '[:space:]' || echo 'unknown')"
fi

# --- refuse if Invoke stack non-empty in sibling RUN-MANIFEST.md ---
# (M011/S04: relaxed for --to paused — pausing mid-invocation is exactly the
# legitimate case; TRUE blockers surface inside an active invocation.)
MANIFEST="$DIR/RUN-MANIFEST.md"
STACK_ROWS=0
if [ -f "$MANIFEST" ]; then
  STACK_ROWS="$(awk '/^## Invoke stack$/ {on=1; next} /^## / {on=0} on && /[^[:space:]]/' "$MANIFEST" | wc -l | tr -d ' ')"
  if [ "$TO" = "paused" ]; then
    : # paused allowed mid-execution; audit note emitted below
  elif [ "$STACK_ROWS" -gt 0 ]; then
    echo "phase-advance.sh: refused — Invoke stack non-empty ($STACK_ROWS rows). Complete active invocation first." >&2
    log_audit "refused-invoke-active" "$FROM_PHASE"
    exit 10
  fi
fi

# --- scaffold-assert gate (M016/S11a): planning→running transition only ---
# ADR-M016-B: scaffold-assert.sh is the Step E2 gate. Exit 13 propagates gate failure.
if [[ "$TO" == "running" && "$FROM_PHASE" == "planning" ]]; then
  bash "$(dirname "$0")/scaffold-assert.sh" "$DIR" || exit 13
fi

# --- detect handwritten (legacy) STATUS.md (no DO-NOT-EDIT marker) ---
BACKUP_CREATED="false"
if [ -f "$STATUS_FILE" ] && ! grep -q "DO-NOT-EDIT" "$STATUS_FILE"; then
  cp -f "$STATUS_FILE" "$STATUS_FILE.handwritten.bak" 2>/dev/null && BACKUP_CREATED="true"
fi

# --- atomic write (tmp + mv; OneDrive-safe Python fallback) ---
TMP="$STATUS_FILE.tmp"
cat > "$TMP" <<EOF
$TO
<!-- DERIVED FROM RUN-MANIFEST.md — DO-NOT-EDIT-MANUALLY (phase-advance.sh is the sole writer) -->
<!-- last_updated: $(ts_iso) -->
EOF

FALLBACK_USED="false"
onedrive_path=0
case "$STATUS_FILE" in
  *OneDrive*|*"One Drive"*|*Dropbox*|*iCloud*) onedrive_path=1 ;;
esac

if [ "$onedrive_path" -eq 1 ] && command -v python3 >/dev/null 2>&1; then
  # Python os.replace is atomic across OneDrive/NTFS
  if python3 -c "import os,sys; os.replace(sys.argv[1], sys.argv[2])" "$TMP" "$STATUS_FILE" 2>/dev/null; then
    FALLBACK_USED="true"
  else
    mv -f "$TMP" "$STATUS_FILE" 2>/dev/null || { log_audit "fail-atomic" "$FROM_PHASE" "$FALLBACK_USED" "$BACKUP_CREATED"; exit 11; }
  fi
else
  mv -f "$TMP" "$STATUS_FILE" 2>/dev/null || { log_audit "fail-atomic" "$FROM_PHASE" "$FALLBACK_USED" "$BACKUP_CREATED"; exit 11; }
fi

# --- also update PLAN.md / CONTEXT.md Status frontmatter if present ---
for secondary in "$DIR/PLAN.md" "$DIR/CONTEXT.md"; do
  [ -f "$secondary" ] || continue
  # Match **Status:** <phase> or Status: <phase> in frontmatter; rewrite to new phase (idempotent)
  TMP2="$secondary.tmp"
  awk -v to="$TO" '
    BEGIN { changed=0 }
    /^\*\*Status:\*\*/ && !changed { sub(/\*\*Status:\*\*.*/, "**Status:** " to); changed=1 }
    /^Status:/ && !changed { sub(/Status:.*/, "Status: " to); changed=1 }
    { print }
  ' "$secondary" > "$TMP2" && mv -f "$TMP2" "$secondary" 2>/dev/null || true
done

# --- M011/S04: paused writes Metadata.status + Metadata.pause_reason + progress log ---
if [ "$TO" = "paused" ] && [ -f "$MANIFEST" ]; then
  # update_metadata_kv and append_progress_log both operate on $MANIFEST_PATH.
  MANIFEST_PATH="$MANIFEST"
  export MANIFEST_PATH
  update_metadata_kv "status" "paused"
  update_metadata_kv "pause_reason" "$REASON"
  update_metadata_kv "last_updated" "$(ts_iso)"
  append_progress_log "paused: $REASON (active-stack-rows=$STACK_ROWS)"
fi

log_audit "ok" "$FROM_PHASE" "$FALLBACK_USED" "$BACKUP_CREATED"
echo "phase-advance.sh: $FROM_PHASE → $TO (dir=$DIR)"
