import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdir, mkdtemp, readdir, rm, symlink, unlink, writeFile } from "node:fs/promises";
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

test("tool CLIs show bounded help before parsing or touching a repository", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "aihaus-cli-help-"));
  try {
    for (const [tool, anchors] of [
      ["scope-check.mjs", ["--allow", "--base", "--json"]],
      ["task.mjs", ["create", "move", "question", "answer", "list", "--title", "--room", "--external-id", "--text", "--question", "--draft-rule", "--json"]],
      ["evidence-validate.mjs", ["<evidence.json>"]],
      ["online-action-gate.mjs", ["--command", "--repo", "--json"]],
    ]) {
      const script = path.join(path.dirname(scopeCheck), tool);
      const result = run(process.execPath, [script, "--help"], temp);
      const help = result.stdout;
      assert.equal(result.stderr, "", tool);
      assert.match(help, /usage:/i, tool);
      assert.ok(help.length <= 600, tool);
      for (const anchor of [...anchors, "--help", "-h"]) assert.ok(help.includes(anchor), `${tool}: ${anchor}`);
      const shortHelp = run(process.execPath, [script, "-h"], temp);
      assert.equal(shortHelp.stdout, help, tool);
      assert.equal(shortHelp.stderr, "", tool);
    }
    assert.deepEqual(await readdir(temp), []);
  } finally {
    await assertPathWithin({ root: os.tmpdir(), candidate: temp });
    await rm(temp, { recursive: true, force: true });
  }
});

for (const [tool, prefixes, fields] of [
  ["scope-check.mjs", [["--allow", "a"], ["--allow"]], (help) => ({ ok: false, error: `unknown option: ${help}` })],
  ["task.mjs", [["create"], ["move", "X", "done"], ["create", "--title"]], (help) => ({ ok: false, error: `unknown option: ${help}` })],
  ["evidence-validate.mjs", [["arquivo.json"]], (help) => ({ ok: false, errors: [`unknown option: ${help}`] })],
  ["online-action-gate.mjs", [["--command", "git push origin main"], ["--command"]], (help) => ({ allowed: false, reason: `unknown argument: ${help}` })],
]) {
  test(`${tool} rejects help mixed with other arguments before execution`, async () => {
    const temp = await mkdtemp(path.join(os.tmpdir(), "aihaus-cli-mixed-help-"));
    try {
      const script = path.join(path.dirname(scopeCheck), tool);
      const usage = run(process.execPath, [script, "--help"], temp).stdout.trimEnd();
      for (const help of ["--help", "-h"]) {
        for (const args of [
          ...prefixes.map((prefix) => [...prefix, help]),
          [help, help], [help, "--bogus"], ["--bogus", help], ["bogus", help, "--bogus"], ["create", "--title", help],
        ]) {
          const result = spawnSync(process.execPath, [script, ...args], { cwd: temp, encoding: "utf8" });
          assert.equal(result.status, 2, `${tool}: ${args.join(" ")}`);
          assert.equal(result.stdout, "", tool);
          assert.deepEqual(JSON.parse(result.stderr), { ...fields(help), usage });
        }
      }
      assert.deepEqual(await readdir(temp), []);
    } finally {
      await assertPathWithin({ root: os.tmpdir(), candidate: temp });
      await rm(temp, { recursive: true, force: true });
    }
  });
}

test("tool CLI argument errors keep JSON on stderr and include the same usage", () => {
  for (const [tool, args, fields] of [
    ["scope-check.mjs", ["--repo", "."], { ok: false, error: "unknown option: --repo" }],
    ["scope-check.mjs", ["unexpected"], { ok: false, error: "unknown option: unexpected" }],
    ["task.mjs", ["bogus"], { ok: false, error: "unknown command: bogus" }],
    ["task.mjs", ["list", "--bogus"], { ok: false, error: "unknown option: --bogus" }],
    ["task.mjs", ["list", "unexpected"], { ok: false, error: "unknown argument: unexpected" }],
    ["evidence-validate.mjs", [], { ok: false, errors: ["evidence file is required"] }],
    ["evidence-validate.mjs", ["--bogus"], { ok: false, errors: ["unknown option: --bogus"] }],
    ["evidence-validate.mjs", ["missing.json", "extra"], { ok: false, errors: ["unknown argument: extra"] }],
    ["online-action-gate.mjs", ["--bogus"], { allowed: false, reason: "unknown argument: --bogus" }],
    ["online-action-gate.mjs", ["--command", "git status", "extra"], { allowed: false, reason: "unknown argument: extra" }],
  ]) {
    const script = path.join(path.dirname(scopeCheck), tool);
    const help = run(process.execPath, [script, "--help"], root).stdout.trimEnd();
    const result = spawnSync(process.execPath, [script, ...args], { cwd: root, encoding: "utf8" });
    assert.equal(result.status, 2, tool);
    assert.equal(result.stdout, "", tool);
    assert.deepEqual(JSON.parse(result.stderr), { ...fields, usage: help }, `${tool}: ${args.join(" ")}`);
  }
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

test("scope check compares committed work with --base", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "aihaus-scope-base-"));
  const commit = (message) => {
    run("git", ["add", "."], temp);
    run("git", ["-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-m", message], temp);
  };
  try {
    run("git", ["init", "-b", "main"], temp);
    await writeFile(path.join(temp, "seed.md"), "seed\n", "utf8");
    commit("base");
    const base = run("git", ["rev-parse", "HEAD"], temp).stdout.trim();
    await mkdir(path.join(temp, "allowed"));
    await writeFile(path.join(temp, "allowed", "inside.md"), "ok\n", "utf8");
    commit("inside");
    const args = [scopeCheck, "--allow", "allowed", "--base", base, "--json"];
    const accepted = JSON.parse(run(process.execPath, args, temp).stdout);
    assert.deepEqual(accepted.changed, ["allowed/inside.md"]);
    assert.equal(accepted.ok, true);

    await writeFile(path.join(temp, "outside.md"), "drift\n", "utf8");
    commit("outside");
    const rejected = spawnSync(process.execPath, args, { cwd: temp, encoding: "utf8" });
    assert.equal(rejected.status, 2, rejected.stderr || rejected.stdout);
    assert.deepEqual(JSON.parse(rejected.stdout).outside, ["outside.md"]);

    for (const bad of ["no-such-ref", "--output=x"]) {
      const invalid = spawnSync(process.execPath, [scopeCheck, "--allow", "allowed", "--base", bad], { cwd: temp, encoding: "utf8" });
      assert.equal(invalid.status, 2, invalid.stdout);
      assert.equal(JSON.parse(invalid.stderr).ok, false);
    }
  } finally {
    await assertPathWithin({ root: os.tmpdir(), candidate: temp });
    await rm(temp, { recursive: true, force: true });
  }
});

test("tool CLIs run when invoked through a linked directory", async (context) => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "aihaus-entry-link-"));
  const link = path.join(temp, "tools");
  try {
    try {
      await symlink(path.dirname(scopeCheck), link, process.platform === "win32" ? "junction" : "dir");
    } catch (error) {
      context.skip(`symlink creation unavailable: ${error.code}`);
      return;
    }
    try {
      for (const tool of ["evidence-validate.mjs", "scope-check.mjs", "online-action-gate.mjs"]) {
        const result = spawnSync(process.execPath, [path.join(link, tool)], { cwd: temp, encoding: "utf8" });
        assert.equal(result.status, 2, `${tool}: ${result.stderr || result.stdout}`);
        assert.notEqual(`${result.stdout}${result.stderr}`.trim(), "", tool);
      }
    } finally {
      await unlink(link);
    }
  } finally {
    await assertPathWithin({ root: os.tmpdir(), candidate: temp });
    await rm(temp, { recursive: true, force: true });
  }
});
