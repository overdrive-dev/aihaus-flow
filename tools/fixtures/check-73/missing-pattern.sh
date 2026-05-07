#!/usr/bin/env bash
# Fixture for Check 73 — missing LSDD-PT-Etapa pattern.
# This is a synthesized autonomy-guard variant where the LSDD-PT-Etapa pattern
# has been REMOVED. Check 73 sub-assert (f) verifies that this fixture does NOT
# block "Etapa 5 paralelo" — proving Check 73 catches the regression.
#
# DO NOT modify this fixture. It must permanently lack LSDD-PT-Etapa.

set -euo pipefail

# Read input message
MSG="$(cat)"

# Mini regex set — INTENTIONALLY missing LSDD-PT-Etapa to prove fixture-fail
PATTERNS=$(cat <<'FIXTURE_EOF'
[Pp]hase [A-Z].*(complete|completa|completo|done|paralelo|seguir|working|remaining|shipped|finalizada|finalizado|pronta|in progress)	LSDD-EN-Phase-letter
[Pp]hase [0-9]+.*(complete|completa|completo|done|paralelo|seguir|working|remaining|shipped|finalizada|finalizado|pronta|in progress)	LSDD-EN-Phase-numeric
[Rr]ound [0-9]+.*(complete|completa|completo|done|paralelo|seguir|working|remaining|shipped|finalizada|finalizado|pronta|in progress)	LSDD-EN-Round
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

# No match — silent allow
exit 0
