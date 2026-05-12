# ASSUMPTIONS.md — fixture for Check 81 drift-detected case
#
# Contains ambiguity markers so Check 81 detects drift:
#   - TBD marker (Check 78 regex match)
#   - assumed qualifier (Check 78 regex match)
#
# Expected: ambiguity count >= 1 -> drift detected

## Assumptions

- Retry count: TBD (not yet confirmed by stakeholder)
- Timeout threshold is assumed to be 30 seconds
- Pagination size: TODO confirm with product owner
- Rollback strategy: pending confirmation from engineering lead
