---
name: aih-plan-to-milestone
description: "Promote a /aih-plan output (PLAN.md) into a milestone draft so it can be refined conversationally before execution."
disable-model-invocation: true
allowed-tools: Read Write Edit Grep Glob Bash
argument-hint: "[plan slug (optional)]"
---

## Task
Seed a milestone draft from an existing plan file, then enter gathering mode on the new draft.

$ARGUMENTS

## Step 1 — Resolve Plan

**If a slug is given:** read `.aihaus/plans/[slug]/PLAN.md`. Error if not found.

**If no slug given:**
- `Glob` `.aihaus/plans/*/PLAN.md`.
- Exclude slugs that already have a corresponding draft at `.aihaus/milestones/drafts/[slug]/`.
- **One candidate** → confirm ("Promote plan [slug] to milestone draft? Y/n").
- **Multiple** → present a table (slug, created, estimated scope summary), ask user to pick.
- **Zero** → "No plans found. Run `/aih-plan` first."

## Step 2 — Load Plan

Parse PLAN.md sections:
- `## Problem Statement` → becomes the draft's Goal.
- `## Proposed Approach` → becomes the draft's Scope (may need light summarization for fit).
- `## Affected Files` → becomes the draft's Affected Areas (extract file paths + descriptions).
- `## Risk Assessment` → copied verbatim into a References/Risks subsection.
- `## Alternatives Considered` → copied verbatim under Decisions (keeps reasoning trail).
- `## Estimated Scope` → copied verbatim under Scope as a sub-block.

## Step 3 — Create Draft

Create `.aihaus/milestones/drafts/[slug]/`:

**CONTEXT.md:**
```markdown
# Milestone Draft: [title from PLAN.md]
**Slug:** [slug]
**Started:** [ISO date]
**Seeded from:** .aihaus/plans/[slug]/PLAN.md

## Goal
[Problem Statement content]

## Constraints & Deadlines
_None captured yet — add via gathering._

## Scope
[Proposed Approach content]

### Estimated Scope (from plan)
[Estimated Scope block]

## Affected Areas
[Affected Files content, reformatted as a list with paths]

## References
### Risks (from plan)
[Risk Assessment table]

## Decisions
### Alternatives Considered (from plan)
[Alternatives Considered table]

## Open Questions
_Add via gathering._
```

**STATUS.md:** `gathering`

**CONVERSATION.md:**
```markdown
# Conversation Log: [slug]
_Seeded from plan .aihaus/plans/[slug]/PLAN.md on [date]._
_Raw user messages appended during gathering below._
```

## Step 4 — Backlink from the Plan

Append to `.aihaus/plans/[slug]/PLAN.md` (do not edit existing sections):

```markdown

## Promoted To Milestone Draft
- **Draft:** `.aihaus/milestones/drafts/[slug]/`
- **Promoted on:** [ISO date]
- **Status:** gathering — run `/aih-milestone` to continue refinement, then `/aih-run` to execute.
```

## Step 5 — Report and Hand Off

Tell the user:

```
Milestone draft created at .aihaus/milestones/drafts/[slug]/

Seeded from plan. Review the draft and add more context as needed.

When ready:
  - Run /aih-milestone to continue adding context (it will surface this draft)
  - Run /aih-run [slug] when ready to execute
  - Or say "start"/"go" to execute now
```

Then, in the ongoing conversation, follow the same gathering instructions used by `/aih-milestone` Step 5 — absorb subsequent user messages into CONTEXT.md, ask follow-ups, recognize start intent.

## Agent Invocation

Agents (and the main conversation) can invoke this skill when the user says:
- "convert this plan to a milestone"
- "turn this plan into a milestone"
- "promote the plan"
- "make this a milestone"

## Guardrails
- NEVER delete or overwrite the original PLAN.md content — only append the `## Promoted To Milestone Draft` footer.
- NEVER execute the milestone — hand off to `/aih-run`.
- If a draft already exists for the slug, ask the user: "Draft exists. Overwrite or pick a new slug?"
