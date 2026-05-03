# Golden-Rows Fixture

Exemplar canonical-shape rows covering all 4 SKILL step formats.
Every S02-S07 implementer briefing references this file before drafting any row.

## Purpose

These 9 rows define the canonical shape for `enforcement-audit.md` entries.
They cover:
- All 4 step format types (H3-colon, H2-step, H3-numbered, D2-fallback)
- Composite Primary (`B+C`)
- `eligibility=model-judgment` (non-promotable A step)
- `escape=opt-out-env` (ADR-M017-family hook with AIHAUS_* bypass)
- `escape=manual-override` (explicit user command bypass)
- `gate=advisory+blocking` (hook emitting advisory at one site + blocking at another)

## Schema Reference

| SKILL | Location | Step | Label | Primary | Actor | Gate | Escape | Leverage | Reversibility | Drift Risk | Eligibility | Notes |
|-------|----------|------|-------|---------|-------|------|--------|----------|---------------|------------|-------------|-------|

Column definitions (ADR-260503-A §Decision):
- **SKILL** — `aih-<slug>` identifier
- **Location** — relative path within `pkg/.aihaus/skills/`; composite with ` + ` when step spans files
- **Step** — exact heading text (e.g., `Step 7: Implement`)
- **Label** — kebab-case short label for the step's enforcement concern
- **Primary** — `{A, B, C, A+C, B+C, A+B+C}` — primary enforcement layer
- **Actor** — `{model, agent, hook, multi}`
- **Gate** — `{none, advisory, blocking, advisory+blocking}`
- **Escape** — `{none, opt-out-env, manual-override}`
- **Leverage** — `{low, med, high}` — blast-radius of drift
- **Reversibility** — `{rev, irrev}` — recovery cost after drift
- **Drift Risk** — `{easy, med, hard}` — detectability of drift
- **Eligibility** — `{deterministic, model-judgment, partial}` — ADR-260502-A gate
- **Notes** — free-form rationale; required when `eligibility=model-judgment` or `Primary` is composite

## Golden Rows

| SKILL | Location | Step | Label | Primary | Actor | Gate | Escape | Leverage | Reversibility | Drift Risk | Eligibility | Notes |
|-------|----------|------|-------|---------|-------|------|--------|----------|---------------|------------|-------------|-------|
| aih-feature | aih-feature/SKILL.md | Step 1: Load Context | context-load | A | model | none | none | low | rev | easy | deterministic | H3-colon format; model reads project.md + decisions.md |
| aih-milestone | aih-milestone/SKILL.md | Step 2 — List Existing Drafts | list-drafts | A | model | none | none | low | rev | easy | model-judgment | H2-step format (D2 fallback path); listing requires NLP scan of plan dir — eligibility=model-judgment; stays A by ADR-260502-A |
| aih-bugfix | aih-bugfix/SKILL.md | 7. Derive Slug | derive-slug | A | model | none | none | low | rev | easy | deterministic | H3-numbered format; deterministic slug derivation from branch name |
| aih-plan | aih-plan/SKILL.md | Phase 1 — Capture + clarify | capture-clarify | A | model | none | none | med | rev | med | model-judgment | D2 fallback (zero numbered-H3); free-form capture requires model judgment; stays A by ADR-260502-A |
| aih-feature | aih-feature/SKILL.md | Step 7: Implement (delegate; never inline for non-trivial work) | implement-delegate | B+C | multi | advisory+blocking | opt-out-env | high | irrev | hard | deterministic | H3-colon; composite B+C — agent spawned (B) + worktree-drift-check hook (C); AIHAUS_MERGE_BACK_GUARD=0 opt-out; move candidate (leverage=high, irrev, hard) |
| aih-milestone | aih-milestone/annexes/execution.md | Step E5 — Spawn agent team | spawn-agents | B | agent | advisory | none | high | irrev | med | deterministic | H3-colon in annex; agent-routing.md governs dispatch; high leverage because wrong agent = wrong file set |
| aih-feature | aih-feature/SKILL.md | Step 13: Report Completion | report-completion | A | model | none | none | low | rev | easy | model-judgment | H3-colon; free-form prose report; eligibility=model-judgment — cannot deterministically enforce narrative quality; stays A by ADR-260502-A |
| aih-milestone | aih-milestone/SKILL.md | Step 0 — --from-brainstorm intake (conditional) | from-brainstorm-intake | A+C | multi | blocking | opt-out-env | med | rev | med | deterministic | H2-step; conditional gate enforced by invoke-guard.sh (C layer) + model reads plan (A layer); escape via AIHAUS_INVOKE_GUARD=0 |
| aih-bugfix | aih-bugfix/SKILL.md | 16. Report Completion | report-completion-bugfix | A | model | none | manual-override | low | rev | easy | model-judgment | H3-numbered; completion prose is model-driven; manual-override = user can skip via /aih-close; eligibility=model-judgment |
