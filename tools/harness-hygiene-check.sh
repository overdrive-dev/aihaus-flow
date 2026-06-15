#!/usr/bin/env bash
# Checks tracked files for stale custom harness/runtime references.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SELF_REL="tools/$(basename "$0")"

TERMS=(
  "aihaus-pi"
  "aihaus-team"
  "domus-nora-app"
  "goose"
  "chatgpt_codex"
  "gpt-5\\.5"
  "runtime-check"
)

ALTERNATION=""
for term in "${TERMS[@]}"; do
  if [[ -z "$ALTERNATION" ]]; then
    ALTERNATION="$term"
  else
    ALTERNATION="${ALTERNATION}|${term}"
  fi
done

BOUNDARY_REGEX="(^|[^A-Za-z0-9_])(${ALTERNATION})([^A-Za-z0-9_]|\$)"

printf "aihaus custom harness hygiene check\n"
printf "Scanning tracked files under: %s\n\n" "$REPO_ROOT"

TMP_BASE="${TMPDIR:-}"
if [[ -z "$TMP_BASE" || ! -d "$TMP_BASE" || ! -w "$TMP_BASE" ]]; then
  TMP_BASE="${REPO_ROOT}/tmp"
  mkdir -p "$TMP_BASE" 2>/dev/null || {
    printf "ERROR: cannot create temp directory: %s\n" "$TMP_BASE" >&2
    exit 2
  }
fi
TMP_OUT=$(mktemp "${TMP_BASE%/}/harness-hygiene.XXXXXX" 2>/dev/null) || {
  printf "ERROR: cannot create temp file under %s\n" "$TMP_BASE" >&2
  exit 2
}
trap 'rm -f "$TMP_OUT"' EXIT

while IFS= read -r -d '' rel; do
  [[ "$rel" == "$SELF_REL" ]] && continue
  grep -IEni --regexp="$BOUNDARY_REGEX" "${REPO_ROOT}/${rel}" 2>/dev/null || true
done < <(git -C "$REPO_ROOT" ls-files -z) > "$TMP_OUT"

MATCH_COUNT=$(wc -l < "$TMP_OUT" | tr -d ' ')
if [[ "$MATCH_COUNT" -eq 0 ]]; then
  printf "Custom harness hygiene: PASSED (zero stale custom references)\n"
  exit 0
fi

printf "Custom harness hygiene: FAILED (%d matches)\n" "$MATCH_COUNT"
printf -- "----------------------------------------\n"
cat "$TMP_OUT"
exit 1
