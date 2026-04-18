# aih-milestone annex: Milestone Execution

Triggered when `/aih-milestone --execute [description]` runs, when a ready draft is dispatched, or when `/aih-plan --plan [slug]` threshold gate confirms execution. Pre-v0.11.0 this lived in `/aih-run` (since retired — split between `/aih-milestone` execution here and `/aih-feature` for single-plan small-scope execution).

---

## Pre-flight (M005 behavioral invariants — port verbatim, do not paraphrase)

### Git status tiered auto-decide (M005 S04/B2)

Run `git status --porcelain`. Policy: clean OR all-untracked → proceed silently. 1-5 modified, no staged → auto-stash as `aih-milestone pre-run stash [slug] [iso-ts]`, log to RUN-MANIFEST.md, proceed; mention stash in final report. >5 modified OR any staged → TRUE blocker, pause and ask "Commit, stash, or abort?"

### Candidate discovery — single-candidate silent proceed (M005 S05/B3)

When no slug is given, scan:
- `Glob` `.aihaus/milestones/drafts/*/STATUS.md` — drafts with status `ready` or `gathering`
- `Glob` `.aihaus/plans/*/PLAN.md` — plans whose slug does NOT already have a milestone dir under `.aihaus/milestones/`

Build a table and present it:
```
# | Type            | Slug                    | Status    | Updated
1 | milestone-draft | 260412-user-auth        | ready     | [mtime]
2 | milestone-draft | 260411-billing-refactor | gathering | [mtime]
3 | plan            | 260410-rate-limiting    | —         | [mtime]
```

- **One candidate** → proceed silently; log one line: *"Running [slug]."* (No Y/n — see `_shared/autonomy-protocol.md`.)
- **Multiple** → ask user to pick by number or slug.
- **Zero** → "No ready work. Run `/aih-plan` or `/aih-milestone` first." Stop.

### 3-bullet pre-flight summary (M005 S08/B1)

Emit 3-bullet pre-flight summary, then proceed. Do not ask for approval — the user invoked the skill already; that is the threshold gate per `_shared/autonomy-protocol.md`. Dispatch the agent team immediately after the summary line.

---

## Routing (for plan candidates only)

If the candidate is a `milestone-draft`, skip to **Milestone Execution** below.

If the candidate is a `plan`: read the plan's "Estimated Scope" section.
- **Small scope** (< 10 files, single-story) → hand off to `/aih-feature [slug]` (feature execution inline: `feature/[slug]` branch, `.aihaus/features/[YYMMDD]-[slug]/` artifacts). Do NOT run milestone execution here.
- **Large scope** (multi-story or > 10 files) → auto-promote to milestone draft by running `annexes/promotion.md` Steps P1-P4 inline (seed a draft from the plan), then continue with **Milestone Execution** below on the new draft.

---

## Milestone Execution

> **Execution-phase autonomy reminder** (enforced at runtime via
> `autonomy-guard.sh` Stop hook): during the Wave 2 per-story loop
> and every step below, NEVER emit `Checkpoint honesto`, `Opção
> sua`, `Qual prefere?`, lettered menus `(a)/(b)/(c)`, numbered
> menus `1. → / 2. → / 3. →`, `Pausing to...`, `Three realistic
> forks`, `Realista: 4-6h+`, or `retoma com /aih-...`. Pick safer
> default per `_shared/autonomy-protocol.md` TRUE blocker test
> (L15-31), log the choice in RUN-MANIFEST progress log, proceed
> silently. The Stop hook blocks the turn on forbidden patterns.

### Task tracking (two waves)

**Wave 1** — create as `pending` at Phase-start using TaskCreate:

| Subject | activeForm |
|---------|-----------|
| Run analysis brief | Analyzing milestone scope |
| Write PRD and stories | Writing PRD and stories |
| Design architecture | Designing architecture |
| Verify plan coherence | Checking plan coherence |

Chain sequentially. **Wave 2** (per-story tasks + completion) is created after planning completes.

Before each step, set its task to `in_progress`. After completion, set to `completed`.

### Step E1 — Determine Milestone ID

Scan for existing milestone directories to determine the next ID:
- `Glob` for `M0*` directories in `.aihaus/milestones/`
- Extract numeric IDs, find the maximum, increment by 1
- Format: `M0XX` (pad with leading zeros)

### Step E2 — Create directory + RUN-MANIFEST

Create `.aihaus/milestones/[M0XX]-[slug]/`:
```
stories/
execution/
execution/reviews/
execution/DECISIONS-LOG.md
execution/KNOWLEDGE-LOG.md
execution/AGENT-EVOLUTION.md    ← scaffolded here; Step 4.5 consume-check is non-trivially true
RUN-MANIFEST.md       ← new checkpoint file
```

`execution/AGENT-EVOLUTION.md` initial content (scaffold only; content accumulates during milestone execution via implementer/reviewer proposals):
```markdown
# Agent Evolution Proposals — [M0XX]-[slug]

Agent-evolution proposals accumulated during milestone execution.
Applied at completion-protocol Step 4.5 by the orchestrator.
Each proposal must include: agent name, evidence (file path + symptom), proposed change, story that surfaced it.

---

<!-- proposals appended below during execution -->
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

### Step E3 — Planning (sequential subagents)

Spawn planning agents sequentially, updating RUN-MANIFEST.md progress log after each.

**Attachments handoff:** If `.aihaus/milestones/[M0XX]-[slug]/attachments/` has files, include this block in every agent spawn prompt:
```
## Attachments Available
The following files may be relevant to your task. Read them as needed.
- attachments/01-[desc].png — [one-line description]
- attachments/02-[desc].pdf — [one-line description]
Use the Read tool to view. Reference what you observed in your output using relative paths.
```

- **analyst** → writes `analysis-brief.md` (uses CONTEXT.md as input).
- **product-manager** → reads analysis brief, writes `PRD.md` and `stories/`.
- **architect** → reads PRD/stories, writes `architecture.md`, appends ADRs to `.aihaus/decisions.md`.
- **plan-checker** → verifies story coherence, file ownership, ADR coverage.

Wait for each to complete before spawning the next. After plan-checker, advance phase via `bash .aihaus/hooks/phase-advance.sh --to running --dir <milestone-dir>` AND `manifest-append.sh --field phase --payload execute-stories`.

**Agent return post-processing (ADR-003 marker protocol):** after each agent spawn, pipe the agent's return through `bash .aihaus/hooks/invoke-guard.sh`. On `INVOKE_OK skill|args|rationale|blocking`: if manifest is v1, first `manifest-migrate.sh`; then prompt user (or auto-dispatch if `aihaus.autoInvoke: true`); `manifest-append.sh --field invoke-push --payload "..."`; dispatch via Skill tool; `manifest-append.sh --field invoke-pop`. On `INVOKE_REJECT <reason>` or `NO_INVOKE`: log + proceed normally.

### Step E4 — Create feature branch

```bash
git checkout -b milestone/[M0XX]-[slug]
```

### Step E5 — Spawn agent team

Read `team-template.md` (co-located with this annex's SKILL.md). Spawn:
- **backend-dev** (implementer), **frontend-dev** (frontend-dev), **qa** (reviewer)
- Skip frontend-dev if backend-only, vice versa. Second dev if >8 stories.
- Quality gates: **ux-designer** if frontend stories exist; **security** pass if auth/payments/user-data touched.

**MANIFEST_PATH env injection (M011/S03 — F-04 resolution):** every Agent-tool spawn prompt in Steps E5 / E6 / E7 MUST begin with a one-line env-hint so worktree-isolated subagents can resolve Q-4 case 1 deterministically:

```
MANIFEST_PATH="<abs-path-to-main-repo>/.aihaus/milestones/M0XX-<slug>/RUN-MANIFEST.md"
```

Resolve `<abs-path>` from the milestone directory at spawn time (same variable the dispatcher itself uses for `manifest-append.sh` calls). Inherited by the spawned Agent's bash processes so `statusline-milestone.sh` and `autonomy-guard.sh` (paused short-circuit) see Q-4 case 1 hit even when the hook fires inside a git worktree.

### Step E6 — Execute stories (Wave 2 task creation)

Read story files from `stories/`. For each story, TaskCreate with:
- **subject**: story title
- **activeForm**: `Implementing [story title]`
- **description**: story file path, summary/review paths, owned files, log reminders

Chain by story dependency order. First story blocked by "Verify plan coherence"; last story blocks completion. After all story tasks, create final task `Run completion protocol`. Assign stories to teammates, monitor progress, handle QA cycles.

**Story serialization (prevents commit attribution race):** complete each story's full cycle — implement → QA pass → merge-back → commit → `git status` clean — BEFORE spawning the next story's teammate. Between stories, verify `git status --porcelain` is empty. If unexpected files appear (orphans from a prior worktree merge-back), STOP and surface to user; do not sweep them into the next commit. Commits must use explicit file lists from the story's `Owned files` (never `git add <dir>/`, never `git add -A`). See `team-template.md` → Commit Discipline and Worktree Merge-Back Protocol.

Update RUN-MANIFEST.md after each story: `manifest-append.sh --field story-record --payload "<story_id>|complete|<started>|<sha>|<verified>|<notes>"` + `manifest-append.sh --field progress-log --payload "Story [N] complete: [title]"`.

**Mid-story inventory refresh:** after each story's QA passes and commit lands, check if the committed paths fall within Inventory directories (same detection as `completion-protocol.md` Step 6). If yes, spawn `project-analyst` with `subagent_type: "project-analyst"` in `--refresh-inventory-only` mode and merge the AUTO block of `.aihaus/project.md`. Append `[ts] — project.md inventory refreshed after story [N]` to RUN-MANIFEST.md. Skip if the story was documentation-only. Also refresh Active Milestones since phase may have changed.

**CRITICAL:** The coordinating skill is the COORDINATOR. Never write code in the coordinator itself. Delegate everything.

### Step E7 — Verify and integrate (adversarial gates, always-on)

After all stories are implemented and QA-passed, run in parallel:
- Spawn `verifier` with `subagent_type: "verifier"` — goal-backward check, must produce evidence per acceptance criterion or FAIL. Writes `execution/VERIFICATION.md`.
- Spawn `integration-checker` with `subagent_type: "integration-checker"` — checks E2E wiring across the committed stories. Writes `execution/INTEGRATION.md`.
- If the milestone touches auth, payments, PII, sessions, or any stack-identified sensitive area: spawn `security-auditor` with `subagent_type: "security-auditor"`. Writes `execution/SECURITY.md`.

Any FAIL verdict or unmitigated OPEN threat halts before completion protocol — surface to user.

### Step E8 — Completion

Read `completion-protocol.md` (co-located with SKILL.md). Follow it: merge decisions, promote knowledge, write MILESTONE-SUMMARY.md, clean up the team, report to user.

---

## Finalize

### Step F1 — Update RUN-MANIFEST.md

`manifest-append.sh --field status --payload completed` + `--field phase --payload completed` + `phase-advance.sh --to complete --dir <milestone-dir>`.

### Step F2 — Report

Summarize:
- Command that ran, slug, branch, commit range
- Stories completed, decisions promoted, knowledge added
- Artifact path: `.aihaus/milestones/[M0XX]-[slug]/`
- Next: "Merge or push the branch."

---

## Hook-call reference table (port verbatim)

Each hook invocation below MUST land in the annex with the `--field` / `--payload` args exactly as shown. Silent paraphrase breaks ADR-004's phase-advance contract (which refuses advance when the Invoke stack is non-empty — the stack rows are written by the `invoke-push`/`invoke-pop` calls below).

| Call site | Hook | Args |
|-----------|------|------|
| Story start (Step E6) | `manifest-append.sh` | `--field story-record --payload "<story_id>|<status>|<started>|<sha>|<verified>|<notes>"` |
| Phase transition (Step E3 end) | `manifest-append.sh` | `--field phase --payload <phase>` |
| Phase transition (Step E3 end) | `phase-advance.sh` | `--to <phase> --dir <milestone-dir>` |
| Before Agent spawn (dispatcher mode, ADR-003) | `manifest-append.sh` | `--field invoke-push --payload "<skill>|<args>|<rationale>|<blocking>|<depth>"` |
| After Agent returns | `manifest-append.sh` | `--field invoke-pop --payload "<skill>"` |
| Per-story progress (Step E6) | `manifest-append.sh` | `--field progress-log --payload "<1-line msg>"` |
| End of milestone loop (Step F1) | `manifest-append.sh` | `--field status --payload completed` |
| End of milestone loop (Step F1) | `manifest-append.sh` | `--field phase --payload completed` |
| End of milestone loop (Step F1) | `phase-advance.sh` | `--to complete --dir <milestone-dir>` |
| Agent-return parsing (Step E3) | `invoke-guard.sh` | stdin = agent return text; consumed by parent skill for dispatch decision |
| Before every Agent spawn (Steps E5/E6/E7) | (env hint) | Inject `MANIFEST_PATH=<abs-path>` into the prompt body so worktree-isolated subagents resolve Q-4 case 1 deterministically (M011/S03 F-04). |

---

## Guardrails

- NEVER execute story code in the coordinator. Delegate everything via Agent tool to `implementer` / `frontend-dev` / `code-fixer` (worktree-isolated).
- NEVER use `git add -A` or `git add <dir>/` during story commits. Always explicit file list from `Owned files`.
- NEVER edit RUN-MANIFEST.md or STATUS.md inline. Use `manifest-append.sh` + `phase-advance.sh` hooks (ADR-004).
- Pause ONLY on TRUE blockers (see `_shared/autonomy-protocol.md`). "Estimate was wrong" is not a blocker.
