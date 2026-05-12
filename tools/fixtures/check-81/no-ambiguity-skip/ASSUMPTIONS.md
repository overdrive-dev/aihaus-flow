# ASSUMPTIONS.md — fixture for Check 81 no-ambiguity-skip case
#
# All parameters are explicitly confirmed. Zero ambiguity markers present.
# Check 81 must evaluate this plan as ALLOW (zero-ambiguity legitimate skip).
#
# Expected: ambiguity count = 0 -> allow

## Assumptions

- Retry count: 3 attempts (confirmed by stakeholder on 2026-05-01)
- Timeout threshold: 30 seconds (confirmed)
- Pagination size: 20 rows per page (confirmed)
- Rollback strategy: blue-green with 5-minute drain (confirmed)
- Cache TTL: 300 seconds (confirmed with infrastructure team)
