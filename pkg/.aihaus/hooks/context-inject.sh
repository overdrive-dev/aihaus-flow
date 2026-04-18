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
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo ".")"
ROLE_DEFAULTS_JSON="${SCRIPT_DIR}/lib/role-defaults.json"
COHORTS_MD_REL=".aihaus/skills/aih-effort/annexes/cohorts.md"

ts_iso() { date -u +%FT%TZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "1970-01-01T00:00:00Z"; }

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
        milestone="${7:-}" story="${8:-}"
  mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || return 0
  _rotate_audit_if_needed
  local ts; ts="$(ts_iso)"
  # Escape quotes in string fields.
  _eq() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
  printf '{"ts":"%s","milestone":"%s","story":"%s","target_agent":"%s","cohort":"%s","static_or_haiku":"%s","payload_bytes":%s,"truncated":"%s","duration_ms":%s}\n' \
    "$ts" "$(_eq "$milestone")" "$(_eq "$story")" "$(_eq "$target_agent")" \
    "$(_eq "$cohort")" "$(_eq "$static_or_haiku")" \
    "${payload_bytes:-0}" "${truncated:-false}" "${duration_ms:-0}" \
    >> "$AUDIT_LOG" 2>/dev/null || true
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
# 12. Build additionalContext block (≤ 200 tokens heuristic)
# ---------------------------------------------------------------------------
header="## Required pre-read (context-inject.sh, M013)

Before your first tool call, read these files in tier order (HIGH first):

"
footer="
> Context provided by context-inject.sh — SubagentStart hook (M013/S05).
> Tier: HIGH = binding | MED = useful | LOW = if capacity allows."

full_context="${header}${payload_lines}${footer}"

# Truncation guard: if payload exceeds ~1600 chars, trim LOW lines first.
payload_bytes=${#full_context}
truncated="false"
if [ "$payload_bytes" -gt 1600 ]; then
  trimmed_lines="$(printf '%s' "$payload_lines" | grep -v '^LOW:')"
  full_context="${header}${trimmed_lines}${footer}"
  payload_bytes=${#full_context}
  truncated="true"
fi

# ---------------------------------------------------------------------------
# 13. Audit log entry
# ---------------------------------------------------------------------------
_write_audit "$target_agent_name" "$cohort" "$path_method" \
  "$payload_bytes" "$truncated" "$duration_ms" \
  "$(basename "${milestone_dir:-}")" "$story_id"

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
