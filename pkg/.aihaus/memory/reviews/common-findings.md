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

## CF-007: Meta-milestones ship schema + consumers across stories without a reconciliation gate

**First observed:** 2026-04-14 review of `M003-260414-workflow-core-atomicity-invoke` (findings F-C1, F-M4)

**Pattern:** When a milestone introduces BOTH a new data schema AND multiple downstream consumers of that schema across different stories, the schema-author story (story N) and the consumer stories (N+K) can drift from each other silently. Examples from M003: story 03 (schema v2) defines columns that stories 05/06/11/19 consume — but a column required by story 19's pass-through logic (parent_pid / correlation-id) is hand-waved across those consumer stories and never mandated in the schema spec. The plan is internally consistent per-story but cross-story-broken. Similarly, story 20 asks `architect.md` to write a new ADR stub, but architect's existing `tools:` line lacks Write — a constraint the story claims is already satisfied, but that constraint was never verified against the actual agent file.

**Detection:** When a milestone introduces a new schema + multiple consumers:
1. Enumerate every field/column/key the downstream stories reference.
2. Cross-check: is each one declared in the schema-author story's Acceptance Criteria?
3. For every agent the plan amends with new behavior: grep that agent's current `tools:` line. Is the capability assumed by the new behavior actually present?
4. If either (2) or (3) fails → CRITICAL. The plan will either ship broken or one story will silently under-spec.

**Recommended remediation:** Add a "schema consumers reconciliation" story (or an explicit acceptance-criteria bullet in the schema-author story) that enumerates EVERY consumer story and EVERY field each one reads. Require that list to match 1:1 to the schema grammar. For agent tools: add a pre-flight check in every story that modifies an agent that the existing `tools:` line contains the capabilities the new prose assumes.

**Process feedback for `/aih-plan`:** Cross-story schema drift is invisible to linear reviews. Consider a "shape graph" artifact in the plan phase that lists every novel data structure + every story that reads/writes it, so reviewers can trace consistency.

---

_Appended by plan-checker during self-evolution. Future passes: promote patterns that recur across 3+ reviews into the reviewer's evolution-pass queue._

---

## CF-008: Option menus and "honest checkpoints" masquerading as safety

**First observed:** 2026-04-14 (M005 / evidencias.txt retrospective — cross-project runs including aihaus-flow M003).

**Pattern:** Mid-execution, orchestrator agents emit lettered/numbered option menus ("(a) ship 2a in sequence (b) start with S01 (c) pause..." or "Option 1 / Option 2 / Option 3") and "Honest checkpoint" prose with scope renegotiation, even after the user has explicitly approved autonomous execution. User then has to type unblock signals ("vai", "d", "3", "continue") repeatedly in the same run. The agent treats each wave/story/phase boundary as a natural permission checkpoint despite no contract requiring it.

**Detection:** Scan agent outputs for: `Option [0-9]`, `\([a-d]\)`, `"Honest checkpoint"`, `"Realidade check"`, `"reality check"`, `"surface honest scope"`, `"pausing to surface"`. Any of these emitted after an execution-phase commit == a violation.

**Recommended remediation:** Three layers of defense (M005 Epic C + Epic G in upcoming M006):
1. Skill-level prose ban in `_shared/autonomy-protocol.md` (M005/S06) — this file is authoritative.
2. Explicit one-line reference in every SKILL.md (M005/S07).
3. Planned Haiku `drift-detector` agent (M006) runs after each agent return and strips/flags these patterns automatically.

**Process feedback:** Memory entries alone (e.g., `feedback_execute_dont_ask.md`) were insufficient — the drift reappeared. The annex codifies the rule *inside the skill contract itself*, not just in user memory.
