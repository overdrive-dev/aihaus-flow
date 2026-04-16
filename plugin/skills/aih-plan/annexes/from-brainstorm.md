# aih-plan annex: --from-brainstorm seeding (Phase 0)

Conditional intake when `$ARGUMENTS` contains `--from-brainstorm <slug>`.

## Step 1 — Resolve the brainstorm

Read `.aihaus/brainstorm/<slug>/BRIEF.md`. Emit the exact error string and abort if:
- Slug dir does not exist → `No brainstorm found at <slug>. Run /aih-brainstorm first or check the slug.`
- BRIEF.md missing → `Brainstorm at <slug> has no BRIEF.md — run was not completed. Re-run /aih-brainstorm <slug>.`
- BRIEF.md missing any required H2 header → `BRIEF.md at <slug> is missing section(s): <list>. Cannot seed plan.` — `<list>` = comma-separated missing headers.

Required H2 headers: `Problem Statement`, `Perspectives Summary`, `Key Disagreements`, `Challenges`, `Research Evidence`, `Synthesis`, `Open Questions`, `Suggested Next Command`.

## Step 2 — Read-only

No writes to `.aihaus/brainstorm/<slug>/`.

## Step 3 — Section mapping

Seed PLAN.md from BRIEF.md:

| BRIEF.md section | PLAN.md destination |
|------------------|---------------------|
| Problem Statement | Problem Statement |
| Synthesis + Key Disagreements | Proposed Approach (draft seed) |
| Open Questions | Open Questions |
| Challenges | Risk Assessment (seeded rows) |
| Research Evidence | Referenced as source, verbatim if < 1k chars (body length, excluding header line) else one-paragraph summary |

## Step 4 — Clarifying-question shortcut

**Skip core Phase 1 step 2 (clarifying questions)** if BRIEF.md has fewer than 3 Open Questions — brainstorm already synthesized the context.

## Step 5 — Attachments

Copy `.aihaus/brainstorm/<slug>/attachments/` → `.aihaus/plans/[slug]/attachments/` (follow `annexes/attachments.md` naming rules).

## Step 6 — Handoff

Proceed to core Phase 1 using the seeded content; later phases (pattern-mapper, plan-checker, etc.) run unchanged.
