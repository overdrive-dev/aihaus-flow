#!/usr/bin/env bash
# phase-advance.sh — atomic STATUS.md writer + PLAN.md/CONTEXT.md frontmatter Status update.
# ADR-004 projection of Metadata.phase from RUN-MANIFEST.md. Sole writer of STATUS.md post-M003.
#
# Usage: phase-advance.sh --to <phase> --dir <milestone_or_plan_dir>
#   <phase> ∈ gathering | planning | ready | running | complete | paused
#
# Env: AIHAUS_AUDIT_LOG (optional; default .claude/audit/hook.jsonl)
#
# Exit codes: 0 ok, 2 invalid args, 3 worktree-refuse, 10 invoke-stack-non-empty,
#             11 atomic-replace-failed, 12 target-dir-missing.
set -euo pipefail

AUDIT_LOG="${AIHAUS_AUDIT_LOG:-.claude/audit/hook.jsonl}"

TO=""
DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --to) TO="$2"; shift 2 ;;
    --dir) DIR="$2"; shift 2 ;;
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

# --- worktree refusal ---
if command -v git >/dev/null 2>&1; then
  SUPER="$(git rev-parse --show-superproject-working-tree 2>/dev/null || true)"
  if [ -n "$SUPER" ]; then
    echo "phase-advance.sh: refused — inside a git worktree." >&2
    exit 3
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

# --- detect existing STATUS.md state ---
STATUS_FILE="$DIR/STATUS.md"
FROM_PHASE="none"
if [ -f "$STATUS_FILE" ]; then
  FROM_PHASE="$(head -1 "$STATUS_FILE" | tr -d '[:space:]' || echo 'unknown')"
fi

# --- refuse if Invoke stack non-empty in sibling RUN-MANIFEST.md ---
MANIFEST="$DIR/RUN-MANIFEST.md"
if [ -f "$MANIFEST" ]; then
  STACK_ROWS="$(awk '/^## Invoke stack$/ {on=1; next} /^## / {on=0} on && /[^[:space:]]/' "$MANIFEST" | wc -l | tr -d ' ')"
  if [ "$STACK_ROWS" -gt 0 ]; then
    echo "phase-advance.sh: refused — Invoke stack non-empty ($STACK_ROWS rows). Complete active invocation first." >&2
    log_audit "refused-invoke-active" "$FROM_PHASE"
    exit 10
  fi
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

log_audit "ok" "$FROM_PHASE" "$FALLBACK_USED" "$BACKUP_CREATED"
echo "phase-advance.sh: $FROM_PHASE → $TO (dir=$DIR)"
