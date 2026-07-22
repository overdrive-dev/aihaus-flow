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
3. Identify affected callers, tests, and an owned-file scope.
4. Establish a failing or absent acceptance check.
5. Implement the smallest coherent slice and run verification.
6. Run independent adversarial review for consequential changes.
7. Promote only durable rules, decisions, and reusable knowledge.

Quick path: for a covered, low-risk, mechanical edit, keep the same evidence
rules but skip formal planning artifacts. Auth, payments, destructive actions,
schema migrations, secrets, and production work never qualify as quick.
