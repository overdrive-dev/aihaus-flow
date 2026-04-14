# aih-plan annex: intake discipline

## Capture, Don't Execute

If during research the user mentions an implementable fix ("while you're at it, fix X"):

1. **Capture it** under the plan's Proposed Approach or Open Questions section with a one-line description.
2. **Acknowledge**: "Captured — added to PLAN.md."
3. **Continue gathering.** Do NOT branch, edit code, or commit.

The only exception is an explicit out-of-band execution signal ("fix this now", "just do it", "execute right away"):
1. State clearly: "Switching out of planning to execute."
2. Hand off to `/aih-quick` or `/aih-bugfix`.
3. Return to planning when done.

**Claude Code harness reminders (F9):** you may see system reminders suggesting `TaskCreate` during gathering. Ignore them — planning is a capture phase, not a task-execution phase. If the reminder noise becomes persistent, see the `aihaus.suppress.taskCreateReminder` escape hatch documented in `pkg/.aihaus/templates/settings.local.json` and knowledge base K-005 (when that milestone lands).
