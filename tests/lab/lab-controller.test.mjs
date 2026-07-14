import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const controller = path.join(root, "tools", "aihaus-lab.mjs");

function run(args, labRoot) {
  return spawnSync(process.execPath, [controller, ...args], {
    cwd: root,
    encoding: "utf8",
    env: { ...process.env, AIHAUS_LAB_ROOT: labRoot },
  });
}

test("initializes, verifies, and safely resets a nested consumer repo", async () => {
  const labRoot = await mkdtemp(path.join(os.tmpdir(), "aihaus-lab-test-"));
  const consumer = path.join(labRoot, "consumer");
  try {
    const initialized = run(["init", "--json"], labRoot);
    assert.equal(initialized.status, 0, initialized.stderr);
    assert.equal(JSON.parse(initialized.stdout).initialized, true);

    const verified = run(["verify", "--json"], labRoot);
    assert.equal(verified.status, 0, verified.stderr);
    assert.equal(JSON.parse(verified.stdout).exit_code, 0);

    const source = path.join(consumer, "src", "counter.mjs");
    await writeFile(source, "export const increment = () => 99;\n");
    const reset = run(["reset", "--json"], labRoot);
    assert.equal(reset.status, 0, reset.stderr);
    assert.match(await readFile(source, "utf8"), /return value \+ 1/);
    assert.equal(JSON.parse(reset.stdout).clean, true);
  } finally {
    await rm(labRoot, { recursive: true, force: true });
  }
});
