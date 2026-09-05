# Contract: evidence

Completion claims use `aihaus.evidence.v1` and are validated by
`tools/evidence-validate.mjs`.

Each acceptance criterion records:

- `criterion`: stable human-readable requirement;
- `status`: `satisfied`, `partial`, or `not_satisfied`;
- `executable`: whether a command can prove it;
- `evidence`: one or more rungs.

Rungs are `written`, `ran`, `verified`, or `blocked`. A passing executable
criterion requires a `ran` or `verified` rung produced by a tool or CI, with a
non-empty command and integer `exit_code: 0`. Self-reported execution is only
`written`, even when it uses stronger language.

A PASS document cannot contain partial/not-satisfied criteria. Missing tooling
must be reported as degraded or blocked, never silently counted as passing.

Every criterion needs at least one evidence entry. A non-executable PASS needs
support that is not `blocked`, with a non-empty `artifact` reference or `detail`
describing the actual review. For example:
`{ "rung": "written", "artifact": "review/approved.png" }`.
Validators check the document contract; source labels and exit codes are not
cryptographic proof. The verifier must inspect artifacts and rerun checks.

## Completing a file task

Use checked, unique `- [x] criterion text` items in `## Acceptance`. In
`## Evidence`, include `Artifact: evidence/task-result.json`, relative to the
Git root. The JSON must use `aihaus.evidence.v1`, pass the validator, declare
`PASS`, and cover exactly those criterion texts without extras or duplicates.
Resolve questions and draft-rule gaps before moving to `done`.

`review` may contain blocked or failed results for discussion; `done` cannot.
An existing task must acquire valid evidence before its next move to `done`;
the tool does not rewrite historical task files automatically.
