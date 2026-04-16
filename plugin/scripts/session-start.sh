#!/bin/bash
set -euo pipefail

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export AIHAUS_PROJECT_DIR=\"$CLAUDE_PROJECT_DIR\"" >> "$CLAUDE_ENV_FILE"
fi

# Inject project status context from .aihaus/ artifacts
PLANNING_STATUS=""

# .aihaus/ artifact detection
AIHAUS_MS=$(ls -d "$CLAUDE_PROJECT_DIR/.aihaus/milestones"/M0* 2>/dev/null | wc -l || true)
[ "$AIHAUS_MS" -gt 0 ] 2>/dev/null && PLANNING_STATUS="${PLANNING_STATUS}milestones:${AIHAUS_MS} "
AIHAUS_FT=$(ls -d "$CLAUDE_PROJECT_DIR/.aihaus/features"/*/ 2>/dev/null | wc -l || true)
[ "$AIHAUS_FT" -gt 0 ] 2>/dev/null && PLANNING_STATUS="${PLANNING_STATUS}features:${AIHAUS_FT} "
AIHAUS_PL=$(ls -d "$CLAUDE_PROJECT_DIR/.aihaus/plans"/*/ 2>/dev/null | wc -l || true)
[ "$AIHAUS_PL" -gt 0 ] 2>/dev/null && PLANNING_STATUS="${PLANNING_STATUS}plans:${AIHAUS_PL} "

# project.md presence
[ -f "$CLAUDE_PROJECT_DIR/.aihaus/project.md" ] && PLANNING_STATUS="${PLANNING_STATUS}project.md:ready "

jq -n --arg status "${PLANNING_STATUS:-no artifacts yet}" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: ("aihaus status: " + $status + ". Use /aih-init to bootstrap project.md, /aih-plan to scope work, /aih-milestone to build, /aih-help for all commands.")
  }
}'
