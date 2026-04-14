#!/usr/bin/env bash
# Maintainer-only regression assertion for generate-release-notes.sh.
# Runs the generator against M001 and fails if maintainer-only strings leak.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
out="$(bash "${SCRIPT_DIR}/generate-release-notes.sh" M001 2>/dev/null)"
for forbidden in "smoke-test" "purity-check" "dogfood-brainstorm"; do
  if printf '%s' "$out" | grep -Fq "$forbidden"; then
    printf "[FAIL] release-notes leak: %s\n" "$forbidden" >&2
    exit 1
  fi
done
printf "[PASS] release-notes generator: no maintainer-only leakage for M001\n"
