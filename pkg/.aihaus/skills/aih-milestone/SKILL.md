---
name: aih-milestone
description: "Start or resume a milestone draft via conversational gathering. Iterate context across messages, then run /aih-run to execute."
disable-model-invocation: true
allowed-tools: Read Write Edit Grep Glob Bash
argument-hint: "[description] [--execute] [--plan slug]"
---

## Task
Enter gathering mode for a milestone. Absorb user context iteratively into a draft. Never executes — use `/aih-run` to start execution.

$ARGUMENTS

## Flags
- `--execute` — skip gathering, go straight to execution (backward-compat one-shot behavior).
- `--plan [slug]` — seed a milestone draft from an existing `PLAN.md`, then enter gathering. See `annexes/promotion.md`.
- `--from-brainstorm [slug]` — seed CONTEXT.md from `.aihaus/brainstorm/[slug]/BRIEF.md` (see Step 0).
- `--no-split` — bypass the force-split decision gate (see `annexes/promotion.md` Step P1.6).

## Step 0 — `--from-brainstorm <slug>` intake (conditional)

If `$ARGUMENTS` contains `--from-brainstorm <slug>`, run before Step 1. Otherwise skip.

1. Resolve `.aihaus/brainstorm/<slug>/BRIEF.md`. Emit the exact error string and abort if:
   - Slug dir does not exist → `No brainstorm found at <slug>. Run /aih-brainstorm first or check the slug.`
   - BRIEF.md missing → `Brainstorm at <slug> has no BRIEF.md — run was not completed. Re-run /aih-brainstorm <slug>.`
   - BRIEF.md missing any required H2 header below → `BRIEF.md at <slug> is missing section(s): <list>. Cannot seed plan.` (string identical to `/aih-plan` — do not swap "plan" for "milestone"; `<list>` = comma-separated missing headers).

   Required H2 headers: `Problem Statement`, `Perspectives Summary`, `Key Disagreements`, `Challenges`, `Research Evidence`, `Synthesis`, `Open Questions`, `Suggested Next Command`.

2. **Read-only** on `.aihaus/brainstorm/<slug>/`.

3. Skip Step 2 (drafts listing). Proceed to Step 3 and, after creating the draft directory, seed `CONTEXT.md` per the mapping below before entering Step 4 gathering:

   | BRIEF.md section | CONTEXT.md destination |
   |------------------|------------------------|
   | Problem Statement | Goal |
   | Synthesis | Proposed Scope (new section under Scope) |
   | Challenges + Open Questions | Decisions (as items to resolve during gathering) |
   | Research Evidence | References |

4. Copy attachments if `.aihaus/brainstorm/<slug>/attachments/` exists → `.aihaus/milestones/drafts/[slug]/attachments/` (see Attachment Handling for naming).

## Step 1 — Handle Flags

**If `--execute` is present:** Skip Steps 2–5. Create a minimal draft from $ARGUMENTS, then immediately invoke the milestone execution flow from `/aih-run` (so `/aih-resume` can recover if interrupted). Print: "Executing directly (--execute flag). Use `/aih-milestone` without the flag for conversational gathering."

**If `--plan [slug]` is present:** Follow `annexes/promotion.md` Steps P1–P5 to seed a milestone draft from the plan (M### auto-propose, force-split gate, PLAN→CONTEXT mapping, attachment reference, backlink footer, threshold gate). Skip Step 2 (drafts listing). Threshold gate in P5 either dispatches execution or hands back to Step 5 gathering here.

## Step 2 — List Existing Drafts

`Glob` `.aihaus/milestones/drafts/*/STATUS.md`. If any drafts exist (excluding the `.archive/` directory):

```
Active milestone drafts:

# | Slug                      | Status    | Updated
1 | 260412-user-auth          | gathering | [mtime]
2 | 260411-billing-refactor   | ready     | [mtime]

Options:
  - Continue a draft: tell me which number or slug
  - Start a new draft: say "new" or provide a description
  - Execute a ready draft: /aih-run [slug]
```

Wait for the user's choice.

- **User picks an existing slug** → go to Step 4 with that slug (load existing CONTEXT.md).
- **User says "new" or provides description** → go to Step 3.

If no drafts exist, go to Step 3 directly.

## Step 3 — Create New Draft

Derive a slug:
- If $ARGUMENTS has a description → slug from description (lowercase, hyphens, max 40 chars, YYMMDD prefix).
- Else → ask: "What's a short slug or working title for this milestone?"

Create `.aihaus/milestones/drafts/[slug]/` with:

**CONTEXT.md:**
```markdown
# Milestone Draft: [title]
**Slug:** [slug]
**Started:** [ISO date]

## Goal
[initial description or "pending"]

## Constraints & Deadlines
_None captured yet._

## Scope
_Pending._

## Affected Areas
_Pending._

## References
_Links, tickets, designs._

## Decisions
_Captured during gathering._

## Open Questions
_Things to resolve before execution._
```

**STATUS.md:** single line `gathering`

**CONVERSATION.md:**
```markdown
# Conversation Log: [slug]
_Raw user messages appended during gathering, most recent last._
```

## Step 3.5 — Refresh Active Milestones in project.md
If `.aihaus/project.md` exists, spawn `project-analyst` with `subagent_type: "project-analyst"` in `--refresh-active-milestones` mode. Merge `.aihaus/.active-milestones-scratch.md` content between `<!-- AIHAUS:ACTIVE-MILESTONES-START -->` and `<!-- AIHAUS:ACTIVE-MILESTONES-END -->` markers. Preserves everything outside. This way the new draft appears in the Drafts table immediately.

## Step 4 — Enter Gathering Mode

Print the initial prompt for the user:

```
Draft created at .aihaus/milestones/drafts/[slug]/CONTEXT.md

Send context freely — goals, constraints, affected areas, links, stakeholders, deadlines. I'll absorb each message into CONTEXT.md and ask follow-up questions when gaps emerge.

When ready to execute:
  - Run /aih-run [slug]
  - Or say "start", "go", "kick off" — I'll run it for you.
```

## Step 5 — Session Gathering Instructions (what to do after this skill returns)

The main conversation continues after this skill exits. Follow these rules for the rest of the session (or until the user moves on):

1. **On every user message that is not a slash command**:
   - Append raw message to `.aihaus/milestones/drafts/[slug]/CONVERSATION.md` with timestamp.
   - Update the relevant section(s) of `CONTEXT.md` with the distilled content.
   - **Persist attachments** if the message includes pasted images or files (see Attachment Handling below).
   - Ask up to 1 follow-up question if you detect a gap (missing constraint, unclear success criterion, ambiguous scope).
2. **On start intent** ("start", "go", "kick off", "let's begin", "ready", etc.):
   - Set `STATUS.md` to `ready`.
   - Invoke `/aih-run [slug]`.
3. **On slash command other than start intent**:
   - Let the user run the other command. Leave `STATUS.md` at `gathering`.
   - Draft is preserved — user can come back via `/aih-milestone` later.
4. **On new `/aih-milestone` invocation in a later session**:
   - The drafts listing (Step 2) will surface this draft for resumption.

## Attachment Handling
When a user message includes a pasted image or file:
1. Detect source path. Pasted images land at `~/.claude/image-cache/[uuid]/[n].png`. Files referenced via absolute paths or drag-drop appear in the message text.
2. Copy **immediately on first mention** via `cp`. If the draft's final slug is already set (Step 3 complete), copy to `.aihaus/milestones/drafts/[slug]/attachments/[seq]-[short-desc].[ext]`. If the slug is not yet set (Step 3 pending), copy to a temp-slug dir `.aihaus/milestones/drafts/YYMMDD-wip-HHMMSS-<rand4>/attachments/` and `mv` on Step 3 slug finalization (M004 story H — prevents loss if conversation drops before slug is decided). Seq is 2-digit zero-padded (01, 02, ...). Short description derived from content (e.g., `login-error-screenshot`). See `pkg/.aihaus/skills/aih-plan/annexes/attachments.md` for the canonical temp-slug + crash-recovery protocol.
3. Describe the content in one sentence using your vision capability.
4. Append to CONTEXT.md `## Attachments` section:
   ```
   | # | File | Added | Description |
   |---|------|-------|-------------|
   | 01 | attachments/01-login-error.png | [ISO ts] | Login page showing "Network Error" |
   ```
5. Warn at 5+ attachments ("Consider culling"). Reject files > 20 MB. Remind: "If sensitive, crop/redact before committing — `.aihaus/` is git-tracked."

## Capture, Don't Execute (intake discipline)
During gathering, if the user describes an implementable change (e.g. "and also fix the login logo"), you MUST:
1. Capture it to CONTEXT.md under "Proposed Stories" or "Open Items" — with a one-line description of what would be done.
2. Acknowledge: "Captured — added to CONTEXT.md as a story/item."
3. Continue gathering. Do NOT checkout a branch, edit code, or commit.

The only exception is an explicit out-of-band execution signal ("fix this now", "just do it", "execute right away"). In that case:
1. State clearly: "Switching out of gathering to execute — draft remains at `gathering`."
2. Hand off to `/aih-quick` or `/aih-bugfix` (proper execution skill).
3. Return to gathering context when done.

## Guardrails
- NEVER execute the milestone. `/aih-run` is the only execution path.
- NEVER delete CONTEXT.md — only append/update sections.
- Archive on execution — draft moves to `.aihaus/milestones/drafts/.archive/[YYMMDD]-[slug]/` by `/aih-run`.
- The `--execute` flag exists for backward compat; do not default to it.
- Capture, don't execute — see section above.

## Autonomy
See `_shared/autonomy-protocol.md` — binding rules for planning/threshold/execution phases, no option menus, no honest checkpoints, no delegated typing. Overrides contradictory prose above.
