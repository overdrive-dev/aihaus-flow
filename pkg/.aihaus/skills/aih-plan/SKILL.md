---
name: aih-plan
description: Research a problem and produce a plan without writing code. Use when you want to think before building.
disable-model-invocation: true
allowed-tools: Read Grep Glob Bash WebFetch
argument-hint: "[what you want to plan — feature, migration, refactor, etc.]"
---

## Task
Research the following and produce a detailed plan — no code changes.

$ARGUMENTS

## Phase 0 — `--from-brainstorm <slug>` intake (conditional)

If `$ARGUMENTS` contains `--from-brainstorm <slug>`, run this phase before Phase 1. Otherwise skip to Phase 1.

1. **Resolve** `.aihaus/brainstorm/<slug>/BRIEF.md`. Emit the exact error string and abort if:
   - Slug dir does not exist → `No brainstorm found at <slug>. Run /aih-brainstorm first or check the slug.`
   - BRIEF.md missing → `Brainstorm at <slug> has no BRIEF.md — run was not completed. Re-run /aih-brainstorm <slug>.`
   - BRIEF.md missing any required H2 header (see list below) → `BRIEF.md at <slug> is missing section(s): <list>. Cannot seed plan.` — `<list>` is a comma-separated list of missing headers.

   Required H2 headers: `Problem Statement`, `Perspectives Summary`, `Key Disagreements`, `Challenges`, `Research Evidence`, `Synthesis`, `Open Questions`, `Suggested Next Command`.

2. **Do not write** to `.aihaus/brainstorm/<slug>/` — read-only.

3. **Section-mapping** — seed PLAN.md sections from BRIEF.md:

   | BRIEF.md section | PLAN.md destination |
   |------------------|---------------------|
   | Problem Statement | Problem Statement |
   | Synthesis + Key Disagreements | Proposed Approach (draft seed) |
   | Open Questions | Open Questions |
   | Challenges | Risk Assessment (seeded rows) |
   | Research Evidence | Referenced as source, verbatim if < 1k chars (body length, excluding header line) else one-paragraph summary |

4. **Skip Phase 1 step 2 (clarifying questions)** if BRIEF.md has fewer than 3 Open Questions.

5. **Copy attachments** if `.aihaus/brainstorm/<slug>/attachments/` exists → `.aihaus/plans/[slug]/attachments/` (follow Attachment Handling below for naming).

6. Proceed to Phase 1 using the seeded content; later phases (pattern-mapper, plan-checker, etc.) run unchanged.

## Phase 1 — Context & Clarification

1. **Load context silently** (do not print these to the user):
   - Read `.aihaus/memory/MEMORY.md` and any referenced memory files
   - Read `.aihaus/project.md` (if present) for project-level context
   - Read `.aihaus/decisions.md` (if present) for existing ADRs
   - Read `.aihaus/knowledge.md` (if present) for known gotchas

1.5. **Surface assumptions (delegate to assumptions-analyzer)**
Spawn `assumptions-analyzer` with `subagent_type: "assumptions-analyzer"` on the user's request. Writes `.aihaus/plans/[slug]/ASSUMPTIONS.md` with evidence-tagged assumptions. Surface blockers before asking questions.

2. **Ask clarifying questions** — present 1-3 questions in a single batch:
   - What are you trying to achieve? (skip if $ARGUMENTS is already specific)
   - Any constraints, preferences, or deadlines?
   - Is this likely a milestone-sized change, a single feature, or a bugfix?
   - Flag any high-confidence blocker from the assumptions-analyzer output.

   Wait for the human to answer before proceeding.

## Phase 2 — Research & Plan Generation

3. **Deep codebase research** — invest real time here:
   - Identify all affected models, schemas, endpoints, services, and frontend screens
   - Read each affected file to understand current behavior
   - Check for existing patterns that the plan should follow
   - Note any database migration implications
   - Note any cross-cutting concerns (auth, permissions, audit logging)

3.5. **Pattern mapping (delegate to pattern-mapper)**
Spawn `pattern-mapper` with `subagent_type: "pattern-mapper"` to find existing codebase analogs. Writes `.aihaus/plans/[slug]/PATTERNS.md` with file excerpts. Reference these concrete patterns in the plan instead of guessing.

3.7. **Technical research (conditional, delegate to phase-researcher)**
If the plan involves new technical territory (unfamiliar framework, new service type, unusual pattern), spawn `phase-researcher` with `subagent_type: "phase-researcher"`. Writes `.aihaus/plans/[slug]/RESEARCH.md` with VERIFIED/CITED/ASSUMED provenance tags. Skip for straightforward work.

4. **Generate the slug:**
   - Format: `YYMMDD-lowercase-hyphen-description`
   - Max 40 characters total (including date prefix)
   - Example: `260410-rate-limiting`

5. **Write the plan** to `.aihaus/plans/[slug]/PLAN.md` with this structure:

   ```markdown
   # Plan: [Title]

   **Created:** [YYYY-MM-DD]
   **Slug:** [slug]
   **Status:** Draft

   ## Problem Statement
   [What needs to change and why — 2-4 sentences]

   ## Affected Files
   | File | Change Type | Description |
   |------|-------------|-------------|
   | `path/to/file.py` | Modify | [what changes] |

   ## Proposed Approach
   [Step-by-step plan — numbered, specific, referencing actual file paths]

   ## Alternatives Considered
   | # | Alternative | Pros | Cons | Why Not |
   |---|------------|------|------|---------|
   | 1 | [option] | ... | ... | ... |

   ## Risk Assessment
   | Risk | Likelihood | Impact | Mitigation |
   |------|-----------|--------|------------|
   | [risk] | Low/Med/High | Low/Med/High | [how to handle] |

   ## Estimated Scope
   - **Files:** [N] files across [N] directories
   - **Complexity:** Low / Medium / High
   - **Migrations:** Yes / No
   - **Tests needed:** [list]

   ## Suggested Next Command
   [One of these, based on scope:]
   - `/aih-run [slug]` (executes directly — small scope: single-story feature, large scope: auto-promotes to milestone)
   - `/aih-plan-to-milestone [slug]` (promote to milestone draft for conversational refinement before execution — recommended for multi-story work)
   - `/aih-feature --plan [slug]` (legacy, one-shot feature path)
   ```

5.5. **Adversarial plan-checker gate (delegate to plan-checker)**
After PLAN.md is drafted, spawn `plan-checker` with `subagent_type: "plan-checker"`. Adversarial — must produce findings or written justification. Writes `.aihaus/plans/[slug]/CHECK.md`. Pipe agent return through `bash .aihaus/hooks/invoke-guard.sh` (ADR-003) — on `INVOKE_OK` for `aih-quick draft-adr`, prompt user before dispatching. **Disposition-based verdict (ADR-M003-E):** if CHECK.md findings table has `Disposition` column → APPROVED = zero BLOCKER; else fall back to zero CRITICAL + zero HIGH. If not APPROVED: update PLAN.md. Cap at 2 iterations.

6. **Report to the user:**
   - Summarize the plan in 3-5 bullet points
   - Print the plan path: `.aihaus/plans/[slug]/PLAN.md`
   - Print paths of auxiliary artifacts (ASSUMPTIONS.md, PATTERNS.md, CHECK.md, and RESEARCH.md if present)
   - Print the suggested next command
   - If scope is milestone-sized (>10 files or multi-story), explicitly recommend `/aih-plan-to-milestone [slug]` as the primary path (lets user refine context conversationally before commit).

## Attachment Handling
If the user pastes images or files during the request or clarifying questions:
1. Source paths: pasted images are at `~/.claude/image-cache/[uuid]/[n].png`; dragged files appear as absolute paths.
2. Copy to `.aihaus/plans/[slug]/attachments/[seq]-[short-desc].[ext]` via `cp`.
3. Describe each in one sentence using vision.
4. Add a `## Attachments` section to PLAN.md listing them (path + description). Reference them by path in Proposed Approach when they inform decisions.
5. Reject files > 20 MB. Remind: crop/redact if sensitive — `.aihaus/` is git-tracked.

## Capture, Don't Execute (intake discipline)
If during research the user mentions an implementable fix ("while you're at it, fix X"), capture it under the plan's Proposed Approach or as an item in the Open Questions section. Do NOT branch, edit, or commit — plans are research artifacts, execution is a separate path. Explicit override only: "fix this now" / "just do it" → hand off to `/aih-quick` or `/aih-bugfix`, don't inline.

## Guardrails
- MUST NOT create git branches
- MUST NOT modify any source code, tests, configs, or migrations
- MUST NOT write files outside `.aihaus/plans/`
- If `.aihaus/plans/` does not exist, create it before writing
- If the topic is too vague to plan after clarification, say so and suggest what info is needed
- Capture, don't execute — see section above.
