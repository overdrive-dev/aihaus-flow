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
After PLAN.md is drafted, spawn `plan-checker` with `subagent_type: "plan-checker"`. Adversarial — must produce findings or written justification. Writes `.aihaus/plans/[slug]/CHECK.md`. If findings: update PLAN.md to address them. Cap at 2 iterations.

6. **Report to the user:**
   - Summarize the plan in 3-5 bullet points
   - Print the plan path: `.aihaus/plans/[slug]/PLAN.md`
   - Print paths of auxiliary artifacts (ASSUMPTIONS.md, PATTERNS.md, CHECK.md, and RESEARCH.md if present)
   - Print the suggested next command
   - If scope is milestone-sized (>10 files or multi-story), explicitly recommend `/aih-plan-to-milestone [slug]` as the primary path (lets user refine context conversationally before commit).

## Guardrails
- MUST NOT create git branches
- MUST NOT modify any source code, tests, configs, or migrations
- MUST NOT write files outside `.aihaus/plans/`
- If `.aihaus/plans/` does not exist, create it before writing
- If the topic is too vague to plan after clarification, say so and suggest what info is needed
