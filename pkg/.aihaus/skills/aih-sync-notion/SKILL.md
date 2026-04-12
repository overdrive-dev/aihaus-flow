---
name: aih-sync-notion
description: Sync the Notion Kanban board with current execution state. Updates card statuses, creates missing cards, and verifies role coverage.
disable-model-invocation: true
context: fork
agent: aihaus-notion-sync
allowed-tools: Read Write Edit Grep Glob Bash
argument-hint: "[action: sync|triage|verify|status]"
---

## Phase 0: Configuration Check

Before executing any action, verify that Notion sync is configured:

1. Check if `.aihaus/notion/config.json` exists
2. If **missing**:
   - Inform the user that Notion sync requires configuration
   - Offer to scaffold from the template:
     ```
     mkdir -p .aihaus/notion
     cp .aihaus/templates/notion/config.example.json .aihaus/notion/config.json
     ```
   - Print: "Configuration scaffolded. Edit `.aihaus/notion/config.json` with
     your Notion database ID, status names, roles, and sync commands.
     See `.aihaus/templates/notion/SETUP.md` for full setup instructions."
   - Stop execution — do not proceed to any action until config is valid
3. If **present**, read it and validate that `notion_database_id` is not
   `"YOUR_NOTION_DATABASE_ID"` (the placeholder value)
4. Check that `NOTION_TOKEN` is set in the environment

Only proceed to the requested action after Phase 0 passes.

## Task
Synchronize the Notion Kanban board with the current project state.

Action: $ARGUMENTS

## Actions

### sync (default)
Read the current execution state from `.aihaus/milestones/[M0XX]-[slug]/execution/`
and planning artifacts, then sync all card statuses to Notion.
1. Read story summaries in `.aihaus/milestones/[M0XX]-[slug]/execution/*-SUMMARY.md`
2. Read QA reviews in `.aihaus/milestones/[M0XX]-[slug]/execution/reviews/`
3. Map story status to Notion status using `status_flow` from `.aihaus/notion/config.json`
4. Update `.aihaus/notion/sync-items.json`
5. Run the `sync` command from `.aihaus/notion/config.json`
6. Report what changed

### triage
Fetch and triage client requests from the intake column (the `request` status in config).
1. Query the intake status using the `query` command from config
2. Summarize each request
3. Identify duplicates and dependencies
4. Propose categorization: milestone task / Icebox / needs clarification

### verify
Verify role coverage and board health after a sync.
1. Check all expected roles have cards for each item
2. Verify Kanban view configuration
3. Report any gaps

### status
Quick status check — show current board state without modifying anything.
1. Query each active status column
2. Report card counts per status per role

## Capture, Don't Execute (triage discipline)
During card triage and intake sync, if the user describes an implementable change mid-conversation ("and also fix the login logo"), capture it as a new card or an appended checklist item on the relevant card — do NOT checkout a branch, edit code, or commit. The triage session is about *organizing work*, not doing it. Explicit execution signals ("fix this now") hand off to `/aih-quick` or `/aih-bugfix`; acknowledge the context switch and return to triage after.

## Context
- Read `.aihaus/notion/config.json` for all configurable values (statuses, roles, fields, commands)
- Read `.aihaus/notion/runbook.md` (if present) for the full sync protocol specific to this project
- Read `.aihaus/notion/sync-items.json` for the current catalog
- Read `.aihaus/milestones/[M0XX]-[slug]/execution/` for the latest implementation state
- Read `.aihaus/project.md` for project-level context
- Requires `NOTION_TOKEN` in the environment
