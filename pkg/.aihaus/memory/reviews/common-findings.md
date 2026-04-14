# plan-checker — Common Findings Log

Recurring patterns observed across reviews. Each entry is a pattern that appeared in >1 review or is worth codifying for future passes.

## CF-001: Brainstorm findings silently dropped in plan

**First observed:** 2026-04-14 review of `260413-port-to-cursor-feasibility/PLAN.md`

**Pattern:** When a plan is seeded from a brainstorm BRIEF.md (via `/aih-plan --from-brainstorm`), the plan tends to inherit the CRITICAL finding explicitly (it's load-bearing) and the MEDIUM/LOW findings via Risk Assessment seeding — but HIGH findings *between* those tiers often vanish without explicit disposition. The plan author addresses 2-3 marquee HIGH items and silently drops the rest.

**Detection:** When reviewing a `--from-brainstorm`-seeded plan, count HIGH findings in `.aihaus/brainstorm/<slug>/CHALLENGES.md`. Then scan the plan for each — is it (a) addressed in an Approach step, (b) seeded as a Risk row, (c) deferred with a named follow-up, (d) silently absent? Category (d) is a HIGH finding itself.

**Recommended remediation:** Require plans seeded from brainstorms to include a "Brainstorm Findings Disposition" section (or equivalent table) after Risk Assessment. Every CHALLENGES.md HIGH (and CRITICAL) gets one row: addressed-by / deferred-to / accepted-as-risk / explicit-rationale.

**Process feedback for `/aih-plan`:** Consider adding a Phase 2 requirement: "If `--from-brainstorm` was used AND BRIEF.md references any HIGH findings, PLAN.md MUST include a dispositions table." Plan-checker can then assert this as a structural check, not a per-finding hunt.

---

## CF-002: Decision-gate thresholds with undefined edge cases

**First observed:** 2026-04-14 review of `260413-port-to-cursor-feasibility/PLAN.md` (finding F-H3)

**Pattern:** Plans with a "Decision gate" step tend to define Green/Yellow/Red (or equivalent) branches with thresholds ("≥4 of 5 verified") that don't cover edge cases — PARTIAL verdicts, one UNVERIFIED, classifications performed by the implementer rather than a neutral party. The gate is load-bearing but has rules with holes, so whoever reaches it at run time will just pick the branch they prefer.

**Detection:** When a plan includes branching ("if X, do A; else do B"), ask: (1) Is the condition exhaustive over all possible Story N outcomes? (2) Who evaluates — the executor who has skin in the game, or a neutral reviewer? (3) Are edge cases (PARTIAL, ambiguous) explicitly classified?

**Recommended remediation:** Replace threshold-based gates with explicit decision matrices (all possible outcome tuples → one branch each). Add a "classification performed by plan-checker" or similar neutral-party clause.

---

## CF-003: "Preview framing" as prose-only safety rail

**First observed:** 2026-04-14 review of `260413-port-to-cursor-feasibility/PLAN.md` (finding F-M2)

**Pattern:** Plans that ship something "experimental" or "preview" often rely on README prose, installer friction, or documentation to prevent production use. None of these are machine-enforced. Users ignore prose; friction becomes workflow; and the "preview" label erodes the moment anyone links to the code.

**Detection:** When a plan justifies risk acceptance with "preview framing," ask: where is the enforcement boundary? Is it a word in README.md, or a frontmatter field the smoke-test asserts, or a runtime check that refuses to execute in non-preview mode?

**Recommended remediation:** File-level invariants (required `preview: true` frontmatter, header banners, runtime guards) are stronger than prose. Either harden the enforcement to file level, or explicitly accept the risk that "preview" is advisory.

---

_Appended by plan-checker during self-evolution. Future passes: promote patterns that recur across 3+ reviews into the reviewer's evolution-pass queue._
