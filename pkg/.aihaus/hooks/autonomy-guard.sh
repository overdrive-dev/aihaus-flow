#!/usr/bin/env bash
# autonomy-guard.sh — detect + block autonomy-protocol violations in the
# final assistant turn. Wired to the Stop event in settings.local.json.
#
# Exit 0 with no output = no violation (or no execution-phase context).
# Exit 0 with block JSON = forbidden pattern detected during execution phase.
#
# Enforcement targets (per _shared/autonomy-protocol.md):
#   - §No option menus (L32-50)
#   - §No honest checkpoints (L52-63)
#   - §No delegated typing (L65-72)
#
# Execution-phase detection:
#   - $AIHAUS_EXEC_PHASE=1 set by parent skill (primary signal); OR
#   - $MANIFEST_PATH points to a RUN-MANIFEST.md with non-empty Invoke stack.
#
# Outside execution phase: violations LOGGED but NOT blocked — plan
# documents (Alternatives tables) reference option-menu prose legitimately.
#
# M011/S05: three decision paths in order:
#   1. status=paused short-circuit → exit 0 silent (S04 legitimate escape)
#   2. 11-regex fast-path (M005, byte-identical) → block if exec phase
#   3. haiku backstop (NEW) → regex-miss + exec phase + claude CLI + opt-in
#      → `claude --print --model haiku-4.5` with CONTEXT.md § Q-3 prompt,
#      3s timeout, strict JSON parse, fail-safe allow on every ambiguous
#      path. Opt-out via AIHAUS_AUTONOMY_HAIKU=0.
#
# Gate decisions are emitted to .claude/audit/autonomy-gate.jsonl (S06
# owns the schema); legacy M005 pattern matches keep their existing
# .claude/audit/autonomy-violations.jsonl sink unchanged.
#
# Story 7 of plan 260414-exec-auto-approve; extended by M011/S05.
set -uo pipefail

AUDIT_LOG="${AIHAUS_AUDIT_LOG:-.claude/audit/autonomy-violations.jsonl}"
AUDIT_GATE_LOG="${AIHAUS_AUDIT_GATE_LOG:-.claude/audit/autonomy-gate.jsonl}"
GATE_CACHE="${AIHAUS_AUDIT_GATE_CACHE:-.claude/audit/autonomy-gate.cache}"

INPUT="$(cat)"

# Extract the assistant's final message from Stop hook payload.
MSG=""
if command -v jq >/dev/null 2>&1; then
  MSG=$(echo "$INPUT" | jq -r '
    .message.content //
    .assistant_message //
    .transcript //
    .content //
    empty
  ' 2>/dev/null || echo "")
fi
[ -z "$MSG" ] && MSG="$INPUT"

# Forbidden patterns. Each line below is: REGEX<TAB>SECTION
# Patterns use ERE syntax (grep -E). Quotes are plain single-quoted strings
# to avoid shell-escape hell.
# (M005 fast-path — byte-identical under M011/S05. 11 patterns, F-05 count.)
PATTERNS=$(cat <<'PATTERNS_EOF'
[Cc]heckpoint honesto	L52-63:no-honest-checkpoints
[Hh]onest checkpoint	L52-63:no-honest-checkpoints
[Oo]pção sua	L32-50:no-option-menus
Qual (prefere|escolhe)\??	L32-50:no-option-menus
[Rr]ealista:.*([4-9]|1[0-9])h\+?	L52-63:no-reality-renegotiation
[Pp]ausing (to|here|for)	L52-63:no-honest-checkpoints
[Ss]hould I (continue|proceed|pause)	L32-50:no-option-menus
[Tt]hree realistic forks	L52-63:no-honest-checkpoints
[Ww]ave [0-9]+ complet[ao].*([Ss]top|[Pp]ause|[Aa]linha)	L52-63:no-honest-checkpoints
retoma depois com /aih-	L65-72:no-delegated-typing
[Tt]ype the command.*/aih-	L65-72:no-delegated-typing
PATTERNS_EOF
)

ts_iso() { date -u +%FT%TZ; }

log_violation() {
  local pattern="$1" section="$2" exec_phase="$3"
  mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || return 0
  local pattern_json section_json
  pattern_json=$(printf '%s' "$pattern" | sed 's/\\/\\\\/g; s/"/\\"/g')
  section_json=$(printf '%s' "$section" | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '{"ts":"%s","violation":"%s","section":"%s","exec_phase":"%s"}\n' \
    "$(ts_iso)" "$pattern_json" "$section_json" "$exec_phase" \
    >> "$AUDIT_LOG" 2>/dev/null || true
}

# M011/S05 — minimal log_gate_decision shim (S06 finalizes the 13-field schema).
# Emits one JSON line to $AUDIT_GATE_LOG per stop-gate decision. Fields emitted
# here are the core 6 (ts, decision, exec_phase, manifest_status, cli_available,
# message_hash) + optional (matched_pattern, section, haiku_reason,
# matched_whitelist, haiku_latency_ms, cache_hit, rate_limited) passed via env.
log_gate_decision() {
  local decision="$1"
  mkdir -p "$(dirname "$AUDIT_GATE_LOG")" 2>/dev/null || return 0
  local ts; ts="$(ts_iso)"
  local hash="${GATE_MSG_HASH:-null}"
  local mstatus="${GATE_MANIFEST_STATUS:-null}"
  local cliok="${GATE_CLI_AVAILABLE:-0}"
  local pat="${GATE_MATCHED_PATTERN:-null}"
  local sec="${GATE_SECTION:-null}"
  local hreason="${GATE_HAIKU_REASON:-null}"
  local hwhite="${GATE_HAIKU_WHITELIST:-null}"
  local hlat="${GATE_HAIKU_LATENCY_MS:-null}"
  local chit="${GATE_CACHE_HIT:-0}"
  local rlim="${GATE_RATE_LIMITED:-0}"
  local tmo="${GATE_TIMEOUT:-0}"
  # Quote-safe serialization (null keeps as bare literal; strings quoted).
  _qq() {
    local v="$1"
    if [ "$v" = "null" ]; then
      printf 'null'
    else
      printf '"%s"' "$(printf '%s' "$v" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    fi
  }
  printf '{"ts":"%s","decision":"%s","message_hash":%s,"matched_pattern":%s,"section":%s,"haiku_reason":%s,"matched_whitelist":%s,"haiku_latency_ms":%s,"exec_phase":"%s","manifest_status":%s,"cli_available":"%s","cache_hit":"%s","rate_limited":"%s","timeout":"%s"}\n' \
    "$ts" "$decision" \
    "$(_qq "$hash")" "$(_qq "$pat")" "$(_qq "$sec")" "$(_qq "$hreason")" "$(_qq "$hwhite")" "$hlat" \
    "$in_execution" "$(_qq "$mstatus")" "$cliok" "$chit" "$rlim" "$tmo" \
    >> "$AUDIT_GATE_LOG" 2>/dev/null || true
}

emit_block() {
  local pattern="$1" section="$2"
  local reason="Autonomy violation: pattern '$pattern' matches autonomy-protocol.md $section. Pick the safer default per TRUE blocker test (L15-31) and proceed silently. Log the choice in RUN-MANIFEST progress log instead of asking the user."
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg r "$reason" '{decision:"block", reason:$r}'
  else
    local reason_json
    reason_json=$(printf '%s' "$reason" | sed 's/\\/\\\\/g; s/"/\\"/g')
    printf '{"decision":"block","reason":"%s"}\n' "$reason_json"
  fi
}

emit_block_haiku() {
  local reason="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg r "$reason" '{decision:"block", reason:$r}'
  else
    local reason_json
    reason_json=$(printf '%s' "$reason" | sed 's/\\/\\\\/g; s/"/\\"/g')
    printf '{"decision":"block","reason":"%s"}\n' "$reason_json"
  fi
}

# Detect execution phase.
in_execution=0
if [ "${AIHAUS_EXEC_PHASE:-0}" = "1" ]; then
  in_execution=1
elif [ -n "${MANIFEST_PATH:-}" ] && [ -f "${MANIFEST_PATH}" ]; then
  if awk '/^## Invoke stack$/ {on=1; next} /^## / {on=0} on && /\|/ {found=1} END {exit !found}' "$MANIFEST_PATH" 2>/dev/null; then
    in_execution=1
  fi
fi

# M011/S05 — resolve manifest status for paused short-circuit + audit hint.
resolve_manifest_status() {
  local m=""
  if [ -n "${MANIFEST_PATH:-}" ] && [ -f "${MANIFEST_PATH}" ]; then
    m="$MANIFEST_PATH"
  else
    for cand in .aihaus/milestones/M0*/RUN-MANIFEST.md; do
      [ -f "$cand" ] || continue
      if awk '/^## Metadata$/ {on=1; next} /^## / {on=0} on && /^status:[[:space:]]*running[[:space:]]*$/ {found=1; exit} END {exit !found}' "$cand" 2>/dev/null; then
        m="$cand"; break
      fi
    done
  fi
  [ -n "$m" ] || { printf 'null'; return; }
  [ -f "$m" ] || { printf 'null'; return; }
  awk '/^## Metadata$/ {on=1; next} /^## / {on=0} on && /^status:/ {sub(/^status:[[:space:]]*/, ""); gsub(/[[:space:]]/, ""); print; exit}' "$m" 2>/dev/null || printf 'null'
}

GATE_MANIFEST_STATUS="$(resolve_manifest_status)"
[ -z "$GATE_MANIFEST_STATUS" ] && GATE_MANIFEST_STATUS="null"

# --- M011/S05 Step 1: paused short-circuit -----------------------------------
# When the active manifest has `Metadata.status: paused`, treat the stop as a
# legitimate TRUE-blocker escape (S04) and allow it silently. This MUST run
# before the regex scan so a regex match on (e.g.) a paused agent's final
# progress prose doesn't falsely block.
if [ "$GATE_MANIFEST_STATUS" = "paused" ]; then
  log_gate_decision "paused-allow"
  exit 0
fi

# --- M011/S05 Step 2: regex fast-path (M005 byte-identical) ------------------
# Scan message against each pattern. First match in exec phase blocks.
REGEX_MATCHED=0
while IFS=$'\t' read -r pattern section; do
  [ -z "$pattern" ] && continue
  if printf '%s' "$MSG" | grep -qE "$pattern" 2>/dev/null; then
    log_violation "$pattern" "$section" "$in_execution"
    if [ "$in_execution" = "1" ]; then
      GATE_MATCHED_PATTERN="$pattern"
      GATE_SECTION="$section"
      log_gate_decision "regex-match"
      emit_block "$pattern" "$section"
      exit 0
    fi
    REGEX_MATCHED=1
  fi
done <<< "$PATTERNS"

# --- M011/S05 Step 3: haiku backstop (regex-miss + exec phase only) ---------
# Early-exit gates (each logs one decision row; all fail-safe allow):
#   - outside execution phase → no block possible; no haiku
#   - AIHAUS_AUTONOMY_HAIKU=0 → explicit opt-out
#   - claude CLI absent       → graceful degrade (regex-only already ran)
#   - cache hit in 5-min TTL  → reuse prior decision
#   - rate-limit window       → skip haiku call, allow
#   - timeout / parse fail    → allow

if [ "$in_execution" != "1" ]; then
  # No audit row when not in execution — reduces log noise for planning mode.
  exit 0
fi

if [ "${AIHAUS_AUTONOMY_HAIKU:-1}" = "0" ]; then
  log_gate_decision "haiku-opt-out"
  exit 0
fi

# Compute message hash (first 4000 chars; sha256 or md5 fallback).
compute_hash() {
  local head="$(printf '%s' "$MSG" | head -c 4000)"
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$head" | sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s' "$head" | shasum -a 256 | awk '{print $1}'
  else
    # Fallback: md5sum — not cryptographic but fine for cache key.
    printf '%s' "$head" | md5sum 2>/dev/null | awk '{print $1}' || printf 'nohash'
  fi
}
GATE_MSG_HASH="$(compute_hash)"

# CLI availability probe.
GATE_CLI_AVAILABLE=0
if command -v claude >/dev/null 2>&1; then
  GATE_CLI_AVAILABLE=1
else
  # One-time stderr warn (idempotent per-day marker).
  mkdir -p "$(dirname "$AUDIT_GATE_LOG")" 2>/dev/null || true
  marker="$(dirname "$AUDIT_GATE_LOG")/.haiku-no-cli-$(date -u +%F)"
  if [ ! -f "$marker" ]; then
    touch "$marker" 2>/dev/null || true
    echo "autonomy-guard.sh: claude CLI not found on PATH — haiku backstop disabled; regex-only for this session." >&2
  fi
  log_gate_decision "no-cli-skip"
  exit 0
fi

# --- Cache lookup (S06 owns the file; S05 emits the call-site) ---------------
# Cache format (per line): <ts_unix>|<hash>|<decision>
# 5-min TTL; 30-s rate-limit window.
now_unix="$(date +%s 2>/dev/null || echo 0)"
mkdir -p "$(dirname "$GATE_CACHE")" 2>/dev/null || true
if [ -f "$GATE_CACHE" ]; then
  # Cache hit: same hash within 5 min → reuse decision.
  while IFS='|' read -r c_ts c_hash c_decision; do
    [ -z "$c_ts" ] && continue
    age=$((now_unix - c_ts))
    if [ "$age" -le 300 ] && [ "$c_hash" = "$GATE_MSG_HASH" ]; then
      GATE_CACHE_HIT=1
      log_gate_decision "cache-hit-$c_decision"
      if [ "$c_decision" = "block" ]; then
        emit_block_haiku "Cached haiku decision (block) for identical message within 5 min."
      fi
      exit 0
    fi
  done < "$GATE_CACHE"
  # Rate limit: newest cache entry within 30 s → skip haiku call.
  newest_ts="$(awk -F'|' 'NF>=1 {if ($1+0 > max) max=$1+0} END {print max+0}' "$GATE_CACHE" 2>/dev/null || echo 0)"
  if [ "$newest_ts" -gt 0 ] && [ $((now_unix - newest_ts)) -lt 30 ]; then
    GATE_RATE_LIMITED=1
    log_gate_decision "rate-limit-skip-allow"
    exit 0
  fi
fi

# --- Haiku invocation --------------------------------------------------------
# Build prompt body (CONTEXT.md § Q-3 verbatim).
manifest_tail="(manifest unavailable)"
if [ -n "${MANIFEST_PATH:-}" ] && [ -f "${MANIFEST_PATH}" ]; then
  manifest_tail="$(tail -50 "$MANIFEST_PATH" 2>/dev/null)"
fi
msg_trunc="$(printf '%s' "$MSG" | head -c 4000)"

PROMPT_BODY="$(cat <<EOF
SYSTEM: You are a stop-gate judge for the aihaus milestone system.
Be conservative: when in doubt, prefer allowing the stop (user can
re-engage) over blocking (which risks infinite loops).

USER:
## Assistant's final message
$msg_trunc

## RUN-MANIFEST state (last 50 lines)
$manifest_tail

## Legitimate-stop whitelist
- status=completed or phase=complete in manifest
- status=paused (user or model explicit pause with reason)
- API key / secret genuinely missing (not a test/placeholder)
- Unresolvable git merge conflict
- User-requested abort
- Migration blocking continuation (schema version mismatch, etc.)

Return JSON ONLY, no prose:
{"decision": "continue" | "block", "reason": "<1 sentence>", "matched_whitelist"?: "<item>"}
EOF
)"

# Invoke haiku with 3-s timeout. Capture stdout; ignore stderr.
HAIKU_START_MS="$(date +%s%3N 2>/dev/null || echo 0)"
if command -v timeout >/dev/null 2>&1; then
  HAIKU_OUT="$(printf '%s' "$PROMPT_BODY" | timeout 3s claude --print --model haiku-4.5 2>/dev/null || true)"
  HAIKU_RC=$?
else
  # No timeout command → best-effort invocation (rare; git-bash ships it).
  HAIKU_OUT="$(printf '%s' "$PROMPT_BODY" | claude --print --model haiku-4.5 2>/dev/null || true)"
  HAIKU_RC=$?
fi
HAIKU_END_MS="$(date +%s%3N 2>/dev/null || echo 0)"
GATE_HAIKU_LATENCY_MS=$((HAIKU_END_MS - HAIKU_START_MS))
[ "$GATE_HAIKU_LATENCY_MS" -lt 0 ] && GATE_HAIKU_LATENCY_MS=0

# Timeout RC (124 from `timeout`) → fail-safe allow.
if [ "${HAIKU_RC:-0}" = "124" ]; then
  GATE_TIMEOUT=1
  log_gate_decision "timeout-fallback-allow"
  # Record cache entry so subsequent storms dedupe.
  printf '%s|%s|%s\n' "$now_unix" "$GATE_MSG_HASH" "timeout" >> "$GATE_CACHE" 2>/dev/null || true
  exit 0
fi

if [ -z "$HAIKU_OUT" ]; then
  log_gate_decision "parse-fail-allow"
  printf '%s|%s|%s\n' "$now_unix" "$GATE_MSG_HASH" "parsefail" >> "$GATE_CACHE" 2>/dev/null || true
  exit 0
fi

# Strict JSON parse of {"decision":"...","reason":"...","matched_whitelist"?:"..."}.
# Prefer jq; fall back to grep if jq missing.
DECISION=""
HREASON=""
HWHITE=""
if command -v jq >/dev/null 2>&1; then
  DECISION="$(printf '%s' "$HAIKU_OUT" | jq -r '.decision // empty' 2>/dev/null || true)"
  HREASON="$(printf '%s' "$HAIKU_OUT" | jq -r '.reason // empty' 2>/dev/null || true)"
  HWHITE="$(printf '%s' "$HAIKU_OUT" | jq -r '.matched_whitelist // empty' 2>/dev/null || true)"
else
  DECISION="$(printf '%s' "$HAIKU_OUT" | grep -oE '"decision"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
  HREASON="$(printf '%s' "$HAIKU_OUT" | grep -oE '"reason"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
  HWHITE="$(printf '%s' "$HAIKU_OUT" | grep -oE '"matched_whitelist"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
fi
[ -n "$HREASON" ] && GATE_HAIKU_REASON="$HREASON"
[ -n "$HWHITE" ]  && GATE_HAIKU_WHITELIST="$HWHITE"

case "$DECISION" in
  continue)
    log_gate_decision "haiku-continue"
    printf '%s|%s|%s\n' "$now_unix" "$GATE_MSG_HASH" "continue" >> "$GATE_CACHE" 2>/dev/null || true
    exit 0
    ;;
  block)
    log_gate_decision "haiku-block"
    printf '%s|%s|%s\n' "$now_unix" "$GATE_MSG_HASH" "block" >> "$GATE_CACHE" 2>/dev/null || true
    emit_block_haiku "${HREASON:-Stop-gate haiku backstop blocked the turn (no TRUE-blocker match).}"
    exit 0
    ;;
  *)
    # Parse failure — fail-safe allow (never block on ambiguous output).
    log_gate_decision "parse-fail-allow"
    printf '%s|%s|%s\n' "$now_unix" "$GATE_MSG_HASH" "parsefail" >> "$GATE_CACHE" 2>/dev/null || true
    exit 0
    ;;
esac
