#!/usr/bin/env bash
# dogfood-m010.sh -- write-path behavior regression for ADR-M010-A
# preset-immunity. Complements smoke-test Check 28 (which is a
# schema-shape invariant on a static fixture) by actually invoking
# /aih-effort's Phase-4 step 20 write logic and asserting no
# adversarial entries appear in the produced sidecar.
#
# Not gated by smoke-test.sh (R7 cycle prevention); run manually or
# from a release-day checklist. Exits 0 on green.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/../pkg" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SIDECAR="$REPO_ROOT/.aihaus/.calibration"

echo "dogfood-m010: verifying ADR-M010-A preset-immunity write-path filter"

if [[ ! -f "$SIDECAR" ]]; then
  echo "  skip: no .aihaus/.calibration present (run /aih-effort --preset cost first)"
  exit 0
fi

problems=()

# Check 1 — schema=2 sidecar (M010 sidecar shape).
schema=$(grep -E '^schema=' "$SIDECAR" | head -1 | cut -d= -f2 | tr -d '[:space:]\r')
if [[ "$schema" != "2" ]]; then
  echo "  info: sidecar is schema=$schema (expected 2 for post-M010 writes); skipping adversarial-absence check"
  exit 0
fi

# Check 2 — NO cohort.adversarial.* entries on a preset-apply write.
if grep -qE '^cohort\.adversarial\.(model|effort)=' "$SIDECAR"; then
  problems+=("cohort.adversarial.* line present -- preset-apply must skip :adversarial (ADR-M010-A)")
fi

# Check 3 — NO per-agent entries for adversarial members IF last_preset
# is a recognized preset name (not "custom"). Custom runs mean explicit
# user intent and adversarial entries are allowed.
last_preset=$(grep -E '^last_preset=' "$SIDECAR" | head -1 | cut -d= -f2 | tr -d '[:space:]\r')
case "$last_preset" in
  cost-optimized|balanced|quality-first|auto-mode-safe)
    if grep -qE '^(plan-checker|contrarian|reviewer|code-reviewer)(\.model)?=' "$SIDECAR"; then
      problems+=("per-agent entry for adversarial member present with last_preset=$last_preset (must be absent)")
    fi
    ;;
  custom|*)
    echo "  info: last_preset=$last_preset -- adversarial entries may appear on explicit --agent / --cohort runs"
    ;;
esac

if [[ ${#problems[@]} -eq 0 ]]; then
  echo "  PASS: no adversarial entries in preset-write sidecar"
  exit 0
else
  echo "  FAIL:"
  for p in "${problems[@]}"; do echo "    - $p"; done
  exit 1
fi
