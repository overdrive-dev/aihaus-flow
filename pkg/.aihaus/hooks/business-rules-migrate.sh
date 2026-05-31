#!/bin/bash
set -uo pipefail

# business-rules-migrate.sh — one-time LOSSY migration of per-plan BUSINESS-RULES.md
# (plan-calibrator's Confirmed-Rules table) into the project-wide ledger
# (.aihaus/memory/workflows/business-rules.md, BDD format). Per ADR-260531-A.
#
# LOSSY: the table has no Given/When/Then scenarios, no domain, no code bindings.
# Migrated rules carry the statement + provenance (plan slug, source-line,
# confidence) but a scenario/domain PLACEHOLDER for you to complete — the rule-gate
# keeps flagging them until a real scenario is added. They land under a clearly
# marked "## Migrated rules (review …)" section so they're easy to triage.
#
# Idempotent: skips plans already recorded in the migration marker, and skips any
# rule whose statement already appears in the ledger.
#
# Usage: bash business-rules-migrate.sh [--dry-run]
# Opt-out of the marker write: --dry-run (prints what would migrate, changes nothing).

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/path-helpers.sh
. "${HOOK_DIR}/lib/path-helpers.sh"

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

ROOT="$(aihaus_project_root)"
LEDGER="${ROOT}/.aihaus/memory/workflows/business-rules.md"
MARKER="${ROOT}/.aihaus/memory/workflows/.business-rules-migrated"
PLANS_DIR="${ROOT}/.aihaus/plans"

if [ ! -f "$LEDGER" ]; then
  echo "business-rules-migrate: no ledger at ${LEDGER#"$ROOT"/} — run the installer first." >&2
  exit 1
fi
if [ ! -d "$PLANS_DIR" ]; then
  echo "business-rules-migrate: no .aihaus/plans/ — nothing to migrate."
  exit 0
fi

# Next BR id = max existing ### BR-<num> in the ledger + 1 (covers the commented
# template example too, so we never collide).
_max="$(grep -oE '^###[[:space:]]+BR-[0-9]+' "$LEDGER" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1)"
next_id=$(( ${_max:-0} + 1 ))

date_now="$(date -u +%F 2>/dev/null || echo 'unknown')"
migrated=0
buf=""

for brf in "$PLANS_DIR"/*/BUSINESS-RULES.md; do
  [ -f "$brf" ] || continue
  slug="$(basename "$(dirname "$brf")")"
  if [ -f "$MARKER" ] && grep -qxF "$slug" "$MARKER" 2>/dev/null; then
    continue
  fi
  # Confirmed-Rules data rows: `| <n> | <rule> | <source> | <confidence> |`.
  # The `^\|\s*[0-9]+\s*\|` anchor skips the header (`| # |`) + separator (`|---|`).
  while IFS= read -r line; do
    rule="$(printf '%s' "$line" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$3); print $3}')"
    src="$(printf '%s'  "$line" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$4); print $4}')"
    conf="$(printf '%s' "$line" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$5); print $5}')"
    [ -z "$rule" ] && continue
    grep -qF "$rule" "$LEDGER" 2>/dev/null && continue   # already present
    id="$(printf 'BR-%03d' "$next_id")"
    next_id=$(( next_id + 1 ))
    buf="${buf}
### ${id} — ${rule}
- **domain:** software
- **statement:** ${rule}
- **scenarios:**
  - Given <TODO context>, When <TODO action>, Then <TODO outcome>
- **status:** accepted
- **source:** migrated from plan ${slug} (${src:-?}, confidence ${conf:-?}), ${date_now}
- **links:** implements:[] · relates:[] · decided-by:[]
- **last-reviewed:** -
"
    migrated=$(( migrated + 1 ))
  done < <(grep -E '^\|[[:space:]]*[0-9]+[[:space:]]*\|' "$brf" 2>/dev/null)
  [ "$DRY" -eq 0 ] && printf '%s\n' "$slug" >> "$MARKER"
done

if [ "$migrated" -eq 0 ]; then
  echo "business-rules-migrate: nothing new to migrate."
  exit 0
fi

if [ "$DRY" -eq 1 ]; then
  echo "business-rules-migrate (--dry-run): would migrate ${migrated} rule(s):"
  printf '%s\n' "$buf"
  exit 0
fi

{
  printf '\n## Migrated rules (review — set the domain + add a Given/When/Then)\n'
  printf '%s\n' "$buf"
} >> "$LEDGER"

echo "business-rules-migrate: migrated ${migrated} rule(s) into the ledger. Review the '## Migrated rules' section — set each domain + add a real scenario (the rule-gate flags them until then)."
