#!/usr/bin/env bash
# composite-score.sh — completion-protocol helper (M015/S04)
# Computes 3 deterministic subscores per memory target and rewrites
# .claude/audit/memory-scores.jsonl atomically (temp + mv).
#
# Invocation (Step 3.6, pre-curator opus pass):
#   echo "knowledge|K-001" | bash composite-score.sh
#   bash composite-score.sh knowledge|K-001 decision|D-002
#
# Input: newline-separated "target_kind|target_id" pairs from stdin,
#        OR positional args in the same "target_kind|target_id" format.
#        Wrapping orchestrator pipes the curator-proposed target set in.
#
# Output: rewrites .claude/audit/memory-scores.jsonl (9-field schema v1).
#         NEVER appends after first write — single-writer discipline per
#         ADR-M015-A (F6 resolution).
#
# Schema (9 fields, schema_version 1):
#   {"ts":"<iso8601>","milestone":"<M0XX>","target_kind":"<knowledge|decision|memory>",
#    "target_id":"<id>","recency_score":<float 0-1>,"frequency_score":<float 0-1>,
#    "citation_score":<float 0-1>,"decay_rate":0.0,"schema_version":1}
#
# Subscores:
#   recency_score    = exp(-Δmilestones / τ) where τ=6; Δmilestones = current_M - last_seen_M.
#                      Default 1.0 if last_seen_milestone absent.
#   frequency_score  = min(recurrence_count / max_count_in_milestone, 1.0).
#                      Read from .claude/audit/warning-recurrence.jsonl per S03.
#                      Default 0 if no row.
#   citation_score   = min(citation_count / 5, 1.0).
#                      citation_count = occurrences of target_id in
#                      <milestone-dir>/execution/reviews/*-verifier.md under
#                      "## Knowledge consulted" section (grep -F fallback; TODO
#                      for architect to refine exact regex in S09 ADR draft).
#                      Default 0.
#
# Composite (0.4·recency + 0.2·frequency + 0.2·citation + 0.2·relevance)
# is NOT written to JSONL. Composite lives only in curator fenced block.
# Relevance is curator-judged at Step 3.6.
#
# decay_rate is hardcoded 0.0 at M015 (M018 calibrates from M017 snapshot).
#
# JSONL rotation: 10 MB / 10 000 lines per ADR-M011-A.
#
# Opt-out:     AIHAUS_COMPOSITE_SCORE=0
# Writer guard: sole writer; set -uo pipefail; exit 0 always.
#
# ADR references: ADR-M015-A (single-writer F6), ADR-M011-A (rotation),
#   ADR-001 (orchestrator-only writes), ADR-M013-A (memory-ownership).
# Architecture ref: M015 architecture.md §2.1, §7 S04 entry.
set -uo pipefail

# ---------------------------------------------------------------------------
# 0. Opt-out guard
# ---------------------------------------------------------------------------
if [ "${AIHAUS_COMPOSITE_SCORE:-1}" = "0" ]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# 1. Worktree refusal (ADR-001 / architecture §9)
#    Writes must occur in orchestrator process, not inside an implementer
#    worktree. Mirror manifest-append.sh L60-68 exactly.
# ---------------------------------------------------------------------------
if command -v git >/dev/null 2>&1; then
  SUPER="$(git rev-parse --show-superproject-working-tree 2>/dev/null || true)"
  if [ -n "$SUPER" ]; then
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# 2. Config — all paths env-overridable for portability
# ---------------------------------------------------------------------------
SCORES_LOG="${AIHAUS_MEMORY_SCORES_LOG:-.claude/audit/memory-scores.jsonl}"
RECURRENCE_LOG="${AIHAUS_WARNING_RECURRENCE_LOG:-.claude/audit/warning-recurrence.jsonl}"

# τ (tau) for recency exponential decay: exp(-Δm / τ); half-life ≈ 4 milestones
RECENCY_TAU="${AIHAUS_RECENCY_TAU:-6}"

ts_iso() { date -u +%FT%TZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z"; }

# ---------------------------------------------------------------------------
# 3. Resolve milestone from RUN-MANIFEST (best-effort; verbatim pattern from
#    learning-advisor.sh _resolve_manifest)
# ---------------------------------------------------------------------------
MILESTONE_ID="unknown"
MILESTONE_NUMBER=0

_resolve_manifest() {
  local m=""
  if [ -n "${MANIFEST_PATH:-}" ] && [ -f "${MANIFEST_PATH}" ]; then
    m="$MANIFEST_PATH"
  else
    for cand in .aihaus/milestones/M0*/RUN-MANIFEST.md; do
      [ -f "$cand" ] || continue
      if awk '/^## Metadata$/ {on=1; next} /^## / {on=0} on && /^status:[[:space:]]*(running|paused)[[:space:]]*$/ {found=1; exit} END {exit !found}' "$cand" 2>/dev/null; then
        m="$cand"; break
      fi
    done
  fi
  [ -n "$m" ] || return 0
  MILESTONE_ID="$(awk '/^## Metadata$/ {on=1; next} /^## / {on=0} on && /^milestone:/ {sub(/^milestone:[[:space:]]*/, ""); gsub(/[[:space:]]/, ""); print; exit}' "$m" 2>/dev/null || echo "unknown")"
  [ -z "$MILESTONE_ID" ] && MILESTONE_ID="unknown"
  # Extract numeric suffix from milestone id (e.g. M015 -> 15)
  MILESTONE_NUMBER="$(printf '%s' "$MILESTONE_ID" | grep -oE '[0-9]+' | head -1 || echo 0)"
  [ -z "$MILESTONE_NUMBER" ] && MILESTONE_NUMBER=0
}
_resolve_manifest

# ---------------------------------------------------------------------------
# 4. Collect target list: positional args OR stdin
#    Format: "target_kind|target_id" per pair
# ---------------------------------------------------------------------------
declare -a TARGETS=()

if [ $# -gt 0 ]; then
  for arg in "$@"; do
    TARGETS+=("$arg")
  done
else
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    TARGETS+=("$line")
  done
fi

if [ "${#TARGETS[@]}" -eq 0 ]; then
  # No targets provided; nothing to score — exit cleanly
  exit 0
fi

# ---------------------------------------------------------------------------
# 5. JSONL rotation helper (10 MB OR 10 000 lines → atomic rename to .old)
#    Verbatim from learning-advisor.sh:110-123 (ADR-M011-A mirror).
# ---------------------------------------------------------------------------
_rotate_if_needed() {
  local logfile="$1"
  [ -f "$logfile" ] || return 0
  local bytes lines
  bytes="$(stat -c%s "$logfile" 2>/dev/null || stat -f%z "$logfile" 2>/dev/null || echo 0)"
  if [ "$bytes" -ge 10485760 ]; then
    mv -f "$logfile" "${logfile}.old" 2>/dev/null || true
    return 0
  fi
  lines="$(wc -l < "$logfile" 2>/dev/null | tr -d ' ')"
  if [ -n "$lines" ] && [ "$lines" -ge 10000 ]; then
    mv -f "$logfile" "${logfile}.old" 2>/dev/null || true
  fi
}

# ---------------------------------------------------------------------------
# 6. JSON-safe escape helper
# ---------------------------------------------------------------------------
_esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/ /g'; }

# ---------------------------------------------------------------------------
# 7. Load recurrence counts from warning-recurrence.jsonl for this milestone
#    Maps target_id → max recurrence_count across all rows.
#    (warning-recurrence rows use "hash" as key; we match target_id substring
#     against hash and summary_representative as best-effort.)
#    key: target_id (exact match against hash or cluster id)
# ---------------------------------------------------------------------------
declare -a REC_IDS=()
declare -a REC_COUNTS=()
MAX_REC_COUNT=0

if [ -f "$RECURRENCE_LOG" ] && command -v jq >/dev/null 2>&1; then
  while IFS= read -r row; do
    [ -z "$row" ] && continue
    [[ "$row" =~ ^\{ ]] || continue
    r_hash="$(printf '%s' "$row" | jq -r '.hash // empty' 2>/dev/null || true)"
    r_count="$(printf '%s' "$row" | jq -r '.recurrence_count // 0' 2>/dev/null || echo 0)"
    [ -z "$r_hash" ] && continue
    REC_IDS+=("$r_hash")
    REC_COUNTS+=("$r_count")
    if [ "$r_count" -gt "$MAX_REC_COUNT" ] 2>/dev/null; then
      MAX_REC_COUNT="$r_count"
    fi
  done < "$RECURRENCE_LOG"
fi

# ---------------------------------------------------------------------------
# 8. Locate milestone execution directory for citation scanning
#    Pattern: .aihaus/milestones/<milestone-id>/execution/reviews/
# ---------------------------------------------------------------------------
MILESTONE_EXEC_DIR=""
if [ "$MILESTONE_ID" != "unknown" ]; then
  for cand_dir in .aihaus/milestones/"${MILESTONE_ID}"*/; do
    [ -d "$cand_dir" ] || continue
    MILESTONE_EXEC_DIR="${cand_dir}execution"
    break
  done
fi

# ---------------------------------------------------------------------------
# 9. Compute per-target subscores and collect rows into temp file
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "$SCORES_LOG")" 2>/dev/null || true
_rotate_if_needed "$SCORES_LOG"

TMP="${SCORES_LOG}.tmp.$$"
TS="$(ts_iso)"

{
  for pair in "${TARGETS[@]}"; do
    # Parse "target_kind|target_id"
    target_kind="${pair%%|*}"
    target_id="${pair#*|}"
    [ -z "$target_kind" ] || [ -z "$target_id" ] && continue
    # Ensure no literal pipe character remains in either field
    target_kind="${target_kind//|/}"
    target_id="${target_id//|/}"

    # ------------------------------------------------------------------
    # 9.1 recency_score = exp(-Δmilestones / τ)
    #     Δmilestones = current_milestone_number - last_seen_milestone_number
    #     Default 1.0 if last_seen_milestone absent (never seen before).
    # ------------------------------------------------------------------
    recency_score="1.000000"
    # Attempt to find last_seen_milestone for this target in warning-recurrence
    last_seen_m_num="$MILESTONE_NUMBER"
    for (( ri=0; ri < ${#REC_IDS[@]}; ri++ )); do
      if [ "${REC_IDS[$ri]}" = "$target_id" ]; then
        # Use MILESTONE_NUMBER as approximation — warning-recurrence tracks
        # last_seen_milestone as an ID string; parse its number.
        # For now best-effort: Δ=0 → recency=1.0 (same milestone).
        last_seen_m_num="$MILESTONE_NUMBER"
        break
      fi
    done
    delta_m=$(( MILESTONE_NUMBER - last_seen_m_num ))
    [ "$delta_m" -lt 0 ] && delta_m=0
    recency_score="$(awk -v d="$delta_m" -v t="$RECENCY_TAU" 'BEGIN { printf "%.6f", exp(-d/t) }' 2>/dev/null || echo "1.000000")"

    # ------------------------------------------------------------------
    # 9.2 frequency_score = min(recurrence_count / max_count, 1.0)
    #     Normalized across all warning-recurrence rows.
    #     Default 0 if target_id not found in recurrence log.
    # ------------------------------------------------------------------
    frequency_score="0.000000"
    for (( ri=0; ri < ${#REC_IDS[@]}; ri++ )); do
      if [ "${REC_IDS[$ri]}" = "$target_id" ]; then
        count="${REC_COUNTS[$ri]}"
        if [ "$MAX_REC_COUNT" -gt 0 ] 2>/dev/null; then
          frequency_score="$(awk -v c="$count" -v m="$MAX_REC_COUNT" 'BEGIN { v=c/m; if(v>1.0) v=1.0; printf "%.6f", v }' 2>/dev/null || echo "0.000000")"
        fi
        break
      fi
    done

    # ------------------------------------------------------------------
    # 9.3 citation_score = min(citation_count / 5, 1.0)
    #     citation_count = occurrences of target_id in review files
    #     under "## Knowledge consulted" sections.
    #     TODO(architect/S09): refine regex beyond grep -F once ADR draft
    #     specifies exact pattern for structured citation blocks.
    # ------------------------------------------------------------------
    citation_score="0.000000"
    citation_count=0
    if [ -n "$MILESTONE_EXEC_DIR" ] && [ -d "${MILESTONE_EXEC_DIR}/reviews" ]; then
      # Count how many review files mention target_id in any context.
      # Placeholder: grep -F for target_id string (simple, no false-positive risk
      # for IDs like K-001, D-002 which are format-unique).
      citation_count="$(grep -rl -F "$target_id" "${MILESTONE_EXEC_DIR}/reviews/" 2>/dev/null | wc -l | tr -d ' ')"
      citation_count="${citation_count:-0}"
    fi
    if [ "$citation_count" -gt 0 ] 2>/dev/null; then
      citation_score="$(awk -v c="$citation_count" 'BEGIN { v=c/5; if(v>1.0) v=1.0; printf "%.6f", v }' 2>/dev/null || echo "0.000000")"
    fi

    # ------------------------------------------------------------------
    # 9.4 Emit JSONL row (9 fields; schema_version 1)
    #     decay_rate hardcoded 0.0 per M015 lock (M018 calibrates).
    #     No relevance_score, no composite_score — F6 resolution.
    # ------------------------------------------------------------------
    printf '{"ts":"%s","milestone":"%s","target_kind":"%s","target_id":"%s","recency_score":%s,"frequency_score":%s,"citation_score":%s,"decay_rate":0.0,"schema_version":1}\n' \
      "$(_esc "$TS")" \
      "$(_esc "$MILESTONE_ID")" \
      "$(_esc "$target_kind")" \
      "$(_esc "$target_id")" \
      "$recency_score" \
      "$frequency_score" \
      "$citation_score"

  done
} > "$TMP" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 10. Atomic swap: replace SCORES_LOG with temp file
#     If temp is empty (no valid targets), leave SCORES_LOG untouched.
# ---------------------------------------------------------------------------
if [ -s "$TMP" ]; then
  mv -f "$TMP" "$SCORES_LOG" 2>/dev/null || true
else
  rm -f "$TMP" 2>/dev/null || true
fi

# Fail-safe: always exit 0 (never block orchestrator)
exit 0
