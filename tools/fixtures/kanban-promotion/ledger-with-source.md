# Business rules — kanban-promotion fixture (carries the Source join token; must PASS)

This fixture ledger backs smoke Check 99 (M050/S07): the eval
`planning-answer-promotion` join greps the byte-stable `Source: pq-<id>` token
for every answered planning question. This file carries the token for
`pq-001`, so the join must PASS.

## Draft rules from planning answers (review)

### BR-001 — Archived records stay visible to admins only
- **domain:** software
- **statement:** Archived records stay visible to admins only.
- **scenarios:**
  - Given an archived record, When a non-admin lists records, Then the archived record is not shown.
  - Given an archived record, When an admin lists records, Then the archived record is shown with an archived marker.
- **status:** DRAFT
- **source:** Source: pq-001 — planning answer, 2026-06-12
- **links:** implements:[] · relates:[] · decided-by:[]
- **last-reviewed:** -
