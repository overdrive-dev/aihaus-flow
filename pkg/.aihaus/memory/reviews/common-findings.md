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

## CF-004: Load-bearing claims unverified against target platform

**First observed:** 2026-04-14 review of `260414-workflow-polish-agent-invoke/PLAN.md` (findings F-C2, F-C3, F-H3)

**Pattern:** Plans that span BOTH protocol design AND hook/tool implementation tend to make platform-dependent assumptions that are never empirically tested. Examples: (a) env var propagation across Agent tool boundaries, (b) `flock` availability on Git Bash, (c) atomic `mv` semantics on cloud-synced filesystems (OneDrive, Dropbox, iCloud), (d) Windows NTFS case-insensitivity, (e) "Claude Code ignores unknown settings keys." Each assumption is plausible, none are verified. Hooks that rely on them silently no-op or race.

**Detection:** When reviewing a plan that introduces shell-level primitives (hooks, lock files, env vars, atomic renames), extract every platform-specific claim and ask: "Was this empirically tested on the actual target platform, or cited from ASSUMED training data?" Cross-reference with existing hooks in `pkg/.aihaus/hooks/` to see how similar concerns were handled before (e.g., `session-start.sh`'s `CLAUDE_ENV_FILE` pattern).

**Recommended remediation:** Require platform-verification pre-stories before any cross-platform hook lands. Write a throwaway harness test for each load-bearing assumption, attach output, THEN design the hook. If `flock` is missing, design around it explicitly; don't fallback-handwave. Document confirmed platform behaviors in `.aihaus/knowledge.md` so future plans inherit the verification.

**Process feedback for `/aih-plan`:** When the plan adds hooks that rely on `flock`, env vars, atomic mv, or any filesystem primitive, the plan-checker's absence analysis should add one row per claim: "Did the plan verify X on Git Bash / Windows / OneDrive?" Unverified = CRITICAL by default.

---

## CF-005: Internal contradictions between tables and prose ("Not touched" paradox)

**First observed:** 2026-04-14 review of `260414-workflow-polish-agent-invoke/PLAN.md` (finding F-C4)

**Pattern:** Plans with both an "Affected Files" table and a "Not touched" exclusion block sometimes list the same file in both — usually because the file is "not touched" in one dimension (e.g., tools frontmatter unchanged) but "modified" in another (prose added). The contradictory framing confuses implementers and reviewers, and creates merge-conflict risk when two stories race on the same file with different mental models of what's off-limits.

**Detection:** Grep the plan for every file path in the Affected Files table. If the same path appears in a "Not touched" or "stay read-only" block, the plan has a contradiction — flag it.

**Recommended remediation:** Replace "not touched" prose with an explicit contract: "These fields stay byte-for-byte identical: [list]. New prose may be added elsewhere in the file." Avoid overloaded vocabulary like "read-only" when ADR-001 already owns that term for a different concept.

---

## CF-006: Self-applying rules the plan itself violates

**First observed:** 2026-04-14 review of `260414-workflow-polish-agent-invoke/PLAN.md` (finding F-H1)

**Pattern:** Plans that introduce a new guardrail (e.g., "force-split on >12 stories", "reject plans with >N open questions") occasionally violate the guardrail on the plan that introduces it. Author acknowledges the violation in prose but defers the rule to a subsequent invocation. This makes the guardrail's first enforcement the plan AFTER the guardrail ships — skipping the load-bearing case.

**Detection:** For any plan that introduces a new threshold or gate, measure the plan itself against the proposed rule. If the plan would fail the rule, the plan must either (a) apply the rule to itself before promoting, or (b) drop the rule (it's not load-bearing enough to enforce on the introducing plan).

**Recommended remediation:** Apply the rule self-reflexively. Split the plan, trim the scope, or abandon the rule. "We'll apply it to the NEXT plan" is a tell that the author doesn't actually believe the rule is necessary.

---

_Appended by plan-checker during self-evolution. Future passes: promote patterns that recur across 3+ reviews into the reviewer's evolution-pass queue._
