# Calibration-gate — Step 7.5 Contract for aih-milestone --plan (M027/S5)

Binding contract for `/aih-milestone --plan <slug>` Step 7.5, anchored AFTER
plan-checker emits CHECK.md during the plan-promotion pipeline
(`annexes/promotion.md` Steps P1–P5).

**Scope-fence (ADR-260509-W):** same distinction as aih-plan and aih-feature
calibration-gates — plan-calibrator is plan-time, conversation-grounded.
DISTINCT from assumptions-analyzer (brainstorm-phase, codebase-grounded) and
contrarian (brainstorm pre-plan).

---

## M024 short-circuit interaction

When the 3-way M024 short-circuit gate fires at Step E3
(`annexes/execution.md`) — i.e., (a) OQ-resolved + (b) architecture-coverage +
(d) story-table pass AND the on-disk CHECK.md SHA proves plan-checker ran —
calibration is **also skipped by default** (consistent with the analyst/PM/architect
pipeline skip on short-circuit).

To force calibration even on a short-circuit run, pass `--calibrate` explicitly.
This is the inverse of the default: the milestone short-circuit path assumes
the plan was pre-calibrated via the /aih-plan or /aih-brainstorm pipeline.

---

## Trigger conditions

Calibration fires when ALL of the following hold:
1. `--no-calibrate` flag is NOT present in `$ARGUMENTS`.
2. The M024 3-way short-circuit did NOT fire (or `--calibrate` was passed explicitly).
3. A plan-checker pass ran and CHECK.md exists at `.aihaus/milestones/[slug]/execution/CHECK.md`
   (or at `.aihaus/plans/[slug]/CHECK.md` if promotion ran via `/aih-plan` first).
4. At least one of: (a) CONTEXT.md / PRD contains `default`, `TBD`, or `TODO` markers;
   (b) analyst-brief has Low-confidence assumptions; (c) CHECK.md has RECOMMENDATION
   or NIT findings traceable to user-confirmable rules.

---

## `--no-calibrate` override

If `$ARGUMENTS` contains `--no-calibrate`:

```bash
bash .aihaus/hooks/manifest-append.sh \
  --audit calibration-skip \
  --reason "user-override --no-calibrate flag (aih-milestone)"
```

Skip calibration. Proceed to next Step.

---

## Spawn contract

When calibration fires, spawn `plan-calibrator` with `subagent_type: "plan-calibrator"`.
Include in the spawn prompt:

```
MANIFEST_PATH="<abs>/.aihaus/milestones/<slug>/execution/RUN-MANIFEST.md"
Calibration target: /aih-milestone --plan slug=<slug>
Analyst-brief path: .aihaus/milestones/<slug>/execution/analyst-brief.md (if present)
PRD path: .aihaus/milestones/<slug>/execution/PRD.md
Architecture path: .aihaus/milestones/<slug>/execution/architecture.md (if present)
CHECK.md path: .aihaus/milestones/<slug>/execution/CHECK.md
CHECK.md SHA: <git log -1 --format=%H -- .aihaus/milestones/<slug>/execution/CHECK.md>
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

**NEVER auto-stop heuristic.**

---

## Output contract (ADR-001 single-writer preserved)

Calibrator returns a `BUSINESS-RULES-PAYLOAD-START...BUSINESS-RULES-PAYLOAD-END` block.
Parent skill (`/aih-milestone`) is the SOLE writer:

1. Write `.aihaus/milestones/<slug>/execution/BUSINESS-RULES.md` verbatim from payload.
2. Apply PRD patches via `Edit` (one patch at a time; cite file + line per patch
   in the RUN-MANIFEST progress log).
3. Append to RUN-MANIFEST progress log:
   ```
   Calibration-gate: BUSINESS-RULES.md written. Turns: <N>. Stop: <reason>.
   ```

Calibrator has NO Write and NO Edit tools — it returns payload only.

---

## `--from-brainstorm` deduplication

When `/aih-milestone` was invoked with `--from-brainstorm <slug>`, pass the
brainstorm slug to the calibrator. The calibrator reads
`.aihaus/brainstorm/<slug>/SUBSTRATE-FINDINGS.md` before turn 1 (non-fatal if
absent) and dedupes its ambiguity set against already-surfaced findings.

---

## Relation to enforcement-audit

This annex adds 7 Step 7.5 rows to `pkg/.aihaus/skills/_shared/enforcement-audit.md`:
M024-short-circuit-interaction, trigger-detection, no-calibrate-skip, spawn-contract,
stop-conditions, output-contract, and deduplication-scope-fence. See rows with label
prefix `milestone-calibration-`.
