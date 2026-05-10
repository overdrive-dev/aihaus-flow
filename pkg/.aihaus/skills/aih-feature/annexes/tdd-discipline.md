# TDD Discipline — Step 7.6 Contract (M028/S3)

Binding contract for `/aih-feature` Step 7.6, anchored AFTER plan-checker + calibration-gate
(Phase 2 → Step 7.6, sequential after Step 7.5 calibration-gate per M027/S5 precedent).

**Scope-fence:** This step governs test-first discipline for user application code only.
aihaus's own bash hooks/scripts are integration-tested via smoke-test — NOT bats unit tests
(Decision G, ADR-260510-D). Do not apply TDD prescription to aihaus internal files.

---

## Trigger

Step 7.6 fires when BOTH of the following hold:

1. `project.md` `testing_discipline` field equals `tdd` (checked via `AIHAUS_TESTING_DISCIPLINE`
   env var — cached from session start by parent skill; no per-invocation file re-read).
2. `--no-tdd` flag is NOT present in `$ARGUMENTS`.

If either condition is absent, Step 7.6 is a no-op — proceed to Step 8 silently.

---

## Step 7.6 — TDD discipline conditional dispatch

**Reading `AIHAUS_TESTING_DISCIPLINE`:** The parent skill reads `project.md` at Step 1 (Load
Context). If `## Practices` section is present and contains `testing_discipline: tdd`, set
`AIHAUS_TESTING_DISCIPLINE=tdd` in the session environment before any agent spawns. This
avoids per-invocation file re-reads by downstream agents (R4 caching per ADR-260510-C).

**Dispatch logic:**

```
if AIHAUS_TESTING_DISCIPLINE == "tdd" AND "--no-tdd" not in $ARGUMENTS:
  → prepend the following instruction to every implementer/frontend-dev spawn briefing
    in Phase 2 Step 7:
    "Draft a failing test that captures the expected behavior BEFORE writing the
     implementation. Commit the failing test first, then implement to make it pass."
  → verify implementer/frontend-dev wrote test files before implementation files
    (check file modification timestamps in merge-back artifacts; warn only — do not block)
else if AIHAUS_TESTING_DISCIPLINE == "test-after":
  → no-op at Step 7.6; test discipline is handled by Step 8 (verify) + Step 10.5 (review)
else (none or unset):
  → no-op; proceed to Step 8
```

**Agent briefing injection point:** The prepend instruction goes at the START of the
implementer/frontend-dev spawn prompt, before MANIFEST_PATH injection and task description.
Label it `[TDD-ACTIVE]` so code-reviewer can confirm test-first order in Step 9.

---

## --no-tdd opt-out

If `$ARGUMENTS` contains `--no-tdd`:

```bash
bash .aihaus/hooks/manifest-append.sh \
  --audit tdd-skip \
  --reason "user-override --no-tdd flag"
```

Skip Step 7.6 entirely. Proceed to Step 8. The `tdd-guard.sh` PreToolUse hook is also
suppressed for this invocation via `AIHAUS_TDD_GUARD=0` env (set alongside `--no-tdd` flag
processing; mirrors `--no-calibrate` opt-out contract in `calibration-gate.md`).

---

## Composition

Step 7.6 runs AFTER Step 7.5 (calibration-gate) completes. Sequence:

1. Step 7 — Implement (agent spawn, parallel where independent)
2. Step 7.5 — Calibration-gate (plan-calibrator, if triggered)
3. **Step 7.6 — TDD discipline (this annex)**
4. Step 8 — Verify

If calibration-gate was skipped (via `--no-calibrate` or plan-checker absent), Step 7.6 still
runs independently — the two flags are orthogonal opt-outs.

---

## Relation to enforcement-audit

This annex adds 4 Step 7.6 rows to `pkg/.aihaus/skills/_shared/enforcement-audit.md`:
trigger-detection, no-tdd skip, dispatch injection, and composition-sequence. See
enforcement-audit.md rows with label prefix `feature-tdd-`.
