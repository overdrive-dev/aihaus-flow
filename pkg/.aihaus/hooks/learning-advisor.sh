#!/usr/bin/env bash
# learning-advisor.sh — SubagentStop hook (M013/S06 Component B)
# Fires on every subagent return. Inspects the just-completed agent's task
# + output for patterns worth capturing, then appends per-warning rows to
# .claude/audit/LEARNING-WARNINGS.jsonl.
#
# Pattern mirrors autonomy-guard.sh (ADR-M011-A):
#   - 3s haiku timeout (fail-safe allow on every error path)
#   - 5-min hash cache (key = hash(task_prompt + output_head_256_bytes))
#   - 30s global rate window (prevents retry-storm duplicates)
#   - Append-only JSONL discipline (rotation is the only deletion surface)
#   - Atomic rotation at 10 MB OR 10 000 lines → .old (overwrites prior .old)
#
# Opt-out:       AIHAUS_LEARNING_ADVISOR=0
# Recursion guard: AIHAUS_HAIKU_ADVISOR_ACTIVE=1 (set before haiku call)
# Audit trail:   .claude/audit/learning-advisor-audit.jsonl (per-fire record)
#
# ADR references: ADR-M011-A (haiku probe + JSONL pattern), ADR-001 (writes
#   from orchestrator process only), ADR-M013-A (memory-ownership).
# Architecture ref: M013 architecture.md §2.2, §4.1, §9.
set -uo pipefail

# ---------------------------------------------------------------------------
# 0. Recursion guard
# ---------------------------------------------------------------------------
if [ "${AIHAUS_HAIKU_ADVISOR_ACTIVE:-0}" = "1" ]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# 1. Opt-out guard
# ---------------------------------------------------------------------------
if [ "${AIHAUS_LEARNING_ADVISOR:-1}" = "0" ]; then
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
AUDIT_LOG="${AIHAUS_LEARNING_ADVISOR_AUDIT_LOG:-.claude/audit/learning-advisor-audit.jsonl}"
ADVISOR_CACHE="${AIHAUS_LEARNING_ADVISOR_CACHE:-.claude/audit/learning-advisor.cache}"

ts_iso() { date -u +%FT%TZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z"; }

# ---------------------------------------------------------------------------
# 4. Read SubagentStop payload from stdin
# ---------------------------------------------------------------------------
INPUT="$(cat)"

AGENT_NAME=""
TASK_DESCRIPTION=""
TASK_OUTPUT=""
if command -v jq >/dev/null 2>&1; then
  AGENT_NAME="$(printf '%s' "$INPUT" | jq -r '.agent_name // .subagent_name // .name // empty' 2>/dev/null || true)"
  TASK_DESCRIPTION="$(printf '%s' "$INPUT" | jq -r '.task_description // .task // .prompt // empty' 2>/dev/null || true)"
  TASK_OUTPUT="$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // .output // .result // empty' 2>/dev/null || true)"
fi
# Fallback: use raw input
[ -z "$AGENT_NAME" ]       && AGENT_NAME="unknown"
[ -z "$TASK_DESCRIPTION" ] && TASK_DESCRIPTION="$(printf '%s' "$INPUT" | head -c 512)"
[ -z "$TASK_OUTPUT" ]      && TASK_OUTPUT="$(printf '%s' "$INPUT" | head -c 512)"

# Truncate for cache key and haiku input
TASK_DESC_HEAD="$(printf '%s' "$TASK_DESCRIPTION" | head -c 256)"
TASK_OUT_HEAD="$(printf '%s' "$TASK_OUTPUT" | head -c 256)"

# ---------------------------------------------------------------------------
# 5. Resolve milestone + story from RUN-MANIFEST (best-effort)
# ---------------------------------------------------------------------------
MILESTONE_ID="unknown"
STORY_ID="unknown"

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
  STORY_ID="$(awk '/^## Metadata$/ {on=1; next} /^## / {on=0} on && /^current_story:/ {sub(/^current_story:[[:space:]]*/, ""); gsub(/[[:space:]]/, ""); print; exit}' "$m" 2>/dev/null || echo "unknown")"
  [ -z "$MILESTONE_ID" ] && MILESTONE_ID="unknown"
  [ -z "$STORY_ID" ]     && STORY_ID="unknown"
}
_resolve_manifest

# ---------------------------------------------------------------------------
# 6. JSONL rotation helper (10 MB OR 10 000 lines → atomic rename to .old)
#    Mirrors autonomy-guard.sh rotate_gate_log_if_needed verbatim.
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
# 7. Audit write helper (per-fire record — separate from LEARNING-WARNINGS)
# ---------------------------------------------------------------------------
_write_audit() {
  local decision="$1" duration_ms="${2:-0}" warning_count="${3:-0}" reason="${4:-}"
  mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || return 0
  _rotate_if_needed "$AUDIT_LOG"
  local ts; ts="$(ts_iso)"
  local reason_safe=""
  [ -n "$reason" ] && reason_safe="$(printf '%s' "$reason" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  printf '{"ts":"%s","decision":"%s","source_agent":"%s","milestone":"%s","story":"%s","haiku_duration_ms":%s,"warnings_emitted":%s,"reason":"%s"}\n' \
    "$ts" "$decision" "$AGENT_NAME" "$MILESTONE_ID" "$STORY_ID" \
    "$duration_ms" "$warning_count" "$reason_safe" \
    >> "$AUDIT_LOG" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# 8. Cache helpers (5-min hash cache + 30s rate-limit window)
#    Mirrors autonomy-guard.sh append_cache_entry + lookup logic.
# ---------------------------------------------------------------------------
compute_hash() {
  local combined="${TASK_DESC_HEAD}${TASK_OUT_HEAD}"
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$combined" | sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s' "$combined" | shasum -a 256 | awk '{print $1}'
  else
    printf '%s' "$combined" | md5sum 2>/dev/null | awk '{print $1}' || printf 'nohash'
  fi
}

append_cache_entry() {
  local entry="$1"
  mkdir -p "$(dirname "$ADVISOR_CACHE")" 2>/dev/null || return 0
  local now; now="$(date +%s 2>/dev/null || echo 0)"
  if [ -f "$ADVISOR_CACHE" ]; then
    local tmp="${ADVISOR_CACHE}.tmp.$$"
    awk -F'|' -v now="$now" 'NF>=1 && (now - ($1+0)) <= 300 {print}' "$ADVISOR_CACHE" > "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$ADVISOR_CACHE" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  fi
  printf '%s\n' "$entry" >> "$ADVISOR_CACHE" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# 9. Cache lookup + rate-limit check
# ---------------------------------------------------------------------------
ADVISOR_MSG_HASH="$(compute_hash)"
now_unix="$(date +%s 2>/dev/null || echo 0)"
mkdir -p "$(dirname "$ADVISOR_CACHE")" 2>/dev/null || true

if [ -f "$ADVISOR_CACHE" ]; then
  # Cache hit: same hash within 5 min → skip (previously inspected identical payload)
  while IFS='|' read -r c_ts c_hash; do
    [ -z "$c_ts" ] && continue
    age=$((now_unix - c_ts))
    if [ "$age" -le 300 ] && [ "$c_hash" = "$ADVISOR_MSG_HASH" ]; then
      _write_audit "cache-hit-skip" "0" "0" "identical-payload-within-5min"
      exit 0
    fi
  done < "$ADVISOR_CACHE"
  # Rate limit: if any cache entry within 30 s → skip haiku call
  newest_ts="$(awk -F'|' 'NF>=1 {if ($1+0 > max) max=$1+0} END {print max+0}' "$ADVISOR_CACHE" 2>/dev/null || echo 0)"
  if [ "$newest_ts" -gt 0 ] && [ $((now_unix - newest_ts)) -lt 30 ]; then
    _write_audit "rate-limited" "0" "0" "rate-window-30s"
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# 10. CLI availability check (fail-safe: no warnings on missing claude)
# ---------------------------------------------------------------------------
if ! command -v claude >/dev/null 2>&1; then
  _write_audit "no-cli-skip" "0" "0" "claude-cli-not-found"
  exit 0
fi

# ---------------------------------------------------------------------------
# 11. Build haiku prompt
# ---------------------------------------------------------------------------
TASK_DESC_TRUNC="$(printf '%s' "$TASK_DESCRIPTION" | head -c 1024)"
TASK_OUT_TRUNC="$(printf '%s' "$TASK_OUTPUT" | head -c 1024)"

PROMPT_BODY="$(cat <<EOF
SYSTEM: You are the learning-advisor for the aihaus milestone system.
Inspect the just-completed subagent task and output for patterns worth capturing.
Be conservative: only flag genuine gotchas, near-misses, or missed decisions.
Prefer zero warnings over noisy low-confidence output.

USER:
## Subagent that just completed
agent_name: ${AGENT_NAME}
milestone: ${MILESTONE_ID}
story: ${STORY_ID}

## Task description (truncated to 1024 chars)
${TASK_DESC_TRUNC}

## Task output / return (truncated to 1024 chars)
${TASK_OUT_TRUNC}

## Instructions
Emit 0 to 5 JSON objects, one per line. Each object:
{"kind":"<kind>","category":"<category>","summary":"<1-sentence max 120 chars>","evidence":"<excerpt max 200 chars or empty>","suggested_entry":"<optional prose max 300 chars or empty>"}

kind enum: decision-missed | knowledge-missed | gotcha | pattern-worth-capture | shell-quirk | tool-gotcha
category enum (must match): shell-quirk | tool-gotcha | pattern-worth-capture | decision-missed | knowledge-missed | gotcha-missed

Emit ONLY valid JSON lines. No prose. No headers. No code blocks.
Empty response (zero warnings) is correct when nothing qualifies.
EOF
)"

# ---------------------------------------------------------------------------
# 12. Invoke haiku with 3s timeout (fail-safe allow on any error)
# ---------------------------------------------------------------------------
export AIHAUS_HAIKU_ADVISOR_ACTIVE=1

HAIKU_START_MS="$(date +%s%3N 2>/dev/null || echo 0)"
HAIKU_OUT=""
HAIKU_RC=0

if command -v timeout >/dev/null 2>&1; then
  HAIKU_OUT="$(printf '%s' "$PROMPT_BODY" | timeout 3s claude --print --model haiku-4.5 2>/dev/null)" || HAIKU_RC=$?
else
  HAIKU_OUT="$(printf '%s' "$PROMPT_BODY" | claude --print --model haiku-4.5 2>/dev/null)" || HAIKU_RC=$?
fi

HAIKU_END_MS="$(date +%s%3N 2>/dev/null || echo 0)"
HAIKU_DURATION_MS=$((HAIKU_END_MS - HAIKU_START_MS))
[ "$HAIKU_DURATION_MS" -lt 0 ] && HAIKU_DURATION_MS=0

# Timeout (RC 124) or error → fail-safe allow, no warnings
if [ "$HAIKU_RC" = "124" ]; then
  append_cache_entry "${now_unix}|${ADVISOR_MSG_HASH}"
  _write_audit "timeout-skip" "$HAIKU_DURATION_MS" "0" "haiku-3s-timeout"
  exit 0
fi

if [ -z "$HAIKU_OUT" ]; then
  append_cache_entry "${now_unix}|${ADVISOR_MSG_HASH}"
  _write_audit "empty-output-skip" "$HAIKU_DURATION_MS" "0" "haiku-empty-response"
  exit 0
fi

# ---------------------------------------------------------------------------
# 13. UUID generation helper (v4 random)
# ---------------------------------------------------------------------------
gen_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c "import uuid; print(uuid.uuid4())"
  elif command -v python >/dev/null 2>&1; then
    python -c "import uuid; print(uuid.uuid4())"
  else
    # Fallback: construct a pseudo-UUID from /dev/urandom or date
    local r1 r2 r3 r4 r5
    r1="$(dd if=/dev/urandom bs=4 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n' | head -c 8 || printf '%08x' "$(date +%s)")"
    r2="$(dd if=/dev/urandom bs=2 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n' | head -c 4 || printf '%04x' "$$")"
    r3="$(printf '4%03x' "$(( RANDOM % 4096 ))")"
    r4="$(printf '%04x' "$(( (RANDOM % 16384) + 32768 ))")"
    r5="$(dd if=/dev/urandom bs=6 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n' | head -c 12 || printf '%012x' "$(date +%N 2>/dev/null || echo 0)")"
    printf '%s-%s-%s-%s-%s' "$r1" "$r2" "$r3" "$r4" "$r5"
  fi
}

# ---------------------------------------------------------------------------
# 14. Parse haiku output and append JSONL rows
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "$WARNINGS_LOG")" 2>/dev/null || true

WARNING_COUNT=0
PARSE_ERRORS=0
TS="$(ts_iso)"

while IFS= read -r line; do
  # Skip blank lines
  [ -z "$line" ] && continue
  # Skip lines that aren't JSON objects (start with '{')
  [[ "$line" =~ ^\{ ]] || continue
  # Cap at 5 warnings per invocation
  [ "$WARNING_COUNT" -ge 5 ] && break

  # Validate we can parse the line (needs jq for full validation; else best-effort)
  if command -v jq >/dev/null 2>&1; then
    if ! printf '%s' "$line" | jq -e . >/dev/null 2>&1; then
      PARSE_ERRORS=$((PARSE_ERRORS + 1))
      # Log corrupt-row to audit
      _write_audit "corrupt-row-skip" "$HAIKU_DURATION_MS" "0" "haiku-output-invalid-json"
      continue
    fi
    KIND="$(printf '%s' "$line" | jq -r '.kind // empty' 2>/dev/null || true)"
    CATEGORY="$(printf '%s' "$line" | jq -r '.category // empty' 2>/dev/null || true)"
    SUMMARY="$(printf '%s' "$line" | jq -r '.summary // empty' 2>/dev/null || true)"
    EVIDENCE="$(printf '%s' "$line" | jq -r '.evidence // empty' 2>/dev/null || true)"
    SUGGESTED="$(printf '%s' "$line" | jq -r '.suggested_entry // empty' 2>/dev/null || true)"
  else
    # No jq: try grep-based extraction
    KIND="$(printf '%s' "$line" | grep -oE '"kind"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
    CATEGORY="$(printf '%s' "$line" | grep -oE '"category"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
    SUMMARY="$(printf '%s' "$line" | grep -oE '"summary"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
    EVIDENCE=""
    SUGGESTED=""
  fi

  # Require at minimum kind + summary
  [ -z "$KIND" ] || [ -z "$SUMMARY" ] && continue

  # Stamp warning_uuid (v4)
  WARNING_UUID="$(gen_uuid)"

  # JSON-safe escaping helper
  _esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/ /g'; }

  # Emit JSONL row
  _rotate_if_needed "$WARNINGS_LOG"
  printf '{"warning_uuid":"%s","timestamp":"%s","milestone":"%s","story":"%s","source_agent":"%s","category":"%s","summary":"%s","evidence":"%s","suggested_entry":"%s"}\n' \
    "$WARNING_UUID" "$TS" \
    "$(_esc "$MILESTONE_ID")" "$(_esc "$STORY_ID")" "$(_esc "$AGENT_NAME")" \
    "$(_esc "${CATEGORY:-$KIND}")" "$(_esc "$SUMMARY")" \
    "$(_esc "$EVIDENCE")" "$(_esc "$SUGGESTED")" \
    >> "$WARNINGS_LOG" 2>/dev/null || true

  WARNING_COUNT=$((WARNING_COUNT + 1))
done <<< "$HAIKU_OUT"

# ---------------------------------------------------------------------------
# 15. Record cache entry + write audit
# ---------------------------------------------------------------------------
append_cache_entry "${now_unix}|${ADVISOR_MSG_HASH}"

if [ "$WARNING_COUNT" -gt 0 ]; then
  _write_audit "warnings-emitted" "$HAIKU_DURATION_MS" "$WARNING_COUNT"
else
  _write_audit "no-warnings" "$HAIKU_DURATION_MS" "0"
fi

# Fail-safe: always exit 0 (never block the returning agent)
exit 0
