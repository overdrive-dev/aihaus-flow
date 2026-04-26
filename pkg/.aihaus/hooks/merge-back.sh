#!/usr/bin/env bash
# merge-back.sh — atomic per-file merge-back from worktree to main (M017/S03 / ADR-M017-A)
# Replaces prose protocol in team-template.md + execution.md.
# Single-writer via acquire_coarse_lock (manifest-helpers.sh).
#
# Usage:
#   merge-back.sh --story S<NN> --manifest <path> [--worktree <path>] [--drop <file>] [--abort]
#
# Env fallback: MANIFEST_PATH, STORY_ID, AIHAUS_WORKTREE_PATH
# Opt-out: AIHAUS_MERGE_BACK_GUARD=0 (falls back to operator discipline)
#
# Exit codes: 0=ok, 2=bad-args, 3=manifest-refuse, 6=lock-timeout, 12=worktree-dir-missing
#
# Owned Files parsing: reads from the story .md file inside the milestone directory
# (stories/<story-id>.md → ## Owned Files section). The story file path is derived from
# the manifest directory ($(dirname "$MANIFEST_PATH")/stories/). This is deterministic
# and requires no new manifest schema (D-006).
#
# Refusal grammar (exit 3, machine-parseable, MUST be stable per CHECK F-6):
#   MERGE_BACK_REFUSED story=S<NN> reason=<unexpected-files|missing-files|cross-story-spill> expected=<f1,f2> actual=<f1,f2,f3> worktree=<path>
#
# Audit: .claude/audit/hook.jsonl event:"merge-back" 8 fields:
#   story, agent, worktree, files-copied, sha, ts, result, duration-ms

set -euo pipefail

# --- opt-out bypass ---
if [ "${AIHAUS_MERGE_BACK_GUARD:-}" = "0" ]; then
  echo "merge-back.sh: DISABLED via AIHAUS_MERGE_BACK_GUARD=0 — falling back to operator discipline" >&2
  exit 0
fi

AUDIT_LOG="${AIHAUS_AUDIT_LOG:-.claude/audit/hook.jsonl}"
START_MS=$(date +%s%3N 2>/dev/null || echo "0")

# --- argument parsing ---
STORY=""
MANIFEST=""
WORKTREE="${AIHAUS_WORKTREE_PATH:-}"
DROP_FILE=""
ABORT=0

while [ $# -gt 0 ]; do
  case "$1" in
    --story)
      [ $# -ge 2 ] || { echo "merge-back.sh: --story requires <story-id>" >&2; exit 2; }
      STORY="$2"; shift 2 ;;
    --manifest)
      [ $# -ge 2 ] || { echo "merge-back.sh: --manifest requires <path>" >&2; exit 2; }
      MANIFEST="$2"; shift 2 ;;
    --worktree)
      [ $# -ge 2 ] || { echo "merge-back.sh: --worktree requires <path>" >&2; exit 2; }
      WORKTREE="$2"; shift 2 ;;
    --drop)
      [ $# -ge 2 ] || { echo "merge-back.sh: --drop requires <file>" >&2; exit 2; }
      DROP_FILE="$2"; shift 2 ;;
    --abort)
      ABORT=1; shift ;;
    *)
      echo "merge-back.sh: unknown arg $1" >&2; exit 2 ;;
  esac
done

# --- env fallback ---
STORY="${STORY:-${STORY_ID:-}}"
MANIFEST="${MANIFEST:-${MANIFEST_PATH:-}}"

[ -n "$STORY" ]   || { echo "merge-back.sh: --story S<NN> required (or STORY_ID env)" >&2; exit 2; }
[ -n "$MANIFEST" ] || { echo "merge-back.sh: --manifest <path> required (or MANIFEST_PATH env)" >&2; exit 2; }
[ -f "$MANIFEST" ] || { echo "merge-back.sh: manifest not found: $MANIFEST" >&2; exit 2; }

# --- source shared helpers ---
# shellcheck source=./lib/manifest-helpers.sh
. "$(dirname "$0")/lib/manifest-helpers.sh"

detect_platform
detect_fractional_sleep

# Export MANIFEST_PATH for helpers that need it
MANIFEST_PATH="$MANIFEST"
export MANIFEST_PATH

# --- helpers ---

ts_iso() { date -u +%FT%TZ; }

log_audit() {
  local result="$1" files_copied="${2:-0}" sha="${3:-}" duration_ms="${4:-0}"
  mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true
  printf '{"ts":"%s","event":"merge-back","hook":"merge-back","story":"%s","agent":"implementer","worktree":"%s","files-copied":%s,"sha":"%s","result":"%s","duration-ms":%s}\n' \
    "$(ts_iso)" "$STORY" "${WORKTREE:-unknown}" "$files_copied" "$sha" "$result" "$duration_ms" \
    >> "$AUDIT_LOG" 2>/dev/null || true
}

elapsed_ms() {
  local now
  now=$(date +%s%3N 2>/dev/null || echo "0")
  echo $(( now - START_MS ))
}

# --- acquire coarse lock ---
if ! acquire_coarse_lock "$MANIFEST"; then
  echo "merge-back.sh: coarse lock timeout after 2s on $MANIFEST.lock" >&2
  log_audit "fail-lock-timeout" "0" "" "$(elapsed_ms)"
  exit 6
fi
if [ "${AIH_USE_MKDIR_LOCK:-0}" = "1" ]; then
  trap 'release_coarse_lock "$MANIFEST"' EXIT INT TERM
fi

# --- checkpoint enter ---
bash "$(dirname "$0")/manifest-append.sh" \
  --checkpoint-enter "$STORY" merge-back "merge-back:$STORY" 2>/dev/null || true

# --- --abort path ---
if [ "$ABORT" = "1" ]; then
  # Flag preserved-for-inspection in manifest progress log
  bash "$(dirname "$0")/manifest-append.sh" \
    --field progress-log \
    --payload "merge-back:$STORY --abort: worktree preserved-for-inspection at ${WORKTREE:-unknown}" \
    2>/dev/null || true
  bash "$(dirname "$0")/manifest-append.sh" \
    --checkpoint-exit "$STORY" merge-back "merge-back:$STORY" ERR 2>/dev/null || true
  log_audit "aborted" "0" "" "$(elapsed_ms)"
  echo "merge-back.sh: aborted — worktree preserved-for-inspection at ${WORKTREE:-unknown}" >&2
  exit 0
fi

# --- parse Owned Files from story .md file (D-006) ---
# Derives story file path from manifest directory: $(dirname MANIFEST)/stories/<story-id>.md
# Parses the ## Owned Files section (backtick-less lines starting with '- ').
MILESTONE_DIR="$(dirname "$MANIFEST")"
STORY_FILE=""

# Search for story file by ID (story files may have varied name prefixes)
while IFS= read -r -d '' candidate; do
  if head -5 "$candidate" | grep -qiE "^\[?${STORY}\]?[[:space:]]*[—-]|^#.*\[?${STORY}\]?"; then
    STORY_FILE="$candidate"
    break
  fi
done < <(find "$MILESTONE_DIR/stories" -maxdepth 1 -type f -name '*.md' -print0 2>/dev/null || true)

# Fallback: try exact name match <STORY>.md
if [ -z "$STORY_FILE" ] && [ -f "$MILESTONE_DIR/stories/${STORY}.md" ]; then
  STORY_FILE="$MILESTONE_DIR/stories/${STORY}.md"
fi

if [ -z "$STORY_FILE" ] || [ ! -f "$STORY_FILE" ]; then
  echo "merge-back.sh: story file not found for $STORY in $MILESTONE_DIR/stories/" >&2
  bash "$(dirname "$0")/manifest-append.sh" \
    --checkpoint-exit "$STORY" merge-back "merge-back:$STORY" ERR 2>/dev/null || true
  log_audit "fail-story-missing" "0" "" "$(elapsed_ms)"
  exit 2
fi

# Parse ## Owned Files section: lines that start with '- ' (backtick or plain path)
# Pattern matches:
#   - `path/to/file.sh` — description
#   - path/to/file.sh
mapfile -t OWNED_RAW < <(awk '
  /^## Owned Files/ { in_sec=1; next }
  /^## / && in_sec { exit }
  in_sec && /^- / {
    line = $0
    # strip leading "- " and optional backtick
    sub(/^- /, "", line)
    sub(/^`/, "", line)
    # strip trailing backtick + optional " — comment"
    sub(/`.*$/, "", line)
    sub(/ —.*$/, "", line)
    sub(/[[:space:]]*$/, "", line)
    # skip empty or section-only lines
    if (length(line) > 0) print line
  }
' "$STORY_FILE" 2>/dev/null || true)

if [ "${#OWNED_RAW[@]}" -eq 0 ]; then
  echo "merge-back.sh: no Owned Files found in $STORY_FILE — cannot proceed" >&2
  bash "$(dirname "$0")/manifest-append.sh" \
    --checkpoint-exit "$STORY" merge-back "merge-back:$STORY" ERR 2>/dev/null || true
  log_audit "fail-owned-empty" "0" "" "$(elapsed_ms)"
  exit 2
fi

# Normalize paths: strip leading ./ and trailing whitespace
OWNED=()
for f in "${OWNED_RAW[@]}"; do
  f="${f#./}"
  f="${f%[[:space:]]}"
  [ -n "$f" ] && OWNED+=("$f")
done

# --- resolve worktree path ---
# Env AIHAUS_WORKTREE_PATH or --worktree arg; no further discovery (deterministic per D-006)
if [ -z "$WORKTREE" ]; then
  echo "merge-back.sh: worktree path required (--worktree <path> or AIHAUS_WORKTREE_PATH env)" >&2
  bash "$(dirname "$0")/manifest-append.sh" \
    --checkpoint-exit "$STORY" merge-back "merge-back:$STORY" ERR 2>/dev/null || true
  log_audit "fail-worktree-missing" "0" "" "$(elapsed_ms)"
  exit 12
fi

if [ ! -d "$WORKTREE" ]; then
  echo "merge-back.sh: worktree-dir-missing $WORKTREE" >&2
  bash "$(dirname "$0")/manifest-append.sh" \
    --checkpoint-exit "$STORY" merge-back "merge-back:$STORY" ERR 2>/dev/null || true
  log_audit "fail-worktree-missing" "0" "" "$(elapsed_ms)"
  exit 12
fi

# --- --drop path: move unexpected file to rejected/ before proceeding ---
if [ -n "$DROP_FILE" ]; then
  REJECT_TS=$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || date -u +%Y%m%dT%H%M%SZ)
  REJECT_DIR=".claude/audit/rejected/${STORY}-${REJECT_TS}"
  mkdir -p "$REJECT_DIR" 2>/dev/null || true
  if [ -f "$WORKTREE/$DROP_FILE" ]; then
    mv "$WORKTREE/$DROP_FILE" "$REJECT_DIR/$DROP_FILE" 2>/dev/null || true
    echo "merge-back.sh: dropped $DROP_FILE to $REJECT_DIR/" >&2
  else
    echo "merge-back.sh: --drop: file not found in worktree: $WORKTREE/$DROP_FILE" >&2
  fi
fi

# --- per-file cp from worktree → main (never cp -R) ---
FILES_COPIED=0
for f in "${OWNED[@]}"; do
  SRC="$WORKTREE/$f"
  DST="./$f"
  if [ ! -f "$SRC" ]; then
    echo "merge-back.sh: source file missing in worktree: $SRC" >&2
    bash "$(dirname "$0")/manifest-append.sh" \
      --checkpoint-exit "$STORY" merge-back "merge-back:$STORY" ERR 2>/dev/null || true
    log_audit "fail-src-missing" "$FILES_COPIED" "" "$(elapsed_ms)"
    exit 3
  fi
  # Ensure destination directory exists
  DST_DIR="$(dirname "$DST")"
  mkdir -p "$DST_DIR" 2>/dev/null || true
  cp "$SRC" "$DST"
  FILES_COPIED=$((FILES_COPIED + 1))
done

# --- stage only Owned Files via explicit git add loop ---
for f in "${OWNED[@]}"; do
  git add "$f"
done

# --- verify staged == Owned exactly (exit 3 on mismatch) ---
STAGED_SORTED=$(git diff --cached --name-only 2>/dev/null | sort)
EXPECTED_SORTED=$(printf '%s\n' "${OWNED[@]}" | sort)

if [ "$STAGED_SORTED" != "$EXPECTED_SORTED" ]; then
  # Determine reason
  UNEXPECTED=$(comm -23 <(echo "$STAGED_SORTED") <(echo "$EXPECTED_SORTED") | tr '\n' ',' | sed 's/,$//')
  MISSING=$(comm -13 <(echo "$STAGED_SORTED") <(echo "$EXPECTED_SORTED") | tr '\n' ',' | sed 's/,$//')

  REASON="cross-story-spill"
  [ -n "$MISSING" ] && [ -z "$UNEXPECTED" ] && REASON="missing-files"
  [ -n "$UNEXPECTED" ] && [ -z "$MISSING" ] && REASON="unexpected-files"

  EXPECTED_CSV=$(printf '%s\n' "${OWNED[@]}" | tr '\n' ',' | sed 's/,$//')
  ACTUAL_CSV=$(echo "$STAGED_SORTED" | tr '\n' ',' | sed 's/,$//')

  echo "MERGE_BACK_REFUSED story=$STORY reason=$REASON expected=$EXPECTED_CSV actual=$ACTUAL_CSV worktree=$WORKTREE" >&2

  bash "$(dirname "$0")/manifest-append.sh" \
    --checkpoint-exit "$STORY" merge-back "merge-back:$STORY" ERR 2>/dev/null || true
  log_audit "refused-$REASON" "$FILES_COPIED" "" "$(elapsed_ms)"
  exit 3
fi

# --- emit audit row (8 fields) ---
CURRENT_SHA=$(git rev-parse HEAD 2>/dev/null | cut -c1-7 || echo "")
DURATION="$(elapsed_ms)"
log_audit "ok" "$FILES_COPIED" "$CURRENT_SHA" "$DURATION"

# --- checkpoint exit OK ---
bash "$(dirname "$0")/manifest-append.sh" \
  --checkpoint-exit "$STORY" merge-back "merge-back:$STORY" OK "$CURRENT_SHA" 2>/dev/null || true

echo "merge-back.sh: ok — story=$STORY files-copied=$FILES_COPIED worktree=$WORKTREE" >&2
exit 0
