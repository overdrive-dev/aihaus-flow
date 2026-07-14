import assert from "node:assert/strict";
import test from "node:test";
import { validateEvidenceDocument } from "../../pkg/.aihaus/tools/evidence-validate.mjs";

function document(evidence, overrides = {}) {
  return {
    schema: "aihaus.evidence.v1",
    verdict: "PASS",
    acceptance: [{
      criterion: "contract tests pass",
      status: "satisfied",
      executable: true,
      evidence,
      ...overrides,
    }],
  };
}

test("accepts trusted command evidence", () => {
  const result = validateEvidenceDocument(document([{
    rung: "ran",
    source: "tool",
    command: "node --test",
    exit_code: 0,
  }]));
  assert.equal(result.ok, true);
});

test("rejects self-reported or forged execution", () => {
  const result = validateEvidenceDocument(document([{
    rung: "verified",
    source: "self",
    command: "node --test",
    exit_code: 0,
  }]));
  assert.equal(result.ok, false);
  assert.match(result.errors.join("\n"), /lacks trusted/);
});

test("rejects non-zero execution and partial PASS criteria", () => {
  const failed = validateEvidenceDocument(document([{
    rung: "ran",
    source: "ci",
    command: "node --test",
    exit_code: 1,
  }]));
  assert.equal(failed.ok, false);

  const partial = validateEvidenceDocument(document([], { status: "partial" }));
  assert.equal(partial.ok, false);
  assert.match(partial.errors.join("\n"), /must be satisfied/);
});
