import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const packageRoot = path.join(root, "pkg", ".aihaus");

async function lines(file) {
  return (await readFile(file, "utf8")).split(/\r?\n/).length;
}

test("root adapters stay thin", async () => {
  assert.ok(await lines(path.join(root, "AGENTS.md")) <= 50);
  assert.ok(await lines(path.join(root, "CLAUDE.md")) <= 50);
  assert.ok(await lines(path.join(packageRoot, "MAP.md")) <= 50);
});

test("portable core starts with six roles and three rooms", async () => {
  const roles = (await readdir(path.join(packageRoot, "roles"))).sort();
  assert.deepEqual(roles, [
    "implementer.md",
    "orchestrator.md",
    "planner.md",
    "researcher.md",
    "reviewer.md",
    "verifier.md",
  ]);

  const rooms = (await readdir(path.join(packageRoot, "rooms"))).sort();
  assert.deepEqual(rooms, ["bugfix", "feature", "research"]);
});

test("portable contracts and durable project memory are present", async () => {
  const contracts = (await readdir(path.join(packageRoot, "contracts"))).sort();
  assert.deepEqual(contracts, [
    "adversarial-review.md",
    "evidence.md",
    "harness.md",
    "ops-safety.md",
  ]);

  const memory = (await readdir(path.join(packageRoot, "memory", "project"))).sort();
  assert.deepEqual(memory, [
    "README.md",
    "business-rules.md",
    "decisions.md",
    "deployment.md",
    "environment.md",
    "glossary.md",
    "knowledge.md",
    "procedures.md",
    "project.md",
  ]);
});

test("legacy orchestration surfaces are absent from the canonical package", async () => {
  for (const directory of [
    "agents",
    "skills",
    "hooks",
    "protocols",
    "templates",
    "output-styles",
    "eval",
  ]) {
    try {
      const entries = await readdir(path.join(packageRoot, directory), {
        recursive: true,
        withFileTypes: true,
      });
      assert.deepEqual(entries.filter((entry) => entry.isFile()), [], directory);
    } catch (error) {
      assert.equal(error.code, "ENOENT", directory);
    }
  }
});
