import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { validateEvidenceDocument } from "../../pkg/.aihaus/tools/evidence-validate.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");

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

test("names the missing source on execution evidence", () => {
  const result = validateEvidenceDocument(document([{ rung: "ran", command: "node --test", exit_code: 0 }]));
  assert.equal(result.ok, false);
  assert.match(result.errors.join("\n"), /source "tool" or "ci"/);
});

test("the evidence contract example passes the validator", async () => {
  const contract = await readFile(path.join(root, "pkg", ".aihaus", "contracts", "evidence.md"), "utf8");
  const example = contract.match(/```json\r?\n([\s\S]*?)```/);
  assert.ok(example, "evidence.md must contain a json example");
  assert.deepEqual(validateEvidenceDocument(JSON.parse(example[1])), { ok: true, errors: [] });
});

test("CLI accepts a UTF-8 BOM", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "aihaus-evidence-bom-"));
  try {
    const file = path.join(temp, "evidence.json");
    const passing = document([{ rung: "ran", source: "tool", command: "node --test", exit_code: 0 }]);
    await writeFile(file, `\uFEFF${JSON.stringify(passing)}`, "utf8");
    const tool = path.join(root, "pkg", ".aihaus", "tools", "evidence-validate.mjs");
    const result = spawnSync(process.execPath, [tool, file], { encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.equal(JSON.parse(result.stdout).ok, true);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
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

test("non-executable PASS requires supporting evidence", () => {
  for (const evidence of [[], [{ rung: "blocked", detail: "Reviewer unavailable" }], [{ rung: "written" }]]) {
    assert.equal(validateEvidenceDocument(document(evidence, { executable: false })).ok, false);
  }
  for (const support of [{ artifact: "review/approved.png" }, { detail: "Reviewer approved the wording." }]) {
    assert.equal(validateEvidenceDocument(document([{ rung: "written", ...support }], { executable: false })).ok, true);
  }
  const blocked = document([{ rung: "blocked", detail: "Reviewer unavailable" }], { executable: false, status: "not_satisfied" });
  blocked.verdict = "BLOCKED";
  assert.equal(validateEvidenceDocument(blocked).ok, true);
});
