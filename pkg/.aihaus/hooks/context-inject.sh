#!/usr/bin/env bash
# context-inject.sh — SubagentStart hook (M013/S05 Component A)
# Fires on every subagent spawn, resolves relevance-tiered file list,
# and emits SubagentStart.additionalContext payload so the agent's
# first token is grounded in project/workflow memory and task artifacts.
#
# Hybrid Option C (S01-validated SubagentStart.additionalContext path):
#   (a) Static role-default map keyed on cohort (lib/role-defaults.json)
#       covers ~80% of spawns with zero haiku cost.
#   (b) Novel-task heuristic: if task prompt doesn't mention any
#       role-default path, invoke context-curator via haiku CLI probe.
#       3s timeout, fail-safe allow (empty additionalContext on error).
#
# Opt-out: AIHAUS_CONTEXT_INJECT=0 disables entirely.
# Recursion guard: AIHAUS_HAIKU_CURATOR_ACTIVE=1 (set before haiku call;
#   checked at hook entry) mirrors M011 autonomy-guard.sh shape.
#
# Audit: .claude/audit/context-inject.jsonl (ADR-M011-A rotation).
# Receipts: .claude/audit/memory-read.jsonl (M050/S05, ADR-260611-F) — one row
#   per inlined artifact per spawn; context-inject.sh is the SOLE writer (BR-P5).
# Cache: .claude/audit/context-inject.cache (M016-S07 5-min memoization).
#   Cache key: hash(target_agent_name | cohort_name | task_description).
#   Cache hit skips S05 warning-recurrence read + S06 budget parse.
#   Cache invalidated at milestone close (completion-protocol Step 6.5).
# M050/S05 v2: ONE batched `aihaus memory packet` call (12s internal / 15s
#   settings belt) replaces the M048 two-call path; the aihaus harness is
#   inlined VERBATIM and trim-exempt (ADR-260611-B); F8 yield order governs
#   small budgets (ADR-260611-F); worktree contexts emit context but suppress
#   all writes (ADR-260611-G canary result).
# Architecture ref: M013 architecture.md §2.1, §4.1, §9; M050 architecture.md §2.3/§4/§5.
set -uo pipefail

# ---------------------------------------------------------------------------
# 0. Recursion guard — exit immediately if we're inside a curator invocation
# ---------------------------------------------------------------------------
if [ "${AIHAUS_HAIKU_CURATOR_ACTIVE:-0}" = "1" ]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# 1. Opt-out guard
# ---------------------------------------------------------------------------
if [ "${AIHAUS_CONTEXT_INJECT:-1}" = "0" ]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# 2. Submodule refusal (ADR-001 / architecture §9). NOTE (M050/S05 canary,
#    ADR-260611-G): `git rev-parse --show-superproject-working-tree` returns
#    EMPTY (exit 0) inside a LINKED WORKTREE — this check is a SUBMODULE check
#    and is a confirmed no-op for worktrees (plan B1 misdiagnosis corrected).
#    It stays for its real purpose: refusing to run from a submodule checkout.
#    Worktree handling is section 3b below.
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
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo ".")"
# shellcheck source=lib/path-helpers.sh
. "${SCRIPT_DIR}/lib/path-helpers.sh"
PROJECT_ROOT="$(aihaus_project_root)"

# ---------------------------------------------------------------------------
# 3a. Worktree detection + main-repo anchor rewrite (M050/S05, ADR-260611-G
#     canary branch (a)). Canary facts (live-CC, BR-P9): a worktree-isolated
#     subagent's cwd is <main>/.claude/worktrees/agent-<id>; CLAUDE_PROJECT_DIR
#     is EMPTY in the subagent's own env (aihaus_project_root then falls back
#     to git toplevel / pwd — the worktree path); paths arrive forward-slashed
#     even on Windows Git Bash (backslashes normalized defensively anyway);
#     `git rev-parse --git-common-dir` reliably resolves <main>/.git from
#     inside the worktree (M047-style anchor rewrite). `.aihaus/` is absent in
#     worktrees unless carried via .worktreeinclude (canary branch (b)).
#     In worktree contexts: context IS emitted from main-repo paths, but ALL
#     writes (audit + cache + receipts) are suppressed — single-writer
#     discipline (ADR-001 / BR-P5).
# ---------------------------------------------------------------------------
AIHAUS_INJECT_WORKTREE_CONTEXT=0
_pr_norm="${PROJECT_ROOT//\\//}"
case "$_pr_norm" in
  */.claude/worktrees/*)
    AIHAUS_INJECT_WORKTREE_CONTEXT=1
    _main_root=""
    if command -v git >/dev/null 2>&1; then
      _common_dir="$(git -C "$PROJECT_ROOT" rev-parse --git-common-dir 2>/dev/null || true)"
      _common_dir="${_common_dir//\\//}"
      if [ -n "$_common_dir" ]; then
        if aihaus_is_abs_path "$_common_dir"; then
          _main_root="$(dirname "$_common_dir")"
        else
          # Relative --git-common-dir: resolve against the worktree root.
          _main_root="$(cd "$PROJECT_ROOT/$_common_dir/.." 2>/dev/null && pwd || true)"
        fi
      fi
    fi
    # Fallback: strip everything from /.claude/worktrees/ onward (M047 shape).
    if [ -z "$_main_root" ] || [ ! -d "$_main_root" ]; then
      _main_root="${_pr_norm%%/.claude/worktrees/*}"
    fi
    [ -n "$_main_root" ] && [ -d "$_main_root" ] && PROJECT_ROOT="$_main_root"
    ;;
esac

# Anchor on the (possibly rewritten) PROJECT_ROOT — not on cwd helpers, which
# would re-resolve into the worktree.
_anchor_path() {
  local p="${1:-}"
  if aihaus_is_abs_path "$p"; then printf '%s\n' "$p"; else printf '%s/%s\n' "$PROJECT_ROOT" "$p"; fi
}
AUDIT_LOG="$(_anchor_path "${AIHAUS_CONTEXT_INJECT_LOG:-.claude/audit/context-inject.jsonl}")"
INJECT_CACHE="$(_anchor_path "${AIHAUS_CONTEXT_INJECT_CACHE:-.claude/audit/context-inject.cache}")"
RECEIPTS_LOG="$(_anchor_path "${AIHAUS_MEMORY_READ_LOG:-.claude/audit/memory-read.jsonl}")"
ROLE_DEFAULTS_JSON="${SCRIPT_DIR}/lib/role-defaults.json"
COHORTS_MD_REL=".aihaus/skills/aih-effort/annexes/cohorts.md"
BUDGET_CONF="${SCRIPT_DIR}/context-budget.conf"
AIHAUS_MEMORY_INJECT="${AIHAUS_MEMORY_INJECT:-1}"
AIHAUS_MEMORY_CONTEXT_MAX_BYTES="${AIHAUS_MEMORY_CONTEXT_MAX_BYTES:-6000}"
AIHAUS_MEMORY_QUERY_TOP="${AIHAUS_MEMORY_QUERY_TOP:-3}"

ts_iso() { date -u +%FT%TZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z"; }

# Pure-bash JSON string escape into a named variable — zero forks (M050/S05;
# Windows Git Bash pays ~10-15ms per fork, and receipt rows escape 7 fields
# each). Usage: _jesc <out_var_name> <value>
_jesc() { local s="${2-}"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; printf -v "$1" '%s' "$s"; }

# ---------------------------------------------------------------------------
# 3b. Per-cohort token budget loading (M016-S06)
#     Loads shipped defaults from context-budget.conf, then overlays
#     .aihaus/.context-budgets sidecar (user-owned, never committed).
#     Format (both files): key=value pairs; # comment lines skipped.
#     Sidecar cohort keys: planner-binding=N  (no colon prefix on disk)
#     Sidecar agent keys:  agent:architect=N  (agent: prefix)
#     Missing sidecar = silent skip; unknown cohort = doer default (2500).
# ---------------------------------------------------------------------------
declare -A _CB_COHORT   # cohort-name → token budget
declare -A _CB_AGENT    # agent-name  → token budget override

_load_budget_file() {
  local fpath="$1"
  [ -f "$fpath" ] || return 0
  while IFS= read -r raw_line; do
    # Strip CRLF and leading/trailing whitespace; skip blank + comment lines.
    # Pure-bash trim (M050/S05): the previous sed-per-line forked once per
    # conf line — ~35 lines × 2 files × ~13ms on Windows Git Bash.
    local line="${raw_line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    # Agent override: agent:architect=5000
    if [[ "$line" =~ ^agent:([A-Za-z0-9_-]+)=([0-9]+)$ ]]; then
      _CB_AGENT["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
      continue
    fi
    # Cohort default: planner-binding=4000
    if [[ "$line" =~ ^([a-z-]+)=([0-9]+)$ ]]; then
      _CB_COHORT["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
    fi
  done < "$fpath"
}

# Load shipped defaults first.
_load_budget_file "$BUDGET_CONF"

# Overlay user sidecar (wins over defaults).
_SIDECAR_BUDGETS=""
for _cand in \
  "${CLAUDE_PROJECT_DIR:-.}/.aihaus/.context-budgets" \
  "$(git rev-parse --show-toplevel 2>/dev/null || echo ".")/.aihaus/.context-budgets"; do
  if [ -f "$_cand" ]; then
    _SIDECAR_BUDGETS="$_cand"
    break
  fi
done
[ -n "$_SIDECAR_BUDGETS" ] && _load_budget_file "$_SIDECAR_BUDGETS"

# Resolve budget for a given agent + cohort (strips leading colon from cohort).
_resolve_budget() {
  local agent_nm="$1" cohort_nm="$2"
  # Per-agent override wins (guard: skip empty name to avoid bad subscript).
  if [[ -n "$agent_nm" ]] && [[ -n "${_CB_AGENT[$agent_nm]:-}" ]]; then
    echo "${_CB_AGENT[$agent_nm]}"
    return
  fi
  # Strip leading colon from cohort name (e.g. :doer → doer).
  local cohort_key="${cohort_nm#:}"
  if [[ -n "${_CB_COHORT[$cohort_key]:-}" ]]; then
    echo "${_CB_COHORT[$cohort_key]}"
    return
  fi
  # Unknown cohort: default to doer (2500).
  echo "2500"
}

# ---------------------------------------------------------------------------
# 4. Audit JSONL write with rotation (ADR-M011-A)
# ---------------------------------------------------------------------------
_rotate_audit_if_needed() {
  [ -f "$AUDIT_LOG" ] || return 0
  local bytes lines
  bytes="$(stat -c%s "$AUDIT_LOG" 2>/dev/null || stat -f%z "$AUDIT_LOG" 2>/dev/null || echo 0)"
  if [ "$bytes" -ge 10485760 ]; then
    mv -f "$AUDIT_LOG" "$AUDIT_LOG.old" 2>/dev/null || true
    return 0
  fi
  lines="$(wc -l < "$AUDIT_LOG" 2>/dev/null | tr -d ' ')"
  if [ -n "$lines" ] && [ "$lines" -ge 10000 ]; then
    mv -f "$AUDIT_LOG" "$AUDIT_LOG.old" 2>/dev/null || true
  fi
}

_write_audit() {
  # M050/S05: suppressed entirely in worktree contexts — the orchestrator
  # process is the sole writer of this JSONL (ADR-001 / BR-P5 / ADR-260611-G).
  [ "$AIHAUS_INJECT_WORKTREE_CONTEXT" = "1" ] && return 0
  local target_agent="$1" cohort="$2" static_or_haiku="$3" \
        payload_bytes="$4" truncated="$5" duration_ms="$6" \
        milestone="${7:-}" story="${8:-}" cache_hit="${9:-false}" \
        memory_packet="${10:-skipped}"
  mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || return 0
  _rotate_audit_if_needed
  local ts; ts="$(ts_iso)"
  # Escape quotes in string fields (fork-free _jesc, M050/S05).
  local e_ms e_st e_ag e_co e_sh e_mp
  _jesc e_ms "$milestone"; _jesc e_st "$story"; _jesc e_ag "$target_agent"
  _jesc e_co "$cohort"; _jesc e_sh "$static_or_haiku"; _jesc e_mp "$memory_packet"
  # memory_packet (M050/S02; real single-call outcome since M050/S05):
  # "present" when the batched memory packet made it into the payload, else
  # "skipped". context-inject.sh remains the sole writer (BR-P5/ADR-001).
  printf '{"ts":"%s","milestone":"%s","story":"%s","target_agent":"%s","cohort":"%s","static_or_haiku":"%s","payload_bytes":%s,"truncated":"%s","duration_ms":%s,"cache_hit":%s,"memory_packet":"%s"}\n' \
    "$ts" "$e_ms" "$e_st" "$e_ag" "$e_co" "$e_sh" \
    "${payload_bytes:-0}" "${truncated:-false}" "${duration_ms:-0}" \
    "${cache_hit}" "$e_mp" \
    >> "$AUDIT_LOG" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# 4a. Injection receipts (M050/S05, ADR-260611-F) — one JSONL row per inlined
#     artifact per spawn → .claude/audit/memory-read.jsonl.
#     context-inject.sh is the SOLE writer of this file (BR-P5; S08's
#     memory-read-audit.sh reads it and writes verdicts to its OWN JSONL).
#     Suppressed entirely in worktree contexts (ADR-260611-G).
# ---------------------------------------------------------------------------
_rotate_receipts_if_needed() {
  [ -f "$RECEIPTS_LOG" ] || return 0
  local bytes lines
  bytes="$(stat -c%s "$RECEIPTS_LOG" 2>/dev/null || stat -f%z "$RECEIPTS_LOG" 2>/dev/null || echo 0)"
  if [ "$bytes" -ge 10485760 ]; then
    mv -f "$RECEIPTS_LOG" "$RECEIPTS_LOG.old" 2>/dev/null || true
    return 0
  fi
  lines="$(wc -l < "$RECEIPTS_LOG" 2>/dev/null | tr -d ' ')"
  if [ -n "$lines" ] && [ "$lines" -ge 10000 ]; then
    mv -f "$RECEIPTS_LOG" "$RECEIPTS_LOG.old" 2>/dev/null || true
  fi
}

_RECEIPT_TS=""

_write_receipt() {
  [ "$AIHAUS_INJECT_WORKTREE_CONTEXT" = "1" ] && return 0
  local artifact="$1" source_path="$2" bytes="${3:-0}" r_truncated="${4:-false}"
  mkdir -p "$(dirname "$RECEIPTS_LOG")" 2>/dev/null || return 0
  _rotate_receipts_if_needed
  # One ts_iso fork per spawn, not per row (M050/S05 Windows fork economy).
  [ -z "$_RECEIPT_TS" ] && _RECEIPT_TS="$(ts_iso)"
  local e_ag e_co e_ar e_sp e_mp e_ya e_se
  _jesc e_ag "${target_agent_name:-}"; _jesc e_co "${cohort:-}"
  _jesc e_ar "$artifact"; _jesc e_sp "$source_path"
  _jesc e_mp "${memory_packet:-skipped}"; _jesc e_ya "${yield_applied:-none}"
  _jesc e_se "${session_id:-}"
  printf '{"ts":"%s","event":"inject-receipt","agent":"%s","cohort":"%s","artifact":"%s","source":"%s","bytes":%s,"truncated":%s,"memory_packet":"%s","budget_tokens":%s,"yield_applied":"%s","session":"%s"}\n' \
    "$_RECEIPT_TS" "$e_ag" "$e_co" "$e_ar" "$e_sp" "${bytes}" "${r_truncated}" \
    "$e_mp" "${token_budget:-0}" "$e_ya" "$e_se" \
    >> "$RECEIPTS_LOG" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# 4b. Cache helpers (M016-S07 — 5-min hash cache for context-inject)
#     Byte-identical transplant from learning-advisor.sh compute_hash +
#     append_cache_entry; variable names changed: ADVISOR_* → INJECT_*.
#     Cache key: hash(target_agent_name | cohort_name | task_description).
#     Cache file: .claude/audit/context-inject.cache
#     Cache row:  <unix_ts>|<hash>|<base64-encoded-payload>
#     Rotation:   10 KB OR 100 lines (lighter than 10 MB/10000 in advisor)
# ---------------------------------------------------------------------------
compute_hash() {
  local combined="${target_agent_name:-}|${cohort:-}|${_active_profile:-}|${task_description:-}"
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$combined" | sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s' "$combined" | shasum -a 256 | awk '{print $1}'
  else
    printf '%s' "$combined" | md5sum 2>/dev/null | awk '{print $1}' || printf 'nohash'
  fi
}

append_cache_entry() {
  # M050/S05: suppressed in worktree contexts (ADR-001 / ADR-260611-G).
  [ "$AIHAUS_INJECT_WORKTREE_CONTEXT" = "1" ] && return 0
  local entry="$1"
  mkdir -p "$(dirname "$INJECT_CACHE")" 2>/dev/null || return 0
  local now; now="$(date +%s 2>/dev/null || echo 0)"
  if [ -f "$INJECT_CACHE" ]; then
    local tmp="${INJECT_CACHE}.tmp.$$"
    awk -F'|' -v now="$now" 'NF>=1 && (now - ($1+0)) <= 300 {print}' "$INJECT_CACHE" > "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$INJECT_CACHE" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  fi
  printf '%s\n' "$entry" >> "$INJECT_CACHE" 2>/dev/null || true
}

_rotate_cache_if_needed() {
  # M050/S05: rotation is a write — suppressed in worktree contexts.
  [ "$AIHAUS_INJECT_WORKTREE_CONTEXT" = "1" ] && return 0
  [ -f "$INJECT_CACHE" ] || return 0
  local bytes lines
  bytes="$(stat -c%s "$INJECT_CACHE" 2>/dev/null || stat -f%z "$INJECT_CACHE" 2>/dev/null || echo 0)"
  if [ "$bytes" -ge 10240 ]; then
    mv -f "$INJECT_CACHE" "${INJECT_CACHE}.old" 2>/dev/null || true
    return 0
  fi
  lines="$(wc -l < "$INJECT_CACHE" 2>/dev/null | tr -d ' ')"
  if [ -n "$lines" ] && [ "$lines" -ge 100 ]; then
    mv -f "$INJECT_CACHE" "${INJECT_CACHE}.old" 2>/dev/null || true
  fi
}

# ---------------------------------------------------------------------------
# 5. Parse SubagentStart payload from stdin
# ---------------------------------------------------------------------------
INPUT="$(cat)"
task_description=""
target_agent_name=""
session_id=""

if command -v jq >/dev/null 2>&1; then
  task_description="$(printf '%s' "$INPUT" | jq -r '
    .hook_input.task_description //
    .task_description //
    .agent_task //
    empty
  ' 2>/dev/null || echo "")"
  target_agent_name="$(printf '%s' "$INPUT" | jq -r '
    .hook_input.agent_name //
    .agent_name //
    .name //
    empty
  ' 2>/dev/null || echo "")"
  session_id="$(printf '%s' "$INPUT" | jq -r '
    .session_id //
    .hook_input.session_id //
    empty
  ' 2>/dev/null || echo "")"
fi
# Fallback: grep from raw JSON when jq unavailable or returns empty.
[ -z "$task_description" ] && task_description="$(printf '%s' "$INPUT" | grep -o '"task_description":"[^"]*"' | head -1 | sed 's/.*":"\(.*\)"/\1/' 2>/dev/null || echo "")"
[ -z "$target_agent_name" ] && target_agent_name="$(printf '%s' "$INPUT" | grep -o '"agent_name":"[^"]*"' | head -1 | sed 's/.*":"\(.*\)"/\1/' 2>/dev/null || echo "")"
[ -z "$session_id" ] && session_id="$(printf '%s' "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/.*":"\(.*\)"/\1/' 2>/dev/null || echo "")"

# Extract optional milestone_dir and story_id from task description heuristics.
milestone_dir=""
story_id=""
if [ -n "$task_description" ]; then
  milestone_dir="$(printf '%s' "$task_description" | grep -oE '\.aihaus/milestones/M[0-9]+-[^ ]+' | head -1 2>/dev/null || echo "")"
  story_id="$(printf '%s' "$task_description" | grep -oE '\bS[0-9]+\b' | head -1 2>/dev/null || echo "")"
fi

# ---------------------------------------------------------------------------
# 6. Resolve target_agent → cohort (reads cohorts.md 5-column table)
# ---------------------------------------------------------------------------
_resolve_cohort() {
  local agent_name="$1"
  # Try to find cohorts.md relative to PROJECT_ROOT or from script location.
  local cohorts_md=""
  # Try common locations.
  for candidate in \
    "${CLAUDE_PROJECT_DIR:-.}/${COHORTS_MD_REL}" \
    "$(git rev-parse --show-toplevel 2>/dev/null || echo ".")/${COHORTS_MD_REL}" \
    "$(dirname "$SCRIPT_DIR")/${COHORTS_MD_REL}" \
    "$(dirname "$SCRIPT_DIR")/${COHORTS_MD_REL#.aihaus/}"; do
    if [ -f "$candidate" ]; then
      cohorts_md="$candidate"
      break
    fi
  done
  [ -z "$cohorts_md" ] && { echo ""; return; }

  # Parse 5-column table: NF=7 per F-006 (ADR-M012-A parse contract).
  awk -F'|' -v agent="$agent_name" '
    NF==7 {
      a=substr($3,1); gsub(/^[[:space:]]+|[[:space:]]+$/,"",a)
      c=substr($4,1); gsub(/^[[:space:]]+|[[:space:]]+$/,"",c)
      if (a==agent) { print c; exit }
    }
  ' "$cohorts_md" 2>/dev/null || echo ""
}

cohort="$(_resolve_cohort "$target_agent_name")"
# Default to :doer if cohort cannot be resolved.
[ -z "$cohort" ] && cohort=":doer"

# Resolve active profile (role-scoped context, S4). Folded into the cache key
# below so builder/devops never share a cached payload — the online env must
# never leak into a non-devops profile's context.
_active_profile=""
_profile_file_early="$(aihaus_project_path ".aihaus/.profile" 2>/dev/null || echo "")"
if [ -n "$_profile_file_early" ] && [ -f "$_profile_file_early" ]; then
  _active_profile="$(tr ',' ' ' < "$_profile_file_early" 2>/dev/null | tr -s '[:space:]' ' ' | sed 's/^ *//; s/ *$//')"
fi

# ---------------------------------------------------------------------------
# 6b. Cache lookup (M016-S07) — cache key: hash(target_agent_name | cohort | task)
#     Hit: skip S05 warning-recurrence read + S06 budget parse; emit cached
#          payload directly and exit.  Miss: fall through to full S05+S06 path.
# ---------------------------------------------------------------------------
_inject_cache_hit="false"
_inject_cache_payload=""
INJECT_MSG_HASH="$(compute_hash)"
_inject_now_unix="$(date +%s 2>/dev/null || echo 0)"
_rotate_cache_if_needed
[ "$AIHAUS_INJECT_WORKTREE_CONTEXT" = "1" ] || mkdir -p "$(dirname "$INJECT_CACHE")" 2>/dev/null || true

if [ -f "$INJECT_CACHE" ]; then
  while IFS='|' read -r c_ts c_hash c_payload_b64; do
    [ -z "$c_ts" ] && continue
    _inject_age=$(( _inject_now_unix - c_ts ))
    if [ "$_inject_age" -le 300 ] && [ "$c_hash" = "$INJECT_MSG_HASH" ]; then
      _inject_cache_hit="true"
      # Decode base64 payload; fall back to empty string on decode failure.
      if command -v base64 >/dev/null 2>&1; then
        _inject_cache_payload="$(printf '%s' "$c_payload_b64" | base64 -d 2>/dev/null || echo "")"
      fi
      break
    fi
  done < "$INJECT_CACHE"
fi

if [ "$_inject_cache_hit" = "true" ] && [ -n "$_inject_cache_payload" ]; then
  # M050/S05 receipts on cache-hit: intentionally NOT re-written. The original
  # assembly (≤5 min ago, same hash key) already wrote one receipt row per
  # artifact; the audit row below records cache_hit=true for the join.
  # memory_packet on cache-hit: no memory CLI call happens this invocation;
  # derive from whether the cached payload carries the M048 packet marker.
  _cache_memory_packet="skipped"
  case "$_inject_cache_payload" in
    *"Native repository memory (auto-injected, M048)"*) _cache_memory_packet="present" ;;
  esac
  _write_audit "$target_agent_name" "$cohort" "cache-hit" \
    "${#_inject_cache_payload}" "false" "0" \
    "$(basename "${milestone_dir:-}")" "$story_id" "true" "$_cache_memory_packet"
  # Emit cached payload directly.
  if command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
    py_bin="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || echo "")"
    if [ -n "$py_bin" ]; then
      "$py_bin" - "$_inject_cache_payload" <<'PYEOF' 2>/dev/null
import json, sys
ctx = sys.argv[1]
out = {"hookSpecificOutput": {"hookEventName": "SubagentStart", "additionalContext": ctx}}
print(json.dumps(out))
PYEOF
      exit 0
    fi
  fi
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg ctx "$_inject_cache_payload" \
      '{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":$ctx}}'
    exit 0
  fi
  ctx_escaped="$(printf '%s' "$_inject_cache_payload" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | awk '{printf "%s\\n", $0}' | sed '$ s/\\n$//')"
  printf '{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"%s"}}\n' "$ctx_escaped"
  exit 0
fi

# ---------------------------------------------------------------------------
# 6c. Native repository memory packet (M048)
#     Subagents should not depend on the human remembering to call memory.
#     This hook injects a bounded, best-effort `aihaus memory ... --json`
#     packet before the agent starts. The role prompt may still run targeted
#     follow-up memory commands when this packet is not enough.
# ---------------------------------------------------------------------------
declare -a AIHAUS_MEMORY_CMD=()

_cap_text() {
  local max_bytes="${1:-6000}"
  local text
  text="$(cat)"
  if [ "${#text}" -le "$max_bytes" ]; then
    printf '%s' "$text"
    return
  fi
  printf '%s' "$text" | head -c "$max_bytes"
  printf '\n... [truncated by context-inject.sh]\n'
}

_resolve_aihaus_memory_cmd() {
  # M050/S05: the registry/AIHAUS_HOME-resolved shim is trusted FIRST; a PATH
  # `aihaus` is only the last resort. Field evidence (S05 dogfood): an
  # unrelated npm package also installs an `aihaus` bin — trusting PATH first
  # burned the full packet timeout on every spawn.
  AIHAUS_MEMORY_CMD=()

  local roots=() reg root pkg_candidate
  [[ -n "${AIHAUS_HOME:-}" ]] && roots+=("$AIHAUS_HOME")
  reg="$HOME/.aihaus/.install-source"
  if [[ -f "$reg" ]]; then
    root="$(head -n1 "$reg" | tr -d '[:space:]' 2>/dev/null || true)"
    [[ -n "$root" ]] && roots+=("$root")
  fi
  roots+=("$PROJECT_ROOT")
  pkg_candidate="$(cd "$SCRIPT_DIR/../.." 2>/dev/null && pwd || true)"
  [[ -n "$pkg_candidate" ]] && roots+=("$pkg_candidate")
  pkg_candidate="$(cd "$SCRIPT_DIR/../../.." 2>/dev/null && pwd || true)"
  [[ -n "$pkg_candidate" ]] && roots+=("$pkg_candidate")

  for root in "${roots[@]}"; do
    [[ -z "$root" ]] && continue
    if [[ -f "$root/pkg/scripts/aihaus" ]]; then
      export AIHAUS_HOME="$root"
      AIHAUS_MEMORY_CMD=(bash "$root/pkg/scripts/aihaus" memory)
      return 0
    fi
    if [[ -f "$root/scripts/aihaus" ]]; then
      export AIHAUS_HOME="$(cd "$root/.." 2>/dev/null && pwd || echo "$root")"
      AIHAUS_MEMORY_CMD=(bash "$root/scripts/aihaus" memory)
      return 0
    fi
  done

  if command -v aihaus >/dev/null 2>&1; then
    AIHAUS_MEMORY_CMD=(aihaus memory)
    return 0
  fi
  return 1
}

_run_memory_with_timeout() {
  # M050/S05: 12s internal timeout sized to the SINGLE batched packet call
  # (was 2×8s in the M048 two-call path — the structural 19s-vs-10s overrun).
  # Settings belt: 15s on the SubagentStart hook entry.
  if command -v timeout >/dev/null 2>&1; then
    timeout 12s "${AIHAUS_MEMORY_CMD[@]}" "$@"
  else
    "${AIHAUS_MEMORY_CMD[@]}" "$@"
  fi
}

# M050/S05: ONE batched `aihaus memory packet` call replaces the M048
# status+query pair. Fetch and framing are split so the F8 yield order can
# re-frame the same packet under a smaller cap (6KB → 2KB) without a refetch.
MEMORY_PACKET_JSON=""
MEMORY_PACKET_QUERY=""
MEMORY_PACKET_SOURCE=""

_fetch_memory_packet() {
  [ "$AIHAUS_MEMORY_INJECT" = "0" ] && return 0
  _resolve_aihaus_memory_cmd || return 0

  local query_text packet_json
  local db_args=()
  if [[ -n "${AIH_GRAPH_DB:-}" ]]; then
    db_args+=(--db "$AIH_GRAPH_DB")
    MEMORY_PACKET_SOURCE="$AIH_GRAPH_DB"
  else
    local default_db="$PROJECT_ROOT/.aihaus/state/aih-graph.db"
    [ "$AIHAUS_INJECT_WORKTREE_CONTEXT" = "1" ] || mkdir -p "$(dirname "$default_db")" 2>/dev/null || true
    db_args+=(--db "$default_db")
    MEMORY_PACKET_SOURCE="$default_db"
  fi
  query_text="${task_description:-${target_agent_name:-repository context}}"
  query_text="$(printf '%s' "$query_text" | tr '\n' ' ' | head -c 600)"
  MEMORY_PACKET_QUERY="$query_text"

  packet_json="$(_run_memory_with_timeout packet --repo "$PROJECT_ROOT" "${db_args[@]}" --task "$query_text" --json 2>/dev/null || true)"

  # Packet failure/timeout → fail-open: section stays empty, the audit row
  # reports memory_packet: skipped (BR-P4 — degradation, never silence).
  case "$packet_json" in
    "{"*) MEMORY_PACKET_JSON="$packet_json" ;;
    *) return 0 ;;
  esac
}

_frame_memory_section() {
  local cap="${1:-$AIHAUS_MEMORY_CONTEXT_MAX_BYTES}"
  [ -z "$MEMORY_PACKET_JSON" ] && return 0
  local body
  body="$(printf '%s' "$MEMORY_PACKET_JSON" | _cap_text "$cap")"
  cat <<EOF

## Native repository memory (auto-injected, M048)

This memory packet was loaded automatically by context-inject.sh (M050/S05: one batched \`aihaus memory packet\` call — status + Rule/Decision slice + top matches). Use targeted \`aihaus memory ... --json\` only when this packet is insufficient.

Query: ${MEMORY_PACKET_QUERY}

Packet:
\`\`\`json
${body}
\`\`\`
EOF
}

# ---------------------------------------------------------------------------
# 6c-bis. aihaus harness inline (M050/S05, ADR-260611-B/F)
#     The harness body is inlined VERBATIM (MAIN-SESSION-ONLY span stripped —
#     the orchestrator-routing lines are meaningless inside a subagent) as a
#     trim-exempt section. The harness NEVER yields to budget pressure (F8).
# ---------------------------------------------------------------------------
HARNESS_SOURCE_PATH=""

_resolve_harness_path() {  # sets HARNESS_SOURCE_PATH (runs in main shell)
  local cand
  for cand in \
    "$(dirname "$SCRIPT_DIR")/protocols/harness.md" \
    "$PROJECT_ROOT/.aihaus/protocols/harness.md" \
    "$PROJECT_ROOT/pkg/.aihaus/protocols/harness.md"; do
    [ -f "$cand" ] && { HARNESS_SOURCE_PATH="$cand"; return 0; }
  done
  return 0
}

_build_harness_section() {
  [ -z "$HARNESS_SOURCE_PATH" ] && return 0
  local body
  # Span-delete the <!-- MAIN-SESSION-ONLY --> fence (inverted ensure_block()
  # awk technique per ADR-260611-B), then cap at the 2048B harness byte cap.
  body="$(awk '
    /<!-- MAIN-SESSION-ONLY -->/ { skip=1; next }
    /<!-- \/MAIN-SESSION-ONLY -->/ { skip=0; next }
    !skip { print }
  ' "$HARNESS_SOURCE_PATH" 2>/dev/null | _cap_text 2048)"
  [ -z "$(printf '%s' "$body" | tr -d '[:space:]')" ] && return 0
  cat <<EOF

## aihaus harness (auto-injected, M050 — binding; never trimmed)

${body}
EOF
}

# ---------------------------------------------------------------------------
# 7. Static role-default map lookup
# ---------------------------------------------------------------------------
_get_static_paths() {
  local cohort_key="$1"
  [ -f "$ROLE_DEFAULTS_JSON" ] || { echo ""; return; }

  if command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
    local py_bin
    py_bin="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || echo "")"
    [ -z "$py_bin" ] && { echo ""; return; }
    "$py_bin" - "$ROLE_DEFAULTS_JSON" "$cohort_key" <<'PYEOF' 2>/dev/null
import json, sys
f, key = sys.argv[1], sys.argv[2]
with open(f, encoding='utf-8') as fh:
    d = json.load(fh)
entries = d.get(key)
if entries is None and key.startswith(':adversarial'):
    # M050/S02: merged :adversarial cohort (M027/ADR-260509-Y) must resolve
    # even against a stale role-defaults.json still carrying the pre-M027
    # :adversarial-scout/:adversarial-review keys (and vice versa). Never
    # fall through to :doer for adversarial agents.
    for alias in (':adversarial', ':adversarial-review', ':adversarial-scout'):
        entries = d.get(alias)
        if entries is not None:
            break
if entries is None:
    entries = d.get(':doer', [])
for e in entries:
    tier = e.get('tier','MED')
    path = e.get('path','')
    rationale = e.get('rationale','')
    print(f"{tier}:{path} — {rationale}")
PYEOF
  elif command -v jq >/dev/null 2>&1; then
    # M050/S02: same merged-:adversarial fall-through as the python path —
    # legacy pre-M027 keys resolve before the :doer default, both directions.
    jq -r --arg k "$cohort_key" '
      (.[$k] //
        (if ($k | startswith(":adversarial"))
         then (.[":adversarial"] // .[":adversarial-review"] // .[":adversarial-scout"])
         else null end) //
        .[":doer"] // []) |
      .[] |
      (.tier + ":" + .path + " — " + .rationale)
    ' "$ROLE_DEFAULTS_JSON" 2>/dev/null
  else
    echo ""
  fi
}

static_lines="$(_get_static_paths "$cohort")"

# ---------------------------------------------------------------------------
# 8. Novel-task heuristic: does the task prompt already reference any
#    of the role-default paths? If yes → static path (haiku not needed).
# ---------------------------------------------------------------------------
_is_novel_task() {
  local task="$1" defaults="$2"
  # Novel if task mentions none of the default paths.
  # M050/S05: pure-bash extraction — the previous sed pattern keyed on the
  # em-dash separator, whose byte encoding differs between the script (UTF-8)
  # and Windows python pipe output (cp1252), so it never matched on Windows
  # and the haiku probe fired on EVERY spawn (+3-4s). The path has no spaces,
  # so splitting at the first space is encoding-immune (and fork-free).
  local novel=1 line path_part base
  local task_lc="${task,,}"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    # Extract path portion: strip rationale (first space) then TIER: prefix.
    path_part="${line%% *}"
    path_part="${path_part#*:}"
    [ -z "$path_part" ] && continue
    # Strip template tokens.
    [[ "$path_part" == *"<"* ]] && continue
    # Check if path basename appears in task description (case-insensitive).
    base="${path_part##*/}"
    [ -z "$base" ] && continue
    if [[ "$task_lc" == *"${base,,}"* ]]; then
      novel=0
      break
    fi
  done <<< "$defaults"
  echo "$novel"
}

novel_task="0"
[ -n "$task_description" ] && novel_task="$(_is_novel_task "$task_description" "$static_lines")"

# ---------------------------------------------------------------------------
# 8b. Recurring-warnings feedback loop (M016-S05)
#     Reads .claude/audit/warning-recurrence.jsonl (written by S03/warning-
#     recurrence-tracker.sh). Filters rows with recurrence_count >= 3.
#     Builds a labeled section injected into the pre-spawn context payload.
#     Graceful degradation: file absent / empty / jq missing → skip silently.
#     No new audit write — preserves ADR-M013-A single-writer discipline.
# ---------------------------------------------------------------------------
RECURRENCE_LOG="$(_anchor_path ".claude/audit/warning-recurrence.jsonl")"
recurring_warnings_section=""
if [ -f "$RECURRENCE_LOG" ] && command -v jq >/dev/null 2>&1; then
  # Build bullets: one per qualifying row, grouped by source_agent annotation.
  # Format: "- [<category>] <source_agent>: <summary truncated to 120 chars>"
  RECURRING_BULLETS="$(jq -r '
    select(.recurrence_count >= 3) |
    "- [" + (.category // "unknown") + "] " +
    (.source_agent // "unknown") + ": " +
    ((.summary // "") | .[0:120])
  ' "$RECURRENCE_LOG" 2>/dev/null || true)"
  if [ -n "$RECURRING_BULLETS" ]; then
    recurring_warnings_section="$(printf '\n## Recurring warnings (>=3 occurrences)\n%s' "$RECURRING_BULLETS")"
  fi
fi

# ---------------------------------------------------------------------------
# 9. Haiku delta path (novel tasks only)
# ---------------------------------------------------------------------------
haiku_lines=""
path_method="static"
start_ms="$(date +%s%3N 2>/dev/null || echo 0)"

if [ "$novel_task" = "1" ] && command -v claude >/dev/null 2>&1 && [ -n "$task_description" ]; then
  export AIHAUS_HAIKU_CURATOR_ACTIVE=1
  path_method="haiku"

  task_trunc="$(printf '%s' "$task_description" | head -c 1500)"
  cohorts_summary=":planner-binding->project.md,protocols,business-rules,environment,user-preferences,analysis-brief  :planner->project.md,protocols,business-rules,environment,user-preferences  :doer->project.md,protocols,business-rules,environment,user-preferences,story-file  :verifier->project.md,protocols,business-rules,environment,user-preferences,story-file,execution  :adversarial->project.md,protocols,business-rules,environment,user-preferences,story-file,review-memory"

  PROMPT="$(cat <<EOF
SYSTEM: You are context-curator for the aihaus milestone system.
Output ONLY a line list in format TIER:path — rationale.
Max 12 lines. Max 200 tokens. No prose. No headers. No code blocks.

USER:
target_agent: ${target_agent_name:-unknown}
cohort: ${cohort}
task: ${task_trunc}
cohort_defaults: ${cohorts_summary}

Emit additional HIGH/MED/LOW paths beyond the cohort defaults if the task
mentions specific subsystems, files, or domains. Merge static defaults first.
Output only the line list.
EOF
)"

  if command -v timeout >/dev/null 2>&1; then
    haiku_lines="$(printf '%s' "$PROMPT" | timeout 3s claude --print --model haiku-4.5 2>/dev/null || true)"
  else
    haiku_lines="$(printf '%s' "$PROMPT" | claude --print --model haiku-4.5 2>/dev/null || true)"
  fi

  export -n AIHAUS_HAIKU_CURATOR_ACTIVE 2>/dev/null || true
fi

end_ms="$(date +%s%3N 2>/dev/null || echo 0)"
duration_ms=$(( end_ms - start_ms ))
[ "$duration_ms" -lt 0 ] && duration_ms=0

# ---------------------------------------------------------------------------
# 10. Resolve template tokens in static_lines (e.g. <story-file>)
# ---------------------------------------------------------------------------
_resolve_templates() {
  local lines="$1" m_dir="$2" s_id="$3"
  local out=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    # M050/S05: pure-bash token tests (each grep forked a process per line on
    # Windows Git Bash; ~10-15ms each across 3 tokens × N lines).
    # Resolve <story-file>
    if [[ "$line" == *'<story-file>'* ]]; then
      if [ -n "$m_dir" ] && [ -n "$s_id" ]; then
        local sf="${m_dir}/stories/${s_id}.md"
        line="${line//<story-file>/$sf}"
      else
        line="${line//<story-file>/.aihaus/milestones/<milestone>/stories/<story>.md}"
      fi
    fi
    # Resolve <analysis-brief>
    if [[ "$line" == *'<analysis-brief>'* ]]; then
      if [ -n "$m_dir" ]; then
        line="${line//<analysis-brief>/${m_dir}/execution/analysis-brief.md}"
      else
        line="${line//<analysis-brief>/.aihaus/milestones/<milestone>/execution/analysis-brief.md}"
      fi
    fi
    # Resolve <execution-dir>
    if [[ "$line" == *'<execution-dir>'* ]]; then
      if [ -n "$m_dir" ]; then
        line="${line//<execution-dir>/${m_dir}/execution/}"
      else
        line="${line//<execution-dir>/.aihaus/milestones/<milestone>/execution/}"
      fi
    fi
    out="${out}${line}
"
  done <<< "$lines"
  printf '%s' "$out"
}

resolved_static="$(_resolve_templates "$static_lines" "$milestone_dir" "$story_id")"

# ---------------------------------------------------------------------------
# 11. Merge static + haiku lines; deduplicate; cap at 12 lines
# ---------------------------------------------------------------------------
_merge_and_cap() {
  local static_l="$1" haiku_l="$2"
  local seen=() merged=""
  local count=0

  _add_line() {
    local l="$1"
    [ -z "$l" ] && return
    [ "$count" -ge 12 ] && return
    # M050/S05: pure-bash path-key extraction (encoding-immune, fork-free —
    # same defect class as _is_novel_task: sed keyed on the em-dash byte).
    local path_key="${l%% *}"
    path_key="${path_key#*:}"
    [ -z "$path_key" ] && path_key="$l"
    for s in "${seen[@]:-}"; do [ "$s" = "$path_key" ] && return; done
    seen+=("$path_key")
    merged="${merged}${l}
"
    count=$(( count + 1 ))
  }

  # Static lines first (higher priority).
  while IFS= read -r line; do _add_line "$line"; done <<< "$static_l"
  # Haiku delta lines supplement.
  while IFS= read -r line; do _add_line "$line"; done <<< "$haiku_l"

  printf '%s' "$merged"
}

payload_lines="$(_merge_and_cap "$resolved_static" "$haiku_lines")"

# Fallback to universal minimum if empty.
if [ -z "$(printf '%s' "$payload_lines" | tr -d '[:space:]')" ]; then
  payload_lines="HIGH:.aihaus/project.md - Stack and conventions are required context.
HIGH:.aihaus/protocols/default.md - Workflow gates and protocols are required context.
HIGH:.aihaus/protocols/routing.md - Intent routing decides workflow entry or no-workflow handling.
HIGH:.aihaus/memory/workflows/business-rules.md - Business rules are the repository behavior contract.
HIGH:.aihaus/memory/workflows/environment.md - Runtime, CI/CD, credential locations, and validation commands are required context.
MED:.aihaus/memory/workflows/user-preferences.md - Repository-scoped user preferences shape execution and reporting.
MED:.aihaus/memory/MEMORY.md - Agent memory index for cross-task context."
  path_method="fallback"
fi

# Role-scoped online env (S4): only profiles holding `devops` get the online
# (staging/prod) env pointer. Keeps online URLs/credential locations out of
# builder/dev/qa agent context (reinforces the role-guard online boundary).
# Uses _active_profile resolved above (also folded into the cache key).
case " ${_active_profile:-} " in
  *" devops "*)
    payload_lines="${payload_lines}
HIGH:.aihaus/memory/local/environment-online.md — Online (staging/prod) env: deploy URLs, promote/rollback commands, credential locations. devops-scoped."
    ;;
esac

# M050/S05: single batched packet fetch (one `aihaus memory packet` call).
_fetch_memory_packet
memory_context_section="$(_frame_memory_section "$AIHAUS_MEMORY_CONTEXT_MAX_BYTES")"
# memory_packet (M050/S02, real single-call outcome since S05): "present" iff
# the batched packet call produced a JSON payload; every failure/timeout/
# opt-out path leaves it empty -> "skipped" (fail-open, exit 0 — BR-P4).
memory_packet="skipped"
[ -n "$memory_context_section" ] && memory_packet="present"
[ -n "$memory_context_section" ] && memory_context_section="${memory_context_section}"$'\n'

# M050/S05: aihaus harness — verbatim, trim-exempt (ADR-260611-B).
_resolve_harness_path
harness_section="$(_build_harness_section)"
[ -n "$harness_section" ] && harness_section="${harness_section}"$'\n'

# Tier-C user-preferences excerpt (M050/S06, ADR-260611-E/F): reads the repo
# mirror (.aihaus/memory/local/user-preferences-global.md, regenerated by
# project-context-refresh.sh on its 900s cadence) first, falling back to the
# global file (~/.aihaus/memory/user/preferences.md) direct. Emitted only when
# at least one real `- PREF-` entry exists (a pristine template is noise, not
# signal). Capped so the whole section stays ≤1.5KB (1536B). It is the FIRST
# F8 yield victim (ADR-260611-F §4) — dropped before the packet shrinks, and
# always before the harness, which never yields.
TIER_C_SOURCE_PATH=""

_resolve_tier_c_path() {  # sets TIER_C_SOURCE_PATH (runs in main shell — the
                          # harness _resolve/_build split avoids the subshell
                          # variable-loss trap of command substitution)
  local cand
  for cand in \
    "$PROJECT_ROOT/.aihaus/memory/local/user-preferences-global.md" \
    "$HOME/.aihaus/memory/user/preferences.md"; do
    if [ -f "$cand" ] && grep -q '^- PREF-[0-9]' "$cand" 2>/dev/null; then
      # Only inline when a real entry exists (entry grammar: `- PREF-<n> ...`);
      # a pristine seeded template is noise, not signal.
      TIER_C_SOURCE_PATH="$cand"
      return 0
    fi
  done
  return 0
}

_build_tier_c_excerpt() {
  [ -z "$TIER_C_SOURCE_PATH" ] && return 0
  local body
  # Extract the AIHAUS:PREFS-START/END marker span (entries only — template
  # header prose is boilerplate); fall back to the whole file if unmarked.
  body="$(awk '
    index($0, "<!-- AIHAUS:PREFS-START -->") > 0 { inside=1; next }
    index($0, "<!-- AIHAUS:PREFS-END -->") > 0 { inside=0; next }
    inside { print }
  ' "$TIER_C_SOURCE_PATH" 2>/dev/null)"
  [ -z "$(printf '%s' "$body" | tr -d '[:space:]')" ] && body="$(cat "$TIER_C_SOURCE_PATH" 2>/dev/null)"
  # Cap body at 1400B: header line (~90B) + truncation marker (~40B) keep the
  # emitted section under the 1536B (1.5KB) excerpt cap on every path.
  body="$(printf '%s' "$body" | _cap_text 1400)"
  [ -z "$(printf '%s' "$body" | tr -d '[:space:]')" ] && return 0
  cat <<EOF

## Global user preferences (tier C, M050 — repo overrides global on conflict)

${body}
EOF
}

_resolve_tier_c_path
tier_c_excerpt_section="$(_build_tier_c_excerpt)"
if [ -n "$tier_c_excerpt_section" ]; then
  tier_c_excerpt_section="${tier_c_excerpt_section}"$'\n'
else
  TIER_C_SOURCE_PATH=""
fi

# ---------------------------------------------------------------------------
# 12. Build additionalContext block with per-cohort budget enforcement (M016-S06)
#     + F8 yield order on small budgets (M050/S05, ADR-260611-F)
# ---------------------------------------------------------------------------
header="## Required pre-read (context-inject.sh, M013)

Before your first tool call, read these files in tier order (HIGH first):

"
footer="
> Context provided by context-inject.sh — SubagentStart hook (M013/S05).
> Tier: HIGH = binding | MED = useful | LOW = if capacity allows."

# Resolve token budget for spawning agent (chars/4 heuristic per Anthropic docs).
token_budget="$(_resolve_budget "$target_agent_name" "$cohort")"
char_budget=$(( token_budget * 4 ))

# Priority-ordered assembly (highest priority first so trim-from-end is safe):
#   1. harness_section             (M050/S05 — binding law, NEVER trimmed)
#   2. recurring_warnings_section  (S05 feedback loop — actionable, high signal)
#   3. tier_c_excerpt_section      (S06 slot — first F8 yield victim)
#   4. memory_context_section      (M050 batched repository memory packet)
#   5. payload_lines               (file list — core context)
# Footer appended last (lowest priority if we must trim).
_assemble_context() {
  full_context="${header}${harness_section}${recurring_warnings_section}${tier_c_excerpt_section}${memory_context_section}${payload_lines}${footer}"
  payload_bytes=${#full_context}
}
yield_applied="none"
truncated="false"
_assemble_context

# Phase 1 — shed LOW-tier file lines if over budget.
if [ "$payload_bytes" -gt "$char_budget" ]; then
  payload_lines="$(printf '%s' "$payload_lines" | grep -v '^LOW:')"
  truncated="true"
  _assemble_context
fi

# Phase 2 — F8 yield order (M050/S05, ADR-260611-F): below the :verifier
# 1500-token threshold, fixed sections yield strictly in order —
#   (1) tier-C excerpt drops first
#   (2) memory-packet cap shrinks 6KB → 2KB
#   (3) the harness NEVER yields (trim-exempt at any budget).
if [ "$payload_bytes" -gt "$char_budget" ] && [ "$token_budget" -le 1500 ]; then
  if [ -n "$tier_c_excerpt_section" ]; then
    tier_c_excerpt_section=""
    yield_applied="tier_c_dropped"
    truncated="true"
    _assemble_context
  fi
  if [ "$payload_bytes" -gt "$char_budget" ] && [ -n "$memory_context_section" ]; then
    memory_context_section="$(_frame_memory_section 2048)"
    [ -n "$memory_context_section" ] && memory_context_section="${memory_context_section}"$'\n'
    yield_applied="packet_shrunk"
    truncated="true"
    _assemble_context
  fi
fi

# Phase 3 — hard char-cap: truncate payload_lines to fit within budget.
#   Preserves the trim-exempt fixed set (header + harness + recurring_warnings
#   + tier-C + packet + footer); drops tail of file list. The harness is part
#   of local_fixed and therefore NEVER truncated here (F8 invariant 3).
if [ "$payload_bytes" -gt "$char_budget" ]; then
  local_fixed="${header}${harness_section}${recurring_warnings_section}${tier_c_excerpt_section}${memory_context_section}${footer}"
  fixed_bytes=${#local_fixed}
  remaining=$(( char_budget - fixed_bytes ))
  if [ "$remaining" -lt 0 ]; then remaining=0; fi
  # Truncate payload_lines to remaining chars.
  payload_lines="$(printf '%s' "$payload_lines" | head -c "$remaining")"
  truncated="true"
  _assemble_context
fi

# ---------------------------------------------------------------------------
# 12b. Cache-write (M016-S07) — store full_context payload in cache
#      Cache row: <unix_ts>|<hash>|<base64-encoded-payload>
#      Only write when base64 is available; skip silently on failure.
# ---------------------------------------------------------------------------
if command -v base64 >/dev/null 2>&1; then
  _encoded_payload="$(printf '%s' "$full_context" | base64 2>/dev/null | tr -d '\n' || echo "")"
  if [ -n "$_encoded_payload" ]; then
    _cache_row="${_inject_now_unix}|${INJECT_MSG_HASH}|${_encoded_payload}"
    append_cache_entry "$_cache_row"
  fi
fi

# ---------------------------------------------------------------------------
# 13. Audit log entry
# ---------------------------------------------------------------------------
_write_audit "$target_agent_name" "$cohort" "$path_method" \
  "$payload_bytes" "$truncated" "$duration_ms" \
  "$(basename "${milestone_dir:-}")" "$story_id" "false" "$memory_packet"

# ---------------------------------------------------------------------------
# 13b. Injection receipts (M050/S05, ADR-260611-F) — one row per inlined
#      artifact → .claude/audit/memory-read.jsonl (sole writer: this hook;
#      suppressed in worktree contexts together with audit + cache above).
# ---------------------------------------------------------------------------
if [ -n "$harness_section" ]; then
  _write_receipt "harness" "$HARNESS_SOURCE_PATH" "${#harness_section}" "false"
fi
if [ "$memory_packet" = "present" ]; then
  _write_receipt "memory_packet" "$MEMORY_PACKET_SOURCE" "${#memory_context_section}" \
    "$([ "$yield_applied" = "packet_shrunk" ] && echo true || echo false)"
fi
if [ -n "$recurring_warnings_section" ]; then
  _write_receipt "warnings" "$RECURRENCE_LOG" "${#recurring_warnings_section}" "false"
fi
if [ -n "$tier_c_excerpt_section" ]; then
  # M050/S06: receipt only when the excerpt was actually inlined (an F8-yielded
  # excerpt empties the section above, so no row lands — yield_applied says why).
  # truncated=true when the 1.5KB excerpt cap clipped the source (_cap_text marker).
  tier_c_truncated="false"
  case "$tier_c_excerpt_section" in
    *"[truncated by context-inject.sh]"*) tier_c_truncated="true" ;;
  esac
  _write_receipt "tier_c_excerpt" "${TIER_C_SOURCE_PATH:-user-preferences-excerpt}" "${#tier_c_excerpt_section}" "$tier_c_truncated"
fi
_write_receipt "path_list" "$ROLE_DEFAULTS_JSON" "${#payload_lines}" "$truncated"

# ---------------------------------------------------------------------------
# 14. Emit SubagentStart hook output (additionalContext)
# ---------------------------------------------------------------------------
# Escape the context for JSON embedding.
if command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
  py_bin="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || echo "")"
  if [ -n "$py_bin" ]; then
    "$py_bin" - "$full_context" <<'PYEOF' 2>/dev/null
import json, sys
ctx = sys.argv[1]
out = {"hookSpecificOutput": {"hookEventName": "SubagentStart", "additionalContext": ctx}}
print(json.dumps(out))
PYEOF
    exit 0
  fi
fi

# jq fallback
if command -v jq >/dev/null 2>&1; then
  jq -n --arg ctx "$full_context" \
    '{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":$ctx}}'
  exit 0
fi

# Manual JSON serialization (last resort — handles common special chars).
ctx_escaped="$(printf '%s' "$full_context" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | awk '{printf "%s\\n", $0}' | sed '$ s/\\n$//')"
printf '{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"%s"}}\n' "$ctx_escaped"

exit 0
