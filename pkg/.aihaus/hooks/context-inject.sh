#!/usr/bin/env bash
# context-inject.sh — SubagentStart hook (M013/S05 Component A)
# Fires on every subagent spawn, resolves relevance-tiered file list,
# and emits SubagentStart.additionalContext payload so the agent's
# first token is grounded in decisions.md, knowledge.md, and peers.
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
# Cache: .claude/audit/context-inject.cache (M016-S07 5-min memoization).
#   Cache key: hash(target_agent_name | cohort_name).
#   Cache hit skips S05 warning-recurrence read + S06 budget parse.
#   Cache invalidated at milestone close (completion-protocol Step 6.5).
# Architecture ref: M013 architecture.md §2.1, §4.1, §9.
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
# 2. Worktree refusal (ADR-001 / architecture §9 — writes audit from
#    orchestrator process only; worktree agents don't fire context-inject
#    for their own sub-spawns because they use Task tool inside worktree)
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
AUDIT_LOG="${AIHAUS_CONTEXT_INJECT_LOG:-.claude/audit/context-inject.jsonl}"
INJECT_CACHE=".claude/audit/context-inject.cache"
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo ".")"
ROLE_DEFAULTS_JSON="${SCRIPT_DIR}/lib/role-defaults.json"
COHORTS_MD_REL=".aihaus/skills/aih-effort/annexes/cohorts.md"
BUDGET_CONF="${SCRIPT_DIR}/context-budget.conf"

ts_iso() { date -u +%FT%TZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z"; }

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
    local line="${raw_line%$'\r'}"
    line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
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
  local target_agent="$1" cohort="$2" static_or_haiku="$3" \
        payload_bytes="$4" truncated="$5" duration_ms="$6" \
        milestone="${7:-}" story="${8:-}" cache_hit="${9:-false}"
  mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || return 0
  _rotate_audit_if_needed
  local ts; ts="$(ts_iso)"
  # Escape quotes in string fields.
  _eq() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
  printf '{"ts":"%s","milestone":"%s","story":"%s","target_agent":"%s","cohort":"%s","static_or_haiku":"%s","payload_bytes":%s,"truncated":"%s","duration_ms":%s,"cache_hit":%s}\n' \
    "$ts" "$(_eq "$milestone")" "$(_eq "$story")" "$(_eq "$target_agent")" \
    "$(_eq "$cohort")" "$(_eq "$static_or_haiku")" \
    "${payload_bytes:-0}" "${truncated:-false}" "${duration_ms:-0}" \
    "${cache_hit}" \
    >> "$AUDIT_LOG" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# 4b. Cache helpers (M016-S07 — 5-min hash cache for context-inject)
#     Byte-identical transplant from learning-advisor.sh compute_hash +
#     append_cache_entry; variable names changed: ADVISOR_* → INJECT_*.
#     Cache key: hash(target_agent_name | cohort_name).
#     Cache file: .claude/audit/context-inject.cache
#     Cache row:  <unix_ts>|<hash>|<base64-encoded-payload>
#     Rotation:   10 KB OR 100 lines (lighter than 10 MB/10000 in advisor)
# ---------------------------------------------------------------------------
compute_hash() {
  local combined="${target_agent_name:-}|${cohort:-}"
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
fi
# Fallback: grep from raw JSON when jq unavailable or returns empty.
[ -z "$task_description" ] && task_description="$(printf '%s' "$INPUT" | grep -o '"task_description":"[^"]*"' | head -1 | sed 's/.*":"\(.*\)"/\1/' 2>/dev/null || echo "")"
[ -z "$target_agent_name" ] && target_agent_name="$(printf '%s' "$INPUT" | grep -o '"agent_name":"[^"]*"' | head -1 | sed 's/.*":"\(.*\)"/\1/' 2>/dev/null || echo "")"

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
    "$(dirname "$SCRIPT_DIR")/${COHORTS_MD_REL}"; do
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

# ---------------------------------------------------------------------------
# 6b. Cache lookup (M016-S07) — cache key: hash(target_agent_name | cohort)
#     Hit: skip S05 warning-recurrence read + S06 budget parse; emit cached
#          payload directly and exit.  Miss: fall through to full S05+S06 path.
# ---------------------------------------------------------------------------
_inject_cache_hit="false"
_inject_cache_payload=""
INJECT_MSG_HASH="$(compute_hash)"
_inject_now_unix="$(date +%s 2>/dev/null || echo 0)"
_rotate_cache_if_needed
mkdir -p "$(dirname "$INJECT_CACHE")" 2>/dev/null || true

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
  _write_audit "$target_agent_name" "$cohort" "cache-hit" \
    "${#_inject_cache_payload}" "false" "0" \
    "$(basename "${milestone_dir:-}")" "$story_id" "true"
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
entries = d.get(key, d.get(':doer', []))
for e in entries:
    tier = e.get('tier','MED')
    path = e.get('path','')
    rationale = e.get('rationale','')
    print(f"{tier}:{path} — {rationale}")
PYEOF
  elif command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$cohort_key" '
      .[$k] // .[":doer"] // [] |
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
  local novel=1
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    # Extract path portion (after colon, before dash).
    local path_part; path_part="$(printf '%s' "$line" | sed 's/^[A-Z]*://; s/ —.*//' 2>/dev/null || echo "")"
    [ -z "$path_part" ] && continue
    # Strip template tokens.
    [[ "$path_part" == *"<"* ]] && continue
    # Check if path basename appears in task description.
    local basename; basename="$(basename "$path_part" 2>/dev/null)"
    if printf '%s' "$task" | grep -qiF "$basename" 2>/dev/null; then
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
RECURRENCE_LOG=".claude/audit/warning-recurrence.jsonl"
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
  cohorts_summary=":planner-binding→decisions.md,knowledge.md,project.md  :planner→decisions.md,knowledge.md,project.md  :doer→decisions.md,knowledge.md,project.md,story-file  :verifier→decisions.md,knowledge.md,story-file  :adversarial-*→decisions.md,knowledge.md"

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
    # Resolve <story-file>
    if printf '%s' "$line" | grep -q '<story-file>'; then
      if [ -n "$m_dir" ] && [ -n "$s_id" ]; then
        local sf="${m_dir}/stories/${s_id}.md"
        line="${line//<story-file>/$sf}"
      else
        line="${line//<story-file>/.aihaus/milestones/<milestone>/stories/<story>.md}"
      fi
    fi
    # Resolve <analysis-brief>
    if printf '%s' "$line" | grep -q '<analysis-brief>'; then
      if [ -n "$m_dir" ]; then
        line="${line//<analysis-brief>/${m_dir}/execution/analysis-brief.md}"
      else
        line="${line//<analysis-brief>/.aihaus/milestones/<milestone>/execution/analysis-brief.md}"
      fi
    fi
    # Resolve <execution-dir>
    if printf '%s' "$line" | grep -q '<execution-dir>'; then
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
    local path_key; path_key="$(printf '%s' "$l" | sed 's/^[A-Z]*://; s/ —.*//' 2>/dev/null || echo "$l")"
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
  payload_lines="HIGH:.aihaus/decisions.md — ADRs are binding; reading prevents conflicts.
HIGH:.aihaus/knowledge.md — Known gotchas prevent known failures.
HIGH:.aihaus/project.md — Stack and conventions are required context.
MED:.aihaus/memory/MEMORY.md — Agent memory index for cross-task context."
  path_method="fallback"
fi

# ---------------------------------------------------------------------------
# 12. Build additionalContext block with per-cohort budget enforcement (M016-S06)
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
#   1. recurring_warnings_section  (S05 feedback loop — actionable, high signal)
#   2. payload_lines               (file list — core context)
# Footer appended last (lowest priority if we must trim).
full_context="${header}${recurring_warnings_section}${payload_lines}${footer}"

payload_bytes=${#full_context}
truncated="false"

# Phase 1 — shed LOW-tier file lines if over budget.
if [ "$payload_bytes" -gt "$char_budget" ]; then
  trimmed_lines="$(printf '%s' "$payload_lines" | grep -v '^LOW:')"
  full_context="${header}${recurring_warnings_section}${trimmed_lines}${footer}"
  payload_bytes=${#full_context}
  truncated="true"
fi

# Phase 2 — hard char-cap: truncate payload_lines to fit within budget.
#   Preserves recurring_warnings + header/footer; drops tail of file list.
if [ "$payload_bytes" -gt "$char_budget" ]; then
  # Budget consumed by fixed parts (header + recurring_warnings + footer).
  local_fixed="${header}${recurring_warnings_section}${footer}"
  fixed_bytes=${#local_fixed}
  remaining=$(( char_budget - fixed_bytes ))
  if [ "$remaining" -lt 0 ]; then remaining=0; fi
  # Truncate payload_lines to remaining chars.
  trimmed_lines="$(printf '%s' "$payload_lines" | head -c "$remaining")"
  full_context="${header}${recurring_warnings_section}${trimmed_lines}${footer}"
  payload_bytes=${#full_context}
  truncated="true"
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
  "$(basename "${milestone_dir:-}")" "$story_id" "false"

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
