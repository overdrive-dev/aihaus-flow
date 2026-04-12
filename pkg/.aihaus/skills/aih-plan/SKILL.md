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

2. **Ask clarifying questions** — present 1-3 questions in a single batch:
   - What are you trying to achieve? (skip if $ARGUMENTS is already specific)
   - Any constraints, preferences, or deadlines?
   - Is this likely a milestone-sized change, a single feature, or a bugfix?

   Wait for the human to answer before proceeding.

## Phase 2 — Research & Plan Generation

3. **Deep codebase research** — invest real time here:
   - Identify all affected models, schemas, endpoints, services, and frontend screens
   - Read each affected file to understand current behavior
   - Check for existing patterns that the plan should follow
   - Note any database migration implications
   - Note any cross-cutting concerns (auth, permissions, audit logging)

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

6. **Report to the user:**
   - Summarize the plan in 3-5 bullet points
   - Print the plan path: `.aihaus/plans/[slug]/PLAN.md`
   - Print the suggested next command
   - If scope is milestone-sized (>10 files or multi-story), explicitly recommend `/aih-plan-to-milestone [slug]` as the primary path (lets user refine context conversationally before commit).

## Guardrails
- MUST NOT create git branches
- MUST NOT modify any source code, tests, configs, or migrations
- MUST NOT write files outside `.aihaus/plans/`
- If `.aihaus/plans/` does not exist, create it before writing
- If the topic is too vague to plan after clarification, say so and suggest what info is needed
