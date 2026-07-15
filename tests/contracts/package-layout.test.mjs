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
    "project-bootstrap.md",
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

  assert.match(
    await readFile(path.join(packageRoot, "INIT.md"), "utf8"),
    /provider-neutral initialization routine/i,
  );
  assert.match(
    await readFile(path.join(packageRoot, "tools", "init.mjs"), "utf8"),
    /aihaus\.bootstrap\.discovery\.v1/,
  );
});

test("repository-local host adapters expose only the supported init workflow", async () => {
  const claude = await readFile(
    path.join(root, "pkg", "adapters", "claude", "skills", "aih-init", "SKILL.md"),
    "utf8",
  );
  const codex = await readFile(
    path.join(root, "pkg", "adapters", "codex", "skills", "aih-init", "SKILL.md"),
    "utf8",
  );

  for (const adapter of [claude, codex]) {
    assert.match(adapter, /name: aih-init/);
    assert.match(adapter, /AIHAUS-MANAGED: repository-local-host-adapter-v1/);
    assert.match(adapter, /\.aihaus\/INIT\.md/);
    assert.match(adapter, /project-bootstrap\.md/);
    assert.doesNotMatch(adapter, /allowed-tools|hooks:|!`/);
  }
  assert.match(claude, /disable-model-invocation: true/);
  assert.ok(claude.split(/\r?\n/).length <= 40);
  assert.ok(codex.split(/\r?\n/).length <= 40);
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

test("agent install guide distinguishes repository adapters from global installation", async () => {
  const guide = await readFile(path.join(root, "INSTALL-VIA-LLM.md"), "utf8");
  assert.match(guide, /not a global Codex skill/i);
  assert.match(guide, /npm exec/);
  assert.match(guide, /aihaus setup/);
  assert.match(guide, /--check/);
  assert.match(guide, /--force/);
  assert.match(guide, /changesRequired/);
  assert.match(guide, /github-release/);
  assert.match(guide, /source\.pinned/);
  assert.match(guide, /package-owned/i);
  assert.ok(guide.includes("node .aihaus/tools/init.mjs --repo . --json"));
  assert.ok(guide.includes(".aihaus/contracts/project-bootstrap.md"));
  assert.ok(guide.includes(".claude/skills/aih-init/SKILL.md"));
  assert.ok(guide.includes(".agents/skills/aih-init/SKILL.md"));
  assert.ok(guide.includes("Do not use /aih-env"));
});

test("customer README leads with GitHub Release setup and keeps cloning as fallback", async () => {
  const readme = await readFile(path.join(root, "README.md"), "utf8");
  const releaseStart = readme.indexOf("## Set up from a GitHub Release");
  const sourceStart = readme.indexOf("## Install from source");
  assert.ok(releaseStart > 0);
  assert.ok(sourceStart > releaseStart);
  const primary = readme.slice(releaseStart, sourceStart);
  assert.match(primary, /npm exec/);
  assert.match(primary, /aihaus setup/);
  assert.match(primary, /--check/);
  assert.match(primary, /--force/);
  assert.doesNotMatch(primary, /git clone|rm -rf|Remove-Item/);
  assert.ok(primary.includes(".aihaus/tools/init.mjs"));
});
