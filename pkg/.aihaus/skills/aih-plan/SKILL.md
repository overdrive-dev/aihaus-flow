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
2. **Parallel evidence gathering** — in a single message, spawn **both** `assumptions-analyzer` AND `pattern-mapper` as concurrent Agent calls. assumptions-analyzer writes `.aihaus/plans/[slug]/ASSUMPTIONS.md` (evidence-tagged findings, blocker flags); pattern-mapper writes `.aihaus/plans/[slug]/PATTERNS.md` (concrete codebase analogs with file excerpts). Wait for both to return before Step 3. Rationale: pattern context informs which clarifying question matters most, so combining the spawns avoids serial wallclock cost AND makes Step 3 evidence-driven. (Replaces former Phase 2 Step 6 — pattern-mapping is no longer a separate phase.)
3. **Clarify (conditional)** — default position is **proceed**. Ask only when ≥2 dimensions are genuinely missing AND the missing info materially changes the plan. Dimensions: (i) goal/intent, (ii) constraint/deadline, (iii) scope hint (bugfix vs feature vs milestone), (iv) attachment context. Heuristic: if `$ARGUMENTS` includes a specific file/function/path OR references an attachment OR is a well-formed "I want X because Y", **skip the question step entirely** and proceed to Phase 2. When asking is justified, ask **at most 1** question — the highest-leverage one informed by ASSUMPTIONS.md + PATTERNS.md evidence (not hypothetical). Wait only on that one. See `_shared/autonomy-protocol.md` — questions are evidence-driven, not ritual.
4. **Intake discipline:** see `annexes/intake-discipline.md`. Capture, don't execute.

## Phase 2 — Research + write plan
5. **Codebase research:** affected models / endpoints / services / frontend; read each affected file; existing patterns (cross-reference PATTERNS.md from Step 2); migration implications; cross-cutting concerns.
7. **Technical research** (conditional delegate): for unfamiliar territory, spawn `phase-researcher` → `.aihaus/plans/[slug]/RESEARCH.md` tagged VERIFIED/CITED/ASSUMED.
8. **Generate slug:** `YYMMDD-lowercase-hyphen-description`, ≤ 40 chars total. Attachments use temp-slug until this finalizes — see `annexes/attachments.md`.
9. **Write PLAN.md** at `.aihaus/plans/[slug]/PLAN.md`. Required sections: Problem Statement, Affected Files, Proposed Approach, Alternatives Considered, Risk Assessment, Estimated Scope, Suggested Next Command. See `annexes/guardrails.md` for full shape.

## Phase 3 — Plan-checker gate
10. Spawn `plan-checker` — adversarial, must produce findings or written justification. Writes CHECK.md. Pipe return through `bash .aihaus/hooks/invoke-guard.sh` (ADR-003); on `INVOKE_OK` for `aih-quick draft-adr`, prompt user. **Disposition-based verdict (ADR-M003-E):** if CHECK.md has `Disposition` column → APPROVED = zero BLOCKER; else fall back to zero CRITICAL + zero HIGH. Revise PLAN.md on not-APPROVED. **Iteration policy (default 1):** a single plan-checker pass covers ~80% of findings in practice; a 2nd iteration runs ONLY when the 1st iteration emits ≥3 CRITICAL findings that cannot be addressed via surgical inline edits (i.e., they require structural plan revision). Otherwise, apply inline fixes to PLAN.md and exit Phase 3. **Escape hatch:** `$ARGUMENTS` containing `--deep-check` forces 2 iterations regardless. Hard cap remains 2.

## Phase 4 — Report + threshold gate
11. **Summarize** the plan in 3-5 bullets. Print: PLAN.md path; auxiliary artifacts (ASSUMPTIONS.md, PATTERNS.md, CHECK.md, RESEARCH.md).
12. **Threshold gate (see `_shared/autonomy-protocol.md`):** planning is complete → ask ONE natural-language question in the conversation. Small scope: *"Posso executar agora?"* Large scope (>10 files or multi-story): *"Posso promover para milestone draft e seguir até execução?"* On affirmative (y/sim/vai/go/enter), dispatch the appropriate skill via the Skill tool (`aih-milestone --plan [slug]` for large, `aih-run [slug]` for small). On negative, plan stays standalone — user retoma quando quiser. **Never print "Suggested Next Command: /aih-xxx" as an instruction for the user to type** — that delegates keyboard work. Opt-out: `--no-chain` in `$ARGUMENTS` reverts to print-suggestion behavior.

## Annexes (referenced, not duplicated)
- `annexes/attachments.md` — temp-slug flow, crash recovery, limits
- `annexes/intake-discipline.md` — capture, don't execute; harness reminder noise
- `annexes/from-brainstorm.md` — Phase 0 section-mapping + error strings
- `annexes/guardrails.md` — must-nots, PLAN.md output shape

## Guardrails (short form — full list in `annexes/guardrails.md`)
- No git branches, no source edits, no writes outside `.aihaus/plans/`.
- Capture, don't execute — explicit override hands off to `/aih-quick` or `/aih-bugfix`.

## Autonomy
See `_shared/autonomy-protocol.md` — binding rules for planning/threshold/execution phases, no option menus, no honest checkpoints, no delegated typing. Overrides contradictory prose above.
