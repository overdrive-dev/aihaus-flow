# Business rules — kanban-promotion fixture (join token deliberately absent; must FAIL)

Fixture-FAIL pair for smoke Check 99 (M050/S07, BR-P8 non-vacuity): this
ledger describes the same rule but omits the byte-stable join token for
`pq-001` on the source line. The eval `planning-answer-promotion` join MUST
report FAIL against an answered `pq-001` — if it passes, the join is
green-but-vacuous.

## Draft rules from planning answers (review)

### BR-001 — Archived records stay visible to admins only
- **domain:** software
- **statement:** Archived records stay visible to admins only.
- **scenarios:**
  - Given an archived record, When a non-admin lists records, Then the archived record is not shown.
- **status:** DRAFT
- **source:** planning answer (join token deliberately absent — fixture-fail pair)
- **links:** implements:[] · relates:[] · decided-by:[]
- **last-reviewed:** -
