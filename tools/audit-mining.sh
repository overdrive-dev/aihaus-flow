#!/usr/bin/env bash
# audit-mining.sh — Telemetry-mining baseline for aihaus autonomy-gate + curator-apply audit logs.
#
# Usage:
#   bash tools/audit-mining.sh [--since YYYY-MM-DD]
#
# Produces 3 reports under tools/.out/:
#   audit-mining-patterns.md   — per-pattern hit-count (regex-match rows only, filtered)
#   audit-mining-timeline.md   — per-day decision distribution
#   audit-mining-tuning.md     — per-agent tuning frequency (/aih-effort --agent invocations)
#
# M027/S1 — implementer story. ADR-001 single-writer respected (no runtime artifact writes).
# K-260506-002: uses temp-file pattern throughout, never `cmd || true; rc=$?`.

set -euo pipefail

# ---- Resolve paths relative to this script (K-018) ---------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
AUDIT_DIR="${REPO_ROOT}/.claude/audit"
OUT_DIR="${SCRIPT_DIR}/.out"
GATE_FILE="${AUDIT_DIR}/autonomy-gate.jsonl"
CURATOR_FILE="${AUDIT_DIR}/curator-apply.jsonl"

# ---- Parse arguments ----------------------------------------------------------
SINCE_DATE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)
      SINCE_DATE="$2"
      shift 2
      ;;
    --since=*)
      SINCE_DATE="${1#--since=}"
      shift
      ;;
    *)
      printf "audit-mining.sh: unknown argument: %s\n" "$1" >&2
      exit 1
      ;;
  esac
done

# Default: rolling 30 days
if [[ -z "${SINCE_DATE}" ]]; then
  # Portable 30-day-ago calculation (handles GNU date + BSD date + Git Bash)
  if date --version >/dev/null 2>&1; then
    # GNU date
    SINCE_DATE="$(date -d "30 days ago" +%Y-%m-%d 2>/dev/null || date -v-30d +%Y-%m-%d 2>/dev/null || true)"
  else
    # BSD/macOS date
    SINCE_DATE="$(date -v-30d +%Y-%m-%d 2>/dev/null || true)"
  fi
  # Final fallback: hard-code 30 days from today via awk arithmetic
  if [[ -z "${SINCE_DATE}" ]]; then
    SINCE_DATE="$(awk 'BEGIN {
      today = systime()
      thirty_days = 30 * 86400
      since = today - thirty_days
      # Format as YYYY-MM-DD
      y = strftime("%Y", since)
      m = strftime("%m", since)
      d = strftime("%d", since)
      printf "%s-%s-%s\n", y, m, d
    }')"
  fi
fi

printf "audit-mining.sh: scanning since %s\n" "${SINCE_DATE}" >&2

# Validate SINCE_DATE format
if ! printf '%s' "${SINCE_DATE}" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
  printf "audit-mining.sh: --since must be YYYY-MM-DD, got: %s\n" "${SINCE_DATE}" >&2
  exit 1
fi

# ---- Guard: audit dir must exist --------------------------------------------
if [[ ! -d "${AUDIT_DIR}" ]]; then
  printf "audit-mining.sh: audit dir not found: %s\n" "${AUDIT_DIR}" >&2
  exit 1
fi

if [[ ! -f "${GATE_FILE}" ]]; then
  printf "audit-mining.sh: autonomy-gate.jsonl not found: %s\n" "${GATE_FILE}" >&2
  exit 1
fi

# ---- Ensure output dir exists -----------------------------------------------
mkdir -p "${OUT_DIR}"

# ---- Temp dir (K-260506-002: temp-file pattern for exit-code capture) --------
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT INT TERM

GATE_FILTERED="${TMP_DIR}/gate_filtered.jsonl"
GATE_PATTERNS="${TMP_DIR}/gate_patterns.txt"
GATE_DECISIONS="${TMP_DIR}/gate_decisions.txt"
GATE_TIMELINE="${TMP_DIR}/gate_timeline.txt"
CURATOR_SINCE="${TMP_DIR}/curator_since.jsonl"
TUNING_HITS="${TMP_DIR}/tuning_hits.txt"

# ---- Detect jq availability --------------------------------------------------
HAS_JQ=0
if command -v jq >/dev/null 2>&1; then
  HAS_JQ=1
fi

# ---- Helper: extract JSON field via awk (field-name-anchored, ADR Finding #18) --
# Usage: awk_field <json-line> <field-name>
# Returns field value (without quotes) or empty string.
# This approach is decoupled from printf order — searches for `"field":"value"` pattern.
awk_extract_field() {
  local json="$1"
  local field="$2"
  printf '%s' "${json}" | awk -v f="${field}" '
    {
      pat = "\"" f "\":\""
      idx = index($0, pat)
      if (idx == 0) { print ""; next }
      rest = substr($0, idx + length(pat))
      # find closing quote (handle escaped quotes minimally)
      out = ""
      for (i = 1; i <= length(rest); i++) {
        c = substr(rest, i, 1)
        if (c == "\\") { i++; continue }
        if (c == "\"") break
        out = out c
      }
      print out
    }
  '
}

# ---- Step 1: Filter autonomy-gate.jsonl for date range and parse fields ------
printf "audit-mining.sh: filtering autonomy-gate.jsonl (since %s) ...\n" "${SINCE_DATE}" >&2

TOTAL_ROWS=0
FILTERED_ROWS=0
NOISE_ROWS=0

# Rows excluded from pattern counts (not user-authored forbidden phrases):
# - rate-limit-skip-allow: rate limited, no model output to classify
# - timeout-fallback-allow: haiku timeout, fallback allow
# - cache_hit=1 rows: hash-cache deduplication, not a new model utterance
NOISE_DECISIONS="rate-limit-skip-allow|timeout-fallback-allow"

# Parse using awk field-name-anchored extraction (decoupled from printf order)
awk -v since="${SINCE_DATE}" '
  function extract(json, field,    pat, idx, rest, out, i, c) {
    pat = "\"" field "\":\""
    idx = index(json, pat)
    if (idx == 0) return ""
    rest = substr(json, idx + length(pat))
    out = ""
    for (i = 1; i <= length(rest); i++) {
      c = substr(rest, i, 1)
      if (c == "\\") { i++; continue }
      if (c == "\"") break
      out = out c
    }
    return out
  }
  function extract_num(json, field,    pat, idx, rest, out, i, c) {
    pat = "\"" field "\":"
    idx = index(json, pat)
    if (idx == 0) return ""
    rest = substr(json, idx + length(pat))
    out = ""
    for (i = 1; i <= length(rest); i++) {
      c = substr(rest, i, 1)
      if (c == "," || c == "}" || c == " " || c == "\n") break
      out = out c
    }
    # strip quotes if present
      gsub(/"/, "", out)
    return out
  }
  {
    ts = extract($0, "ts")
    if (ts == "") next
    # Compare date prefix only (YYYY-MM-DD)
    row_date = substr(ts, 1, 10)
    if (row_date < since) next
    print $0
  }
' "${GATE_FILE}" > "${GATE_FILTERED}"

TOTAL_ROWS=$(wc -l < "${GATE_FILE}"; true)
TOTAL_ROWS=$(printf '%s' "${TOTAL_ROWS}" | tr -d ' \n\r')
FILTERED_ROWS=$(wc -l < "${GATE_FILTERED}"; true)
FILTERED_ROWS=$(printf '%s' "${FILTERED_ROWS}" | tr -d ' \n\r')

printf "audit-mining.sh: total rows=%s in-window rows=%s\n" "${TOTAL_ROWS}" "${FILTERED_ROWS}" >&2

# ---- Step 2: Decision distribution ------------------------------------------
# Extract decision type from each row (field-name-anchored awk)
awk '
  function extract(json, field,    pat, idx, rest, out, i, c) {
    pat = "\"" field "\":\""
    idx = index(json, pat)
    if (idx == 0) return ""
    rest = substr(json, idx + length(pat))
    out = ""
    for (i = 1; i <= length(rest); i++) {
      c = substr(rest, i, 1)
      if (c == "\\") { i++; continue }
      if (c == "\"") break
      out = out c
    }
    return out
  }
  {
    d = extract($0, "decision")
    if (d != "") print d
  }
' "${GATE_FILTERED}" | sort | uniq -c | sort -rn > "${GATE_DECISIONS}"

# ---- Step 3: Per-pattern hit-count (regex-match rows, noise excluded) --------
awk '
  function extract(json, field,    pat, idx, rest, out, i, c) {
    pat = "\"" field "\":\""
    idx = index(json, pat)
    if (idx == 0) return ""
    rest = substr(json, idx + length(pat))
    out = ""
    for (i = 1; i <= length(rest); i++) {
      c = substr(rest, i, 1)
      if (c == "\\") { i++; continue }
      if (c == "\"") break
      out = out c
    }
    return out
  }
  function extract_num(json, field,    pat, idx, rest, out, i, c) {
    pat = "\"" field "\":"
    idx = index(json, pat)
    if (idx == 0) return ""
    rest = substr(json, idx + length(pat))
    out = ""
    for (i = 1; i <= length(rest); i++) {
      c = substr(rest, i, 1)
      if (c == "," || c == "}" || c == " " || c == "\n") break
      out = out c
    }
    gsub(/"/, "", out)
    return out
  }
  {
    d = extract($0, "decision")
    # Only regex-match rows count as pattern hits
    if (d != "regex-match") next
    # Filter noise: rate-limit + timeout rows
    if (d == "rate-limit-skip-allow" || d == "timeout-fallback-allow") next
    # Filter hash-cache hits (cache_hit == "1" or == 1)
    ch = extract($0, "cache_hit")
    if (ch == "") ch = extract_num($0, "cache_hit")
    if (ch == "1") next
    p = extract($0, "matched_pattern")
    s = extract($0, "section")
    if (p != "") print p "\t" s
  }
' "${GATE_FILTERED}" | awk -F'\t' '
  {
    pattern = $1
    section = $2
    counts[pattern]++
    sections[pattern] = section
  }
  END {
    for (p in counts) printf "%d\t%s\t%s\n", counts[p], p, sections[p]
  }
' | sort -t'	' -k1 -rn > "${GATE_PATTERNS}"

PATTERN_ROWS=$(wc -l < "${GATE_PATTERNS}"; true)
PATTERN_ROWS=$(printf '%s' "${PATTERN_ROWS}" | tr -d ' \n\r')

# Count noise rows excluded (rate-limit + timeout + cache_hit)
NOISE_ROWS=$(awk '
  function extract(json, field,    pat, idx, rest, out, i, c) {
    pat = "\"" field "\":\""
    idx = index(json, pat)
    if (idx == 0) return ""
    rest = substr(json, idx + length(pat))
    out = ""
    for (i = 1; i <= length(rest); i++) {
      c = substr(rest, i, 1)
      if (c == "\\") { i++; continue }
      if (c == "\"") break
      out = out c
    }
    return out
  }
  function extract_num(json, field,    pat, idx, rest, out, i, c) {
    pat = "\"" field "\":"
    idx = index(json, pat)
    if (idx == 0) return ""
    rest = substr(json, idx + length(pat))
    out = ""
    for (i = 1; i <= length(rest); i++) {
      c = substr(rest, i, 1)
      if (c == "," || c == "}" || c == " " || c == "\n") break
      out = out c
    }
    gsub(/"/, "", out)
    return out
  }
  {
    d = extract($0, "decision")
    if (d == "rate-limit-skip-allow" || d == "timeout-fallback-allow") { noise++; next }
    ch = extract($0, "cache_hit")
    if (ch == "") ch = extract_num($0, "cache_hit")
    if (ch == "1") { noise++; next }
  }
  END { print (noise+0) }
' "${GATE_FILTERED}"; true)
NOISE_ROWS=$(printf '%s' "${NOISE_ROWS}" | tr -d ' \n\r')

printf "audit-mining.sh: pattern rows=%s noise-excluded=%s\n" "${PATTERN_ROWS}" "${NOISE_ROWS}" >&2

# ---- Step 4: Per-day timeline ------------------------------------------------
awk '
  function extract(json, field,    pat, idx, rest, out, i, c) {
    pat = "\"" field "\":\""
    idx = index(json, pat)
    if (idx == 0) return ""
    rest = substr(json, idx + length(pat))
    out = ""
    for (i = 1; i <= length(rest); i++) {
      c = substr(rest, i, 1)
      if (c == "\\") { i++; continue }
      if (c == "\"") break
      out = out c
    }
    return out
  }
  {
    ts = extract($0, "ts")
    d = extract($0, "decision")
    if (ts == "" || d == "") next
    day = substr(ts, 1, 10)
    total[day]++
    by_decision[day][d]++
  }
  END {
    # collect sorted days
    n = asorti(total, days_sorted)
    for (i = 1; i <= n; i++) {
      day = days_sorted[i]
      # emit: day total regex-match outside-exec-skip paused-allow other
      rm = by_decision[day]["regex-match"] + 0
      oes = by_decision[day]["outside-exec-skip"] + 0
      pa = by_decision[day]["paused-allow"] + 0
      t = total[day] + 0
      other = t - rm - oes - pa
      printf "%s\t%d\t%d\t%d\t%d\t%d\n", day, t, rm, oes, pa, other
    }
  }
' "${GATE_FILTERED}" > "${GATE_TIMELINE}"

printf "audit-mining.sh: timeline rows=%s\n" "$(wc -l < "${GATE_TIMELINE}" | tr -d ' \n\r')" >&2

# ---- Step 5: curator-apply outcomes -----------------------------------------
CURATOR_ROWS=0
CURATOR_APPLIED=0
CURATOR_SKIPPED=0

if [[ -f "${CURATOR_FILE}" ]]; then
  awk -v since="${SINCE_DATE}" '
    function extract(json, field,    pat, idx, rest, out, i, c) {
      pat = "\"" field "\":\""
      idx = index(json, pat)
      if (idx == 0) return ""
      rest = substr(json, idx + length(pat))
      out = ""
      for (i = 1; i <= length(rest); i++) {
        c = substr(rest, i, 1)
        if (c == "\\") { i++; continue }
        if (c == "\"") break
        out = out c
      }
      return out
    }
    {
      ts = extract($0, "ts")
      if (ts == "") next
      if (substr(ts, 1, 10) < since) next
      print $0
    }
  ' "${CURATOR_FILE}" > "${CURATOR_SINCE}"

  CURATOR_ROWS=$(wc -l < "${CURATOR_SINCE}"; true)
  CURATOR_ROWS=$(printf '%s' "${CURATOR_ROWS}" | tr -d ' \n\r')

  CURATOR_APPLIED=$(awk '
    function extract(json, field,    pat, idx, rest, out, i, c) {
      pat = "\"" field "\":\""
      idx = index(json, pat)
      if (idx == 0) return ""
      rest = substr(json, idx + length(pat))
      out = ""
      for (i = 1; i <= length(rest); i++) {
        c = substr(rest, i, 1)
        if (c == "\\") { i++; continue }
        if (c == "\"") break
        out = out c
      }
      return out
    }
    {
      s = extract($0, "status")
      if (s ~ /^applied/) n++
    }
    END { print (n+0) }
  ' "${CURATOR_SINCE}"; true)
  CURATOR_APPLIED=$(printf '%s' "${CURATOR_APPLIED}" | tr -d ' \n\r')

  CURATOR_SKIPPED=$(awk '
    function extract(json, field,    pat, idx, rest, out, i, c) {
      pat = "\"" field "\":\""
      idx = index(json, pat)
      if (idx == 0) return ""
      rest = substr(json, idx + length(pat))
      out = ""
      for (i = 1; i <= length(rest); i++) {
        c = substr(rest, i, 1)
        if (c == "\\") { i++; continue }
        if (c == "\"") break
        out = out c
      }
      return out
    }
    {
      s = extract($0, "status")
      if (s ~ /^skipped/) n++
    }
    END { print (n+0) }
  ' "${CURATOR_SINCE}"; true)
  CURATOR_SKIPPED=$(printf '%s' "${CURATOR_SKIPPED}" | tr -d ' \n\r')
  printf "audit-mining.sh: curator-apply rows=%s applied=%s skipped=%s\n" \
    "${CURATOR_ROWS}" "${CURATOR_APPLIED}" "${CURATOR_SKIPPED}" >&2
else
  printf "audit-mining.sh: curator-apply.jsonl not found, skipping\n" >&2
  touch "${CURATOR_SINCE}"
fi

# ---- Step 6: Per-agent-tuning frequency (grep for /aih-effort --agent) -------
# Grep across ALL .jsonl files in audit dir for actual /aih-effort --agent invocations
# This includes daily hook.jsonl / invoke.jsonl / date-named files
printf "audit-mining.sh: scanning for /aih-effort --agent invocations ...\n" >&2

# Use temp file to capture grep output safely (K-260506-002 pattern)
TUNING_TMP="${TMP_DIR}/tuning_raw.txt"
grep -r -- '--agent' /c/Users/vctrs/OneDrive/Documents/GitHub/aihaus-flow/.claude/audit/ \
  2>"${TMP_DIR}/tuning_err.txt" > "${TUNING_TMP}" || true

# Filter to genuine /aih-effort --agent <name> invocations (not doc/comment matches)
# A genuine invocation looks like: "cmd":"... /aih-effort --agent <name> ..." in hook.jsonl/invoke.jsonl
# or skill invocation entries with the effort skill + --agent flag
grep -E '"/aih-effort[^"]*--agent|aih-effort.*--agent [a-z]' "${TUNING_TMP}" \
  > "${TUNING_HITS}" 2>/dev/null || true

TUNING_RAW_COUNT=$(wc -l < "${TUNING_TMP}"; true)
TUNING_RAW_COUNT=$(printf '%s' "${TUNING_RAW_COUNT}" | tr -d ' \n\r')
TUNING_HIT_COUNT=$(wc -l < "${TUNING_HITS}"; true)
TUNING_HIT_COUNT=$(printf '%s' "${TUNING_HIT_COUNT}" | tr -d ' \n\r')

# Parse agent names from genuine invocations
awk '
  {
    # Match patterns like: --agent <name>
    if (match($0, /--agent ([a-zA-Z][a-zA-Z0-9_-]*)/, arr)) {
      print arr[1]
    } else if (match($0, /--agent[[:space:]]+([a-zA-Z][a-zA-Z0-9_-]*)/, arr)) {
      print arr[1]
    }
  }
' "${TUNING_HITS}" 2>/dev/null | sort | uniq -c | sort -rn > "${TMP_DIR}/tuning_agents.txt" || true

printf "audit-mining.sh: tuning grep-total=%s genuine-hits=%s\n" \
  "${TUNING_RAW_COUNT}" "${TUNING_HIT_COUNT}" >&2

# ---- Step 7: Get total decision counts for percentages -----------------------
TOTAL_REGEX_MATCH=0
TOTAL_OUTSIDE_EXEC_SKIP=0
TOTAL_PAUSED_ALLOW=0
TOTAL_RATE_LIMIT=0
TOTAL_TIMEOUT=0
TOTAL_OTHER=0
TOTAL_FILTERED=0

if [[ "${FILTERED_ROWS}" -gt 0 ]]; then
  while IFS=$'\t' read -r cnt decision; do
    cnt=$(printf '%s' "${cnt}" | tr -d ' ')
    decision=$(printf '%s' "${decision}" | tr -d ' ')
    case "${decision}" in
      "regex-match")          TOTAL_REGEX_MATCH="${cnt}" ;;
      "outside-exec-skip")    TOTAL_OUTSIDE_EXEC_SKIP="${cnt}" ;;
      "paused-allow")         TOTAL_PAUSED_ALLOW="${cnt}" ;;
      "rate-limit-skip-allow") TOTAL_RATE_LIMIT="${cnt}" ;;
      "timeout-fallback-allow") TOTAL_TIMEOUT="${cnt}" ;;
      *)                      TOTAL_OTHER=$((TOTAL_OTHER + cnt)) ;;
    esac
  done < <(awk '{print $1 "\t" $2}' "${GATE_DECISIONS}")
  TOTAL_FILTERED="${FILTERED_ROWS}"
fi

# ---- Emit report A: audit-mining-patterns.md ---------------------------------
GENERATED_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%SZ)"

{
printf '<!-- generated by tools/audit-mining.sh --since %s at %s -->\n' "${SINCE_DATE}" "${GENERATED_TS}"
printf '# Autonomy-Gate Pattern Hit-Count Report\n\n'
printf '**Generated:** %s  \n' "${GENERATED_TS}"
printf '**Since:** %s  \n' "${SINCE_DATE}"
printf '**Source:** `.claude/audit/autonomy-gate.jsonl`  \n'
printf '**Total rows in file:** %s  \n' "${TOTAL_ROWS}"
printf '**Rows in window:** %s  \n' "${TOTAL_FILTERED}"
printf '\n'
printf '## Decision Distribution\n\n'
printf '| Decision | Count | %% of window |\n'
printf '|----------|-------|-------------|\n'

# Print decision distribution
if [[ "${TOTAL_FILTERED}" -gt 0 ]]; then
  awk -v total="${TOTAL_FILTERED}" '{
    cnt = $1
    # decision is $2
    dec = ""
    for (i=2; i<=NF; i++) dec = dec (i>2 ? " " : "") $i
    pct = (total > 0) ? int(cnt * 1000 / total) / 10 : 0
    printf "| %s | %d | %.1f%% |\n", dec, cnt, pct
  }' "${GATE_DECISIONS}"
fi

printf '\n'
printf '## Per-Pattern Hit-Count\n\n'
printf '> **Note:** Only `regex-match` rows counted. '
printf 'Excluded from per-pattern counts: `rate-limit-skip-allow` (%s rows), ' "${TOTAL_RATE_LIMIT}"
printf '`timeout-fallback-allow` (%s rows), and `cache_hit=1` rows (%s total noise rows excluded). ' \
  "${TOTAL_TIMEOUT}" "${NOISE_ROWS}"
printf 'These rows are system-internal signals, not user-authored forbidden phrases.\n\n'

if [[ "${PATTERN_ROWS}" -gt 0 ]]; then
  printf '| Rank | Count | %% of regex-match | Pattern | Section |\n'
  printf '|------|-------|-------------------|---------|---------|\n'
  awk -F'\t' -v total="${TOTAL_REGEX_MATCH}" '{
    cnt = $1
    pat = $2
    sec = $3
    pct = (total > 0) ? int(cnt * 1000 / total) / 10 : 0
    printf "| %d | %d | %.1f%% | `%s` | `%s` |\n", NR, cnt, pct, pat, sec
  }' "${GATE_PATTERNS}"
else
  printf '_No regex-match rows found in date window._\n'
fi

} > "${OUT_DIR}/audit-mining-patterns.md"

printf "audit-mining.sh: wrote audit-mining-patterns.md\n" >&2

# ---- Emit report B: audit-mining-timeline.md ---------------------------------
{
printf '<!-- generated by tools/audit-mining.sh --since %s at %s -->\n' "${SINCE_DATE}" "${GENERATED_TS}"
printf '# Autonomy-Gate Per-Day Timeline\n\n'
printf '**Generated:** %s  \n' "${GENERATED_TS}"
printf '**Since:** %s  \n' "${SINCE_DATE}"
printf '**Source:** `.claude/audit/autonomy-gate.jsonl`  \n'
printf '**Curator-apply rows in window:** %s (applied=%s skipped=%s)  \n' \
  "${CURATOR_ROWS}" "${CURATOR_APPLIED}" "${CURATOR_SKIPPED}"
printf '\n'
printf '## Daily Decision Summary\n\n'

if [[ "$(wc -l < "${GATE_TIMELINE}" | tr -d ' ')" -gt 0 ]]; then
  printf '| Date | Total | regex-match | outside-exec-skip | paused-allow | other |\n'
  printf '|------|-------|-------------|-------------------|--------------|-------|\n'
  awk '{
    printf "| %s | %d | %d | %d | %d | %d |\n", $1, $2, $3, $4, $5, $6
  }' "${GATE_TIMELINE}"
else
  printf '_No rows found in date window._\n'
fi

printf '\n'
printf '## Curator-Apply Log (since %s)\n\n' "${SINCE_DATE}"

if [[ -f "${CURATOR_SINCE}" ]] && [[ "$(wc -l < "${CURATOR_SINCE}" | tr -d ' ')" -gt 0 ]]; then
  printf '| Timestamp | Block | Target | Status | Milestone |\n'
  printf '|-----------|-------|--------|--------|-----------|\n'
  awk '
    function extract(json, field,    pat, idx, rest, out, i, c) {
      pat = "\"" field "\":\""
      idx = index(json, pat)
      if (idx == 0) return ""
      rest = substr(json, idx + length(pat))
      out = ""
      for (i = 1; i <= length(rest); i++) {
        c = substr(rest, i, 1)
        if (c == "\\") { i++; continue }
        if (c == "\"") break
        out = out c
      }
      return out
    }
    {
      ts = extract($0, "ts")
      block = extract($0, "block")
      target = extract($0, "target")
      status = extract($0, "status")
      milestone = extract($0, "milestone")
      printf "| %s | %s | `%s` | %s | %s |\n", ts, block, target, status, milestone
    }
  ' "${CURATOR_SINCE}"
else
  printf '_No curator-apply rows in date window._\n'
fi

} > "${OUT_DIR}/audit-mining-timeline.md"

printf "audit-mining.sh: wrote audit-mining-timeline.md\n" >&2

# ---- Emit report C: audit-mining-tuning.md -----------------------------------
{
printf '<!-- generated by tools/audit-mining.sh --since %s at %s -->\n' "${SINCE_DATE}" "${GENERATED_TS}"
printf '# Per-Agent Tuning Frequency Report\n\n'
printf '**Generated:** %s  \n' "${GENERATED_TS}"
printf '**Since:** %s  \n' "${SINCE_DATE}"
printf '**Source:** `.claude/audit/*.jsonl` (grep for `/aih-effort --agent` invocations)  \n'
printf '\n'
printf '## /aih-effort --agent Invocation Frequency\n\n'

AGENT_ROWS=$(wc -l < "${TMP_DIR}/tuning_agents.txt" | tr -d ' '; true)
AGENT_ROWS=$(printf '%s' "${AGENT_ROWS}" | tr -d ' \n\r')

if [[ "${TUNING_HIT_COUNT}" -gt 0 ]] && [[ "${AGENT_ROWS}" -gt 0 ]]; then
  printf '| Invocations | Agent |\n'
  printf '|-------------|-------|\n'
  awk '{
    cnt = $1
    # agent name is rest of fields
    agent = ""
    for (i=2; i<=NF; i++) agent = agent (i>2 ? " " : "") $i
    printf "| %d | `%s` |\n", cnt, agent
  }' "${TMP_DIR}/tuning_agents.txt"
else
  printf '**Zero `/aih-effort --agent <name>` invocations found** across all audit files.\n\n'
  printf '> This confirms the pre-mining preview finding from analysis-brief §2: per-agent cohort tuning\n'
  printf '> has never been exercised in production. All agents run on their cohort defaults.\n'
  printf '> Implication for S8 (researcher consolidation): zero per-agent invocations satisfies\n'
  printf '> the PROCEED-WITH-MERGE criterion on the tuning axis.\n'
fi

printf '\n'
printf '## Grep Methodology\n\n'
printf '%s\n' '- Scanned: all `.jsonl` files under `.claude/audit/`'
printf '%s\n' '- Pattern: `/aih-effort.*--agent` + `aih-effort.*--agent [a-z]`'
printf '%s%s\n' '- Raw matches (before genuine-invocation filter): ' "${TUNING_RAW_COUNT}"
printf '%s%s\n' '- Genuine invocations (after filter): ' "${TUNING_HIT_COUNT}"
printf '\n'
printf '%s\n' '> **Note:** Most raw grep matches are documentation text (CLAUDE.md excerpts, ADR prose,'
printf '%s\n' '> agent definitions) embedded in bash command log entries. Only entries matching the'
printf '%s\n' '> genuine invocation pattern (actual command execution, not docs) are counted above.'

} > "${OUT_DIR}/audit-mining-tuning.md"

printf "audit-mining.sh: wrote audit-mining-tuning.md\n" >&2

# ---- Final summary -----------------------------------------------------------
printf "audit-mining.sh: done. Reports written to %s/\n" "${OUT_DIR}" >&2
printf "  - audit-mining-patterns.md (%s unique patterns)\n" "${PATTERN_ROWS}" >&2
printf "  - audit-mining-timeline.md (%s days)\n" "$(wc -l < "${GATE_TIMELINE}" | tr -d ' ')" >&2
printf "  - audit-mining-tuning.md (%s genuine /aih-effort --agent invocations)\n" "${TUNING_HIT_COUNT}" >&2
