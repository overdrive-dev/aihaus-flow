---
name: aih-plan
description: "Research a problem and produce a plan with no code, surfaced to the native Plan panel for approval. Use when you want to think and plan before building."
allowed-tools: Read Grep Glob Bash WebFetch Skill ExitPlanMode
argument-hint: "[what you want to plan — feature, migration, refactor, etc.]"
---

## Task
Research `$ARGUMENTS` and produce a detailed plan at `.aihaus/plans/[slug]/PLAN.md`. No code changes.

## Phase 0 — --from-brainstorm seeding (conditional)
If `$ARGUMENTS` contains `--from-brainstorm <slug>`, follow `annexes/from-brainstorm.md` before Phase 1. Else skip.

## Phase 1 — Capture + clarify
1. **Silent context load:** `.aihaus/memory/MEMORY.md`, `.aihaus/project.md`, `.aihaus/decisions.md`, `.aihaus/knowledge.md`.
2. **Parallel evidence gathering** — in a single message, spawn **both** `assumptions-analyzer` AND `pattern-mapper` as concurrent Agent calls. assumptions-analyzer writes `.aihaus/plans/[slug]/ASSUMPTIONS.md` (evidence-tagged findings, blocker flags); pattern-mapper writes `.aihaus/plans/[slug]/PATTERNS.md` (concrete codebase analogs with file excerpts). Wait for both to return before Step 3. Rationale: pattern context informs which clarifying question matters most, so combining the spawns avoids serial wallclock cost AND makes Step 3 evidence-driven. (Replaces a pattern-mapping step that previously lived in Phase 2 — pattern-mapping is no longer a separate phase.) **Active-slug sentinel:** after slug is finalized (Step 7), write `printf '%s' "[slug]" > .claude/calibrate-guard.active-slug` (single-line, no trailing newline). Creates `.claude/` dir if absent. Used by calibrate-guard.sh (M029/ADR-260511-A).
3. **Clarify (conditional)** — default position is **proceed**. Ask only when ≥2 dimensions are genuinely missing AND the missing info materially changes the plan. Dimensions: (i) goal/intent, (ii) constraint/deadline, (iii) scope hint (bugfix vs feature vs milestone), (iv) attachment context. Heuristic: if `$ARGUMENTS` includes a specific file/function/path OR references an attachment OR is a well-formed "I want X because Y", **skip the question step entirely** and proceed to Phase 2. When asking is justified, ask **at most 1** question — the highest-leverage one informed by ASSUMPTIONS.md + PATTERNS.md evidence (not hypothetical). Wait only on that one. See `_shared/autonomy-protocol.md` — questions are evidence-driven, not ritual.
4. **Intake discipline:** see `annexes/intake-discipline.md`. Capture, don't execute.

## Phase 2 — Research + write plan
5. **Codebase research:** affected models / endpoints / services / frontend; read each affected file; existing patterns (cross-reference PATTERNS.md from Step 2); migration implications; cross-cutting concerns.
6. **Technical research** (conditional delegate): for unfamiliar territory, spawn `phase-researcher` → `.aihaus/plans/[slug]/RESEARCH.md` tagged VERIFIED/CITED/ASSUMED.
7. **Generate slug:** `YYMMDD-lowercase-hyphen-description`, ≤ 40 chars total. Attachments use temp-slug until this finalizes — see `annexes/attachments.md`.
8. **Write PLAN.md** at `.aihaus/plans/[slug]/PLAN.md`. Required sections: Problem Statement, Affected Files, Proposed Approach, Alternatives Considered, Risk Assessment, Estimated Scope, Suggested Next Command. See `annexes/guardrails.md` for full shape.

## Phase 3 — Plan-checker gate
9. Spawn `plan-checker` — adversarial, must produce findings or written justification. Writes CHECK.md. Pipe return through `bash .aihaus/hooks/invoke-guard.sh` (ADR-003); on `INVOKE_OK` for `aih-quick draft-adr`, prompt user. **Disposition-based verdict (ADR-M003-E):** if CHECK.md has `Disposition` column → APPROVED = zero BLOCKER; else fall back to zero CRITICAL + zero HIGH. Revise PLAN.md on not-APPROVED. **Iteration policy (default 1):** a single plan-checker pass covers ~80% of findings in practice; a 2nd iteration runs ONLY when the 1st iteration emits ≥3 CRITICAL findings that cannot be addressed via surgical inline edits (i.e., they require structural plan revision). Otherwise, apply inline fixes to PLAN.md and exit Phase 3. **Escape hatch:** `$ARGUMENTS` containing `--deep-check` forces 2 iterations regardless. Hard cap remains 2.

## Phase 3.5 — Calibration-gate (M027/S5)

If `--no-calibrate` flag is present → skip (calibrate-guard.sh writes `"event":"calibration-skip"` row directly to `.claude/audit/hook.jsonl` — M029/ADR-260511-A). Otherwise, spawn `plan-calibrator` (`:adversarial`, read-only). Pass: analyst-brief path, PRD path, architecture path, CHECK.md path, and `git log -1 --format=%H -- .aihaus/plans/<slug>/CHECK.md` SHA. If a brainstorm slug was passed via `--from-brainstorm`, pass it so the calibrator can dedupe against SUBSTRATE-FINDINGS.md. Trigger: ambiguity-surface-detection (defaults applied without ask, gaps in brief, CHECK.md inconsistencies — NOT story-count). Stop: user "no more questions" OR calibrator emits `BUSINESS-RULES-EXHAUSTED` OR hard cap 30 turns. Parent skill writes `.aihaus/plans/<slug>/BUSINESS-RULES.md` verbatim from payload; applies PRD patches via Edit.

## Phase 3.6 — --no-tdd flag (M028/S3)

If `--no-tdd` flag is present in `$ARGUMENTS` → audit-log and suppress downstream tdd-discipline dispatch: `bash .aihaus/hooks/manifest-append.sh --audit tdd-skip --reason "user-override"`. Sets `AIHAUS_TDD_GUARD=0` to bypass `tdd-guard.sh` PreToolUse hook for this invocation. Mirrors `--no-calibrate` opt-out pattern (Phase 3.5). If `--no-tdd` absent, no-op — tdd-discipline dispatch follows project.md `testing_discipline` field at execution time.

## Phase 4 — Report + threshold gate
10. **Summarize** the plan in 3-5 bullets. Print: PLAN.md path; auxiliary artifacts (ASSUMPTIONS.md, PATTERNS.md, CHECK.md, RESEARCH.md, BUSINESS-RULES.md if present). Honor `--no-tdd` flag (audit-logged). **Sentinel cleanup:** `rm -f .claude/calibrate-guard.active-slug 2>/dev/null || true`.
11. **Threshold gate (see `_shared/autonomy-protocol.md`):** planning is complete → **surface the plan via native plan mode (`ExitPlanMode`)** so it renders in the GUI Plan panel; the native approve/reject IS the planejamento gate. PLAN.md stays the durable source — the panel is a projection of it (run-state.md). If plan mode is unavailable, fall back to ONE natural-language question. Small scope: *"Posso executar agora?"* Large scope (>10 files or multi-story): *"Posso promover para milestone draft e seguir até execução?"* On approval/affirmative (y/sim/vai/go/enter), dispatch the appropriate skill via the Skill tool (`aih-milestone --plan [slug]` for large, `aih-feature --plan [slug]` for small). On reject/negative, plan stays standalone — user retoma quando quiser. **Never print "Suggested Next Command: /aih-xxx" as an instruction for the user to type** — that delegates keyboard work. Opt-out: `--no-chain` reverts to print-suggestion; `--no-plan-mode` forces the NL question instead of `ExitPlanMode`.

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
<!-- See pkg/.aihaus/skills/_shared/enforcement-audit.md for this SKILL's enforcement audit. -->
