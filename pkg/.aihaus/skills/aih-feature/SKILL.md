---
name: aih-feature
description: Implement a scoped feature — plan, branch, build, test, commit. Use for changes that fit in one session.
allowed-tools: Read Write Edit Grep Glob Bash TaskCreate TaskUpdate Skill
argument-hint: "[feature description] [--plan slug]"
---

## Task
Implement a scoped feature end-to-end: understand, plan, get approval, branch, build, test, review, commit.

$ARGUMENTS

## --plan Flag (optional)

If `$ARGUMENTS` contains `--plan`, extract the word immediately after `--plan` as the **slug**.

1. **Attempt to read** `.aihaus/plans/[slug]/PLAN.md`.
2. **If the file exists** AND has no unresolved `## Open Questions` section (or the section is empty): **skip Phase 1 entirely** — do NOT re-ask scoping questions, do NOT issue Step 5 "STOP HERE". The plan contains the approved analysis. Dispatch to Phase 2 immediately.
   - Emit a single 3-bullet pre-flight summary before Phase 2: (PLAN.md slug, Affected Files count, Estimated Scope). No interactive acknowledgment needed.
   - Carry the plan's "Affected Files" list as the authoritative scope for Phase 2. Do not re-scan the codebase.
   - In the Phase 2 RUN-MANIFEST progress log, note: "Using plan: `.aihaus/plans/[slug]/PLAN.md` — Phase 1 short-circuited."
3. **If the file exists** BUT contains an `## Open Questions` section with unresolved items: fall back to the full Phase 1 below — the plan is incomplete and needs scoping input before execution.
4. **If the file does not exist**, report this error and **stop**:
   > "Plan not found at `.aihaus/plans/[slug]/PLAN.md`. Run `/aih-plan` first to create it."
5. **If no `--plan` flag is present**, proceed normally — all Phase 1 steps below apply in full.

## Phase 1: Understand & Plan (interactive — ask questions, then wait for approval)

### Step 1: Load Context
1. Read `.aihaus/memory/MEMORY.md` and any relevant domain files it indexes
2. Read `.aihaus/project.md` (if present) for project-level context
3. Read `.aihaus/decisions.md` (if present) — do not contradict any ADR
4. Read `.aihaus/knowledge.md` (if present) — avoid known pitfalls

### Step 1.5: Persist Attachments
If the user's feature request includes pasted images (mockups, screenshots, references) or files:
1. Copy from source (e.g., `~/.claude/image-cache/[uuid]/[n].png`) to `.aihaus/features/[YYMMDD]-[slug]/attachments/[seq]-[desc].[ext]` via `cp`.
2. Describe each via vision.
3. List in PLAN.md `## Attachments` (Step 11 artifact). Reference in Approach when they inform decisions.
4. When spawning `code-reviewer`, `verifier`, or `integration-checker` later, include attachment paths so they can Read if relevant.

### Step 2: Check Working Tree
Run `git status` and `git branch --show-current`.
- If there are uncommitted changes, **warn the user** in your plan summary: "Your working tree has uncommitted changes. I can stash them before branching, or work on the current branch — your call."
- Note the current branch name for the plan summary.

### Step 3: Codebase Scan
Scan the codebase to understand what this feature touches:
1. Search for relevant models, endpoints, schemas, services, components
2. Identify every file that will need changes
3. Identify every file that will need to be created
4. Estimate the verification strategy (which tests, which type checks)

### Step 4: Escalation Check
Count the files identified in Step 3.
- If **>10 files** need changes, or the feature logically splits into **>3 independent stories** (distinct user-facing changes that could be separate commits), include this in your plan:
  > "This touches [N] files across [M] subsystems. Consider running `/aih-milestone` for better coordination. You can still proceed here if you prefer."
- This is a **suggestion**, not a gate. The user decides.

### Step 5: Present Plan & Ask Questions
Present a single message containing:
1. **Clarifying questions** (1-3 max) — ask everything in one batch
2. **Plan summary:**
   - Feature description (your understanding)
   - Files to change (full paths)
   - Files to create (full paths)
   - Approach (brief, technical)
   - Branch: `feature/[slug]` (slug = lowercase, hyphens, max 40 chars)
   - Verification: what tests and checks will run
   - Escalation warning (if triggered)
   - Dirty-state warning (if triggered)
3. **Ask for approval:** "Approve this plan to proceed, or adjust."

**STOP HERE. Wait for the user to respond.**

## Phase 2: Autonomous Execution (zero human input after approval)
**Pre-dispatch (L4/sentinel):** `bash .aihaus/hooks/worktree-reap.sh` (scan, no-op if none); `mkdir -p .claude/worktrees && printf '' > ".claude/worktrees/.session-$$.owned"` (sentinel for S02b L2 reader).

> **Execution autonomy** (enforced via `autonomy-guard.sh` Stop hook): NEVER emit `Checkpoint honesto`, `Opção sua`, `Qual prefere?`, `(a)/(b)/(c)`, numbered `1. →` menus, `Pausing to...`, `Three realistic forks`, `Realista: Nh+`, `retoma com /aih-...`. Pick safer default per `_shared/autonomy-protocol.md` TRUE blocker test (L15-31), log in RUN-MANIFEST, proceed silently. Hook blocks forbidden patterns.

> **MANIFEST_PATH env injection (M011/S03 — F-04):** when `--plan` carries a plan with a RUN-MANIFEST in play, every Agent-tool spawn prompt in Phase 2 (`code-reviewer`, `verifier`, `code-fixer`, `integration-checker`) MUST begin with `MANIFEST_PATH="<abs>/.aihaus/features/[YYMMDD]-[slug]/RUN-MANIFEST.md"` so worktree-isolated subagents resolve Q-4 case 1 deterministically (statusLine + autonomy-guard paused short-circuit).

### Phase 2 Task Tracking
Create all tasks as `pending` at the start of Phase 2 using TaskCreate:
| Subject | activeForm |
|---------|-----------|
| Create feature branch | Creating feature branch |
| Implement changes | Implementing changes |
| Run verification | Verifying build and tests |
| Self-review changes | Reviewing changes for issues |
| Commit changes | Committing changes |
| Write artifacts | Writing feature artifacts |
Chain dependencies sequentially. Before each step, set its task to `in_progress`. After completion, set to `completed`.

### Step 6: Create Branch + RUN-MANIFEST
- Derive `[slug]` from the feature description: lowercase, replace spaces with hyphens, truncate to 40 characters, strip trailing hyphens.
- If user said "stay on this branch" or "don't create a branch", skip branching.
- Otherwise: `git checkout -b feature/[slug]`
- If user approved stashing: `git stash` before branching, note to `git stash pop` after.
- Create `.aihaus/features/[YYMMDD]-[slug]/RUN-MANIFEST.md` with: Run ID, Command, Started ISO, Phase `implement`, Status `running`, Branch name. Update `Last updated` and append to Progress Log after each subsequent step.

### Step 7: Implement
- Make all changes identified in the plan.
- Follow existing patterns in neighboring files.
- Do NOT modify files outside the approved plan without noting why.

### Step 8: Verify
Run the verification commands appropriate to the areas touched (build, typecheck, unit tests, smoke tests). Use whatever the project already defines in its README or CONTRIBUTING docs. Run all relevant checks for every subsystem you changed. If tests fail, fix them. Do not skip.

### Step 9: Adversarial Review (delegate to code-reviewer, loop max 2)
Spawn `code-reviewer` with `subagent_type: "code-reviewer"` on the staged diff. Adversarial contract — must produce findings or written justification. Writes `.aihaus/features/[YYMMDD]-[slug]/REVIEW.md`.

- CRITICAL or HIGH findings → spawn `code-fixer` with `subagent_type: "code-fixer"` to apply fixes, then re-run reviewer.
- MEDIUM findings → inform user inline; proceed unless they object.
- LOW findings → note in SUMMARY.md.
- Cap at 2 review+fix iterations.

### Step 10: Commit
Create a single atomic commit:
```
feat: [concise description of what was added]

Feature: [feature slug]
Files: [count] changed, [count] created
```

### Step 11: Write Artifacts
Determine the artifact directory: `.aihaus/features/[YYMMDD]-[slug]/`
where `[YYMMDD]` is today's date (e.g., `260410`).

Create these files:

**PLAN.md** — The plan that was approved:
```markdown
# Feature: [title]
**Date:** [YYYY-MM-DD]
**Branch:** feature/[slug]
**Files changed:** [list]
**Files created:** [list]
**Approach:** [what was done and why]
```

**SUMMARY.md** — What actually happened:
```markdown
# Feature Summary: [title]
**Date:** [YYYY-MM-DD]
**Branch:** feature/[slug]
**Commit:** [hash]
**Status:** Complete

## What Changed
[Prose description of the implementation]

## Verification
[What tests passed, what checks ran]
```

**decisions.md / knowledge.md** — Optional per-feature notes (if any decisions or discoveries were made):
```markdown
# Decisions / Knowledge: [feature title]
<!-- Append one entry per decision or discovery during implementation -->
```

### Step 11.5: Goal-Backward Verification (delegate to verifier)
Spawn `verifier` with `subagent_type: "verifier"`. Adversarial — must verify each acceptance criterion with evidence or FAIL. Writes `.aihaus/features/[YYMMDD]-[slug]/VERIFICATION.md`. If FAIL or PASS-WITH-GAPS: flag for user review before reporting completion.

### Step 11.7: Integration Check (conditional, delegate to integration-checker)
If the feature touches more than one subsystem (check changed paths against `project.md` Inventory directories, or common fallback patterns like `models/`, `routes/`, `components/`, `api/`), spawn `integration-checker` with `subagent_type: "integration-checker"`. Writes `INTEGRATION.md`. Broken connections raised for user review.

### Step 12: Update project.md if structural changes were made
Runs AFTER the commit. If `.aihaus/project.md` does not exist, print
`"project.md not found, skipping update"` and continue to Step 13.

1. Collect changed paths: `git show --name-only --pretty=format: HEAD | sort -u`.
2. Detect structural change by checking if any changed path falls within
   directories listed in the **Inventory** table of `.aihaus/project.md`.
   If `project.md` is not available, match against these common fallback
   patterns: `models/`, `entities/`, `schemas/`, `routes/`, `api/`,
   `endpoints/`, `controllers/`, `handlers/`, `pages/`, `screens/`,
   `views/`, `components/`, `src/domain/`, `src/app/`, `pkg/`, `cmd/`,
   `internal/`, `lib/`.
3. If ANY match, spawn `subagent_type: "project-analyst"` with the instruction
   `"Run in --refresh-inventory-only mode and rewrite .aihaus/.init-scratch.md"`.
   Then merge ONLY the block between `<!-- AIHAUS:AUTO-GENERATED-START -->`
   and `<!-- AIHAUS:AUTO-GENERATED-END -->` in `.aihaus/project.md` (preserve
   the manual header/footer byte-for-byte; back up to `project.md.bak` first).
4. Always append to `## Milestone History` in the manual section:
   `- [YYYY-MM-DD] feature/[slug] — [one-line summary]`.
5. If `DECISIONS.md` (repo root) or `.aihaus/decisions.md` / `.aihaus/knowledge.md` was touched in this commit, spawn `project-analyst` with `--refresh-recent-decisions` and merge the scratch files between the `RECENT-DECISIONS-START/END` and `RECENT-KNOWLEDGE-START/END` markers in `.aihaus/project.md`.

### Step 13: Report Completion
Update RUN-MANIFEST.md: set Status `completed`, Phase `completed`, append final timestamp. Tell the user:
- What was implemented
- Branch name and commit hash
- Test/verification results
- Path to artifacts
- Any decisions or discoveries worth noting

**Autonomy:** See `_shared/autonomy-protocol.md` — binding rules; overrides contradictory prose above.
