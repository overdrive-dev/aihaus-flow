# Decisions Fixture — Token Rejected (M025/S03/Check 76 fixture-fail #2)

Synthesized decisions.md WITH an ADR mentioning all three gate tokens
(denylist-extension, haiku-classifier, whitelist-on-cadence) but with
`Status: Rejected`. Check 76 must NOT pass — proving the check correctly
distinguishes "tokens present in body" from "decision was Accepted".

This fixture is the "considered X and rejected it" failure mode — exactly
what plan-checker F-HIGH-6 identified as the loose-keyword false-positive
risk.

DO NOT change the Status to Accepted on this fixture.

---

## ADR-FIXTURE-M027-CANDIDATE — Synthesized rejected proposal

**Date:** 2026-06-01
**Status:** Rejected

### Context

This synthesized ADR considered three M027 architectural decision options:
denylist-extension (extend the LSDD pack iteratively), haiku-classifier
(replace regex denylist with haiku classifier), and whitelist-on-cadence
(invert the model — allow only whitelisted cadence prose).

### Decision

After analysis, the maintainer REJECTED all three approaches in favor of
deferring the architectural decision indefinitely. This is the "considered
X and rejected it" prose form that the loose token-presence gate would
incorrectly pass.

Check 76's semantic gate requires `Status: Accepted` — this fixture has
`Status: Rejected` — the gate must therefore fail.

### References

- ADR-260508-A I4 (M025 mechanical forcing function)
- Plan-checker F-HIGH-6 (semantic-gate Status: Accepted requirement)

---
