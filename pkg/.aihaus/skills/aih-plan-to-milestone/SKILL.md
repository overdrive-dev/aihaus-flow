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
- **One candidate** → proceed silently; log one line: *"Promoting [slug] to milestone draft."* (No Y/n — see `_shared/autonomy-protocol.md`.)
- **Multiple** → present a table (slug, created, estimated scope summary), ask user to pick.
- **Zero** → "No plans found. Run `/aih-plan` first."

## Step 1.5 — Auto-propose milestone number (M004 story J)

Before drafting CONTEXT.md, scan for the next M### slot:
```bash
find .aihaus/milestones/ -maxdepth 2 -name 'M[0-9][0-9][0-9]*' -type d | sort -V | tail -1
```
Extract the numeric ID, increment by 1, zero-pad to 3 digits. Display:
`Suggested milestone number: M0XX. Use this? (y/n/<custom>)`

If user supplies a custom number that already exists, re-prompt. `aih-run` remains authoritative at execute time (it also re-numbers) — this proposal is informational.

## Step 1.6 — Force-split decision gate (M004 story K)

Inspect PLAN.md:
- Story count > 12 (count by scanning Estimated Scope table or Proposed Approach sub-milestones), OR
- Any Risk row with Likelihood=High AND Impact=High
→ emit a split-decision prompt listing stories grouped by sub-milestone. Ask user which subset to promote now vs defer.

On **defer** choice: create `.aihaus/milestones/drafts/<next-M>-<deferred-theme>/DRAFT.md` with only the deferred stories + a backlink to the main draft. User runs `/aih-plan-to-milestone` separately when ready.

Override: `--no-split` bypasses the prompt (flag documented; do not use silently).

## Step 2 — Load Plan

Parse PLAN.md sections:
- `## Problem Statement` → becomes the draft's Goal.
- `## Proposed Approach` → **summarized** in the draft's Scope (1 paragraph per sub-section + an explicit `See: ../../../plans/[slug]/PLAN.md#proposed-approach` link). Do NOT verbatim-copy — PLAN.md stays canonical. (M004 story I — F4.)
- `## Affected Files` → **summarized** as a list of top-level paths + link `See: ../../../plans/[slug]/PLAN.md#affected-files`.
- `## Risk Assessment` → copied verbatim into a References/Risks subsection (risks are short; full content in draft is more readable than a link).
- `## Alternatives Considered` → copied verbatim under Decisions (keeps reasoning trail; short tables).
- `## Estimated Scope` → copied verbatim under Scope as a sub-block (short; numbers change based on user decisions).
- `## Attachments` (if present): **referenced** (do not re-copy files — draft links back to plan's attachments dir via relative path).

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
[1-paragraph summary of Proposed Approach]

See: `../../../plans/[slug]/PLAN.md#proposed-approach` for full detail.

### Estimated Scope (from plan)
[Estimated Scope block — verbatim]

## Affected Areas
[List of top-level paths — 1 line each]

See: `../../../plans/[slug]/PLAN.md#affected-files` for full table.

## References
### Risks (from plan)
[Risk Assessment table]

## Decisions
### Alternatives Considered (from plan)
[Alternatives Considered table]

## Open Questions
_Add via gathering._
```

**STATUS.md:** seed via `bash .aihaus/hooks/phase-advance.sh --to gathering --dir .aihaus/milestones/drafts/[slug]/` (ADR-004 / story C.2). The hook writes the canonical 3-line DERIVED form. If the hook is unavailable (legacy install), fall back to `echo gathering > STATUS.md`.

**CONVERSATION.md:**
```markdown
# Conversation Log: [slug]
_Seeded from plan .aihaus/plans/[slug]/PLAN.md on [date]._
_Raw user messages appended during gathering below._
```

## Step 3.5 — Reference Attachments (do NOT re-copy; M004 story I / F4)
If `.aihaus/plans/[slug]/attachments/` exists, reference it from CONTEXT.md via a relative-path link rather than duplicating files:
```markdown
## Attachments
See: `../../../plans/[slug]/attachments/` (N files — see PLAN.md Attachments section for descriptions).
```
PLAN.md stays canonical; the draft stays thin. If PLAN.md is later archived, the backlink-broken smoke-test check flags it.

## Step 4 — Backlink from the Plan

Append to `.aihaus/plans/[slug]/PLAN.md` (do not edit existing sections):

```markdown

## Promoted To Milestone Draft
- **Draft:** `.aihaus/milestones/drafts/[slug]/`
- **Promoted on:** [ISO date]
- **Status:** gathering — run `/aih-milestone` to continue refinement, then `/aih-run` to execute.
```

## Step 5 — Report, threshold gate, and hand off

Print one-line summary: *"Milestone draft created at .aihaus/milestones/drafts/[slug]/ (seeded from plan)."*

**Threshold gate (see `_shared/autonomy-protocol.md`):** ask ONE natural-language question — *"Executar agora ou continuar em gathering para refinar contexto?"* On "executar"/"vai"/"go", dispatch `/aih-run [slug]` via Skill tool. On "gathering"/"continuar"/"refine" or any continuation signal, enter conversational gathering mode (same instructions as `/aih-milestone` Step 5: absorb subsequent user messages into CONTEXT.md, ask follow-ups, recognize start intent). **Never** print "Run /aih-run [slug] when ready" as typing instructions — either ask and dispatch, or enter gathering silently. Opt-out: `--no-chain` preserves legacy print-suggestion behavior.

## Agent Invocation

Agents (and the main conversation) can invoke this skill when the user says:
- "convert this plan to a milestone"
- "turn this plan into a milestone"
- "promote the plan"
- "make this a milestone"

## Capture, Don't Execute (intake discipline)
After the draft is seeded and during subsequent gathering messages, if the user describes an implementable change, capture it to CONTEXT.md — do NOT branch, edit, or commit. Same escape hatch as `/aih-milestone` gathering: explicit execution signals hand off to `/aih-quick` or `/aih-bugfix`, the draft stays at `gathering`.

## Guardrails
- NEVER delete or overwrite the original PLAN.md content — only append the `## Promoted To Milestone Draft` footer.
- NEVER execute the milestone — hand off to `/aih-run`.
- If a draft already exists for the slug, ask the user: "Draft exists. Overwrite or pick a new slug?"
- Capture, don't execute — see section above.
