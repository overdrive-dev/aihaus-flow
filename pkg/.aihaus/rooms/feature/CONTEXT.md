# Room: feature

Use for a business-visible behavior change.

## Load

- `memory/project/business-rules.md`
- relevant decisions, procedures, and project context
- `contracts/evidence.md`; add adversarial review before completion

## Path

1. State the outcome and Given/When/Then acceptance criteria.
2. Resolve only true business-rule gaps; use `tools/task.mjs question/answer`
   to retain the answer and candidate rule. Mechanics are decided locally.
   With an accepted external tracker, record questions and answers where that
   decision says.
3. Identify affected callers, tests, and an owned-file scope.
4. Establish a failing or absent acceptance check.
5. Implement the smallest coherent slice and run verification.
6. Run independent adversarial review for consequential changes.
7. Promote only durable rules, decisions, and reusable knowledge.

Quick path: for a covered, low-risk, mechanical edit, make the change without
acceptance criteria, an evidence document, status moves, or planning artifacts,
unless an accepted project rule requires a full task for every change. Run the
checks that cover the edit, then log it with one call:
`node .aihaus/tools/task.mjs log --title <what changed> --text <changed files; each command with its exit code; assumed decisions; what was skipped>`.
Report the same in the result. With an accepted external tracker, log it where
that decision says. An edit that turns out not to be covered, low-risk, and
mechanical leaves the quick path: create the task and follow the Path. Auth,
payments, destructive actions, schema migrations, secrets, and production work
never qualify as quick.
