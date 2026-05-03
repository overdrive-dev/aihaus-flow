# Promotion Backlog — Audit-Driven A → B/C Candidates

This file ranks candidates for A → B/C promotion sourced from the M021 audit
(`enforcement-audit.md`, 289 rows). It is the sole deliverable of M021/S09
and the primary input for M022+ remediation planning.

**Authority:** ADR-260503-A (M021/2026-05-03) — move rule + filter criteria.
**Sole writer:** S09 implementer (per K-002 fix; M021 plan-checker iter 2).
**Regenerate:** re-apply the filter pipeline below against `enforcement-audit.md`
after any new rows are added.

---

## Filter Rationale

The filter pipeline applies the move rule from ADR-260503-A verbatim:

```
primary == "A"                           # pure model-driven only (not A+C, B+C, A+B+C)
AND leverage == "high"                   # blast-radius is large when enforcement drifts
AND (reversibility == "irrev"            # committed/landed requires forensic recovery
     OR drift_risk == "hard")            # surfaces only via incident, not normal review
AND eligibility == "deterministic"       # ADR-260502-A gate — no model judgment in condition
```

The eligibility gate is inherited verbatim from ADR-260502-A "Worked example #2 — DOES NOT FIT":
enforcement hooks must have deterministic, NLP-free conditions. Any step whose
promotion-gate condition requires model judgment MUST stay A by ADR (no hook
can replicate the judgment without voiding the architectural guarantee).

**Excluded from filter pass:**
- Rows with `primary` containing `+` (A+C, B+C, A+B+C) — already partially enforced.
- Rows with `leverage=med` or `leverage=low` — insufficient blast-radius to justify
  the ~120-150 LOC cost of promotion.
- Rows with `reversibility=rev AND drift_risk ∈ {easy, med}` — recoverable on
  normal review cycle; enforcement cost exceeds expected incident cost.
- Rows with `eligibility=model-judgment` or `eligibility=partial` — promotion
  would require NLP conditions in hook logic, prohibited by ADR-260502-A.

---

## Sanity Gate (L8 / H9)

After filter, each candidate's **step body in the source SKILL.md** (not the
audit row) is grepped for the substrings `model`, `judgment`, `decide`, `ask`.
A match does not auto-disqualify; it triggers a `model-judgment-suspected` flag
requiring explicit Notes rationale before inclusion in the promotion backlog.

**Why H9 matters:** the audit row's Notes column sometimes re-uses these words
as explanation (e.g., "eligibility=deterministic — no NLP"), which would produce
false positives. Grepping the source step body instead limits matches to genuine
judgment-language in the step's operational prose.

Candidates flagged `model-judgment-suspected` are retained in Top-N only if
the Notes column provides a clear rationale for why the step is deterministic
despite the keyword presence.

---

## Count Outside Target Band — Rationale

**Filter yielded 6 candidates. Target band: [8, 15]. Count is below band.**

This is expected, not a framework defect. Explanation:

The strict filter (`primary=A`, no composite classes) produces a conservative set
because most high-leverage, hard-to-detect-drift steps have already been promoted
to partial or full enforcement in prior milestones:

- M017/ADR-M017-A: `merge-back.sh` promotion (A → C+A composite, 5 rows now A+C).
- M018: POSIX fix + worktree-reap corrections.
- M019/M020: `manifest-append.sh` terminal-vocabulary enforcement (A → C, 2 rows
  now primary=C), `autonomy-guard.sh` expansions (A → A+C composite).
- M021 audit intent is discovery, not remediation — the 6 survivors represent
  the genuine remaining pure-A steps where a hook or annex could add value.

If a future audit cycle adds new skills or materially rewords existing steps,
the filter should be re-run. The 6 candidates below are M022's highest-priority
targets per the move rule; they represent the densest remaining enforcement gap
in the package.

---

## Top-N Candidates (N=6)

Ranked by `(drift_risk=hard bonus) × (incident-citation present) × (blast-radius scope)`.
Rows citing a historical incident or known failure mode rank above theoretical rows.

| Rank | SKILL | Step | Label | Current | Proposed | Cost (LOC) | Risk | Eligibility | Rationale |
|------|-------|------|-------|---------|----------|------------|------|-------------|-----------|
| 1 | aih-brainstorm | Phase 7.5 — BRIEF.md Schema Validation | brief-schema-validate | A model-driven | C hook-enforced | ~150 LOC + ADR (Pattern 2a) | low | deterministic | Bash grep assertion is already stated in SKILL prose ("Validation command (bash): grep -n ..."). Promoting to a PostToolUse hook that fires after the synthesizer agent returns would eliminate the class of "brainstorm promoted before schema validated" silent failures. High leverage: wrong BRIEF.md schema breaks downstream /aih-plan --from-brainstorm + /aih-milestone --from-brainstorm. Drift risk=hard: validation passes silently if schema check is skipped. Incident pattern: any synthesizer agent that produces a non-conforming BRIEF.md proceeds to Phase 8 undetected. |
| 2 | aih-close | Mutation path (FR-35): Status flip | mutation-status-flip | A model-driven | C hook-enforced | ~150 LOC + ADR (Pattern 2a) | low | deterministic | The step prose already mandates routing all Status writes through `manifest-append.sh`. Promoting to a PreToolUse hook (file-guard class) that rejects direct edits to RUN-MANIFEST.md `status:` field outside manifest-append.sh would close the direct-edit bypass class. ADR-004 single-writer discipline is already binding; this makes it structurally enforced rather than prose-only. Drift risk=hard: a direct-edit bypass produces a stale manifest that resumes incorrectly without surfacing an error. Priority=urgent per analyst risk 4.6: v0.24.0/M020 added this skill; enforcement gap exists from day one. |
| 3 | aih-effort | Phase 4 — Commit + post-edit gate | post-edit-gate | A model-driven | C hook-enforced | ~150 LOC + ADR (Pattern 2a) | med | deterministic | The post-edit gate (`bash tools/smoke-test.sh && bash tools/purity-check.sh`) with self-revert on failure is currently model-driven. Promoting to a PreToolUse hook (git-commit class) that rejects the commit if smoke/purity checks are not current-pass would close the class of "effort edits committed without gate check". Drift risk=hard: a skipped gate produces a broken agent frontmatter distribution that silently ships. Risk=med because the self-revert instruction is explicit and a disciplined model rarely skips it; however, under session interruption or retry, the gate can be omitted. |
| 4 | aih-effort | Phase 3 — Confirm + apply: Edit apply | edit-apply | A model-driven | B agent-delegated | ~120 LOC (Pattern 2b) | low | deterministic (see L8 note) | Per-file frontmatter edit sequence (Edit model: old→target, Edit effort: old→target) is deterministic. Promoting to an annex (Pattern 2b) that provides the ordered per-agent edit contract + rollback instruction would give future implementers a binding reference. No new hook required. L8 note: "model" appears in step body as a YAML field name literal (`model: <target>`), not as a judgment call — the step is mechanically reproducible. Ranked below post-edit-gate because the step already has an explicit git-checkout-on-failure guard; promotion to B annex is a documentation improvement, not a safety fix. |
| 5 | aih-init | 10a. First-run write | first-run-write | A model-driven | C hook-enforced | ~150 LOC + ADR (Pattern 2a) | med | deterministic | The first-run write (verbatim template write to `.aihaus/project.md`) is deterministic and irrev. A PreToolUse hook that validates the target path is under `.aihaus/` before any Write tool call could prevent cross-directory drift (e.g., write to wrong repo root). Risk=med: the path is fixed in practice; promotion adds defense-in-depth for multi-repo environments where `--target` points to an unexpected location. Drift risk=med not hard (classified as such in audit), so ranked below candidates with drift_risk=hard. |
| 6 | aih-milestone | Recovery option 1: Accept unexpected files | merge-back-recovery-1 | A model-driven | B agent-delegated | ~120 LOC (Pattern 2b) | low | deterministic | Recovery procedure (edit Owned Files, git reset HEAD, re-run merge-back.sh) is a deterministic 3-step sequence. Promoting to an annex section with a precise command-sequence table (Pattern 2b) would eliminate the "caution note is model-judgment" gap identified in the audit — the caution note about "only do this if certain the file belongs" is advisory prose that could be replaced by a structural check (compare file path against story prefix patterns). No hook needed. Ranked last: the step is recovery-path only (fires after merge-back.sh exit 3), so blast-radius is bounded. |

---

## Excluded — Model-Judgment (Informational)

These rows passed the `primary=A AND leverage=high AND (irrev OR hard)` filter but
fail `eligibility=deterministic` per ADR-260502-A. They MUST stay A by ADR;
no promotion path exists without voiding the architectural guarantee.

| SKILL | Step | Label | Eligibility | Why excluded |
|-------|------|-------|-------------|--------------|
| aih-bugfix | 11. Verify | verify-build-tests | model-judgment | Project-specific verification commands discovered from README/CONTRIBUTING; which tests to run requires model NLP. No deterministic gate covers all stacks. |
| aih-feature | Step 8: Verify | verify-build-tests | model-judgment | Same as aih-bugfix verify — project-specific command discovery requires model judgment. |
| aih-resume | 6. Identify next substep | next-substep-identify | model-judgment | Substep identification from checkpoint table requires model judgment on agent story plan sequence; enter-without-exit disambiguation requires NLP. |
| aih-milestone | coordinator-no-inline | coordinator-no-inline | model-judgment | "CRITICAL guardrail: coordinator is coordinator only — never write code inline." Code-vs-coordination distinction requires NLP; autonomy-guard.sh Stop hook cannot enforce inline-coding detection. |
| aih-milestone | File Ownership table | file-ownership | model-judgment | Backend/frontend/execution ownership rules; file-ownership conflicts require model judgment to detect — plan-checker detects Owned Files overlap but not runtime file access. |
| aih-milestone | Conflict Prevention rules | conflict-prevention | model-judgment | 4 behavioral rules (exact owned files, dependency detection, teammate messaging, branch discipline); enforcement entirely model-behavioral; structural backstops exist but runtime access cannot be hook-gated. |
| aih-_shared | The 3-phase rule | three-phase-rule | model-judgment | Phase-transition recognition requires NLP; threshold gate cannot be hook-enforced. Binding across all 13 SKILLs. |
| aih-_shared | TRUE blocker definition | true-blocker-definition | model-judgment | Blocker classification requires reasoning on context — no hook can replicate the 4-item exhaustive list judgment. |
| aih-_shared | Natural skill-to-skill chaining | skill-chaining | model-judgment | Implied-next-skill determination requires NLP context; execution-phase auto-dispatch is behavioral. |

---

## Excluded — Already Enforced (Informational)

These rows passed the initial pre-filter check (`primary ∋ A`) but have composite
classification (A+C, A+B+C, B+C) — they are already partially or fully enforced
and not promotion candidates.

| SKILL | Step | Label | Current Primary | Already-enforced layer |
|-------|------|-------|----------------|------------------------|
| aih-milestone | Step 0 — from-brainstorm intake | from-brainstorm-intake | A+C | invoke-guard.sh C layer enforces BRIEF.md required-header check |
| aih-milestone | Step 1 — abort path | abort-orchestration | A+C | phase-advance.sh + worktree-release-all.sh + manifest-append.sh C layers |
| aih-milestone | Step E2 — Create directory + RUN-MANIFEST | dir-manifest-create | A+C | manifest-append.sh + phase-advance.sh + scaffold-assert.sh C layers |
| aih-milestone | Step E3 — Planning (sequential subagents) | planning-agents | B+C | manifest-append.sh + phase-advance.sh + invoke-guard.sh C layers |
| aih-milestone | Step E5 — Spawn agent team | spawn-agents | B+C | merge-back.sh + MANIFEST_PATH injection C layers |
| aih-milestone | Step E5.5 — Mid-milestone adversarial gate | mid-milestone-gate | B+C | AIHAUS_SKIP_E55 + manifest-append.sh C layers |
| aih-milestone | Step E6 — Execute stories | story-execute-loop | B+C | merge-back.sh + git-add-guard.sh + manifest-append.sh C layers |
| aih-milestone | Step E7 — Verify and integrate | verify-integrate | B+C | MANIFEST_PATH injection C layer |
| aih-milestone | Step E8 — Completion | completion-dispatch | A+C | phase-advance.sh + manifest-append.sh C layers |
| aih-milestone | Step 4.5 — Apply Agent Evolutions | agent-evolutions-apply | A+C | purity-check.sh gate C layer |
| aih-milestone | Step 4.6 — Apply Skill Evolutions | skill-evolutions-apply | A+C | pre-apply smoke-test gate C layer |
| aih-_shared | No option menus | no-option-menus | A+C | autonomy-guard.sh regex fast-path C layer |
| aih-_shared | No honest checkpoints | no-honest-checkpoints | A+C | autonomy-guard.sh regex + haiku backstop C layers |
| aih-plan | Phase 0 — from-brainstorm seeding | from-brainstorm-seed | A+C | invoke-guard.sh C layer |
| aih-plan | Phase 3 — Plan-checker gate | plan-checker-gate | B+C | invoke-guard.sh post-return C layer |
| aih-resume | Step 1. Schema migration | schema-migration | A+C | manifest-migrate.sh C layer |
| aih-resume | Step 8. Dispatch branch | resume-dispatch | A+C | manifest-append.sh checkpoint C layers |
| aih-bugfix | Step 9. Apply Fix | apply-fix-delegate | B+C | agent-routing.md + autonomy-guard.sh + worktree-drift-check.sh C layers |

---

## Cost Reference (PATTERNS.md)

From `PATTERNS.md` Pattern 2 (migration cost data):

| Pattern | Description | Cost signature |
|---------|-------------|----------------|
| 2a (A→C) | model prose → hook-enforced | ~2 SKILL.md prose edits (~6 LOC) + 1 new hook (~50-200 LOC) + ADR stub + 1-2 smoke checks. Total ~150 LOC. |
| 2b (A→B) | model prose → agent-delegated annex | ~2 SKILL.md rewrites (~10 LOC) + new annex (~120 LOC). No hook. No ADR required. Total ~120 LOC. |
| 2c (B+C-advisory) | advisory hook + agent prompt compliance check | ~50 LOC. Hook emits advisory + agent prompt gains compliance checklist item. |
| 2d (worktree-drift class) | PreToolUse hook + agent prompt edits + allowlist | ~1 hook (~80-150 LOC) + 1-2 agent prompt edits + EXPECTED_HOOKS allowlist entry + optional ADR. |

ADR requirement: Pattern 2a (A→C) ALWAYS requires an ADR (new hook = Tier 2 per
ADR-002). Pattern 2b (A→B, annex only) does NOT require an ADR — prose change only.
