---
name: aih-milestone
description: "Full autonomous milestone — plan, architect, implement, test, ship. Use for large features that need multiple stories."
disable-model-invocation: true
allowed-tools: Read Grep Glob Bash Write Edit Agent TaskCreate TaskUpdate
argument-hint: "[milestone description] [--plan slug]"
---

## --plan Flag (optional)

If `$ARGUMENTS` contains `--plan`, extract the word immediately after `--plan` as the **slug**.

1. **Attempt to read** `.aihaus/plans/[slug]/PLAN.md`.
2. **If the file exists**, use its contents as the analysis input for this milestone:
   - Skip the "Goal" scoping question (question 1) — the plan already defines it.
   - Skip the "Existing plan?" scoping question (question 4) — you already have the plan.
   - Skip codebase research that the plan already covers (e.g., if the plan lists affected models/endpoints, do not re-scan for them).
   - Still ask about constraints, deadlines, scope, and additional context **not** addressed by the plan.
   - In your plan summary (Step 4), note: "Using plan: `.aihaus/plans/[slug]/PLAN.md`"
3. **If the file does not exist**, report this error and **stop**:
   > "Plan not found at `.aihaus/plans/[slug]/PLAN.md`. Run `/aih-plan` first to create it."
4. **If no `--plan` flag is present**, proceed normally — all steps below apply in full.

## Phase 1: Question & Approval

### 1. Load Context
- Read `.aihaus/memory/MEMORY.md` and any relevant memory files
- Read `.aihaus/project.md` (if present) for project-level context
- Read `.aihaus/decisions.md` (if present) — follow all existing ADRs
- Read `.aihaus/knowledge.md` (if present) — avoid known pitfalls

### 2. Scoping Questions
Ask 3-5 questions in a single batched turn (do NOT ask one-at-a-time):
1. **Goal:** What is the end-user outcome? (summarize $ARGUMENTS back for confirmation)
2. **Constraints/Deadlines:** Any hard constraints, target date, or dependencies?
3. **Scope:** Frontend only, backend only, or full-stack?
4. **Existing plan?** Is there a `.aihaus/plans/` research brief to reference?
5. **Additional context:** Anything else the team should know?

If `--plan` was provided and the plan file was loaded, skip questions 1 and 4 (the plan
already answers them). Ask only questions 2, 3, and 5.

### 3. Codebase Scan
Scan for affected areas based on the milestone description. Use `Glob` and `Grep` to locate:
- Data models and schemas relevant to the change
- API endpoints or route handlers that would be touched
- Frontend screens or components in scope
- Shared services, utilities, or configuration

### 4. Plan Summary
Present a structured summary for approval:
```
Milestone: [title]
Scope: [frontend | backend | full-stack]
Complexity: [S | M | L | XL] — estimated stories
High-Level Stories:
  1. [story title] — [backend|frontend|full-stack]
  2. ...
Affected Areas:
  [list affected directories/modules from .aihaus/project.md inventory,
   or from codebase scan if project.md is not available]
Branch: milestone/[M0XX]-[slug]
```

### 5. Git Status Check
Run `git status` to check for uncommitted changes. If the working tree is dirty:
- Warn the user: "You have uncommitted changes. Proceeding will branch from
  current HEAD including dirty state."
- Offer: "Would you like to stash first, commit first, or proceed as-is?"

### 6. GATE — Human Approval
Wait for the user to approve, adjust, or reject the plan.
Do NOT proceed to Phase 2 until the user explicitly approves.

## Phase 2: Autonomous Execution

After human approval, execute everything autonomously. Do not ask further questions.

### Phase 2 Task Tracking
Create all tasks as `pending` at the start of Phase 2 using TaskCreate:
| Subject | activeForm |
|---------|-----------|
| Run analysis brief | Analyzing milestone scope |
| Write PRD and stories | Writing PRD and stories |
| Design architecture | Designing architecture |
| Verify plan coherence | Checking plan coherence |
| Execute stories | Executing stories |
| Run completion protocol | Running completion protocol |
Chain dependencies sequentially. Before each step, set its task to `in_progress`. After completion, set to `completed`.

### 7. Determine Milestone ID
Scan for existing milestone directories to determine the next ID:
- `Glob` for `M0*` directories in `.aihaus/milestones/`
- Extract numeric IDs, find the maximum, increment by 1
- Format: `M0XX` (pad with leading zeros; increment the highest existing ID)
- Derive slug from milestone title: lowercase, hyphens, max 40 chars

### 8. Create Directory Structure
Create the milestone artifact tree under `.aihaus/milestones/[M0XX]-[slug]/`:
```
.aihaus/milestones/[M0XX]-[slug]/
  stories/
  execution/
  execution/reviews/
  execution/DECISIONS-LOG.md
  execution/KNOWLEDGE-LOG.md
```

Initialize DECISIONS-LOG.md and KNOWLEDGE-LOG.md with headers so subsequent
agents have a consistent place to append entries.

### 9. Planning — Sequential Agent Subagents
Use the `Agent` tool to spawn planning agents SEQUENTIALLY. Each agent
receives the `.aihaus/milestones/[M0XX]-[slug]/` path as its output location.

**Step 1 — Analyst:**
Spawn an Agent with the `aihaus-analyst` type. Instruct it to:
- Research the milestone scope based on the approved plan summary
- Write output to `.aihaus/milestones/[M0XX]-[slug]/analysis-brief.md`

**Step 2 — Product Manager:**
Spawn an Agent with the `aihaus-product-manager` type. Instruct it to:
- Read the analysis brief from Step 1
- Write PRD to `.aihaus/milestones/[M0XX]-[slug]/PRD.md`
- Write stories to `.aihaus/milestones/[M0XX]-[slug]/stories/`

**Step 3 — Architect:**
Spawn an Agent with the `aihaus-architect` type. Instruct it to:
- Read the PRD and stories from Step 2
- Write architecture to `.aihaus/milestones/[M0XX]-[slug]/architecture.md`
- Append any new ADRs to `.aihaus/decisions.md`

**Step 4 — Plan Checker:**
Before proceeding to execution, verify plan coherence:
- Every story references files that exist (or are explicitly new)
- No two stories claim ownership of the same file without dependency ordering
- Architecture ADRs cover all conflict-prone areas relevant to the milestone
- Stories have clear acceptance criteria that can be verified programmatically
If issues are found, send them back to the Architect for resolution.

Wait for each agent to complete before spawning the next.

### 10. Create Feature Branch
Create the milestone branch:
```bash
git checkout -b milestone/[M0XX]-[slug]
```
Branch name: lowercase, hyphens, max 40 chars for the slug portion.

### 11. Spawn Agent Team
Read `.aihaus/skills/milestone/team-template.md` for Agent Team configuration.

Create an agent team following the template with these roles:
- **backend-dev** using the `aihaus-implementer` agent type
- **frontend-dev** using the `aihaus-frontend-dev` agent type
- **qa** using the `aihaus-reviewer` agent type

If the milestone is backend-only, skip frontend-dev (and vice versa).
If more than 8 stories, spawn a second dev for the heavier side.

Additionally, spawn quality gate agents as needed:
- **ux-designer** using the `aihaus-ux-designer` agent type (if frontend stories exist)
- **security** review pass after implementation (if the milestone touches auth, payments, or user data)

### 12. Execute Stories
Create tasks from the stories in `.aihaus/milestones/[M0XX]-[slug]/stories/`:
- One task per story, with dependencies matching story dependency chains
- Each task description includes: story file path, summary output path,
  review output path, owned files list, decision/knowledge log reminders
- Approve plans, monitor progress, handle QA pass/fail cycles autonomously

**CRITICAL:** You are the COORDINATOR. Never write code or implementation
files yourself. Delegate everything to teammates.

### 13. Completion
Read `.aihaus/skills/milestone/completion-protocol.md` for wrap-up steps.

Follow the completion protocol: merge decisions, promote knowledge,
write MILESTONE-SUMMARY.md, clean up the team, report to user.

$ARGUMENTS
