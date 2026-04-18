# Cohort Taxonomy — 46 Agents → 6 Uniform Cohorts

This annex is the single source of truth for cohort membership, consumed by
`/aih-effort` (preset filter, sidecar write) and by the restore path in
`pkg/scripts/lib/restore-effort.sh` + `install.ps1`. Membership lives ONLY
here — no `cohort:` frontmatter field per agent (keeps the sync surface
minimal). See **ADR-M012-A** in `.aihaus/decisions.md` for the formal
cohort semantics; see `annexes/presets.md` for the 3-preset effort matrix.

A **cohort** is a group of agents sharing one fixed default model + a
calibratable effort tier. Every cohort below declares exactly one
**Default model** (the baseline for a clean v0.16.0 install). Effort is
the only axis preset-calibration mutates, except for `:doer` (model swaps
sonnet → opus on the `high` preset). All other cohorts hold their fixed
model across all 3 presets (`cost`, `balanced`, `high`).

---

## Cohorts

### `:planner-binding`

**Default model:** opus
**Default effort:** xhigh (balanced)

The 4 upstream binding planners whose outputs gate every downstream story.
Elevated to their own cohort (was an intra-cohort `xhigh` carve-out inside
the v0.15.0 `:planner`) so that the binding tier is a first-class calibration
target — explicit `--cohort :planner-binding` or `--cohort :planner` invocations
apply to each independently.

Members (alphabetical):

- architect
- planner
- product-manager
- roadmapper

**Count: 4**

---

### `:planner`

**Default model:** opus
**Default effort:** high (balanced)

Research + structured planning agents that produce upstream-of-decision
artifacts (BRIEFs, research synthesis, arch-adjacent analysis, UX
specifications). Do not produce code or mutate files directly. Output
feeds `:planner-binding` and `:doer`.

Members (alphabetical):

- advisor-researcher
- ai-researcher
- analyst
- assumptions-analyzer
- brainstorm-synthesizer
- domain-researcher
- eval-planner
- framework-selector
- phase-researcher
- project-researcher
- research-synthesizer
- knowledge-curator
- ui-researcher
- ux-designer

**Count: 14**

---

### `:doer`

**Default model:** sonnet
**Default effort:** high (balanced)

Forward-edit implementation agents — write code, tests, docs; perform network
actions (e.g., `notion-sync`). The only cohort with a model swap across
presets: `balanced` = `(sonnet, high)`, `high` = `(opus, high)` (sonnet caps
at effort `high`; xhigh/max exist only on opus). `cost` = `(sonnet, medium)`.

Includes former `investigator` cohort members (`debugger`, `debug-session-manager`,
`user-profiler`) — absorbed in M012 because the default tier `(sonnet, high)`
was byte-identical, making the investigator cohort indistinguishable from
`:doer` at calibration time.

Members (alphabetical):

- code-fixer
- codebase-mapper
- debug-session-manager
- debugger
- doc-writer
- executor
- frontend-dev
- implementer
- intel-updater
- notion-sync
- nyquist-auditor
- pattern-mapper
- project-analyst
- test-writer
- user-profiler

**Count: 15**

---

### `:verifier`

**Default model:** haiku
**Default effort:** high (balanced)

Read-only assessment agents that check existing artifacts for correctness,
integration, security, and visual quality — no code mutation. Haiku 4.5
provides near-frontier intelligence at 5× lower cost than opus for boolean
artifact checks. `cost` = `(haiku, medium)`.

`ui-auditor` moved here from the v0.15.0 `verifier-rich` override subset:
vision-based artifact verification is precisely the haiku-eligible workload —
Haiku 4.5 supports vision, matching `ui-auditor`'s 6-pillar visual audit.
`nyquist-auditor` moved to `:doer` (see Reassignments subsection).

Members (alphabetical):

- context-curator
- doc-verifier
- eval-auditor
- integration-checker
- security-auditor
- ui-auditor
- ui-checker
- verifier

**Count: 8**

---

### `:adversarial-scout`

**Default model:** opus
**Default effort:** max (preset-immune baseline)

**Preset-immune:** true

No `--preset <name>` invocation mutates any member of this cohort. Only
an explicit `--cohort :adversarial-scout --model X --effort Y` (with
literal-word `adversarial` confirmation) or `--agent <member> --model X
--effort Y` invocation may alter a member. Immunity enforced via the
`is_preset_immune(cohort)` helper in `pkg/scripts/lib/restore-effort.sh`
(PowerShell: `Test-PresetImmune` in `install.ps1`). See ADR-M012-A for the
`is_preset_immune` binding contract.

Scout-tier agents produce pre-merge findings that are binding on downstream
plan approval. `(opus, max)` effort reflects the highest-stakes review
position: a scout finding blocks story execution, making false-negatives
catastrophic.

Members (alphabetical):

- contrarian
- plan-checker

**Count: 2**

---

### `:adversarial-review`

**Default model:** opus
**Default effort:** high (preset-immune baseline)

**Preset-immune:** true

No `--preset <name>` invocation mutates any member of this cohort. Only
an explicit `--cohort :adversarial-review --model X --effort Y` (with
literal-word `adversarial` confirmation) or `--agent <member> --model X
--effort Y` invocation may alter a member. Immunity enforced via the same
`is_preset_immune(cohort)` helper referenced above. See ADR-M012-A.

Review-tier agents produce post-implementation code and logic review findings
that gate merge. `(opus, high)` rather than `(opus, max)` — review scope is
bounded to an already-implemented diff, not an open-ended plan.

Members (alphabetical):

- code-reviewer
- reviewer

**Count: 2**

---

## Membership table (46 agents)

**Parse contract (F-006 — binding per ADR-M012-A).** This table has exactly
5 data columns. The header is `| # | Agent | Cohort | Model | Effort |`.
Every data row yields NF=7 when `awk -F'|'` splits on `|` (counting leading
+ trailing empty fields). Column order is positional and must not change
without an ADR amendment — `restore-effort.sh` parses `f[3]=Agent`,
`f[4]=Cohort`; `install.ps1` uses `(?<agent>\S+)` at position 3 and
`(?<cohort>:\w[\w-]*)` at position 4. S07 smoke Check 28 asserts NF=7
on every data row at CI time.

Model column reflects the cohort's **fixed default model** for a balanced
install. Effort column reflects the **balanced preset** default for each
cohort.

| # | Agent | Cohort | Model | Effort |
|---|-------|--------|-------|--------|
|  1 | advisor-researcher       | :planner          | opus   | high  |
|  2 | ai-researcher            | :planner          | opus   | high  |
|  3 | analyst                  | :planner          | opus   | high  |
|  4 | architect                | :planner-binding  | opus   | xhigh |
|  5 | assumptions-analyzer     | :planner          | opus   | high  |
|  6 | brainstorm-synthesizer   | :planner          | opus   | high  |
|  7 | code-fixer               | :doer             | sonnet | high  |
|  8 | code-reviewer            | :adversarial-review | opus | high  |
|  9 | codebase-mapper          | :doer             | sonnet | high  |
| 10 | context-curator          | :verifier         | haiku  | high  |
| 11 | contrarian               | :adversarial-scout | opus  | max   |
| 12 | debug-session-manager    | :doer             | sonnet | high  |
| 13 | debugger                 | :doer             | sonnet | high  |
| 14 | doc-verifier             | :verifier         | haiku  | high  |
| 15 | doc-writer               | :doer             | sonnet | high  |
| 16 | domain-researcher        | :planner          | opus   | high  |
| 17 | eval-auditor             | :verifier         | haiku  | high  |
| 18 | eval-planner             | :planner          | opus   | high  |
| 19 | executor                 | :doer             | sonnet | high  |
| 20 | framework-selector       | :planner          | opus   | high  |
| 21 | frontend-dev             | :doer             | sonnet | high  |
| 22 | implementer              | :doer             | sonnet | high  |
| 23 | integration-checker      | :verifier         | haiku  | high  |
| 24 | intel-updater            | :doer             | sonnet | high  |
| 25 | knowledge-curator        | :planner          | opus   | high  |
| 26 | learning-advisor         | :verifier         | haiku  | high  |
| 27 | notion-sync              | :doer             | sonnet | high  |
| 28 | nyquist-auditor          | :doer             | sonnet | high  |
| 29 | pattern-mapper           | :doer             | sonnet | high  |
| 30 | phase-researcher         | :planner          | opus   | high  |
| 31 | plan-checker             | :adversarial-scout | opus  | max   |
| 32 | planner                  | :planner-binding  | opus   | xhigh |
| 33 | product-manager          | :planner-binding  | opus   | xhigh |
| 34 | project-analyst          | :doer             | sonnet | high  |
| 35 | project-researcher       | :planner          | opus   | high  |
| 36 | research-synthesizer     | :planner          | opus   | high  |
| 37 | reviewer                 | :adversarial-review | opus | high  |
| 38 | roadmapper               | :planner-binding  | opus   | xhigh |
| 39 | security-auditor         | :verifier         | haiku  | high  |
| 40 | test-writer              | :doer             | sonnet | high  |
| 41 | ui-auditor               | :verifier         | haiku  | high  |
| 42 | ui-checker               | :verifier         | haiku  | high  |
| 43 | ui-researcher            | :planner          | opus   | high  |
| 44 | user-profiler            | :doer             | sonnet | high  |
| 45 | ux-designer              | :planner          | opus   | high  |
| 46 | verifier                 | :verifier         | haiku  | high  |

**Totals:** :planner-binding=4 · :planner=14 · :doer=15 · :verifier=9 · :adversarial-scout=2 · :adversarial-review=2 · Sum=46

---

## Reassignments vs v0.15.0

The following moves occurred relative to the v0.15.0 5-cohort taxonomy. All
rationale is authoritative (ADR-M012-A binding).

#### Agent reassignments

| Agent | v0.15.0 cohort | v0.16.0 cohort | Rationale |
|-------|---------------|----------------|-----------|
| nyquist-auditor | `:verifier` (sonnet override, inside the v0.15.0 verifier-rich subset) | `:doer` | Generates and iteratively debugs minimal behavioral tests — a file-generation workload that belongs in the `:doer` cohort, not the read-only `:verifier` cohort. Moving off the sonnet override to `:doer` sonnet-default. |
| ui-auditor | `:verifier` (sonnet override, inside the v0.15.0 verifier-rich subset) | `:verifier` (haiku default) | Artifact verification with vision — Haiku 4.5 supports vision and its near-frontier intelligence suffices for the 6-pillar visual audit. Moving off the sonnet override to `:verifier` haiku-default eliminates the non-uniformity. |
| debugger | `investigator` cohort (deleted in M012) | `:doer` | Cohort deleted. Default tier `(sonnet, high)` byte-identical to `:doer`; no calibration-meaningful distinction. |
| debug-session-manager | `investigator` cohort (deleted in M012) | `:doer` | Same rationale as `debugger`. |
| user-profiler | `investigator` cohort (deleted in M012) | `:doer` | Same rationale as `debugger`. |
| architect | `:planner` (xhigh binding override) | `:planner-binding` | Binding-4 split: elevated to their own cohort from an intra-cohort carve-out. |
| planner | `:planner` (xhigh binding override) | `:planner-binding` | Same rationale as `architect`. |
| product-manager | `:planner` (xhigh binding override) | `:planner-binding` | Same rationale as `architect`. |
| roadmapper | `:planner` (xhigh binding override) | `:planner-binding` | Same rationale as `architect`. |
| plan-checker | `:adversarial` | `:adversarial-scout` | Adversarial split: scouts carry the `(opus, max)` tier. |
| contrarian | `:adversarial` | `:adversarial-scout` | Same rationale as `plan-checker`. |
| reviewer | `:adversarial` | `:adversarial-review` | Adversarial split: reviewers carry the `(opus, high)` tier. |
| code-reviewer | `:adversarial` | `:adversarial-review` | Same rationale as `reviewer`. |

#### Cohort-level changes

| Change | Detail |
|--------|--------|
| `verifier-rich` subset deleted | Was an architect-voice label for the 2-member sonnet-override subset inside v0.15.0 `:verifier` (nyquist-auditor, ui-auditor). Never a formal cohort name in the sidecar; removed from discourse entirely. Members reassigned individually above. |
| `investigator` cohort deleted | 3-member cohort (`debugger`, `debug-session-manager`, `user-profiler`) folded into `:doer`. Default tier was `(sonnet, high)` — byte-identical to `:doer` default. Cohort was not a meaningful calibration target; absorbing into `:doer` eliminates a category without loss of calibration resolution. |
| `:planner` (17) split into `:planner-binding` (4) + `:planner` (13) | The intra-cohort carve-out that granted 4 binding agents `(opus, xhigh)` while the other 13 ran `(opus, high)` becomes two distinct cohorts. Users can now target `--cohort :planner-binding` independently, preserving the tier distinction without intra-cohort special-casing. |
| `:adversarial` (4) split into `:adversarial-scout` (2) + `:adversarial-review` (2) | The internal 2-tier structure (max vs high effort) inside v0.15.0 `adversarial` cohort is now expressed as two cohorts. Both remain preset-immune. Sidecar migration maps old `adversarial.*` settings to `adversarial-scout.*` only (conservative; see ADR-M012-A migration table). |

#### Rationale for the 4 non-trivial moves

1. **`nyquist-auditor` → `:doer`:** `nyquist-auditor` generates tests and
   iteratively debugs them until behavioral coverage is satisfied. This is
   a file-generation workload — the agent writes, runs, and mutates code.
   Keeping it in `:verifier` (a read-only assessment cohort) was a
   category error. `:doer` sonnet-default matches the agent's actual
   compute profile.

2. **`ui-auditor` → `:verifier` (haiku default):** The agent performs a
   6-pillar visual audit of rendered UI artifacts — a read-only,
   vision-based assessment with a pass/fail output. Haiku 4.5 supports
   vision natively and provides near-frontier intelligence for this
   workload at a fraction of sonnet cost. The sonnet override existed
   because of a conservative initial placement before Haiku 4.5 vision
   support was confirmed; that reason no longer applies.

3. **`investigator` cohort merged to `:doer`:** The investigator cohort was
   added in M010.1 to hold `debugger`, `debug-session-manager`, and
   `user-profiler` as hypothesis-driven agents distinct from read-only
   `:verifier`. The split was correct at the time. However, the resulting
   default tuple `(sonnet, high)` is byte-identical to `:doer`'s default —
   a user targeting the investigator cohort was doing the same thing as
   targeting the 3 agents individually within `:doer`. No calibration-level
   distinction survived the M010.1 framing. Absorbing into `:doer` removes
   a cohort without removing any precision.

4. **`:planner` split preserves binding-4 tier distinction as a cohort:**
   v0.15.0 expressed the binding-4 distinction as an intra-cohort override:
   `architect`, `planner`, `product-manager`, `roadmapper` carried
   `(opus, xhigh)` while the other 13 `:planner` members ran `(opus, high)`.
   This meant `--cohort :planner --effort max` would silently apply `max`
   to all 17, overwriting the binding tier distinction that made xhigh
   meaningful. Expressing the 4-member group as its own cohort
   (`:planner-binding`) makes the tier distinction a first-class
   calibration boundary: `--cohort :planner` now targets exactly the 13
   non-binding planners, and `--cohort :planner-binding` targets exactly
   the 4 binding planners. The distinction is preserved as a structural
   cohort, not an intra-cohort carve-out.
