---
name: aih-run
description: "Execute a ready milestone draft or plan autonomously. No slug required — picks from available drafts/plans. Writes RUN-MANIFEST.md checkpoints."
disable-model-invocation: true
allowed-tools: Read Grep Glob Bash Write Edit Agent TaskCreate TaskUpdate
argument-hint: "[slug (optional)]"
---

## Task
Pick a ready milestone draft or plan and execute it autonomously, start to finish.

$ARGUMENTS

## Phase 1 — Candidate Selection

### 1. If a slug is given
Look up the slug in this order. Stop at the first match:
1. `.aihaus/milestones/drafts/[slug]/CONTEXT.md` → type: `milestone-draft`
2. `.aihaus/plans/[slug]/PLAN.md` → type: `plan`
If neither exists, stop and tell the user.

### 2. If no slug is given — discover candidates
Scan:
- `Glob` `.aihaus/milestones/drafts/*/STATUS.md` — drafts with status `ready` or `gathering`
- `Glob` `.aihaus/plans/*/PLAN.md` — plans whose slug does NOT already have a milestone dir under `.aihaus/milestones/`

Build a table and present it:
```
# | Type            | Slug                    | Status    | Updated
1 | milestone-draft | 260412-user-auth        | ready     | [mtime]
2 | milestone-draft | 260411-billing-refactor | gathering | [mtime]
3 | plan            | 260410-rate-limiting    | —         | [mtime]
```

- **One candidate** → confirm ("Run [slug]? Y/n") and proceed.
- **Multiple** → ask user to pick by number or slug.
- **Zero** → "No ready work. Run `/aih-plan` or `/aih-milestone` first." Stop.

### 3. Load Context
- Read `.aihaus/memory/MEMORY.md` and any relevant memory files
- Read `.aihaus/project.md` (if present) for project-level context
- Read `.aihaus/decisions.md` (if present) — follow all existing ADRs
- Read `.aihaus/knowledge.md` (if present) — avoid known pitfalls

### 4. Git Status Check
Run `git status`. If the working tree is dirty, warn and ask: "Stash, commit, or proceed as-is?"

## Phase 2 — Routing

### 5. Route by candidate type

**If `milestone-draft`:** go to Milestone Execution (Phase 3).

**If `plan`:** read the plan's "Estimated Scope" section.
- **Small scope** (< 10 files, single-story) → feature execution inline:
  - Create `feature/[slug]` branch
  - Implement per plan's Proposed Approach
  - Run verification (project-specific)
  - Commit + write artifacts to `.aihaus/features/[YYMMDD]-[slug]/`
  - Skip to Phase 4 (reporting)
- **Large scope** (multi-story or > 10 files) → auto-promote to milestone draft:
  - Run `/aih-plan-to-milestone [slug]` logic inline (seed a draft from the plan)
  - Continue with Milestone Execution on the new draft

### 6. Confirm execution
Present the final summary from CONTEXT.md (or PLAN.md) and ask for approval before spawning agents.

## Phase 3 — Milestone Execution

### Phase 3 Task Tracking (two waves)
**Wave 1** — create as `pending` at Phase 3 start using TaskCreate:
| Subject | activeForm |
|---------|-----------|
| Run analysis brief | Analyzing milestone scope |
| Write PRD and stories | Writing PRD and stories |
| Design architecture | Designing architecture |
| Verify plan coherence | Checking plan coherence |
Chain sequentially. **Wave 2** (per-story tasks + completion) is created in Step 12.
Before each step, set its task to `in_progress`. After completion, set to `completed`.

### 7. Determine Milestone ID
Scan for existing milestone directories to determine the next ID:
- `Glob` for `M0*` directories in `.aihaus/milestones/`
- Extract numeric IDs, find the maximum, increment by 1
- Format: `M0XX` (pad with leading zeros)

### 8. Create Directory + RUN-MANIFEST
Create `.aihaus/milestones/[M0XX]-[slug]/`:
```
stories/
execution/
execution/reviews/
execution/DECISIONS-LOG.md
execution/KNOWLEDGE-LOG.md
RUN-MANIFEST.md       ← new checkpoint file
```

RUN-MANIFEST.md initial content (schema v2 per ADR-004 — see `pkg/.aihaus/templates/RUN-MANIFEST-schema-v2.md`):
```markdown
## Metadata
milestone: M0XX-[slug]
branch: milestone/M0XX-[slug]
started: [ISO]
schema: v2
phase: planning
status: running
last_updated: [ISO]

## Invoke stack

## Story Records
story_id|status|started_at|commit_sha|verified|notes
```

All subsequent RUN-MANIFEST.md mutations go via `bash .aihaus/hooks/manifest-append.sh --field <story-record|invoke-push|invoke-pop|progress-log|phase|status> --payload "..."`. STATUS.md mutations go via `bash .aihaus/hooks/phase-advance.sh --to <phase> --dir <dir>`. Never edit either file inline post-M003.

If the draft has `attachments/`, copy them into the new milestone dir before archiving:
```bash
if [ -d .aihaus/milestones/drafts/[slug]/attachments ]; then
  cp -R .aihaus/milestones/drafts/[slug]/attachments .aihaus/milestones/[M0XX]-[slug]/attachments
fi
```

Archive the draft: `mv .aihaus/milestones/drafts/[slug] .aihaus/milestones/drafts/.archive/[YYMMDD]-[slug]`

**Refresh Active Milestones** (if `.aihaus/project.md` exists): spawn `project-analyst` with `--refresh-active-milestones`, then merge the content of `.aihaus/.active-milestones-scratch.md` into `project.md` between `<!-- AIHAUS:ACTIVE-MILESTONES-START -->` and `<!-- AIHAUS:ACTIVE-MILESTONES-END -->` markers. Preserve everything outside those markers. Do the same refresh whenever RUN-MANIFEST.md status changes (running → paused, paused → running, etc.).

### 9. Planning — Sequential Agent Subagents
Spawn planning agents sequentially, updating RUN-MANIFEST.md progress log after each.

**Attachments handoff:** If `.aihaus/milestones/[M0XX]-[slug]/attachments/` has files, include this block in every agent spawn prompt:
```
## Attachments Available
The following files may be relevant to your task. Read them as needed.
- attachments/01-[desc].png — [one-line description]
- attachments/02-[desc].pdf — [one-line description]
Use the Read tool to view. Reference what you observed in your output using relative paths.
```

**analyst** → writes `analysis-brief.md` (uses CONTEXT.md as input).
**product-manager** → reads analysis brief, writes `PRD.md` and `stories/`.
**architect** → reads PRD/stories, writes `architecture.md`, appends ADRs to `.aihaus/decisions.md`.
**plan-checker** → verifies story coherence, file ownership, ADR coverage.

Wait for each to complete before spawning the next. After plan-checker, advance phase via `bash .aihaus/hooks/phase-advance.sh --to running --dir <milestone-dir>` AND `manifest-append.sh --field phase --payload execute-stories`.

**Agent return post-processing (ADR-003 marker protocol, stories A.2/A.3):** after each agent spawn, pipe the agent's return through `bash .aihaus/hooks/invoke-guard.sh`. On `INVOKE_OK skill|args|rationale|blocking`: if manifest is v1, first `manifest-migrate.sh`; then prompt user (or auto-dispatch if `aihaus.autoInvoke: true`); `manifest-append.sh --field invoke-push --payload "..."`; dispatch via Skill tool; `manifest-append.sh --field invoke-pop`. On `INVOKE_REJECT <reason>` or `NO_INVOKE`: log + proceed normally.

### 10. Create Feature Branch
```bash
git checkout -b milestone/[M0XX]-[slug]
```

### 11. Spawn Agent Team
Read `team-template.md` (co-located with this SKILL.md). Spawn:
- **backend-dev** (implementer), **frontend-dev** (frontend-dev), **qa** (reviewer)
- Skip frontend-dev if backend-only, vice versa. Second dev if >8 stories.
- Quality gates: **ux-designer** if frontend stories exist; **security** pass if auth/payments/user-data touched.

### 12. Execute Stories (Wave 2 task creation)
Read story files from `stories/`. For each story, TaskCreate with:
- **subject**: story title
- **activeForm**: `Implementing [story title]`
- **description**: story file path, summary/review paths, owned files, log reminders

Chain by story dependency order. First story blocked by "Verify plan coherence"; last story blocks completion. After all story tasks, create final task `Run completion protocol`. Assign stories to teammates, monitor progress, handle QA cycles.

**Story serialization (prevents commit attribution race):** complete each story's full cycle — implement → QA pass → merge-back → commit → `git status` clean — BEFORE spawning the next story's teammate. Between stories, verify `git status --porcelain` is empty. If unexpected files appear (orphans from a prior worktree merge-back), STOP and surface to user; do not sweep them into the next commit. Commits must use explicit file lists from the story's `Owned files` (never `git add <dir>/`, never `git add -A`). See `team-template.md` → Commit Discipline and Worktree Merge-Back Protocol.

Update RUN-MANIFEST.md after each story: `manifest-append.sh --field story-record --payload "<story_id>|complete|<started>|<sha>|<verified>|<notes>"` + `manifest-append.sh --field progress-log --payload "Story [N] complete: [title]"`.

**Mid-story inventory refresh:** after each story's QA passes and commit lands, check if the committed paths fall within Inventory directories (same detection as completion-protocol Step 6). If yes, spawn `project-analyst` with `subagent_type: "project-analyst"` in `--refresh-inventory-only` mode and merge the AUTO block of `.aihaus/project.md`. Append `[ts] — project.md inventory refreshed after story [N]` to RUN-MANIFEST.md. Skip if the story was documentation-only. Also refresh Active Milestones (see Step 8 pattern) since phase may have changed.

**CRITICAL:** You are the COORDINATOR. Never write code yourself. Delegate everything.

### 12.5. Verify and Integrate (adversarial gates, always-on)
After all stories are implemented and QA-passed, run in parallel:
- Spawn `verifier` with `subagent_type: "verifier"` — goal-backward check, must produce evidence per acceptance criterion or FAIL. Writes `execution/VERIFICATION.md`.
- Spawn `integration-checker` with `subagent_type: "integration-checker"` — checks E2E wiring across the committed stories. Writes `execution/INTEGRATION.md`.
- If the milestone touches auth, payments, PII, sessions, or any stack-identified sensitive area: spawn `security-auditor` with `subagent_type: "security-auditor"`. Writes `execution/SECURITY.md`.

Any FAIL verdict or unmitigated OPEN threat halts before completion protocol — surface to user.

### 13. Completion
Read `completion-protocol.md` (co-located). Follow it: merge decisions, promote knowledge, write MILESTONE-SUMMARY.md, clean up the team, report to user.

## Phase 4 — Finalize

### 14. Update RUN-MANIFEST.md
`manifest-append.sh --field status --payload completed` + `--field phase --payload completed` + `phase-advance.sh --to complete --dir <milestone-dir>`.

### 15. Report
Summarize:
- Command that ran, slug, branch, commit range
- Stories completed, decisions promoted, knowledge added
- Artifact path: `.aihaus/milestones/[M0XX]-[slug]/`
- Next: "Merge or push the branch."
