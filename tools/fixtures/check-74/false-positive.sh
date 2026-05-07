#!/usr/bin/env bash
# Fixture for Check 74 — false-positive demonstration via UNANCHORED regex.
# This fixture uses bare `[Pp]hase [0-9]+` (no completion-prose anchoring),
# which would fire on legitimate `## Phase 1` markdown headers at runtime.
# Check 74 sub-assert (f) verifies that this fixture DOES block the markdown
# header — proving the production-code anchoring strategy is necessary.
#
# DO NOT modify this fixture. It must permanently use bare [Pp]hase [0-9]+
# without completion-prose anchoring.

set -euo pipefail

MSG="$(cat)"

# INTENTIONALLY UNANCHORED — bare [Pp]hase [0-9]+ to demonstrate why anchoring is required
PATTERNS=$(cat <<'FIXTURE_EOF'
[Pp]hase [0-9]+	LSDD-EN-Phase-numeric-UNANCHORED
FIXTURE_EOF
)

while IFS=$'\t' read -r pattern section; do
  [ -z "$pattern" ] && continue
  if printf '%s' "$MSG" | grep -qE "$pattern" 2>/dev/null; then
    if [ "${AIHAUS_EXEC_PHASE:-0}" = "1" ]; then
      printf '{"decision":"block","reason":"fixture-matched: %s"}\n' "$section"
      exit 0
    fi
  fi
done <<< "$PATTERNS"

exit 0
