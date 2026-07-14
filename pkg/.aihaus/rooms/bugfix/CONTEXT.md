# Room: bugfix

Use when observed behavior contradicts the intended contract.

## Load

- relevant rule/decision and prior gotcha context
- callers/impact retrieval for the failing path
- `contracts/evidence.md` and `contracts/adversarial-review.md`

## Path

1. Reproduce the failure or record why reproduction is impossible.
2. Identify root cause, not only the reported symptom.
3. Search for sibling entry points and the same failure class.
4. Add a regression check that fails on the pre-fix behavior.
5. Fix the narrow root cause and run affected plus broader checks.
6. Challenge completeness and classify pre-existing test debt separately.
7. Record a durable gotcha only when it will prevent recurrence.
