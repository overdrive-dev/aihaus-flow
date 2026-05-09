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
# M027/S7 (ADR-260509-X): two-tier dispatch. Decision paths become:
#   1. status=paused short-circuit → exit 0 silent (unchanged)
#   2. tier_decision() → haiku-primary | regex-primary (NEW)
#      AIHAUS_AUTONOMY_TIER=regex|haiku|two-tier (default unset → context-route)
#      context-route: exec_phase="1" AND manifest_status ∈ {running, in-progress}
#         → haiku-primary (milestone-execution turns)
#      all other manifest_status or exec_phase="0" → regex-primary (fail-safe)
#   3. haiku-primary path: haiku first → on timeout/error falls back to regex
#   4. regex-primary path: 40-pattern walk (M005 byte-identical) + haiku backstop
#   AIHAUS_AUTONOMY_HAIKU=0 preserves M011 opt-out (disables haiku on all paths).
#   Pattern total frozen at 40 (M005=11 + GSP-DS=13 + LSDD=16).
#   rephrase_suggestion: static lookup emitted on regex-match rows only (S3/OPAQUE).
#
# Gate decisions are emitted to .claude/audit/autonomy-gate.jsonl (S06
# owns the schema); legacy M005 pattern matches keep their existing
# .claude/audit/autonomy-violations.jsonl sink unchanged.
#
# Story 7 of plan 260414-exec-auto-approve; extended by M011/S05, M027/S7.
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

# M019/S04.4 — extract session_id from Stop payload for forensic correlation.
GATE_SESSION_ID=""
if command -v jq >/dev/null 2>&1; then
  GATE_SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
fi

# Forbidden patterns. Each line below is: REGEX<TAB>SECTION
# Patterns use ERE syntax (grep -E). Quotes are plain single-quoted strings
# to avoid shell-escape hell.
# (M005 fast-path — byte-identical under M011/S05. 24 patterns, F-05 count. (1 modified, 13 added; M023))
PATTERNS=$(cat <<'PATTERNS_EOF'
[Cc]heckpoint honesto	L52-63:no-honest-checkpoints
[Hh]onest checkpoint	L52-63:no-honest-checkpoints
[Oo]pção sua	L32-50:no-option-menus
Qual (prefere|escolhe)\??	L32-50:no-option-menus
[Rr]ealista:.*([2-9]|1[0-9])h\+?	L52-63:no-reality-renegotiation
[Pp]ausing (to|here|for)	L52-63:no-honest-checkpoints
[Ss]hould I (continue|proceed|pause)	L32-50:no-option-menus
[Tt]hree realistic forks	L52-63:no-honest-checkpoints
[Ww]ave [0-9]+ complet[ao].*([Ss]top|[Pp]ause|[Aa]linha)	L52-63:no-honest-checkpoints
retoma depois com /aih-	L65-72:no-delegated-typing
[Tt]ype the command.*/aih-	L65-72:no-delegated-typing
PATTERNS_EOF
)
# --- M023 / ADR-260506-A: GSP-DS PT-BR pattern pack (env-gated) ---
# AIHAUS_GSP_DS_REGEX=0 bypasses the 13 new PT-BR patterns; existing 12
# (11 original + 1 modified line-69) still fire unconditionally above.
if [ "${AIHAUS_GSP_DS_REGEX:-1}" != "0" ]; then
  PATTERNS="$PATTERNS
$(cat <<'GSP_DS_EOF'
[Hh]onest[oa] sobre (escopo|qualidade)	GSP-DS-honest-scope
[Cc]onversa (muito )?longa	GSP-DS-long-conversation
[Pp]ar(o|amos) aqui (com|para)	GSP-DS-explicit-stop
[Pp]reserv(ar|ando) qualidade	GSP-DS-quality-preserve
[Rr]ealisticamente.*[0-9]+(-[0-9]+)?[ ]?(h|hora)	GSP-DS-time-estimate
[Pp]r[óo]xim[ao] sess[ãa]o	GSP-DS-next-session
/aih-resume (l[êe]|reads?) RUN-MANIFEST	GSP-DS-resume-recipe
[Bb]atch [AB] (mergeado|complet[oa])	GSP-DS-batch-frame
[Cc]onclu[íi]do.*[Bb]atch [AB]	GSP-DS-batch-completion-frame
[Qq]uando voc[êe] quiser continuar	GSP-DS-future-tense-continuation
feature separada	GSP-DS-feature-separation
PR.*revis[áa]vel	GSP-DS-reviewable-pr-frame
tratar o (frontend|backend) como	GSP-DS-domain-split-frame
GSP_DS_EOF
)"
fi

# --- M025 / ADR-260508-A: LSDD anchored cadence-noun pack (env-gated) ---
# AIHAUS_LSDD_REGEX=0 bypasses the 16 new patterns; existing 24 (M005 11
# fast-path + M023 13 PT-BR GSP-DS) still fire unconditionally above.
# Anchoring (F-CRIT-1+F-CRIT-3): every cadence-noun pattern requires same-line
# completion-prose verb to avoid firing on autonomy-protocol §M023 catalog
# (L147+L487 "Etapa/Bloco/Fase/Phase X/Y" enumeration) AND on legitimate
# `## Phase N` H2 headers in skill prose at runtime emission. The PT-BR
# cadence-noun previously enumerated under analyst R2 §3 was excluded per F1
# BLOCKER absorption (no fabricated mandate citation). 16 patterns total
# (5 EN + 5 PT-BR cadence + 1 Sigo + 5 task-fraction).
if [ "${AIHAUS_LSDD_REGEX:-1}" != "0" ]; then
  PATTERNS="$PATTERNS
$(cat <<'LSDD_EOF'
[Pp]hase [A-Z].*(complete|completa|completo|done|paralelo|seguir|working|remaining|shipped|finalizada|finalizado|pronta|in progress)	LSDD-EN-Phase-letter
[Pp]hase [0-9]+.*(complete|completa|completo|done|paralelo|seguir|working|remaining|shipped|finalizada|finalizado|pronta|in progress)	LSDD-EN-Phase-numeric
[Rr]ound [0-9]+.*(complete|completa|completo|done|paralelo|seguir|working|remaining|shipped|finalizada|finalizado|pronta|in progress)	LSDD-EN-Round
[Ss]tage [0-9]+.*(complete|completa|completo|done|paralelo|seguir|working|remaining|shipped|finalizada|finalizado|pronta|in progress)	LSDD-EN-Stage
[Tt]ranche [A-Z0-9]+.*(complete|completa|completo|done|paralelo|seguir|working|remaining|shipped|finalizada|finalizado|pronta|in progress)	LSDD-EN-Tranche
[Ee]tapa [0-9]+.*(complete|completa|completo|done|paralelo|seguir|working|remaining|shipped|finalizada|finalizado|pronta|in progress)	LSDD-PT-Etapa
[Bb]loco [A-Z].*(complete|completa|completo|done|paralelo|seguir|working|remaining|shipped|finalizada|finalizado|pronta|in progress)	LSDD-PT-Bloco
[Ff]ase [A-Z].*(complete|completa|completo|done|paralelo|seguir|working|remaining|shipped|finalizada|finalizado|pronta|in progress)	LSDD-PT-Fase
[Rr]odada [0-9]+.*(complete|completa|completo|done|paralelo|seguir|working|remaining|shipped|finalizada|finalizado|pronta|in progress)	LSDD-PT-Rodada
[Ss]e[çc][ãa]o [0-9]+.*(complete|completa|completo|done|paralelo|seguir|working|remaining|shipped|finalizada|finalizado|pronta|in progress)	LSDD-PT-Secao
[Ss]igo (Round|Rodada|Phase|Fase|Etapa|Bloco|Stage|Tranche)( [0-9A-Z]+)?\?	LSDD-Sigo-question
[0-9]+/[0-9]+ (stories|tasks)([[:space:]]+(complete|done|remaining|left))?	LSDD-fraction-stories
[Pp]rogress: [0-9]+/[0-9]+ done	LSDD-fraction-progress
[0-9]+ stor(y|ies) (done|complete|remaining|shipped)	LSDD-fraction-storyies
[0-9]+ of [0-9]+ (done|complete)	LSDD-fraction-of
[0-9]+ task[s]? (done|complete|remaining)	LSDD-fraction-tasks
LSDD_EOF
)"
fi

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

# M011/S06 — finalized log_gate_decision with 13-field schema + rotation.
# Emits one JSONL line to $AUDIT_GATE_LOG per stop-gate decision. Fields:
#   ts, decision, message_hash, matched_pattern, section, haiku_reason,
#   matched_whitelist, haiku_latency_ms, exec_phase, manifest_status,
#   cli_available, cache_hit, rate_limited, timeout (14 total incl. timeout;
#   13 semantic per architecture § 6 — `timeout` is the operational add-on).
# M019/S04 schema bump adds 4 fields: session_id, story_id, message_head,
#   active_invoke_top (forensic correlation; backward-compatible JSONL).
#
# Decision enum (13 values — 11 original M011 + 2 added M019/S04):
#   paused-allow | regex-match | haiku-continue | haiku-block |
#   timeout-fallback-allow | parse-fail-allow | no-cli-skip |
#   haiku-opt-out | cache-hit-continue | cache-hit-block | rate-limit-skip-allow |
#   outside-exec-skip (12th, M019/S04.1) |
#   unknown-no-substrate-visibility (13th, M019/S04.4 — predicate filled by S05)
#
# Rotation (CONTEXT.md Q-2): at write time, if file size ≥ 10 MB OR line
# count ≥ 10 000, atomic `mv $AUDIT_GATE_LOG $AUDIT_GATE_LOG.old` (overwrites
# prior .old). Single stat + conditional wc per write; < 1 ms overhead.
rotate_gate_log_if_needed() {
  [ -f "$AUDIT_GATE_LOG" ] || return 0
  local bytes lines
  bytes="$(stat -c%s "$AUDIT_GATE_LOG" 2>/dev/null || stat -f%z "$AUDIT_GATE_LOG" 2>/dev/null || echo 0)"
  if [ "$bytes" -ge 10485760 ]; then
    mv -f "$AUDIT_GATE_LOG" "$AUDIT_GATE_LOG.old" 2>/dev/null || true
    return 0
  fi
  lines="$(wc -l < "$AUDIT_GATE_LOG" 2>/dev/null | tr -d ' ')"
  if [ -n "$lines" ] && [ "$lines" -ge 10000 ]; then
    mv -f "$AUDIT_GATE_LOG" "$AUDIT_GATE_LOG.old" 2>/dev/null || true
  fi
}

log_gate_decision() {
  local decision="$1"
  mkdir -p "$(dirname "$AUDIT_GATE_LOG")" 2>/dev/null || return 0
  rotate_gate_log_if_needed
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
  # M019/S04.4 — 4 new forensic fields (backward-compatible; prior rows lack them).
  # session_id: from CC stdin payload (extracted earlier into GATE_SESSION_ID).
  local sess="${GATE_SESSION_ID:-}"
  [ -z "$sess" ] && sess="null"
  # story_id: last Story Records row col-1 from resolved manifest.
  local story_id="null"
  local _rmp
  _rmp="${GATE_RESOLVED_MANIFEST_PATH:-}"
  if [ -z "$_rmp" ] && declare -f resolve_manifest_path >/dev/null 2>&1; then
    _rmp="$(resolve_manifest_path 2>/dev/null || true)"
  fi
  if [ -n "$_rmp" ] && [ -f "$_rmp" ]; then
    local _sid
    _sid="$(awk '
      /^## Story Records$/ { on=1; next }
      /^## / { on=0 }
      on && /\|/ && $0 !~ /^\|[[:space:]]*-+/ && $0 !~ /^\|[[:space:]]*story/ {
        split($0, f, "|"); gsub(/[[:space:]]/, "", f[2]); last=f[2]
      }
      END { if (last != "") print last }
    ' "$_rmp" 2>/dev/null || true)"
    [ -n "$_sid" ] && story_id="$_sid"
  fi
  # message_head: first 80 chars of MSG (privacy: no full body).
  local mhead
  mhead="$(printf '%s' "${MSG:-}" | head -c 80 2>/dev/null || true)"
  [ -z "$mhead" ] && mhead="null"
  # active_invoke_top: last agent slug pushed onto ## Invoke stack.
  local invoke_top="null"
  if [ -n "$_rmp" ] && [ -f "$_rmp" ]; then
    local _itop
    _itop="$(awk '
      /^## Invoke stack$/ { on=1; next }
      /^## / { on=0 }
      on && /[^[:space:]]/ { last=$0 }
      END { if (last != "") print last }
    ' "$_rmp" 2>/dev/null | awk -F'|' '{gsub(/[[:space:]]/, "", $2); if ($2 != "") print $2}' 2>/dev/null || true)"
    [ -n "$_itop" ] && invoke_top="$_itop"
  fi
  # M027/S7 — additive fields: tier_used + rephrase_suggestion (ADR-260509-X).
  # tier_used: regex | haiku | two-tier-fallback
  # rephrase_suggestion: static human-readable string for regex-match rows; null otherwise.
  local tier_used="${GATE_TIER_USED:-regex}"
  local rephrase="${GATE_REPHRASE_SUGGESTION:-null}"
  printf '{"ts":"%s","decision":"%s","message_hash":%s,"matched_pattern":%s,"section":%s,"haiku_reason":%s,"matched_whitelist":%s,"haiku_latency_ms":%s,"exec_phase":"%s","manifest_status":%s,"cli_available":"%s","cache_hit":"%s","rate_limited":"%s","timeout":"%s","session_id":%s,"story_id":%s,"message_head":%s,"active_invoke_top":%s,"tier_used":"%s","rephrase_suggestion":%s}\n' \
    "$ts" "$decision" \
    "$(_qq "$hash")" "$(_qq "$pat")" "$(_qq "$sec")" "$(_qq "$hreason")" "$(_qq "$hwhite")" "$hlat" \
    "$in_execution" "$(_qq "$mstatus")" "$cliok" "$chit" "$rlim" "$tmo" \
    "$(_qq "$sess")" "$(_qq "$story_id")" "$(_qq "$mhead")" "$(_qq "$invoke_top")" \
    "$tier_used" "$(_qq "$rephrase")" \
    >> "$AUDIT_GATE_LOG" 2>/dev/null || true
}

# M011/S06 — append cache entry with opportunistic stale-line pruning.
# Format: <ts_unix>|<hash>|<decision>
# Entries older than 300s (5-min TTL) are dropped on every write — keeps
# the cache small (~50 lines typical) without a background process.
append_cache_entry() {
  local entry="$1"
  mkdir -p "$(dirname "$GATE_CACHE")" 2>/dev/null || return 0
  local now; now="$(date +%s 2>/dev/null || echo 0)"
  if [ -f "$GATE_CACHE" ]; then
    # Keep only entries newer than 300s.
    local tmp="$GATE_CACHE.tmp.$$"
    awk -F'|' -v now="$now" 'NF>=1 && (now - ($1+0)) <= 300 {print}' "$GATE_CACHE" > "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$GATE_CACHE" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  fi
  printf '%s\n' "$entry" >> "$GATE_CACHE" 2>/dev/null || true
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

# M027/S7 — static rephrase_suggestion lookup (ADR-260509-X, S3 OPAQUE verdict).
# Keyed on $GATE_SECTION. Emitted only on regex-match decision rows.
# Mapping: 6 canonical section namespace prefixes → 1 canonical human-readable string.
# <1 ms overhead (no LLM call; pure shell case-statement).
lookup_rephrase_suggestion() {
  local sec="$1"
  case "$sec" in
    L65-72:no-delegated-typing*)
      printf '%s' "Dispatch the next skill directly via the Skill tool. Do not print 'type /aih-...' instructions for the user."
      ;;
    L52-63:no-honest-checkpoints*)
      printf '%s' "Remove the checkpoint prose and proceed. If a TRUE blocker exists, use: bash .aihaus/hooks/phase-advance.sh --to paused --reason '<reason>'."
      ;;
    L32-50:no-option-menus*)
      printf '%s' "Pick one option, log the choice as a one-liner in RUN-MANIFEST progress log, and continue silently."
      ;;
    L52-63:no-reality-renegotiation*)
      printf '%s' "Continue executing. Log the time estimate correction in RUN-MANIFEST. Let the user interrupt via ESC if needed."
      ;;
    GSP-DS-*)
      printf '%s' "Remove scope-reduction or quality-preserve framing. Proceed silently. If a TRUE blocker applies, use phase-advance --to paused."
      ;;
    LSDD-*)
      printf '%s' "Remove cadence-noun progress summary. Use a flat one-liner status update (e.g., 'S3 complete, proceeding to S4') instead."
      ;;
    *)
      printf 'null'
      ;;
  esac
}

# M027/S7 — tier_decision(): determine dispatch tier for this invocation.
# Returns: "haiku-primary" | "regex-primary"
# Reads: AIHAUS_AUTONOMY_TIER env, in_execution (set by detect-exec-phase block),
#        GATE_MANIFEST_STATUS (resolved by resolve_manifest_status()).
# Called AFTER paused short-circuit (line ~340) and AFTER manifest status resolved.
# AIHAUS_AUTONOMY_HAIKU=0 forces regex-primary on all paths (M011 opt-out preserved).
tier_decision() {
  # M011 opt-out: AIHAUS_AUTONOMY_HAIKU=0 disables haiku entirely.
  if [ "${AIHAUS_AUTONOMY_HAIKU:-1}" = "0" ]; then
    printf 'regex-primary'
    return
  fi
  # Explicit tier override.
  local tier_env="${AIHAUS_AUTONOMY_TIER:-}"
  case "$tier_env" in
    regex)
      printf 'regex-primary'
      return
      ;;
    haiku)
      printf 'haiku-primary'
      return
      ;;
    two-tier|"")
      # Context-route (default when unset or explicit two-tier).
      ;;
    *)
      # Unknown value → fail-safe regex-primary.
      printf 'regex-primary'
      return
      ;;
  esac
  # Context-route: exec_phase="1" AND manifest_status ∈ {running, in-progress}
  # → haiku-primary. All other states → regex-primary (fail-safe).
  if [ "${in_execution:-0}" = "1" ]; then
    case "${GATE_MANIFEST_STATUS:-null}" in
      running|in-progress)
        printf 'haiku-primary'
        return
        ;;
    esac
  fi
  printf 'regex-primary'
}

# Compute message hash (first 4000 chars; sha256 or md5 fallback).
# Defined here (before haiku-primary path) so both Step 1.5 and Step 3 can call it.
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

# M027/S7 — tier tracking globals (set after tier_decision call below).
GATE_TIER_USED="regex"  # default; overwritten per dispatch path
GATE_REPHRASE_SUGGESTION="null"

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
# M019/S04.3 — uses resolve_manifest_path() from lib/manifest-helpers.sh;
#   widens status filter from `running` to `running|paused` (FR-017);
#   sort-by-mtime tie-break for multiple non-terminal manifests.
# Source lib/manifest-helpers.sh relative to this script's own location so
# the path is cwd-independent (A5.1 fix).
_GUARD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" \
  || _GUARD_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=lib/manifest-helpers.sh
[ -f "$_GUARD_DIR/lib/manifest-helpers.sh" ] \
  && . "$_GUARD_DIR/lib/manifest-helpers.sh" 2>/dev/null || true

resolve_manifest_status() {
  local m=""
  if [ -n "${MANIFEST_PATH:-}" ] && [ -f "${MANIFEST_PATH}" ]; then
    m="$MANIFEST_PATH"
  else
    # Use shared walk-up helper (S04.2) — cwd-independent.
    if declare -f resolve_manifest_path >/dev/null 2>&1; then
      m="$(resolve_manifest_path 2>/dev/null || true)"
    fi
  fi
  [ -n "$m" ] || { printf 'null'; return; }
  [ -f "$m" ] || { printf 'null'; return; }
  # Cache for log_gate_decision (avoids second walk-up for story_id / invoke_top).
  GATE_RESOLVED_MANIFEST_PATH="$m"
  local val
  val="$(awk '/^## Metadata$/ {on=1; next} /^## / {on=0} on && /^status:/ {sub(/^status:[[:space:]]*/,""); gsub(/[[:space:]]/,""); print; exit}' "$m" 2>/dev/null)"
  printf '%s' "${val:-null}"
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

# M019/S04.4 — S05 fills in the unknown-no-substrate-visibility predicate here.
# Emission site reserved: AFTER paused-allow short-circuit above,
# BEFORE regex scan below (architecture.md §"autonomy-guard audit-row enum extension").
# S05 will insert:
#   if [ "${GATE_OUTPUT_TOKENS:-0}" = "0" ] && [ "${GATE_MANIFEST_MTIME_STALE:-0}" = "1" ]; then
#     log_gate_decision "unknown-no-substrate-visibility"
#     exit 0
#   fi

# --- M027/S7 Step 1.5: two-tier dispatch decision (ADR-260509-X) --------------
# Determine tier AFTER paused-short-circuit + manifest-status resolved.
# tier_decision() reads AIHAUS_AUTONOMY_TIER env + in_execution + GATE_MANIFEST_STATUS.
# Result: "haiku-primary" → run haiku first (milestone-execution turns)
#         "regex-primary" → run 40-pattern walk first (all other contexts)
_ACTIVE_TIER="$(tier_decision)"

# --- M027/S7 haiku-primary path (NEW) ----------------------------------------
# Fires ONLY when _ACTIVE_TIER=haiku-primary (exec_phase="1" AND
# manifest_status ∈ {running, in-progress} AND AIHAUS_AUTONOMY_HAIKU != 0).
# On block → emit block + log tier_used=haiku. Exit.
# On allow → exit 0 (log tier_used=haiku).
# On timeout/error → set tier_used=two-tier-fallback, fall through to regex path.
_HAIKU_PRIMARY_DONE=0
if [ "$_ACTIVE_TIER" = "haiku-primary" ]; then
  # CLI availability probe for haiku-primary path.
  # No claude → fall through to regex-primary silently (no JSONL row for this probe).
  # Step 3 haiku backstop (below) will emit no-cli-skip when it fires (regex-miss path).
  if ! command -v claude >/dev/null 2>&1; then
    GATE_CLI_AVAILABLE=0
    _ACTIVE_TIER="regex-primary"
  else
    # Compute message hash for cache.
    GATE_MSG_HASH="$(compute_hash)"
    GATE_CLI_AVAILABLE=1

    # Cache lookup for haiku-primary path (same 5-min TTL, 30-s rate-limit).
    now_unix_hp="$(date +%s 2>/dev/null || echo 0)"
    mkdir -p "$(dirname "$GATE_CACHE")" 2>/dev/null || true
    _HP_CACHE_HIT=0
    if [ -f "$GATE_CACHE" ]; then
      while IFS='|' read -r c_ts c_hash c_decision; do
        [ -z "$c_ts" ] && continue
        age=$((now_unix_hp - c_ts))
        if [ "$age" -le 300 ] && [ "$c_hash" = "$GATE_MSG_HASH" ]; then
          _HP_CACHE_HIT=1
          GATE_CACHE_HIT=1
          GATE_TIER_USED="haiku"
          log_gate_decision "cache-hit-$c_decision"
          if [ "$c_decision" = "block" ]; then
            emit_block_haiku "Cached haiku decision (block) for identical message within 5 min."
          fi
          exit 0
        fi
      done < "$GATE_CACHE"
      # Rate limit check for haiku-primary.
      _hp_newest_ts="$(awk -F'|' 'NF>=1 {if ($1+0 > max) max=$1+0} END {print max+0}' "$GATE_CACHE" 2>/dev/null || echo 0)"
      if [ "$_hp_newest_ts" -gt 0 ] && [ $((now_unix_hp - _hp_newest_ts)) -lt 30 ]; then
        GATE_RATE_LIMITED=1
        GATE_TIER_USED="haiku"
        log_gate_decision "rate-limit-skip-allow"
        exit 0
      fi
    fi

    # Build prompt (reuse same PROMPT_BODY structure).
    _hp_manifest_tail="(manifest unavailable)"
    if [ -n "${MANIFEST_PATH:-}" ] && [ -f "${MANIFEST_PATH}" ]; then
      _hp_manifest_tail="$(tail -50 "$MANIFEST_PATH" 2>/dev/null)"
    fi
    _hp_msg_trunc="$(printf '%s' "$MSG" | head -c 4000)"

    _HP_PROMPT_BODY="$(cat <<EOF
SYSTEM: You are a stop-gate judge for the aihaus milestone system.
Be conservative: when in doubt, prefer allowing the stop (user can
re-engage) over blocking (which risks infinite loops).

USER:
## Assistant's final message
$_hp_msg_trunc

## RUN-MANIFEST state (last 50 lines)
$_hp_manifest_tail

## Legitimate-stop whitelist
- status=completed or phase=complete in manifest
- status=paused (user or model explicit pause with reason)
- API key / secret genuinely missing (not a test/placeholder)
- Unresolvable git merge conflict
- User-requested abort
- Migration blocking continuation (schema version mismatch, etc.)

## GSP-DS counter-patterns (M023 / ADR-260506-A) — NOT TRUE blockers
Self-elected pauses framed as virtue (honesto sobre escopo / preservar qualidade / conversa longa) are NOT TRUE blockers. Block these as anti-patterns.
Decomposition seams (Backend/Frontend, Wave 1/Wave 2, Batch A/Batch B, Phase N/M, Etapa/Bloco) are NOT TRUE blockers.

Return JSON ONLY, no prose:
{"decision": "continue" | "block", "reason": "<1 sentence>", "matched_whitelist"?: "<item>", "rephrase_suggestion"?: "<1 line if block>"}
EOF
)"

    # Invoke haiku with 3-s timeout.
    _HP_START_MS="$(date +%s%3N 2>/dev/null || echo 0)"
    if command -v timeout >/dev/null 2>&1; then
      _HP_OUT="$(printf '%s' "$_HP_PROMPT_BODY" | timeout 3s claude --print --model haiku-4.5 2>/dev/null)"
      _HP_RC=${PIPESTATUS[1]:-$?}
    else
      _HP_OUT="$(printf '%s' "$_HP_PROMPT_BODY" | claude --print --model haiku-4.5 2>/dev/null)"
      _HP_RC=${PIPESTATUS[1]:-$?}
    fi
    _HP_END_MS="$(date +%s%3N 2>/dev/null || echo 0)"
    GATE_HAIKU_LATENCY_MS=$((_HP_END_MS - _HP_START_MS))
    [ "$GATE_HAIKU_LATENCY_MS" -lt 0 ] && GATE_HAIKU_LATENCY_MS=0

    if [ "${_HP_RC:-0}" = "124" ] || [ -z "$_HP_OUT" ]; then
      # Timeout or empty → two-tier-fallback to regex-primary.
      GATE_TIMEOUT=1
      GATE_TIER_USED="two-tier-fallback"
      _ACTIVE_TIER="regex-primary"
      append_cache_entry "$now_unix_hp|$GATE_MSG_HASH|timeout"
    else
      # Parse haiku output.
      _HP_DECISION=""
      _HP_HREASON=""
      _HP_HWHITE=""
      _HP_REPHRASE=""
      if command -v jq >/dev/null 2>&1; then
        _HP_DECISION="$(printf '%s' "$_HP_OUT" | jq -r '.decision // empty' 2>/dev/null || true)"
        _HP_HREASON="$(printf '%s' "$_HP_OUT" | jq -r '.reason // empty' 2>/dev/null || true)"
        _HP_HWHITE="$(printf '%s' "$_HP_OUT" | jq -r '.matched_whitelist // empty' 2>/dev/null || true)"
        _HP_REPHRASE="$(printf '%s' "$_HP_OUT" | jq -r '.rephrase_suggestion // empty' 2>/dev/null || true)"
      else
        _HP_DECISION="$(printf '%s' "$_HP_OUT" | grep -oE '"decision"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
        _HP_HREASON="$(printf '%s' "$_HP_OUT" | grep -oE '"reason"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
        _HP_HWHITE="$(printf '%s' "$_HP_OUT" | grep -oE '"matched_whitelist"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
        _HP_REPHRASE="$(printf '%s' "$_HP_OUT" | grep -oE '"rephrase_suggestion"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
      fi
      [ -n "$_HP_HREASON" ] && GATE_HAIKU_REASON="$_HP_HREASON"
      [ -n "$_HP_HWHITE" ]  && GATE_HAIKU_WHITELIST="$_HP_HWHITE"
      GATE_TIER_USED="haiku"

      case "$_HP_DECISION" in
        continue)
          log_gate_decision "haiku-continue"
          append_cache_entry "$now_unix_hp|$GATE_MSG_HASH|continue"
          exit 0
          ;;
        block)
          # If haiku provided rephrase_suggestion, store it for the JSONL row.
          [ -n "$_HP_REPHRASE" ] && GATE_REPHRASE_SUGGESTION="$_HP_REPHRASE"
          log_gate_decision "haiku-block"
          append_cache_entry "$now_unix_hp|$GATE_MSG_HASH|block"
          emit_block_haiku "${_HP_HREASON:-Stop-gate haiku-primary blocked the turn (no TRUE-blocker match).}"
          exit 0
          ;;
        *)
          # Parse failure → two-tier-fallback to regex-primary.
          GATE_TIER_USED="two-tier-fallback"
          _ACTIVE_TIER="regex-primary"
          append_cache_entry "$now_unix_hp|$GATE_MSG_HASH|parsefail"
          ;;
      esac
    fi
    _HAIKU_PRIMARY_DONE=1
  fi
fi

# --- M011/S05 Step 2: regex fast-path (M005 byte-identical) ------------------
# Scan message against each pattern. First match in exec phase blocks.
# M027: tier_used=regex for all blocks from this path.
REGEX_MATCHED=0
while IFS=$'\t' read -r pattern section; do
  [ -z "$pattern" ] && continue
  if printf '%s' "$MSG" | grep -qE "$pattern" 2>/dev/null; then
    log_violation "$pattern" "$section" "$in_execution"
    if [ "$in_execution" = "1" ]; then
      GATE_MATCHED_PATTERN="$pattern"
      GATE_SECTION="$section"
      # M027: tier_used is "two-tier-fallback" if haiku-primary failed and fell back;
      # otherwise "regex". Do not overwrite two-tier-fallback (it carries fallback info).
      [ "${GATE_TIER_USED:-regex}" = "regex" ] && GATE_TIER_USED="regex"
      # rephrase_suggestion: static lookup keyed on section (S3 OPAQUE verdict obligation).
      GATE_REPHRASE_SUGGESTION="$(lookup_rephrase_suggestion "$section")"
      log_gate_decision "regex-match"
      emit_block "$pattern" "$section"
      exit 0
    fi
    REGEX_MATCHED=1
  fi
done <<< "$PATTERNS"

# --- M020/Phase-B: Step 7 / Step 9 inline-edit drift advisory (non-blocking) ---
# Fires when MANIFEST_PATH is set and the manifest's Story Records show
# substantive file changes but no implementer/frontend-dev/code-fixer agent
# rows. Soft warning to stderr only — never blocks. Opt-out:
# AIHAUS_STEP7_ADVISORY=0.
if [ -n "${MANIFEST_PATH:-}" ] && [ -f "${MANIFEST_PATH}" ] \
   && [ "${AIHAUS_STEP7_ADVISORY:-1}" != "0" ]; then
  # Count agent: rows in Story Records where agent ∈ {implementer, frontend-dev, code-fixer}
  _s7_agent_rows=$(awk '
    /^## Story Records$/ { in_sec=1; next }
    /^## / && in_sec==1 { exit }
    in_sec==1 && /(implementer|frontend-dev|code-fixer)/ { count++ }
    END { print count+0 }
  ' "${MANIFEST_PATH}" 2>/dev/null || echo 0)

  # Count Progress Log rows (proxy for total work)
  _s7_log_rows=$(awk '
    /^## Progress Log$/ { in_sec=1; next }
    /^## / && in_sec==1 { exit }
    in_sec==1 && /^- / { count++ }
    END { print count+0 }
  ' "${MANIFEST_PATH}" 2>/dev/null || echo 0)

  # Heuristic: if Progress Log has >5 entries (substantive run) but agent_rows == 0,
  # surface a soft advisory pointing at the agent-routing annex.
  if [ "${_s7_log_rows:-0}" -gt 5 ] && [ "${_s7_agent_rows:-0}" -eq 0 ]; then
    printf 'advisory: Step 7/9 — manifest shows substantive work (%s progress entries) but 0 implementer/frontend-dev/code-fixer agent rows. See pkg/.aihaus/skills/aih-feature/annexes/agent-routing.md for delegation contract.\n' \
      "${_s7_log_rows}" >&2
    # Also log to audit (non-fatal)
    _S7_AUDIT_LOG="${AIHAUS_AUDIT_LOG:-.claude/audit/hook.jsonl}"
    mkdir -p "$(dirname "$_S7_AUDIT_LOG")" 2>/dev/null || true
    printf '{"ts":"%s","hook":"autonomy-guard","advisory":"step7-inline-drift","manifest_path":"%s","log_rows":%s,"agent_rows":0}\n' \
      "$(date -u +%FT%TZ)" "${MANIFEST_PATH}" "${_s7_log_rows}" \
      >> "$_S7_AUDIT_LOG" 2>/dev/null || true
  fi
fi
# --- end Phase-B advisory ---

# --- M011/S05 Step 3: haiku backstop (regex-miss + exec phase only) ---------
# Early-exit gates (each logs one decision row; all fail-safe allow):
#   - outside execution phase → no block possible; no haiku
#   - AIHAUS_AUTONOMY_HAIKU=0 → explicit opt-out
#   - claude CLI absent       → graceful degrade (regex-only already ran)
#   - cache hit in 5-min TTL  → reuse prior decision
#   - rate-limit window       → skip haiku call, allow
#   - timeout / parse fail    → allow

if [ "$in_execution" != "1" ]; then
  # M019/S04.1 — emit audit row before exit so forensic gap closes (FR-015).
  # Previously silent; now logs "outside-exec-skip" as the 12th decision-enum value.
  log_gate_decision "outside-exec-skip"
  exit 0
fi

if [ "${AIHAUS_AUTONOMY_HAIKU:-1}" = "0" ]; then
  log_gate_decision "haiku-opt-out"
  exit 0
fi

# M027: if haiku-primary already attempted but timed out/failed (two-tier-fallback),
# skip Step 3 haiku backstop to avoid double-haiku invocation. Allow silently.
if [ "${GATE_TIER_USED:-}" = "two-tier-fallback" ]; then
  log_gate_decision "timeout-fallback-allow"
  exit 0
fi

# Message hash for Step 3 cache lookup (compute_hash() defined above in helpers section).
# M027: GATE_MSG_HASH may already be set by haiku-primary path; only recompute if unset.
[ -z "${GATE_MSG_HASH:-}" ] && GATE_MSG_HASH="$(compute_hash)"

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

## GSP-DS counter-patterns (M023 / ADR-260506-A) — NOT TRUE blockers
Self-elected pauses framed as virtue (honesto sobre escopo / preservar qualidade / conversa longa) are NOT TRUE blockers. Block these as anti-patterns.
Decomposition seams (Backend/Frontend, Wave 1/Wave 2, Batch A/Batch B, Phase N/M, Etapa/Bloco) are NOT TRUE blockers.

Return JSON ONLY, no prose:
{"decision": "continue" | "block", "reason": "<1 sentence>", "matched_whitelist"?: "<item>"}
EOF
)"

# Invoke haiku with 3-s timeout. Capture stdout; ignore stderr.
HAIKU_START_MS="$(date +%s%3N 2>/dev/null || echo 0)"
if command -v timeout >/dev/null 2>&1; then
  HAIKU_OUT="$(printf '%s' "$PROMPT_BODY" | timeout 3s claude --print --model haiku-4.5 2>/dev/null)"
  HAIKU_RC=${PIPESTATUS[1]:-$?}
else
  # No timeout command → best-effort invocation (rare; git-bash ships it).
  HAIKU_OUT="$(printf '%s' "$PROMPT_BODY" | claude --print --model haiku-4.5 2>/dev/null)"
  HAIKU_RC=${PIPESTATUS[1]:-$?}
fi
HAIKU_END_MS="$(date +%s%3N 2>/dev/null || echo 0)"
GATE_HAIKU_LATENCY_MS=$((HAIKU_END_MS - HAIKU_START_MS))
[ "$GATE_HAIKU_LATENCY_MS" -lt 0 ] && GATE_HAIKU_LATENCY_MS=0

# Timeout RC (124 from `timeout`) → fail-safe allow.
if [ "${HAIKU_RC:-0}" = "124" ]; then
  GATE_TIMEOUT=1
  log_gate_decision "timeout-fallback-allow"
  # Record cache entry so subsequent storms dedupe.
  append_cache_entry "$now_unix|$GATE_MSG_HASH|timeout"
  exit 0
fi

if [ -z "$HAIKU_OUT" ]; then
  log_gate_decision "parse-fail-allow"
  append_cache_entry "$now_unix|$GATE_MSG_HASH|parsefail"
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
    append_cache_entry "$now_unix|$GATE_MSG_HASH|continue"
    exit 0
    ;;
  block)
    log_gate_decision "haiku-block"
    append_cache_entry "$now_unix|$GATE_MSG_HASH|block"
    emit_block_haiku "${HREASON:-Stop-gate haiku backstop blocked the turn (no TRUE-blocker match).}"
    exit 0
    ;;
  *)
    # Parse failure — fail-safe allow (never block on ambiguous output).
    log_gate_decision "parse-fail-allow"
    append_cache_entry "$now_unix|$GATE_MSG_HASH|parsefail"
    exit 0
    ;;
esac
