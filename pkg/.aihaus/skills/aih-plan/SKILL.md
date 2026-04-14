---
name: aih-plan
description: Research a problem and produce a plan without writing code. Use when you want to think before building.
disable-model-invocation: true
allowed-tools: Read Grep Glob Bash WebFetch
argument-hint: "[what you want to plan — feature, migration, refactor, etc.]"
---

## Task
Research `$ARGUMENTS` and produce a detailed plan at `.aihaus/plans/[slug]/PLAN.md`. No code changes.

## Phase 0 — --from-brainstorm seeding (conditional)
If `$ARGUMENTS` contains `--from-brainstorm <slug>`, follow `annexes/from-brainstorm.md` before Phase 1. Else skip.

## Phase 1 — Capture + clarify
1. **Silent context load:** `.aihaus/memory/MEMORY.md`, `.aihaus/project.md`, `.aihaus/decisions.md`, `.aihaus/knowledge.md`.
2. **Assumptions** (delegate): spawn `assumptions-analyzer` → writes `.aihaus/plans/[slug]/ASSUMPTIONS.md` with evidence-tagged findings. Surface blockers before asking.
3. **Clarify** in one batch (1-3 questions): goal, constraints/deadlines, scope size (bugfix / feature / milestone), + any high-confidence blocker from assumptions-analyzer. Wait for answer.
4. **Intake discipline:** see `annexes/intake-discipline.md`. Capture, don't execute.

## Phase 2 — Research + write plan
5. **Codebase research:** affected models / endpoints / services / frontend; read each affected file; existing patterns; migration implications; cross-cutting concerns.
6. **Pattern mapping** (delegate): spawn `pattern-mapper` → `.aihaus/plans/[slug]/PATTERNS.md` with concrete file excerpts.
7. **Technical research** (conditional delegate): for unfamiliar territory, spawn `phase-researcher` → `.aihaus/plans/[slug]/RESEARCH.md` tagged VERIFIED/CITED/ASSUMED.
8. **Generate slug:** `YYMMDD-lowercase-hyphen-description`, ≤ 40 chars total. Attachments use temp-slug until this finalizes — see `annexes/attachments.md`.
9. **Write PLAN.md** at `.aihaus/plans/[slug]/PLAN.md`. Required sections: Problem Statement, Affected Files, Proposed Approach, Alternatives Considered, Risk Assessment, Estimated Scope, Suggested Next Command. See `annexes/guardrails.md` for full shape.

## Phase 3 — Plan-checker gate
10. Spawn `plan-checker` — adversarial, must produce findings or written justification. Writes CHECK.md. Pipe return through `bash .aihaus/hooks/invoke-guard.sh` (ADR-003); on `INVOKE_OK` for `aih-quick draft-adr`, prompt user. **Disposition-based verdict (ADR-M003-E):** if CHECK.md has `Disposition` column → APPROVED = zero BLOCKER; else fall back to zero CRITICAL + zero HIGH. Revise PLAN.md on not-APPROVED. Cap: 2 iterations.

## Phase 4 — Report
11. **Summarize** the plan in 3-5 bullets. Print: PLAN.md path; auxiliary artifacts (ASSUMPTIONS.md, PATTERNS.md, CHECK.md, RESEARCH.md); Suggested Next Command.
12. **Scope-based recommendation:** if > 10 files or multi-story, primary path = `/aih-plan-to-milestone [slug]` (conversational refinement before commit).

## Annexes (referenced, not duplicated)
- `annexes/attachments.md` — temp-slug flow, crash recovery, limits
- `annexes/intake-discipline.md` — capture, don't execute; harness reminder noise
- `annexes/from-brainstorm.md` — Phase 0 section-mapping + error strings
- `annexes/guardrails.md` — must-nots, PLAN.md output shape

## Guardrails (short form — full list in `annexes/guardrails.md`)
- No git branches, no source edits, no writes outside `.aihaus/plans/`.
- Capture, don't execute — explicit override hands off to `/aih-quick` or `/aih-bugfix`.
