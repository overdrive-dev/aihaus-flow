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
