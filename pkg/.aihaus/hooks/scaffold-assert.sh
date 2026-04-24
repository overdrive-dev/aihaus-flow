#!/usr/bin/env bash
# scaffold-assert.sh — gate hook: asserts AGENT-EVOLUTION.md and SKILL-EVOLUTION.md
#                      scaffolds exist in <milestone-dir>/execution/ with ≥1 non-empty,
#                      non-comment line before the planning→running phase transition.
#
# ADR-004 extension — exit 13 is the RUN-MANIFEST gate-failure code. Reusing it means
# existing tooling (statusline-milestone, autonomy-guard, manifest-migrate) interprets
# the failure correctly without new code paths.
#
# ADR-M016-B amendment: scaffold-assert.sh is recognized as a Step E2 gate.
# Wired into phase-advance.sh exclusively on the planning→running transition.
#
# Usage: scaffold-assert.sh <milestone-dir>
#   Called by phase-advance.sh on the planning→running transition.
#   Defensive: exits 0 (silently) if <milestone-dir> arg is missing or not a directory.
#
# Exit codes: 0 ok (both scaffolds present with content), 13 gate failure (scaffold absent or empty)
#
# TODO (M016/S16): smoke-test.sh should add a fixture for scaffold-assert.sh
# to exercise the exit-13 path. See architecture §7 S11a + S16 smoke-test additions.
set -uo pipefail

MILESTONE_DIR="${1:-}"

# --- defensive: missing or invalid arg → silent pass (caller error, not gate failure) ---
[ -d "$MILESTONE_DIR" ] || exit 0

AGENT_EVO="$MILESTONE_DIR/execution/AGENT-EVOLUTION.md"
SKILL_EVO="$MILESTONE_DIR/execution/SKILL-EVOLUTION.md"

# --- helper: check file exists and has ≥1 non-empty, non-comment line ---
has_content() {
  local file="$1"
  [ -f "$file" ] || return 1
  # grep -v strips blank lines and HTML comment lines; -c counts remaining lines
  local content_lines
  content_lines=$(grep -cv '^\s*$\|^\s*<!--' "$file" 2>/dev/null || echo 0)
  [ "$content_lines" -ge 1 ]
}

# --- assert AGENT-EVOLUTION.md ---
if [ ! -f "$AGENT_EVO" ]; then
  printf 'scaffold-assert.sh: FATAL — AGENT-EVOLUTION.md missing from %s/execution/\n' \
    "$MILESTONE_DIR" >&2
  exit 13
fi

if ! has_content "$AGENT_EVO"; then
  printf 'scaffold-assert.sh: FATAL — AGENT-EVOLUTION.md exists but has no non-empty non-comment content in %s/execution/\n' \
    "$MILESTONE_DIR" >&2
  exit 13
fi

# --- assert SKILL-EVOLUTION.md ---
if [ ! -f "$SKILL_EVO" ]; then
  printf 'scaffold-assert.sh: FATAL — SKILL-EVOLUTION.md missing from %s/execution/\n' \
    "$MILESTONE_DIR" >&2
  exit 13
fi

if ! has_content "$SKILL_EVO"; then
  printf 'scaffold-assert.sh: FATAL — SKILL-EVOLUTION.md exists but has no non-empty non-comment content in %s/execution/\n' \
    "$MILESTONE_DIR" >&2
  exit 13
fi

# --- both scaffolds present and have content ---
printf 'scaffold-assert.sh: OK — both scaffolds present\n' >&2
exit 0
