# Project memory

These Markdown files are the durable, reviewable source of truth. Fill only
what the project actually knows; empty headings are not facts. Generated search
state belongs under `.aihaus/state/` and may be deleted at any time.

- `project.md`: purpose, users, boundaries, Definition of Done
- `business-rules.md`: business-visible behavior in Given/When/Then form
- `decisions.md`: accepted technical/product decisions and consequences
- `knowledge.md`: durable verified facts and recurring gotchas
- `environment.md`: local/CI/staging/production topology without secrets
- `procedures.md`: repeatable operational and delivery procedures
- `deployment.md`: release, rollback, evidence, and approval expectations
- `glossary.md`: domain terms and meanings

## Retrieval and authority

Start with the active task's domain, rule/decision IDs, and owned file paths.
Search those terms in the relevant pages, read the whole matching entry, then
inspect its cited source. Read `project.md` when purpose or scope is unclear;
load environment or deployment detail only when the task needs it. Do not
preload all eight pages or mistake an index match for a reviewed fact.

Use accepted, current rules and decisions for implementation. Keep draft,
proposed, inferred, superseded, and unresolved entries visibly distinct.
Repository instructions retain their original directory and host scope;
summarizing a nested rule here does not make it a global rule.

Keep each claim with its own provenance, for example:

    - Verified: invoices round once at the total. Source: `src/invoice.mjs` (reviewed <commit>).
    - Verified: checkout draft uses cents. Source: `src/checkout.mjs` (worktree; sha256: <discovery hash>).

Use an actual commit or hash from discovery, not the example placeholders.
Retain owner/date provenance for explicit decisions made in conversation and
record the decision in a reviewable project file. Reverify uncited or ambiguous
entries before use. `refresh --status` reports structural readiness and known
changes; it cannot certify correctness or approval of prose.

When a claim changes, preserve the historical/manual text, mark the old claim
superseded or unresolved as appropriate, and add the reviewed replacement.
Keep source and commit/hash on the same claim; a new review of one claim does
not revalidate the rest of the page. Task logs and host-local automatic memory
are not substitutes for these canonical project files.
