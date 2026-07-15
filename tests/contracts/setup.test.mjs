import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, mkdir, readFile, rm, symlink, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const setup = path.join(root, "pkg", "setup.mjs");

function run(command, args, cwd, allowFailure = false) {
  const result = spawnSync(command, args, { cwd, encoding: "utf8" });
  if (result.error) throw result.error;
  if (!allowFailure && result.status !== 0) {
    throw new Error(`${command} ${args.join(" ")} failed: ${result.stderr || result.stdout}`);
  }
  return result;
}

test("canonical setup is local, idempotent, and preserves project memory", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "aihaus-setup-"));
  try {
    run("git", ["init", "-b", "main"], temp);
    await writeFile(path.join(temp, "AGENTS.md"), "# Existing project instructions\n", "utf8");
    await mkdir(path.join(temp, ".aihaus", "memory", "project"), { recursive: true });
    await writeFile(
      path.join(temp, ".aihaus", "memory", "project", "decisions.md"),
      "# Project-owned decision\n",
      "utf8",
    );

    const first = run(process.execPath, [setup, "--target", temp, "--json"], temp);
    const firstResult = JSON.parse(first.stdout);
    assert.equal(firstResult.ok, true);
    assert.equal(firstResult.scope, "repository-local");
    assert.equal(firstResult.source.version, "1.0.0");
    assert.match(firstResult.preflight.node, /^\d+\.\d+\.\d+/);
    assert.match(firstResult.preflight.git, /^git version /);
    assert.deepEqual(firstResult.created, firstResult.installed);
    assert.deepEqual(firstResult.refreshed, []);
    assert.ok(firstResult.preserved.includes("memory/project/decisions.md"));
    assert.ok(!firstResult.seeded.includes("memory/project/decisions.md"));
    assert.equal(firstResult.verification.ok, true);
    assert.ok(firstResult.verification.required.includes(".aihaus/MAP.md"));
    assert.deepEqual(firstResult.cleanup, { path: null, pending: false });
    await writeFile(path.join(temp, ".aihaus", "roles", "stale.md"), "stale\n", "utf8");
    const second = run(process.execPath, [setup, "--target", temp, "--json"], temp);
    const secondResult = JSON.parse(second.stdout);
    assert.equal(secondResult.ok, true);
    assert.deepEqual(secondResult.created, []);
    assert.deepEqual(secondResult.refreshed, secondResult.installed);
    assert.equal(secondResult.adapters["AGENTS.md"], "unchanged");
    assert.ok(secondResult.preserved.includes("memory/project/decisions.md"));

    const agents = await readFile(path.join(temp, "AGENTS.md"), "utf8");
    assert.match(agents, /Existing project instructions/);
    assert.equal(agents.match(/<!-- AIHAUS:START -->/g)?.length, 1);
    assert.equal(
      await readFile(path.join(temp, ".aihaus", "memory", "project", "decisions.md"), "utf8"),
      "# Project-owned decision\n",
    );
    await assert.rejects(readFile(path.join(temp, ".aihaus", "roles", "stale.md"), "utf8"));
    await assert.rejects(readFile(path.join(temp, ".aihaus", "agents", "planner.md"), "utf8"));
    await assert.rejects(readFile(path.join(temp, ".aihaus", "skills", "aih-init", "SKILL.md"), "utf8"));
    assert.match(
      await readFile(path.join(temp, ".aihaus", "contracts", "harness.md"), "utf8"),
      /# Contract: harness/,
    );
    assert.match(await readFile(path.join(temp, ".gitignore"), "utf8"), /^\/\.aihaus-download\/$/m);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});

test("canonical setup refuses a non-root target", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "aihaus-setup-root-"));
  try {
    run("git", ["init", "-b", "main"], temp);
    const child = path.join(temp, "child");
    await mkdir(child);
    const result = run(process.execPath, [setup, "--target", child], temp, true);
    assert.equal(result.status, 2);
    assert.match(result.stderr, /target must be the repository root/);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});

test("canonical setup rejects a managed junction that escapes the repository", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "aihaus-setup-escape-"));
  const outside = await mkdtemp(path.join(os.tmpdir(), "aihaus-setup-outside-"));
  try {
    run("git", ["init", "-b", "main"], temp);
    await mkdir(path.join(temp, ".aihaus"), { recursive: true });
    await writeFile(path.join(outside, "sentinel.txt"), "keep\n", "utf8");
    await symlink(outside, path.join(temp, ".aihaus", "tools"), "junction");
    const result = run(process.execPath, [setup, "--target", temp], temp, true);
    assert.equal(result.status, 2);
    assert.match(result.stderr, /outside allowed root/);
    assert.equal(await readFile(path.join(outside, "sentinel.txt"), "utf8"), "keep\n");
  } finally {
    await rm(temp, { recursive: true, force: true });
    await rm(outside, { recursive: true, force: true });
  }
});
