import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { isAllowed } from "../../pkg/.aihaus/tools/scope-check.mjs";
import { assertPathWithin } from "../../pkg/.aihaus/tools/path-safety.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const scopeCheck = path.join(root, "pkg", ".aihaus", "tools", "scope-check.mjs");

function run(command, args, cwd) {
  const result = spawnSync(command, args, { cwd, encoding: "utf8" });
  if (result.error) throw result.error;
  assert.equal(result.status, 0, result.stderr || result.stdout);
  return result;
}

test("scope check accepts exact files and directory descendants", () => {
  assert.equal(isAllowed("src/auth/token.mjs", ["src/auth/"]), true);
  assert.equal(isAllowed("README.md", ["README.md"]), true);
  assert.equal(isAllowed("src/authz/token.mjs", ["src/auth/"]), false);
});

test("scope check normalizes separators without widening a rule", () => {
  assert.equal(isAllowed("src\\auth\\token.mjs", ["src/auth"]), true);
  assert.equal(isAllowed("other/auth/token.mjs", ["src/auth"]), false);
});

test("scope check preserves Unicode paths reported by Git", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "aihaus-scope-"));
  try {
    run("git", ["init", "-b", "main"], temp);
    const file = "documentação.md";
    await writeFile(path.join(temp, file), "ok\n", "utf8");
    const result = JSON.parse(run(process.execPath, [scopeCheck, "--allow", file, "--json"], temp).stdout);
    assert.deepEqual(result.changed, [file]);
    assert.deepEqual(result.outside, []);
  } finally {
    await assertPathWithin({ root: os.tmpdir(), candidate: temp });
    await rm(temp, { recursive: true, force: true });
  }
});

test("scope check reports deleted tracked files", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "aihaus-scope-delete-"));
  try {
    run("git", ["init", "-b", "main"], temp);
    const deleted = path.join(temp, "retired.mjs");
    await writeFile(deleted, "legacy\n", "utf8");
    run("git", ["add", "retired.mjs"], temp);
    await rm(deleted);
    const result = spawnSync(process.execPath, [scopeCheck, "--allow", "kept.mjs", "--json"], {
      cwd: temp,
      encoding: "utf8",
    });
    assert.equal(result.status, 2, result.stderr || result.stdout);
    const report = JSON.parse(result.stdout);
    assert.deepEqual(report.changed, ["retired.mjs"]);
    assert.deepEqual(report.outside, ["retired.mjs"]);
  } finally {
    await assertPathWithin({ root: os.tmpdir(), candidate: temp });
    await rm(temp, { recursive: true, force: true });
  }
});

for (const change of ["rename", "type"]) {
  test(`scope check includes the outside path of a ${change}`, async () => {
    const temp = await mkdtemp(path.join(os.tmpdir(), "aihaus-scope-change-"));
    try {
      run("git", ["init", "-b", "main"], temp);
      run("git", ["config", "core.symlinks", "false"], temp);
      await writeFile(path.join(temp, "outside.mjs"), "original\n", "utf8");
      run("git", ["add", "."], temp);
      run("git", ["-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-m", "fixture"], temp);
      if (change === "rename") {
        await mkdir(path.join(temp, "allowed"));
        run("git", ["mv", "outside.mjs", "allowed/moved.mjs"], temp);
      } else {
        const hash = run("git", ["rev-parse", "HEAD:outside.mjs"], temp).stdout.trim();
        run("git", ["update-index", "--cacheinfo", `120000,${hash},outside.mjs`], temp);
        run("git", ["checkout", "--", "outside.mjs"], temp);
        assert.match(run("git", ["diff", "--cached", "--name-status"], temp).stdout, /^T\s+outside\.mjs/m);
      }
      const result = spawnSync(process.execPath, [scopeCheck, "--allow", "allowed", "--json"], { cwd: temp, encoding: "utf8" });
      assert.equal(result.status, 2, result.stderr || result.stdout);
      assert.deepEqual(JSON.parse(result.stdout).outside, ["outside.mjs"]);
      const accepted = JSON.parse(run(process.execPath, [scopeCheck, "--allow", "allowed", "--allow", "outside.mjs", "--json"], temp).stdout);
      assert.equal(accepted.ok, true);
    } finally {
      await assertPathWithin({ root: os.tmpdir(), candidate: temp });
      await rm(temp, { recursive: true, force: true });
    }
  });
}
