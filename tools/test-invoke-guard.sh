#!/usr/bin/env bash
# tools/test-invoke-guard.sh — adversarial harness for pkg/.aihaus/hooks/invoke-guard.sh
# Runs 12 cases, emits PASS/FAIL per case, non-zero exit if any fail.
set -euo pipefail

HOOK="pkg/.aihaus/hooks/invoke-guard.sh"
[ -x "$HOOK" ] || { echo "FAIL: $HOOK not executable"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

PASS=0
FAIL=0
TOTAL=0

export AIHAUS_AUDIT_LOG="$TMP/invoke.jsonl"

run_case() {
  local label="$1" expected="$2"
  local input="$3" manifest="${4:-}"
  TOTAL=$((TOTAL + 1))
  local output
  if [ -n "$manifest" ]; then
    output="$(printf '%s' "$input" | MANIFEST_PATH="$manifest" bash "$HOOK" 2>/dev/null || true)"
  else
    output="$(printf '%s' "$input" | env -u MANIFEST_PATH bash "$HOOK" 2>/dev/null || true)"
  fi
  if [[ "$output" == "$expected"* ]]; then
    echo "PASS [$label]"
    PASS=$((PASS + 1))
  else
    echo "FAIL [$label] expected='$expected', got='$output'"
    FAIL=$((FAIL + 1))
  fi
}

# --- fixtures ---

MANIFEST_EMPTY="$TMP/empty-manifest.md"
cat > "$MANIFEST_EMPTY" <<'EOF'
## Metadata
milestone: test
schema: v2

## Invoke stack

## Story Records
story_id|status|started_at|commit_sha|verified|notes
EOF

MANIFEST_3DEEP="$TMP/3deep-manifest.md"
cat > "$MANIFEST_3DEEP" <<'EOF'
## Metadata
schema: v2

## Invoke stack
aih-run|slug|why|false|1
aih-plan|slug|why|false|2
aih-quick|fix|why|true|3

## Story Records
story_id|status|started_at|commit_sha|verified|notes
EOF

MANIFEST_TOP_QUICK="$TMP/top-quick-manifest.md"
cat > "$MANIFEST_TOP_QUICK" <<'EOF'
## Metadata
schema: v2

## Invoke stack
aih-quick|x|rationale|false|1

## Story Records
story_id|status|started_at|commit_sha|verified|notes
EOF

# --- cases ---

# 1. Happy path
run_case "01 happy-path INVOKE_OK" "INVOKE_OK aih-quick" \
  'lorem ipsum
<AIHAUS_INVOKE skill="aih-quick" args="fix typo" rationale="plan-checker flagged it" blocking="false"/>' \
  "$MANIFEST_EMPTY"

# 2. Marker in fenced code block mid-output (not last line)
run_case "02 marker-in-fence mid-output NO_INVOKE" "NO_INVOKE" \
  'here is an example marker:
```
<AIHAUS_INVOKE skill="aih-quick" args="x" rationale="y" blocking="false"/>
```
the agent then says more stuff' \
  ""

# 3. Marker on non-last line (prose after)
run_case "03 non-last-line NO_INVOKE" "NO_INVOKE" \
  '<AIHAUS_INVOKE skill="aih-quick" args="x" rationale="y" blocking="false"/>
final prose line' \
  ""

# 4. Malformed quoting
run_case "04 malformed-quote NO_INVOKE" "NO_INVOKE" \
  '<AIHAUS_INVOKE skill="aih-quick" args="broken rationale="y" blocking="false"/>' \
  ""

# 5. Depth overflow
run_case "05 depth-overflow REJECT" "INVOKE_REJECT depth" \
  '<AIHAUS_INVOKE skill="aih-plan" args="x" rationale="y" blocking="false"/>' \
  "$MANIFEST_3DEEP"

# 6. Allowlist reject
run_case "06 allowlist REJECT" "INVOKE_REJECT allowlist" \
  '<AIHAUS_INVOKE skill="aih-init" args="x" rationale="y" blocking="false"/>' \
  "$MANIFEST_EMPTY"

# 7. Self-invocation
run_case "07 self-invocation REJECT" "INVOKE_REJECT self-invocation" \
  '<AIHAUS_INVOKE skill="aih-quick" args="x" rationale="y" blocking="false"/>' \
  "$MANIFEST_TOP_QUICK"

# 8. Marker inside URL query string (not XML form)
run_case "08 url-query NO_INVOKE" "NO_INVOKE" \
  'see https://example.com/?AIHAUS_INVOKE=aih-quick' \
  ""

# 9. Marker as JSON string (not last non-empty line)
run_case "09 json-embed-not-last NO_INVOKE" "NO_INVOKE" \
  '{"marker": "<AIHAUS_INVOKE skill=\"aih-quick\" args=\"x\" rationale=\"y\" blocking=\"false\"/>"}
final prose' \
  ""

# 10. Concurrent markers (only last inspected)
run_case "10 concurrent-last-wins INVOKE_OK" "INVOKE_OK aih-plan" \
  '<AIHAUS_INVOKE skill="aih-quick" args="x" rationale="y" blocking="false"/>

<AIHAUS_INVOKE skill="aih-plan" args="x" rationale="y" blocking="false"/>' \
  "$MANIFEST_EMPTY"

# 11. Empty rationale
run_case "11 rationale-empty REJECT" "INVOKE_REJECT rationale-empty" \
  '<AIHAUS_INVOKE skill="aih-quick" args="x" rationale="" blocking="false"/>' \
  "$MANIFEST_EMPTY"

# 12. Rationale over 200 chars
LONG_RAT="$(printf 'x%.0s' {1..201})"
run_case "12 rationale-length REJECT" "INVOKE_REJECT rationale-length" \
  "<AIHAUS_INVOKE skill=\"aih-quick\" args=\"x\" rationale=\"${LONG_RAT}\" blocking=\"false\"/>" \
  "$MANIFEST_EMPTY"

# --- summary ---

echo ""
echo "invoke-guard.sh: $PASS/$TOTAL cases passed"
[ "$FAIL" -eq 0 ] || exit 1
