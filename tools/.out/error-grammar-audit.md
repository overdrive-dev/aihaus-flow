# Error-Grammar Audit — `autonomy-guard.sh`

**Story:** S3 — M027-260508-skills-agents-perf-review  
**Generated:** 2026-05-08  
**Analyst:** implementer (agent)  
**Source files:**
- `.claude/audit/autonomy-gate.jsonl` (4185 rows; 1431 `regex-match` decisions in 30d window)
- `pkg/.aihaus/hooks/autonomy-guard.sh` (591 lines; 40 active patterns: M005×11 + GSP-DS×13 + LSDD×16)
- `tools/.out/audit-mining-patterns.md` (S1 telemetry baseline)

---

## 1. Verified Gap

Inspection of `autonomy-gate.jsonl` `regex-match` rows confirms the following field inventory per row:

| Field | Present? | Example value |
|-------|----------|---------------|
| `matched_pattern` | YES | `"[Cc]heckpoint honesto"` |
| `section` | YES | `"L52-63:no-honest-checkpoints"` |
| `haiku_reason` | YES (for haiku decisions; null for regex-match) | `null` |
| `message_head` | YES (M019+ rows only) | `"Checkpoint honesto: Wave 1 completa..."` |
| **rephrase_suggestion** | **NO** | **field does not exist** |
| **natural_language_rule_name** | **NO** | **field does not exist** |
| **user_facing_explanation** | **NO** | **field does not exist** |

Gap confirmed: the JSONL schema captures which machine-readable pattern fired and what section it maps to, but provides no human-facing guidance on how to rephrase the blocked text. The TUI block message (`emit_block`) reads:

```
Autonomy violation: pattern '<ERE regex>' matches autonomy-protocol.md <section-id>.
Pick the safer default per TRUE blocker test (L15-31) and proceed silently.
Log the choice in RUN-MANIFEST progress log instead of asking the user.
```

This message is directed **at the AI agent** (instructing it to pick a safer default), not at the human developer reading the TUI. A user reviewing the TUI block sees a raw ERE regex string — e.g. `[Pp]ausing (to|here|for)` — and a section code — e.g. `L52-63:no-honest-checkpoints` — without any indication of what prose triggered it, which behavioral anti-pattern it represents, or what to write instead.

---

## 2. Stratified Sample (5 rows)

Rows are drawn from actual `autonomy-gate.jsonl` entries. Three rows cover top-6 M005 patterns; one row covers a GSP-DS pattern (note: GSP-DS has **0 actual hits** in the 30d telemetry — the sample row is drawn from the M025 smoke-test fixture `tools/.out/gsp-ds-test-*` that confirmed pattern registration); one row covers an LSDD pattern. The LSDD row is drawn from actual production telemetry (4 LSDD hits confirmed by S1).

> **Note on GSP-DS:** The 30-day telemetry (S1) records **0 GSP-DS hits** in `autonomy-gate.jsonl`. No production row exists for any of the 13 GSP-DS patterns. The GSP-DS sample below uses the pattern's registered form and the `message_head` value from the smoke-test fixture (`gsp-ds-test-*`) that validated pattern correctness at M023 merge. This is the only honest approach given the telemetry gap; the rubric score is based on what a user **would** see if the pattern fired, not on a fabricated JSONL row.

---

### Row S-1 — Pattern: `retoma depois com /aih-` (M005, rank 1, 286 hits)

**JSONL row (from production, 2026-05-08T23:26:22Z):**
```json
{
  "ts": "2026-05-08T23:26:22Z",
  "decision": "regex-match",
  "matched_pattern": "retoma depois com /aih-",
  "section": "L65-72:no-delegated-typing",
  "haiku_reason": null,
  "message_head": "Commit final pushed. Você retoma depois com /aih-resume [slug] quando quiser.",
  "exec_phase": "1",
  "manifest_status": null
}
```

**TUI block message seen by user:**
```
Autonomy violation: pattern 'retoma depois com /aih-' matches
autonomy-protocol.md L65-72:no-delegated-typing. Pick the safer
default per TRUE blocker test (L15-31) and proceed silently.
Log the choice in RUN-MANIFEST progress log instead of asking the user.
```

**User perspective simulation:**
- The user sees a literal ERE string `retoma depois com /aih-` — they must mentally recognize this as a match for the phrase "retoma depois com /aih-resume" in the assistant's output.
- The section code `L65-72:no-delegated-typing` requires the user to know that line numbers refer to `_shared/autonomy-protocol.md` (not the guard script itself) and that `no-delegated-typing` is the rule slug.
- No hint is given that the blocked anti-pattern is "telling the user to type a skill command manually" — i.e., delegating keyboard work the skill should dispatch itself.
- The correction instruction ("pick the safer default... proceed silently") is addressed to the AI, not the human.

**3-axis rubric:**

| Axis | Score | Reasoning |
|------|-------|-----------|
| (a) Can user identify WHICH pattern matched? | **M** | `message_head` visible in M019+ rows shows the triggering text snippet; `matched_pattern` is a literal ERE string that a Portuguese-speaking developer can roughly parse, but requires regex literacy to decode `retoma depois com /aih-` as a phrase match rather than a capture group |
| (b) Can user understand WHY it matched? | **L** | Section code `L65-72:no-delegated-typing` is a line-range:slug identifier — meaningless without opening `autonomy-protocol.md` at those specific lines. The block message offers no prose explanation of the `no-delegated-typing` rule. The TUI instruction ("Pick the safer default...") is agent-addressed. |
| (c) Does user know HOW to rephrase? | **L** | Zero rephrase guidance. No suggestion that the fix is to dispatch the skill directly instead of printing a "type X" instruction. The block message does not distinguish "the AI did something wrong" from "you, the developer, wrote a forbidden phrase in a skill definition". |

---

### Row S-2 — Pattern: `[Cc]heckpoint honesto` (M005, rank 2, 286 hits)

**JSONL row (from production, 2026-05-08T23:26:52Z):**
```json
{
  "ts": "2026-05-08T23:26:52Z",
  "decision": "regex-match",
  "matched_pattern": "[Cc]heckpoint honesto",
  "section": "L52-63:no-honest-checkpoints",
  "haiku_reason": null,
  "message_head": "Checkpoint honesto: Wave 1 completa. Stop aqui pra alinhar escopo de Wave 2.",
  "exec_phase": "1",
  "manifest_status": null
}
```

**TUI block message seen by user:**
```
Autonomy violation: pattern '[Cc]heckpoint honesto' matches
autonomy-protocol.md L52-63:no-honest-checkpoints. Pick the safer
default per TRUE blocker test (L15-31) and proceed silently.
Log the choice in RUN-MANIFEST progress log instead of asking the user.
```

**User perspective simulation:**
- `[Cc]heckpoint honesto` is a case-insensitive regex that a user can decode as "checkpoint honesto" — fairly transparent compared to patterns with quantifiers.
- `L52-63:no-honest-checkpoints` — again requires navigating to specific lines in `autonomy-protocol.md`.
- `message_head` shows the triggering text ("Checkpoint honesto: Wave 1 completa...") which is visible in M019+ rows; this helps with axis (a). Early rows (before M019) lack `message_head` entirely.
- No explanation that "Wave 1 completa. Stop aqui..." is the anti-pattern, not just "checkpoint honesto" as a phrase.
- The rule violation is "spontaneous scope checkpoint mid-execution" — none of this is communicated.

**3-axis rubric:**

| Axis | Score | Reasoning |
|------|-------|-----------|
| (a) Can user identify WHICH pattern matched? | **H** | `[Cc]heckpoint honesto` is human-readable; the phrase is recognizable as Portuguese "honest checkpoint". `message_head` (M019+ rows) confirms the triggering snippet. |
| (b) Can user understand WHY it matched? | **L** | Section slug `no-honest-checkpoints` is semi-legible but provides no rule explanation. The user cannot distinguish "this pattern catches a disguised scope-pause" from "any use of the phrase 'checkpoint honesto' in any context". The block message's agent-instruction ("pick the safer default") adds nothing for human understanding. |
| (c) Does user know HOW to rephrase? | **L** | No guidance. The correct fix (either: remove the checkpoint entirely and proceed; or use `phase-advance --to paused` if a TRUE blocker exists) is not mentioned. The `autonomy-protocol.md §No honest checkpoints` section lists 5 verbatim anti-patterns to avoid but this is only accessible by reading the file at line 52-63. |

---

### Row S-3 — Pattern: `[Oo]pção sua` (M005, rank 4, 285 hits)

**JSONL row (from production, 2026-05-08T23:28:01Z):**
```json
{
  "ts": "2026-05-08T23:28:01Z",
  "decision": "regex-match",
  "matched_pattern": "[Oo]pção sua",
  "section": "L32-50:no-option-menus",
  "haiku_reason": null,
  "message_head": "Opção sua:",
  "exec_phase": "1",
  "manifest_status": null
}
```

**TUI block message seen by user:**
```
Autonomy violation: pattern '[Oo]pção sua' matches
autonomy-protocol.md L32-50:no-option-menus. Pick the safer
default per TRUE blocker test (L15-31) and proceed silently.
Log the choice in RUN-MANIFEST progress log instead of asking the user.
```

**User perspective simulation:**
- Pattern `[Oo]pção sua` is readable ("opção sua" = "your choice"). The ERE syntax here is minimal.
- `message_head: "Opção sua:"` — extremely short; no context about what options were being presented.
- Section `L32-50:no-option-menus` — the slug `no-option-menus` is the most legible of any section slug in the 40 patterns.
- However: the user still cannot tell from the block message that "opção sua" is flagged as a user-directed decision-menu — the phrase could legitimately appear in many contexts.
- Rule violation ("emitting a lettered/numbered option menu mid-execution") not stated.

**3-axis rubric:**

| Axis | Score | Reasoning |
|------|-------|-----------|
| (a) Can user identify WHICH pattern matched? | **H** | `[Oo]pção sua` is a literal phrase; `message_head: "Opção sua:"` confirms the trigger unambiguously. |
| (b) Can user understand WHY it matched? | **M** | `no-option-menus` slug is human-parseable as "no option menus rule". A developer with passing familiarity with the autonomy protocol can infer the rule. But the section line-range (L32-50) still requires consulting the file; the block message gives no in-line prose. |
| (c) Does user know HOW to rephrase? | **L** | No rephrase guidance. The fix (pick one option, log the choice in RUN-MANIFEST, proceed silently) is exactly what the block message says — but it's addressed to the AI agent, not as rephrase advice. A developer maintaining a skill template would not know whether "opção sua" is always forbidden or only in certain contexts. |

---

### Row S-4 — Pattern: `[Pp]rogress: [0-9]+/[0-9]+ done` (LSDD, 1 hit in 30d window)

**JSONL row (from production, 2026-05-07T15:51:51Z):**
```json
{
  "ts": "2026-05-07T15:51:51Z",
  "decision": "regex-match",
  "matched_pattern": "[Pp]rogress: [0-9]+/[0-9]+ done",
  "section": "LSDD-fraction-progress",
  "haiku_reason": null,
  "message_head": "Total M002 progress: 23/30 done",
  "exec_phase": "1",
  "manifest_status": null
}
```

**TUI block message seen by user:**
```
Autonomy violation: pattern '[Pp]rogress: [0-9]+/[0-9]+ done' matches
autonomy-protocol.md LSDD-fraction-progress. Pick the safer
default per TRUE blocker test (L15-31) and proceed silently.
Log the choice in RUN-MANIFEST progress log instead of asking the user.
```

**User perspective simulation:**
- Pattern `[Pp]rogress: [0-9]+/[0-9]+ done` contains numeric quantifiers — user must read regex syntax to understand "matches any 'Progress: N/M done' phrase".
- Section `LSDD-fraction-progress` — `LSDD` is an internal milestone-era acronym (introduced M025). A user unfamiliar with M025 history has no idea what "LSDD" means. The slug `fraction-progress` hints at "fraction-style progress reporting" but provides no behavioral context.
- `message_head: "Total M002 progress: 23/30 done"` — this is rich context, but it's an M019+ field absent in early rows.
- No indication that the rule concerns "task-fraction status reporting as a decomposition seam" (i.e., saying "23/30 done" signals a cadence-checkpoint that pauses flow rather than proceeding).
- The LSDD acronym is never expanded anywhere in the block message, JSONL schema, or autonomy-protocol.md visible sections.

**3-axis rubric:**

| Axis | Score | Reasoning |
|------|-------|-----------|
| (a) Can user identify WHICH pattern matched? | **M** | The ERE `[Pp]rogress: [0-9]+/[0-9]+ done` is parseable with basic regex literacy. `message_head` ("Total M002 progress: 23/30 done") makes the trigger obvious in M019+ rows. However, `[0-9]+` notation may confuse non-regex users. |
| (b) Can user understand WHY it matched? | **L** | `LSDD-fraction-progress` is opaque without M025 context. "LSDD" is never defined in any user-visible surface. The user cannot determine whether "progress: 23/30 done" is always forbidden or only when it signals a pause intent. The actual rule (task-fraction reporting as cadence-noun stop signal) is nowhere stated. |
| (c) Does user know HOW to rephrase? | **L** | No guidance. The fix would be to drop the fraction-style progress summary and instead write a flat one-liner status update (e.g., "S23 complete, proceeding to S24") — but none of this is communicated. |

---

### Row S-5 — Pattern: `[Hh]onest[oa] sobre (escopo|qualidade)` (GSP-DS, 0 production hits; smoke-test fixture row)

**Constructed JSONL row (from smoke-test fixture `gsp-ds-test-*`; pattern registration confirmed by `audit-mining-patterns.md` footnote):**
```json
{
  "ts": "(smoke-test fixture — no production hit in 30d window)",
  "decision": "regex-match",
  "matched_pattern": "[Hh]onest[oa] sobre (escopo|qualidade)",
  "section": "GSP-DS-honest-scope",
  "haiku_reason": null,
  "message_head": "Sendo honesto sobre escopo: isso vai além do S3 original.",
  "exec_phase": "1",
  "manifest_status": "running"
}
```

> **Transparency note:** This row is constructed from the smoke-test fixture, not sampled from `autonomy-gate.jsonl`, because GSP-DS has **zero production hits** in the 30-day window (S1 confirmed). The rubric below scores what a user WOULD experience if the pattern fired.

**TUI block message seen by user:**
```
Autonomy violation: pattern '[Hh]onest[oa] sobre (escopo|qualidade)' matches
autonomy-protocol.md GSP-DS-honest-scope. Pick the safer
default per TRUE blocker test (L15-31) and proceed silently.
Log the choice in RUN-MANIFEST progress log instead of asking the user.
```

**User perspective simulation:**
- Pattern `[Hh]onest[oa] sobre (escopo|qualidade)` — an alternation group with morphological variants. A Portuguese speaker with basic regex literacy can parse "honesta/honesto sobre escopo/qualidade."
- Section `GSP-DS-honest-scope` — `GSP-DS` is an acronym defined in ADR-260506-A (M023) as "Graceful Self-Pause at Decomposition Seam." Neither the expansion nor the concept is present in any user-visible block message.
- The section slug `honest-scope` is semi-legible but does not explain that the rule targets "self-elected scope-reduction framed as epistemic virtue" — a subtle behavioral pattern, not a simple phrase prohibition.
- Even a sophisticated user reading the TUI cannot deduce from `GSP-DS-honest-scope` whether their use of "honesto sobre escopo" in (e.g.) a skill description template would trigger this pattern, or only in agent execution output.

**3-axis rubric:**

| Axis | Score | Reasoning |
|------|-------|-----------|
| (a) Can user identify WHICH pattern matched? | **M** | Regex is parseable by a Portuguese-literate developer. No `message_head` available (pre-M019 row format used in fixture). Without the triggering snippet, identification relies entirely on regex decoding. |
| (b) Can user understand WHY it matched? | **L** | `GSP-DS-honest-scope` requires knowing that GSP-DS = "Graceful Self-Pause at Decomposition Seam" (ADR-260506-A) and that `honest-scope` targets epistemic-virtue framing of scope reduction. Neither is explained in the block message. This is the most opaque section namespace in the 40-pattern set. |
| (c) Does user know HOW to rephrase? | **L** | No rephrase guidance. The correct fix is to remove scope-reduction framing and proceed silently (or use `phase-advance --to paused` for a TRUE blocker). This is entirely unrecoverable from the TUI block message alone. |

---

## 3. Axis Score Aggregation

| Row | Pattern family | Axis (a) identify | Axis (b) understand why | Axis (c) how to rephrase |
|-----|---------------|-------------------|------------------------|--------------------------|
| S-1 | M005 `retoma depois com /aih-` | M | L | L |
| S-2 | M005 `[Cc]heckpoint honesto` | H | L | L |
| S-3 | M005 `[Oo]pção sua` | H | M | L |
| S-4 | LSDD `[Pp]rogress: [0-9]+/[0-9]+ done` | M | L | L |
| S-5 | GSP-DS `[Hh]onest[oa] sobre (escopo|qualidade)` | M | L | L |
| **Distribution** | — | 0×L / 3×M / 2×H | 4×L / 1×M / 0×H | 5×L / 0×M / 0×H |

---

## 4. Verdict

**Verdict: OPAQUE**

Applying the verdict-translation rubric from CHECK Finding #15:
- Any axis L → opaque
- All axes M with ≥1 H → partial
- All H → clear

Axis (c) "how to rephrase" scores L for all 5 samples — **opaque** verdict is mandatory regardless of (a)/(b) scores.

Supporting evidence:
- Axis (b) "understand why" is L for 4 of 5 samples. Even the single M score (S-3, `[Oo]pção sua`) relies on the legibility of the `no-option-menus` slug — not on any in-line explanation.
- The TUI block message is **agent-addressed** ("Pick the safer default... Log the choice..."), not user-addressed. A developer reading the TUI is receiving instructions intended for the AI, not guidance for the human.
- The `section` field namespace has three distinct prefix styles: `L<NN>-<NN>:<slug>` (M005), `GSP-DS-<slug>` (M023), `LSDD-<family>-<slug>` (M025). Each requires knowledge of a different milestone-era acronym to decode.
- 4185 rows in the JSONL; **0 rows** contain a `rephrase_suggestion` field. The gap is structural, not an omission in specific rows.

---

## 5. Rephrase-Suggestion Field Shape Proposal (for S7 ADR scope)

Since the verdict is opaque, the following field shape is proposed for addition to the `autonomy-gate.jsonl` schema in the S7 ADR (ADR-260509-X):

**Proposed new field: `rephrase_suggestion`**

This field is emitted only on `decision: regex-match` rows (the only decision type where the block is driven by a specific pattern match and a specific section rule). It is a pre-computed, human-readable string keyed statically to the `section` value at guard-script compile time — not generated dynamically per message (which would require an additional LLM call and latency).

Each section slug maps to one canonical rephrase suggestion:

```
section                          → rephrase_suggestion
-----------------------------------------------------------
L65-72:no-delegated-typing       → "Dispatch the next skill directly via the Skill tool. Do not print 'type /aih-...' instructions for the user."
L52-63:no-honest-checkpoints     → "Remove the checkpoint prose and proceed. If a TRUE blocker exists, use: bash .aihaus/hooks/phase-advance.sh --to paused --reason '<reason>'."
L32-50:no-option-menus           → "Pick one option, log the choice as a one-liner in RUN-MANIFEST progress log, and continue silently."
L52-63:no-reality-renegotiation  → "Continue executing. Log the time estimate correction in RUN-MANIFEST. Let the user interrupt via ESC if needed."
GSP-DS-*                         → "Remove scope-reduction or quality-preserve framing. Proceed silently. If a TRUE blocker applies, use phase-advance --to paused."
LSDD-*                           → "Remove cadence-noun progress summary. Use a flat one-liner status update (e.g., 'S3 complete, proceeding to S4') instead."
```

**Implementation shape in JSONL:**
```json
{
  "rephrase_suggestion": "Pick one option, log the choice as a one-liner in RUN-MANIFEST progress log, and continue silently."
}
```

**Wire-up in `autonomy-guard.sh`:** A static lookup table (bash associative array or case-statement keyed on `$GATE_SECTION`) emits the appropriate string into `GATE_REPHRASE_SUGGESTION` before `log_gate_decision`. No new LLM call required; latency impact is <1 ms. The field is `null` for all non-`regex-match` decision types (haiku-block, outside-exec-skip, etc.) to preserve backward-compatible JSONL schema extension.

**Consumer surfaces:**
1. TUI block message (`emit_block` function): append rephrase_suggestion as a second sentence so the message becomes both agent-instruction and human-guidance simultaneously.
2. `tools/audit-mining.sh` per-pattern report: surface the canonical rephrase alongside each hit-count row for maintainer context.
3. Future S7 two-tier dispatch: the `haiku_reason` field from haiku-block decisions currently provides free-text reasoning; `rephrase_suggestion` adds deterministic structured guidance for the regex-match path that bypasses haiku entirely.

This proposal is scoped to S7 ADR consumption. Implementation is one change in `autonomy-guard.sh` (lookup table + `log_gate_decision` field addition) + one change in `emit_block` (append the suggestion to the TUI message). Backward-compatible: prior rows simply lack the field; schema version bump not required if the field is treated as optional.

---

## 6. Summary

| Dimension | Finding |
|-----------|---------|
| JSONL schema gap | `rephrase_suggestion` field absent from all 4185 rows |
| TUI message gap | `emit_block` output is agent-addressed, not user-addressed |
| Axis (a) score distribution | 0×L / 3×M / 2×H (partial identifiability) |
| Axis (b) score distribution | 4×L / 1×M / 0×H (predominantly opaque on why) |
| Axis (c) score distribution | 5×L / 0×M / 0×H (fully opaque on how to fix) |
| **Verdict** | **OPAQUE** — axis (c) is universally L |
| GSP-DS telemetry note | 0 production hits in 30d; audit row constructed from smoke-test fixture |
| S7 ADR scope handoff | Rephrase-suggestion field shape proposed (static lookup, no new LLM call, <1 ms overhead) |
