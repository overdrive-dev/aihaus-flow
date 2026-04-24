#!/usr/bin/env bash
# warning-recurrence.sh — SubagentStop hook (M016/S03)
# Fires on every SubagentStop; file-timestamp guard fires aggregation only once
# per milestone close. Reads LEARNING-WARNINGS.jsonl rows for the current
# milestone and rewrites warning-recurrence.jsonl (one row per distinct cluster).
#
# S00 verdict: noise_floor=100% → Jaccard-similarity primary grouping strategy.
# Hash composition (sha256 of category|summary|source_agent[:16]) is the M016
# real-data recheck fallback per ADR-M016-A Follow-up.
#
# Jaccard clustering: tokenize `summary` field into 5-char n-grams;
# compare against each cluster representative; threshold 0.8 = same cluster.
# Cluster-id: jaccard_cluster_<first_warning_uuid[:8]> (deterministic).
#
# Row schema (warning-recurrence.jsonl, schema_version 1):
#   hash, category, source_agent, recurrence_count, first_seen_milestone,
#   last_seen_milestone, warning_uuids (list), schema_version
#
# Single-writer: this hook is the SOLE writer of .claude/audit/warning-recurrence.jsonl
# (ADR-M016-A writer-table row). Mirrors ADR-M011-A rotation discipline.
#
# Opt-out:        AIHAUS_WARNING_RECURRENCE=0
# Recursion guard: AIHAUS_WARNING_RECURRENCE_ACTIVE=1
# Writer:         .claude/audit/warning-recurrence.jsonl
#
# ADR references: ADR-M016-A (data-plane single-writer), ADR-M011-A (JSONL
#   rotation), ADR-001 (orchestrator-only writes), ADR-M013-A (memory-ownership).
set -uo pipefail

# ---------------------------------------------------------------------------
# 0. Recursion guard
# ---------------------------------------------------------------------------
if [ "${AIHAUS_WARNING_RECURRENCE_ACTIVE:-0}" = "1" ]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# 1. Opt-out guard
# ---------------------------------------------------------------------------
if [ "${AIHAUS_WARNING_RECURRENCE:-1}" = "0" ]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# 2. Worktree refusal (ADR-001 / architecture §9)
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
# 3. Config
# ---------------------------------------------------------------------------
WARNINGS_LOG="${AIHAUS_LEARNING_WARNINGS_LOG:-.claude/audit/LEARNING-WARNINGS.jsonl}"
RECURRENCE_LOG="${AIHAUS_WARNING_RECURRENCE_LOG:-.claude/audit/warning-recurrence.jsonl}"

ts_iso() { date -u +%FT%TZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z"; }

# ---------------------------------------------------------------------------
# 4. Resolve milestone from RUN-MANIFEST (best-effort; verbatim from
#    learning-advisor.sh _resolve_manifest)
# ---------------------------------------------------------------------------
MILESTONE_ID="unknown"

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
}
_resolve_manifest

# ---------------------------------------------------------------------------
# 5. Consume stdin (SubagentStop payload — not used by this hook, but must
#    drain stdin to avoid broken-pipe signals to the caller)
# ---------------------------------------------------------------------------
cat >/dev/null

# ---------------------------------------------------------------------------
# 6. JSONL rotation helper (10 MB OR 10 000 lines → atomic rename to .old)
#    Verbatim from learning-advisor.sh:110-123.
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
# 7. S00 verdict branch — Jaccard (primary) vs sha256 (M016 fallback)
# ---------------------------------------------------------------------------
HASH_MODE="sha256"
if [ -f "tools/.out/s00-verdict.md" ] && grep -q "verdict: fuzzy-match-fallback" "tools/.out/s00-verdict.md" 2>/dev/null; then
  HASH_MODE="jaccard"
fi

# ---------------------------------------------------------------------------
# 8. Once-per-milestone guard
#    Prevents re-firing on every SubagentStop inside the same milestone.
# ---------------------------------------------------------------------------
MILESTONE_GUARD=".claude/audit/.warning-recurrence-${MILESTONE_ID}.done"
if [ -f "$MILESTONE_GUARD" ]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# 9. Early-exit if LEARNING-WARNINGS.jsonl absent or no rows for milestone
# ---------------------------------------------------------------------------
if [ ! -f "$WARNINGS_LOG" ]; then
  exit 0
fi

# Check if any rows exist for this milestone (best-effort grep; fail-safe)
if ! grep -q "\"milestone\":\"${MILESTONE_ID}\"" "$WARNINGS_LOG" 2>/dev/null; then
  # No rows for this milestone; still touch the guard so we don't re-run
  touch "$MILESTONE_GUARD" 2>/dev/null || true
  exit 0
fi

# ---------------------------------------------------------------------------
# 10. Jaccard 5-gram tokenization helpers (pure bash; no jq dependency)
#
#     _ngrams <string> <n>: prints one 5-char n-gram per line
#     _jaccard <summary_a> <summary_b>: prints decimal similarity (0.00-1.00)
#       using 5-char n-grams of each summary.
# ---------------------------------------------------------------------------

# Generate n-grams from a string. Each n-gram is a 5-char substring.
# Whitespace is preserved (not stripped) — spec says "whitespace-preserving".
_ngrams() {
  local s="$1"
  local n="${2:-5}"
  local len="${#s}"
  local i end gram
  for (( i=0; i <= len - n; i++ )); do
    gram="${s:$i:$n}"
    printf '%s\n' "$gram"
  done
}

# Jaccard similarity: |intersection| / |union| of two n-gram multisets.
# Uses sorted unique n-grams (set semantics per spec — threshold 0.8).
_jaccard() {
  local sa="$1"
  local sb="$2"
  local n=5

  local la="${#sa}"
  local lb="${#sb}"

  # Edge case: if either string is shorter than n, treat as dissimilar
  if [ "$la" -lt "$n" ] || [ "$lb" -lt "$n" ]; then
    echo "0.00"
    return 0
  fi

  # Collect n-grams for each summary into temp files (avoid subshell pitfalls)
  local tmp_a tmp_b tmp_i tmp_u
  tmp_a="$(mktemp 2>/dev/null || echo "/tmp/wrngjcc_a_$$")"
  tmp_b="$(mktemp 2>/dev/null || echo "/tmp/wrngjcc_b_$$")"
  tmp_i="$(mktemp 2>/dev/null || echo "/tmp/wrngjcc_i_$$")"
  tmp_u="$(mktemp 2>/dev/null || echo "/tmp/wrngjcc_u_$$")"

  _ngrams "$sa" "$n" | sort -u > "$tmp_a"
  _ngrams "$sb" "$n" | sort -u > "$tmp_b"

  comm -12 "$tmp_a" "$tmp_b" > "$tmp_i" 2>/dev/null
  comm -23 <(sort -u "$tmp_a") <(sort -u "$tmp_b") >> "$tmp_u" 2>/dev/null || true
  comm -13 <(sort -u "$tmp_a") <(sort -u "$tmp_b") >> "$tmp_u" 2>/dev/null || true
  cat "$tmp_i" >> "$tmp_u" 2>/dev/null || true
  sort -u "$tmp_u" -o "$tmp_u" 2>/dev/null || true

  local isect union_count sim_int
  isect="$(wc -l < "$tmp_i" 2>/dev/null | tr -d ' ')"
  union_count="$(wc -l < "$tmp_u" 2>/dev/null | tr -d ' ')"

  rm -f "$tmp_a" "$tmp_b" "$tmp_i" "$tmp_u" 2>/dev/null

  isect="${isect:-0}"
  union_count="${union_count:-0}"

  if [ "$union_count" -eq 0 ]; then
    echo "0.00"
    return 0
  fi

  # Integer arithmetic: multiply by 100, divide, express as 0.XX
  sim_int=$(( isect * 100 / union_count ))
  printf '%d.%02d\n' "$(( sim_int / 100 ))" "$(( sim_int % 100 ))"
}

# Returns 0 if jaccard >= 0.80, 1 otherwise
_jaccard_match() {
  local sim="$1"
  # Compare as integer: strip dot, compare >= 80
  local sim_int
  sim_int="$(printf '%s' "$sim" | sed 's/\.//')"
  # Handle cases like "1.00" → "100", "0.85" → "085"
  # Remove leading zeros for arithmetic, but handle "00" case
  sim_int="$(printf '%s' "$sim_int" | sed 's/^0*//')"
  [ -z "$sim_int" ] && sim_int=0
  [ "$sim_int" -ge 80 ] 2>/dev/null
}

# ---------------------------------------------------------------------------
# 11. sha256 recurrence-hash computation (fallback / M016 recheck path)
# ---------------------------------------------------------------------------
_compute_sha256_hash() {
  local combined="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$combined" | sha256sum | awk '{print $1}' | head -c 16
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s' "$combined" | shasum -a 256 | awk '{print $1}' | head -c 16
  else
    printf '%s' "$combined" | md5sum 2>/dev/null | awk '{print $1}' | head -c 16 || printf 'nohash000000000'
  fi
}

# ---------------------------------------------------------------------------
# 12. JSON-safe escape helper
# ---------------------------------------------------------------------------
_esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/ /g'; }

# ---------------------------------------------------------------------------
# 13. Read LEARNING-WARNINGS.jsonl for this milestone into parallel arrays
#     (bash associative arrays require bash 4+; use indexed arrays + lookup)
# ---------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  # Without jq we cannot safely parse JSONL — fail-safe exit
  touch "$MILESTONE_GUARD" 2>/dev/null || true
  exit 0
fi

# Arrays: each index is one row from LEARNING-WARNINGS for this milestone
declare -a ROW_UUIDS=()
declare -a ROW_CATEGORIES=()
declare -a ROW_SUMMARIES=()
declare -a ROW_AGENTS=()
declare -a ROW_REC_HASHES=()

while IFS= read -r row; do
  [ -z "$row" ] && continue
  [[ "$row" =~ ^\{ ]] || continue
  local_uuid="$(printf '%s' "$row" | jq -r '.warning_uuid // empty' 2>/dev/null || true)"
  local_cat="$(printf '%s' "$row" | jq -r '.category // empty' 2>/dev/null || true)"
  local_sum="$(printf '%s' "$row" | jq -r '.summary // empty' 2>/dev/null || true)"
  local_agent="$(printf '%s' "$row" | jq -r '.source_agent // empty' 2>/dev/null || true)"
  local_hash="$(printf '%s' "$row" | jq -r '.recurrence_hash // empty' 2>/dev/null || true)"
  [ -z "$local_uuid" ] && continue
  ROW_UUIDS+=("$local_uuid")
  ROW_CATEGORIES+=("$local_cat")
  ROW_SUMMARIES+=("$local_sum")
  ROW_AGENTS+=("$local_agent")
  ROW_REC_HASHES+=("$local_hash")
done < <(grep "\"milestone\":\"${MILESTONE_ID}\"" "$WARNINGS_LOG" 2>/dev/null || true)

TOTAL_NEW="${#ROW_UUIDS[@]}"
if [ "$TOTAL_NEW" -eq 0 ]; then
  touch "$MILESTONE_GUARD" 2>/dev/null || true
  exit 0
fi

# ---------------------------------------------------------------------------
# 14. Read existing warning-recurrence.jsonl into cluster arrays
#     cluster_ids[] : the hash/cluster-id string
#     cluster_cats[]: category
#     cluster_agents[]: source_agent
#     cluster_reps[]: representative summary (for Jaccard)
#     cluster_counts[]: recurrence_count (int)
#     cluster_first[]: first_seen_milestone
#     cluster_last[]: last_seen_milestone
#     cluster_uuids[]: JSON array string of warning_uuids
# ---------------------------------------------------------------------------
declare -a cluster_ids=()
declare -a cluster_cats=()
declare -a cluster_agents=()
declare -a cluster_reps=()
declare -a cluster_counts=()
declare -a cluster_first=()
declare -a cluster_last=()
declare -a cluster_uuids=()

if [ -f "$RECURRENCE_LOG" ]; then
  while IFS= read -r row; do
    [ -z "$row" ] && continue
    [[ "$row" =~ ^\{ ]] || continue
    c_id="$(printf '%s' "$row" | jq -r '.hash // empty' 2>/dev/null || true)"
    c_cat="$(printf '%s' "$row" | jq -r '.category // empty' 2>/dev/null || true)"
    c_agent="$(printf '%s' "$row" | jq -r '.source_agent // empty' 2>/dev/null || true)"
    c_sum="$(printf '%s' "$row" | jq -r '.summary_representative // empty' 2>/dev/null || true)"
    c_count="$(printf '%s' "$row" | jq -r '.recurrence_count // 0' 2>/dev/null || echo 0)"
    c_first="$(printf '%s' "$row" | jq -r '.first_seen_milestone // empty' 2>/dev/null || true)"
    c_last="$(printf '%s' "$row" | jq -r '.last_seen_milestone // empty' 2>/dev/null || true)"
    c_uuids="$(printf '%s' "$row" | jq -c '.warning_uuids // []' 2>/dev/null || echo '[]')"
    [ -z "$c_id" ] && continue
    cluster_ids+=("$c_id")
    cluster_cats+=("$c_cat")
    cluster_agents+=("$c_agent")
    cluster_reps+=("$c_sum")
    cluster_counts+=("$c_count")
    cluster_first+=("$c_first")
    cluster_last+=("$c_last")
    cluster_uuids+=("$c_uuids")
  done < "$RECURRENCE_LOG"
fi

# ---------------------------------------------------------------------------
# 15. Assign each new row to a cluster (Jaccard primary / sha256 fallback)
# ---------------------------------------------------------------------------
for (( i=0; i < TOTAL_NEW; i++ )); do
  new_uuid="${ROW_UUIDS[$i]}"
  new_cat="${ROW_CATEGORIES[$i]}"
  new_sum="${ROW_SUMMARIES[$i]}"
  new_agent="${ROW_AGENTS[$i]}"
  new_rhash="${ROW_REC_HASHES[$i]}"

  matched_idx=-1

  if [ "$HASH_MODE" = "jaccard" ]; then
    # --- Jaccard path: compare against each cluster representative ---
    for (( j=0; j < ${#cluster_ids[@]}; j++ )); do
      rep_sum="${cluster_reps[$j]}"
      [ -z "$rep_sum" ] && continue
      sim="$(_jaccard "$new_sum" "$rep_sum")"
      if _jaccard_match "$sim"; then
        matched_idx="$j"
        break
      fi
    done
  else
    # --- sha256 path (M016 fallback): exact hash match ---
    for (( j=0; j < ${#cluster_ids[@]}; j++ )); do
      if [ "${cluster_ids[$j]}" = "$new_rhash" ]; then
        matched_idx="$j"
        break
      fi
    done
  fi

  if [ "$matched_idx" -ge 0 ]; then
    # Merge into existing cluster
    old_count="${cluster_counts[$matched_idx]}"
    cluster_counts[$matched_idx]=$(( old_count + 1 ))
    cluster_last[$matched_idx]="$MILESTONE_ID"
    # Append uuid to the JSON array
    old_arr="${cluster_uuids[$matched_idx]}"
    new_arr="$(printf '%s' "$old_arr" | jq -c ". + [\"${new_uuid}\"]" 2>/dev/null || echo "$old_arr")"
    cluster_uuids[$matched_idx]="$new_arr"
  else
    # Create new cluster
    if [ "$HASH_MODE" = "jaccard" ]; then
      new_cluster_id="jaccard_cluster_${new_uuid:0:8}"
    else
      new_cluster_id="$new_rhash"
    fi
    cluster_ids+=("$new_cluster_id")
    cluster_cats+=("$new_cat")
    cluster_agents+=("$new_agent")
    cluster_reps+=("$new_sum")
    cluster_counts+=(1)
    cluster_first+=("$MILESTONE_ID")
    cluster_last+=("$MILESTONE_ID")
    cluster_uuids+=("[\"${new_uuid}\"]")
  fi
done

# ---------------------------------------------------------------------------
# 16. Write aggregate rows to warning-recurrence.jsonl (in-place rewrite)
#     NOT append-per-warning. One row per cluster.
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "$RECURRENCE_LOG")" 2>/dev/null || true
_rotate_if_needed "$RECURRENCE_LOG"

TMP="${RECURRENCE_LOG}.tmp.$$"
{
  for (( k=0; k < ${#cluster_ids[@]}; k++ )); do
    printf '{"hash":"%s","category":"%s","source_agent":"%s","summary_representative":"%s","recurrence_count":%d,"first_seen_milestone":"%s","last_seen_milestone":"%s","warning_uuids":%s,"schema_version":1}\n' \
      "$(_esc "${cluster_ids[$k]}")" \
      "$(_esc "${cluster_cats[$k]}")" \
      "$(_esc "${cluster_agents[$k]}")" \
      "$(_esc "${cluster_reps[$k]}")" \
      "${cluster_counts[$k]}" \
      "$(_esc "${cluster_first[$k]}")" \
      "$(_esc "${cluster_last[$k]}")" \
      "${cluster_uuids[$k]}"
  done
} > "$TMP" 2>/dev/null || true

if [ -s "$TMP" ]; then
  mv -f "$TMP" "$RECURRENCE_LOG" 2>/dev/null || true
else
  rm -f "$TMP" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 17. Touch milestone guard (prevent re-run on subsequent SubagentStops)
# ---------------------------------------------------------------------------
touch "$MILESTONE_GUARD" 2>/dev/null || true

# Fail-safe: always exit 0 (hooks never block agents)
exit 0
