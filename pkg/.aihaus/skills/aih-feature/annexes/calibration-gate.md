# Calibration-gate — Step 7.5 Contract (M027/S5)

Binding contract for `/aih-feature` Step 7.5, anchored AFTER plan-checker
emits CHECK.md (Phase 2 → Step 7.5, same anchor as the plan-checker pass that
runs within any `/aih-feature --plan <slug>` flow).

**Scope-fence (ADR-260509-W):** plan-calibrator is plan-time, conversation-grounded
(reads CHECK.md inconsistencies + analyst-brief gaps + PRD defaults). It is
DISTINCT from assumptions-analyzer (brainstorm Phase 6.5, codebase-grounded) and
from contrarian (brainstorm pre-plan, idea-challenging). No double-run.

---

## Trigger conditions

Calibration fires when ALL of the following hold:
1. `--no-calibrate` flag is NOT present in `$ARGUMENTS`.
2. A plan-checker pass ran and CHECK.md exists at `.aihaus/features/[YYMMDD]-[slug]/CHECK.md`
   (or at `.aihaus/plans/[slug]/CHECK.md` if invoked via `--plan <slug>`).
3. At least one of: (a) PRD/PLAN.md contains `default`, `TBD`, `assumed`, or
   `TODO` markers; (b) analyst-brief has Low-confidence assumptions; (c) CHECK.md
   has RECOMMENDATION or NIT findings traceable to user-confirmable rules.

If plan-checker was skipped for this invocation (e.g., the `--plan` flag
short-circuited the analysis pipeline), calibration follows the same skip rule.

---

## `--no-calibrate` override

If `$ARGUMENTS` contains `--no-calibrate`:

`calibrate-guard.sh` detects the prior `calibration-skip` audit row (written directly to `.claude/audit/hook.jsonl` via the hook's direct JSONL emit — M029/ADR-260511-A) and exits 0 on subsequent invocations. No `manifest-append.sh --audit` call is needed (that path is dead-code since v0.31.0).

Skip calibration entirely. Proceed to Step 8.

---

## Spawn contract

When calibration fires, spawn `plan-calibrator` with `subagent_type: "plan-calibrator"`.
Include in the spawn prompt:

```
MANIFEST_PATH="<abs>/.aihaus/features/[YYMMDD]-[slug]/RUN-MANIFEST.md"
Calibration target: /aih-feature slug=[slug]
Analyst-brief path: .aihaus/features/[YYMMDD]-[slug]/analyst-brief.md (if present)
PLAN.md path: .aihaus/plans/[slug]/PLAN.md (or .aihaus/features/[YYMMDD]-[slug]/PLAN.md)
CHECK.md path: .aihaus/features/[YYMMDD]-[slug]/CHECK.md
CHECK.md SHA: <git log -1 --format=%H -- .aihaus/features/[YYMMDD]-[slug]/CHECK.md>
Brainstorm slug: <slug from --from-brainstorm, if present> (calibrator dedupes against SUBSTRATE-FINDINGS.md)
OQ schema reference: pkg/.aihaus/skills/_shared/oq-schema.md
```

The calibrator reads these artifacts and conducts turn-by-turn ambiguity
confirmation with the user (one ambiguity per turn; no menus; no A/B/C).

---

## Stop conditions (any one fires)

- User signal: "no more questions" / "satisfeito" / "encerrar" / "stop" / "done".
- `--no-calibrate` re-invoked mid-flow.
- Calibrator returns `BUSINESS-RULES-EXHAUSTED` terminating token.
- Hard cap 30 turns (safety guard).

**NEVER auto-stop heuristic.** Stop is driven by user reply or exhaustion.

---

## Output contract (ADR-001 single-writer preserved)

Calibrator returns a `BUSINESS-RULES-PAYLOAD-START...BUSINESS-RULES-PAYLOAD-END` block.
Parent skill (`/aih-feature`) is the SOLE writer:

1. Write `.aihaus/features/[YYMMDD]-[slug]/BUSINESS-RULES.md` verbatim from payload.
2. Apply PRD patches via `Edit` (one patch at a time; cite file + line per patch
   in the manifest progress log).
3. Append to RUN-MANIFEST progress log:
   ```
   Calibration-gate: BUSINESS-RULES.md written. Turns: <N>. Stop: <reason>.
   ```

Calibrator has NO Write and NO Edit tools — it returns payload only.

---

## `--from-brainstorm` deduplication

When `/aih-feature` was invoked with `--from-brainstorm <slug>`, pass the
brainstorm slug to the calibrator. The calibrator reads
`.aihaus/brainstorm/<slug>/SUBSTRATE-FINDINGS.md` before turn 1 (non-fatal if
absent) and dedupes its ambiguity set against already-surfaced findings.
Prevents the user from being asked the same question twice across the
brainstorm Phase 6.5 → plan post-CHECK.md boundary.

---

## Relation to enforcement-audit

This annex adds 6 Step 7.5 rows to `pkg/.aihaus/skills/_shared/enforcement-audit.md`:
trigger-detection, no-calibrate skip, spawn-contract, stop-conditions, output-contract,
and deduplication-scope-fence. See enforcement-audit.md rows with label prefix
`feature-calibration-`.
