#!/usr/bin/env bash
# statusline-milestone.sh — pure-reader statusLine emitter for Claude Code.
#
# Emits a single line on stdout:
#   M0XX · SNN/total · S<current>→ · MTIME-STALE?<N>m · phase:X · agents:N · sha:abc1234
# when an active milestone RUN-MANIFEST is found; otherwise exits 0 with empty
# stdout (M011 contract preserved). Read-only: no writes to RUN-MANIFEST.md or
# any other file except the cadence-delta append to .claude/audit/hook.jsonl
# (best-effort, no lock — pure-reader hook per CHECK F10).
#
# Sub-field render order (architecture.md §"statusLine 4 sub-fields render-order spec"):
#   1. M<id>          — milestone id from dir basename
#   2. S<n>/<total>   — distinct story-id count / file-count (FR-001, FR-002)
#   3. S<current>→    — latest in-file row of ## Story Records (FR-003; absent if none)
#   4. MTIME-STALE?Nm — stall label when phase=running and last_updated > threshold (FR-004)
#   5. phase:<phase>  — Metadata.phase
#   6. agents:<n>     — Invoke stack depth
#   7. sha:<hash>     — git rev-parse --short HEAD
#
# Manifest resolution order (ADR-M011-B / FR-016 walk-up helper — M019/S04):
#   1. resolve_manifest_path() from lib/manifest-helpers.sh (BASH_SOURCE walk-up)
#   2. $MANIFEST_PATH env set + file exists (fast path when env is propagated)
#   3. Exit 0 with empty stdout (no active milestone)
#
# F-07 relaxed format regex: accepts sha:none | sha:- | sha:<hex7+> plus `?`
# in the denominator when total-stories is unresolvable (F-08).
#
# Cadence-delta instrumentation (FR-005): appends to .claude/audit/hook.jsonl.
# Best-effort only (no lock, no flock); does NOT block the statusLine emit.
#
# Budget: typical ~5 ms on a 100-line manifest; hard cap ~20 ms (NFR-001).

set -uo pipefail

# --- Source lib/manifest-helpers.sh for resolve_manifest_path() (K-S04-001) ---
# Anchor on THIS script's own directory, not cwd (Stop-hook cwd is undocumented).
_STATUSLINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" \
  || _STATUSLINE_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=lib/manifest-helpers.sh
if [ -f "$_STATUSLINE_DIR/lib/manifest-helpers.sh" ]; then
  . "$_STATUSLINE_DIR/lib/manifest-helpers.sh"
fi

# --- Step 1/2: resolve MANIFEST ---
MANIFEST=""

# Primary: resolve_manifest_path() walk-up (available post-S04 merge into milestone branch)
if declare -f resolve_manifest_path >/dev/null 2>&1; then
  MANIFEST="$(resolve_manifest_path 2>/dev/null || true)"
fi

# Secondary: $MANIFEST_PATH env (fast path when propagated by orchestrator)
if [ -z "$MANIFEST" ] && [ -n "${MANIFEST_PATH:-}" ] && [ -f "${MANIFEST_PATH}" ]; then
  MANIFEST="$MANIFEST_PATH"
fi

# Step 3 — no active milestone → exit silent.
[ -n "$MANIFEST" ] || exit 0
[ -f "$MANIFEST" ] || exit 0

# --- parse fields (best-effort; never crash; all errors → safe defaults) ---

# Milestone id from directory name (M0NN-<slug>)
MS_DIR="$(dirname "$MANIFEST")"
MS_ID="$(basename "$MS_DIR" | awk -F- '{print $1}')"
[ -n "$MS_ID" ] || MS_ID="-"

# Metadata.phase and Metadata.last_updated (single awk pass — budget-conscious)
_meta="$(awk '
  /^## Metadata$/ { on=1; next }
  /^## /          { on=0 }
  on && /^phase:/        { phase=$0; gsub(/^phase:[[:space:]]*/,"",phase); gsub(/[[:space:]]/,"",phase) }
  on && /^last_updated:/ { lu=$0; sub(/^last_updated:[[:space:]]*/,"",lu); gsub(/[[:space:]]/,"",lu) }
  END { printf "%s\t%s\n", phase, lu }
' "$MANIFEST" 2>/dev/null || printf "\t")"
PHASE="$(printf '%s' "$_meta" | cut -f1)"
LAST_UPDATED="$(printf '%s' "$_meta" | cut -f2)"

PHASE="${PHASE:--}"
PHASE="$(printf '%s' "$PHASE" | tr -d '\r' | awk '{print $1}')"
[ -n "$PHASE" ] || PHASE="-"

# --- Story Records: FR-001 distinct story-id counter + FR-003 current-story ---
# RUN-MANIFEST Story Records format: story_id|status|started_at|commit_sha|verified|notes
# (pipe-delimited, no leading |; NOT a markdown table). f[1] = story_id.
# Header row "story_id|status|..." is skipped by checking f[1] ~ /^S[0-9]/.
# Retry rows: same story_id appearing multiple times → deduped into ids[].
# Single awk pass extracts both distinct count AND last story_id (FR-001 + FR-003).
_snn_current="$(awk '
  /^## Story Records$/ { on=1; next }
  /^## / && on          { on=0 }
  on && /\|/ {
    split($0, f, "|"); gsub(/[[:space:]]/, "", f[1])
    # Skip header row and markdown-table separator/header rows
    if (f[1] !~ /^S[0-9]/) next
    ids[f[1]]=1
    last=f[1]
  }
  END { n=0; for (k in ids) n++; printf "%d\t%s\n", n, last }
' "$MANIFEST" 2>/dev/null || printf "0\t")"
SNN="$(printf '%s' "$_snn_current" | cut -f1)"
CURRENT_STORY="$(printf '%s' "$_snn_current" | cut -f2)"
SNN="${SNN:-0}"

# Suppress arrow when phase is terminal (complete/aborted) — architect choice
# per architecture.md §"Case D": cosmetically odd to show S47→ on a complete
# milestone but spec allows it; we suppress for cleaner UX.
case "${PHASE:-}" in
  complete|aborted) CURRENT_STORY="" ;;
esac

# --- Total stories: FR-002 (file-count primary, PRD secondary, ? last resort) ---
# Resolution order LOCKED in PRD:
#   1. File-count primary: find <ms-dir>/stories/ -name 'S*.md'
#   2. PRD secondary: parse "## In Scope — N stories" header
#   3. Last-resort: "?" with no stderr (pure-reader hook)
TOTAL="?"

# Primary: filesystem count
STORIES_DIR="$MS_DIR/stories"
if [ -d "$STORIES_DIR" ]; then
  FC="$(find "$STORIES_DIR" -maxdepth 1 -type f -name 'S*.md' 2>/dev/null | wc -l | tr -d ' ')"
  case "$FC" in ''|0) ;; *) TOTAL="$FC" ;; esac
fi

# Secondary: PRD "## In Scope — N stories" (legacy fallback only)
if [ "$TOTAL" = "?" ]; then
  PRD="$MS_DIR/PRD.md"
  if [ -f "$PRD" ]; then
    T="$(awk 'match($0, /^## In Scope.*[-—][[:space:]]*([0-9]+)[[:space:]]*stor/, m) {print m[1]; exit}' "$PRD" 2>/dev/null || true)"
    if [ -z "$T" ]; then
      # Tertiary within PRD: count rows in Rollout table
      T="$(awk '
        /^## Rollout/ { in_roll=1; next }
        /^## / && in_roll { exit }
        in_roll && /^\|/ && $0 !~ /^\|[[:space:]]*-+[[:space:]]*\|/ && $0 !~ /^\|[[:space:]]*[Oo]rder[[:space:]]*\|/ { c++ }
        END { print c+0 }
      ' "$PRD" 2>/dev/null || echo 0)"
    fi
    case "$T" in
      ''|*[!0-9]*|0) TOTAL="?" ;;
      *) TOTAL="$T" ;;
    esac
  fi
fi
# Last-resort: TOTAL remains "?" (no stderr — pure-reader hook)

# --- Invoke stack depth ---
AGENTS="$(awk '
  /^## Invoke stack$/ { on=1; next }
  /^## / && on         { on=0 }
  on && /\|/ && $0 !~ /^\|[[:space:]]*-+[[:space:]]*\|/ && $0 !~ /^\|[[:space:]]*skill[[:space:]]*\|/ { c++ }
  END { print c+0 }
' "$MANIFEST" 2>/dev/null || echo 0)"

# Short SHA
SHA="$(git rev-parse --short HEAD 2>/dev/null || echo none)"
case "$SHA" in
  ''|*[!a-f0-9]*) SHA="none" ;;
esac

# --- MTIME-STALE label: FR-004 ---
# Emit "MTIME-STALE?<N>m" when phase=running AND now-last_updated > threshold.
# Threshold default: 300000 ms (5 min). Override via AIHAUS_STALL_THRESHOLD_MS env.
# Fail-safe: any parse error → suppress label silently (NFR-005).
MTIME_STALE_LABEL=""
if [ "${PHASE:-}" = "running" ] && [ -n "${LAST_UPDATED:-}" ]; then
  {
    _now_s="$(date +%s 2>/dev/null || echo 0)"
    # Convert ISO-8601 UTC timestamp to epoch seconds
    # Handles both GNU date (-d) and BSD date (-j -f) for cross-platform
    _lu_s="$(date -d "${LAST_UPDATED}" +%s 2>/dev/null \
      || date -j -f '%Y-%m-%dT%H:%M:%SZ' "${LAST_UPDATED}" +%s 2>/dev/null \
      || echo 0)"
    _threshold_ms="${AIHAUS_STALL_THRESHOLD_MS:-300000}"
    _threshold_s=$(( _threshold_ms / 1000 ))
    _delta_s=$(( _now_s - _lu_s ))
    if [ "$_now_s" -gt 0 ] && [ "$_lu_s" -gt 0 ] && [ "$_delta_s" -gt "$_threshold_s" ]; then
      _delta_m=$(( _delta_s / 60 ))
      MTIME_STALE_LABEL="MTIME-STALE?${_delta_m}m"
    fi
  } 2>/dev/null || true
fi

# --- Cadence-delta instrumentation: FR-005 ---
# Best-effort append to .claude/audit/hook.jsonl. Single state-file read + single
# append. No lock (pure-reader hook; cadence is informational for M020 tuning).
# Audit dir: walk up from MS_DIR parent to project root (3 levels: M0XX → milestones
# → .aihaus → project_root), then use <project_root>/.claude/audit.
# NFR-001: this block must not push past the 20ms hard cap — kept cheap.
{
  _ts_now="$(date -u +%FT%TZ 2>/dev/null || true)"
  _ts_now_ms="$(date +%s%3N 2>/dev/null || echo 0)"
  # Resolve <project_root>/.claude/audit from MANIFEST path:
  # MANIFEST is at <root>/.aihaus/milestones/M0XX/RUN-MANIFEST.md
  # So we need: dirname(dirname(dirname(dirname(MANIFEST)))) + "/.claude/audit"
  _ms_dir_abs="$(cd "$MS_DIR" 2>/dev/null && pwd)" || _ms_dir_abs="$MS_DIR"
  _milestones_dir="$(dirname "$_ms_dir_abs")"
  _aihaus_dir="$(dirname "$_milestones_dir")"
  _project_root="$(dirname "$_aihaus_dir")"
  _audit_dir="${_project_root}/.claude/audit"
  mkdir -p "$_audit_dir" 2>/dev/null || true
  _state_file="${_audit_dir}/.statusline-last-fire"
  _cadence_ms=0
  if [ -f "$_state_file" ]; then
    _prev_ms="$(cat "$_state_file" 2>/dev/null || echo 0)"
    if [ -n "$_prev_ms" ] && [ "$_prev_ms" -gt 0 ] 2>/dev/null; then
      _cadence_ms=$(( _ts_now_ms - _prev_ms ))
    fi
  fi
  # Write current timestamp for next fire
  printf '%s\n' "$_ts_now_ms" > "$_state_file" 2>/dev/null || true
  # Append cadence row to hook.jsonl
  _hook_jsonl="${_audit_dir}/hook.jsonl"
  printf '{"ts":"%s","hook":"statusline-milestone","cadence_delta_ms":%s,"last_updated":"%s","ms_id":"%s"}\n' \
    "${_ts_now}" "${_cadence_ms}" "${LAST_UPDATED:-}" "${MS_ID}" \
    >> "$_hook_jsonl" 2>/dev/null || true
} 2>/dev/null || true

# --- emit (single line, middle-dot separator per spec) ---
# Render order (architecture.md §"statusLine 4 sub-fields render-order spec"):
#   M<id> · S<n>/<total> [· S<current>→] [· MTIME-STALE?<N>m] · phase:X · agents:N · sha:<hash>
_out="M${MS_ID#M} · S${SNN}/${TOTAL}"
[ -n "${CURRENT_STORY:-}" ] && _out="${_out} · ${CURRENT_STORY}→"
[ -n "${MTIME_STALE_LABEL:-}" ] && _out="${_out} · ${MTIME_STALE_LABEL}"
_out="${_out} · phase:${PHASE} · agents:${AGENTS} · sha:${SHA}"
printf '%s\n' "$_out"
exit 0
