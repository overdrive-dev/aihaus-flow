# ASSUMPTIONS.md — fixture for Check 81 drift-bypassed-by-no-calibrate case
#
# Contains ambiguity markers (same as drift-detected), but Check 81 MUST allow
# because a calibration-skip audit row is present in the companion hook.jsonl.
#
# Expected: ambiguity count >= 1 BUT audit skip row exists -> allow

## Assumptions

- Retry count: TBD (not yet confirmed by stakeholder)
- Timeout threshold is assumed to be 30 seconds
- Pagination size: TODO confirm with product owner
- Rollback strategy: pending confirmation from engineering lead
