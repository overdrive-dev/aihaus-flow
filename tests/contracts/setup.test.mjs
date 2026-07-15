import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { link, mkdtemp, mkdir, readFile, rm, symlink, writeFile } from "node:fs/promises";
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
    assert.equal(firstResult.mode, "apply");
    assert.equal(firstResult.forced, false);
    assert.equal(firstResult.changesRequired, true);
    assert.equal(firstResult.source.version, "1.2.0");
    assert.match(firstResult.preflight.node, /^\d+\.\d+\.\d+/);
    assert.match(firstResult.preflight.git, /^git version /);
    assert.deepEqual(firstResult.created, firstResult.installed);
    assert.deepEqual(firstResult.refreshed, []);
    assert.deepEqual(firstResult.unchanged, []);
    assert.ok(firstResult.preserved.includes("memory/project/decisions.md"));
    assert.ok(!firstResult.seeded.includes("memory/project/decisions.md"));
    assert.equal(firstResult.verification.ok, true);
    assert.ok(firstResult.verification.required.includes(".aihaus/MAP.md"));
    assert.ok(firstResult.verification.required.includes(".aihaus/INIT.md"));
    assert.ok(
      firstResult.verification.required.includes(".aihaus/contracts/project-bootstrap.md"),
    );
    assert.ok(firstResult.verification.required.includes(".aihaus/tools/init.mjs"));
    assert.deepEqual(firstResult.cleanup, { path: null, pending: false });
    assert.equal(
      firstResult.bootstrap.command,
      "node .aihaus/tools/init.mjs --repo . --json",
    );
    assert.equal(firstResult.bootstrap.instruction, ".aihaus/INIT.md");
    assert.deepEqual(firstResult.conflicts, []);
    assert.deepEqual(firstResult.hostCapabilities.claudeCode, {
      adapter: ".claude/skills/aih-init/SKILL.md",
      status: "created",
      available: true,
      invoke: "/aih-init",
      menu: "/",
      restartMayBeRequired: true,
    });
    assert.deepEqual(firstResult.hostCapabilities.codex, {
      adapter: ".agents/skills/aih-init/SKILL.md",
      status: "created",
      available: true,
      invoke: "$aih-init",
      menu: "/skills",
      customSlash: false,
      restartMayBeRequired: true,
    });
    assert.equal(
      firstResult.hostCapabilities.universal.invoke,
      "node .aihaus/tools/init.mjs --repo . --json",
    );
    const second = run(process.execPath, [setup, "--target", temp, "--json"], temp);
    const secondResult = JSON.parse(second.stdout);
    assert.equal(secondResult.ok, true);
    assert.equal(secondResult.changesRequired, false);
    assert.deepEqual(secondResult.created, []);
    assert.deepEqual(secondResult.refreshed, []);
    assert.deepEqual(secondResult.seeded, []);
    assert.deepEqual(secondResult.unchanged, secondResult.installed);
    assert.equal(secondResult.adapters["AGENTS.md"], "unchanged");
    assert.equal(secondResult.hostCapabilities.claudeCode.status, "unchanged");
    assert.equal(secondResult.hostCapabilities.codex.status, "unchanged");

    await writeFile(
      path.join(temp, ".claude", "skills", "aih-init", "SKILL.md"),
      await readFile(path.join(temp, ".claude", "skills", "aih-init", "SKILL.md"), "utf8") +
        "\npackage-owned drift\n",
      "utf8",
    );
    await writeFile(path.join(temp, ".aihaus", "roles", "stale.md"), "stale\n", "utf8");
    const repaired = JSON.parse(
      run(process.execPath, [setup, "--target", temp, "--json"], temp).stdout,
    );
    assert.equal(repaired.ok, true);
    assert.equal(repaired.changesRequired, true);
    assert.deepEqual(repaired.created, []);
    assert.deepEqual(repaired.refreshed, [".aihaus/roles/"]);
    assert.ok(repaired.unchanged.includes(".aihaus/MAP.md"));
    assert.equal(repaired.adapters["AGENTS.md"], "unchanged");
    assert.equal(repaired.hostCapabilities.claudeCode.status, "refreshed");
    assert.equal(repaired.hostCapabilities.codex.status, "unchanged");
    assert.ok(repaired.preserved.includes("memory/project/decisions.md"));

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

test("canonical setup supports read-only check and explicit force modes", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "aihaus-setup-check-"));
  try {
    run("git", ["init", "-b", "main"], temp);

    const preview = JSON.parse(
      run(process.execPath, [setup, "--target", temp, "--check", "--json"], temp).stdout,
    );
    assert.equal(preview.mode, "check");
    assert.equal(preview.forced, false);
    assert.equal(preview.changesRequired, true);
    assert.deepEqual(preview.created, []);
    assert.deepEqual(preview.refreshed, []);
    assert.deepEqual(preview.seeded, []);
    assert.deepEqual(preview.wouldCreate, preview.installed);
    assert.ok(preview.wouldSeed.includes("memory/project/project.md"));
    assert.equal(preview.adapters["AGENTS.md"], "would-create");
    assert.equal(preview.hostCapabilities.claudeCode.status, "would-create");
    assert.equal(preview.hostCapabilities.claudeCode.available, false);
    assert.equal(preview.verification.ok, false);
    await assert.rejects(readFile(path.join(temp, ".aihaus", "MAP.md"), "utf8"));
    await assert.rejects(readFile(path.join(temp, "AGENTS.md"), "utf8"));
    await assert.rejects(readFile(path.join(temp, "CLAUDE.md"), "utf8"));
    await assert.rejects(readFile(path.join(temp, ".gitignore"), "utf8"));
    await assert.rejects(readFile(path.join(temp, ".claude", "skills", "aih-init", "SKILL.md"), "utf8"));
    await assert.rejects(readFile(path.join(temp, ".agents", "skills", "aih-init", "SKILL.md"), "utf8"));

    const incompatible = run(
      process.execPath,
      [setup, "--target", temp, "--check", "--force", "--json"],
      temp,
      true,
    );
    assert.equal(incompatible.status, 2);
    assert.match(incompatible.stderr, /--check and --force cannot be combined/);

    const installed = JSON.parse(
      run(process.execPath, [setup, "--target", temp, "--json"], temp).stdout,
    );
    const projectMemory = path.join(temp, ".aihaus", "memory", "project", "project.md");
    await writeFile(projectMemory, "# User-owned project memory\n", "utf8");
    const cleanCheck = JSON.parse(
      run(process.execPath, [setup, "--target", temp, "--check", "--json"], temp).stdout,
    );
    assert.equal(cleanCheck.changesRequired, false);
    assert.deepEqual(cleanCheck.wouldCreate, []);
    assert.deepEqual(cleanCheck.wouldRefresh, []);
    assert.deepEqual(cleanCheck.wouldSeed, []);
    assert.deepEqual(cleanCheck.unchanged, cleanCheck.installed);

    const mapPath = path.join(temp, ".aihaus", "MAP.md");
    const claudeSkill = path.join(temp, ".claude", "skills", "aih-init", "SKILL.md");
    await writeFile(mapPath, "# Local package drift\n", "utf8");
    await writeFile(claudeSkill, `${await readFile(claudeSkill, "utf8")}\npackage drift\n`, "utf8");

    const driftCheck = JSON.parse(
      run(process.execPath, [setup, "--target", temp, "--check", "--json"], temp).stdout,
    );
    assert.equal(driftCheck.changesRequired, true);
    assert.deepEqual(driftCheck.wouldRefresh, [".aihaus/MAP.md"]);
    assert.equal(driftCheck.hostCapabilities.claudeCode.status, "would-refresh");
    assert.equal(await readFile(mapPath, "utf8"), "# Local package drift\n");
    assert.match(await readFile(claudeSkill, "utf8"), /package drift/);

    const forced = JSON.parse(
      run(process.execPath, [setup, "--target", temp, "--force", "--json"], temp).stdout,
    );
    assert.equal(forced.mode, "apply");
    assert.equal(forced.forced, true);
    assert.equal(forced.changesRequired, true);
    assert.deepEqual(forced.created, []);
    assert.deepEqual(forced.refreshed, forced.installed);
    assert.deepEqual(forced.unchanged, []);
    assert.equal(forced.hostCapabilities.claudeCode.status, "refreshed");
    assert.equal(forced.hostCapabilities.codex.status, "refreshed");
    assert.equal(await readFile(mapPath, "utf8"), await readFile(path.join(root, "pkg", ".aihaus", "MAP.md"), "utf8"));
    assert.deepEqual(forced.seeded, []);
    assert.equal(forced.preserved.length, 10);
    assert.ok(forced.preserved.includes("memory/project/project.md"));
    assert.equal(await readFile(projectMemory, "utf8"), "# User-owned project memory\n");
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});

test("canonical setup preserves colliding user-owned host skills", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "aihaus-setup-collision-"));
  try {
    run("git", ["init", "-b", "main"], temp);
    const claudeSkill = path.join(temp, ".claude", "skills", "aih-init", "SKILL.md");
    const codexSkill = path.join(temp, ".agents", "skills", "aih-init", "SKILL.md");
    await mkdir(path.dirname(claudeSkill), { recursive: true });
    await mkdir(path.dirname(codexSkill), { recursive: true });
    await writeFile(claudeSkill, "# User-owned Claude init\n", "utf8");
    await writeFile(codexSkill, "# User-owned Codex init\n", "utf8");

    const result = JSON.parse(
      run(process.execPath, [setup, "--target", temp, "--json"], temp).stdout,
    );

    assert.equal(result.hostCapabilities.claudeCode.status, "preserved");
    assert.equal(result.hostCapabilities.codex.status, "preserved");
    assert.equal(result.hostCapabilities.claudeCode.available, false);
    assert.equal(result.hostCapabilities.codex.available, false);
    assert.deepEqual(
      result.conflicts.map((conflict) => conflict.path).sort(),
      [".agents/skills/aih-init/SKILL.md", ".claude/skills/aih-init/SKILL.md"],
    );
    assert.ok(result.warnings.some((warning) => /user-owned host skill/.test(warning)));
    assert.equal(await readFile(claudeSkill, "utf8"), "# User-owned Claude init\n");
    assert.equal(await readFile(codexSkill, "utf8"), "# User-owned Codex init\n");
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});

test("canonical setup never writes through hardlinks outside the repository", async () => {
  const lab = await mkdtemp(path.join(os.tmpdir(), "aihaus-setup-hardlink-"));
  try {
    const hostRepo = path.join(lab, "host-repo");
    await mkdir(hostRepo);
    run("git", ["init", "-b", "main"], hostRepo);
    const externalHostSkill = path.join(lab, "external-host-skill.md");
    const linkedHostSkill = path.join(hostRepo, ".claude", "skills", "aih-init", "SKILL.md");
    const markedExternal =
      "<!-- AIHAUS-MANAGED: repository-local-host-adapter-v1 -->\n# External file\n";
    await writeFile(externalHostSkill, markedExternal, "utf8");
    await mkdir(path.dirname(linkedHostSkill), { recursive: true });
    await link(externalHostSkill, linkedHostSkill);

    const hostResult = JSON.parse(
      run(process.execPath, [setup, "--target", hostRepo, "--json"], hostRepo).stdout,
    );
    assert.equal(hostResult.hostCapabilities.claudeCode.status, "preserved");
    assert.equal(hostResult.hostCapabilities.claudeCode.available, false);
    assert.match(
      hostResult.conflicts.find((conflict) => conflict.path.startsWith(".claude"))?.message ?? "",
      /hard-linked/,
    );
    assert.equal(await readFile(externalHostSkill, "utf8"), markedExternal);

    const adapterRepo = path.join(lab, "adapter-repo");
    await mkdir(adapterRepo);
    run("git", ["init", "-b", "main"], adapterRepo);
    const externalAdapter = path.join(lab, "external-agents.md");
    await writeFile(externalAdapter, "# External instructions\n", "utf8");
    await link(externalAdapter, path.join(adapterRepo, "AGENTS.md"));

    const adapterResult = run(
      process.execPath,
      [setup, "--target", adapterRepo, "--json"],
      adapterRepo,
      true,
    );
    assert.equal(adapterResult.status, 2);
    assert.match(adapterResult.stderr, /refusing hard-linked managed block file/);
    assert.equal(await readFile(externalAdapter, "utf8"), "# External instructions\n");

    const packageRepo = path.join(lab, "package-repo");
    await mkdir(path.join(packageRepo, ".aihaus"), { recursive: true });
    run("git", ["init", "-b", "main"], packageRepo);
    const externalPackageFile = path.join(lab, "external-map.md");
    await writeFile(externalPackageFile, "# External package file\n", "utf8");
    await link(externalPackageFile, path.join(packageRepo, ".aihaus", "MAP.md"));

    const packageResult = run(
      process.execPath,
      [setup, "--target", packageRepo, "--json"],
      packageRepo,
      true,
    );
    assert.equal(packageResult.status, 2);
    assert.match(packageResult.stderr, /refusing hard-linked managed file/);
    assert.equal(await readFile(externalPackageFile, "utf8"), "# External package file\n");
  } finally {
    await rm(lab, { recursive: true, force: true });
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

test("canonical setup rejects a dangling host-skill symlink", { skip: process.platform === "win32" }, async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "aihaus-setup-dangling-"));
  const outside = await mkdtemp(path.join(os.tmpdir(), "aihaus-setup-dangling-outside-"));
  try {
    run("git", ["init", "-b", "main"], temp);
    const destination = path.join(temp, ".claude", "skills", "aih-init", "SKILL.md");
    const outsideTarget = path.join(outside, "created-through-symlink.md");
    await mkdir(path.dirname(destination), { recursive: true });
    await symlink(outsideTarget, destination, "file");

    const result = run(process.execPath, [setup, "--target", temp], temp, true);

    assert.equal(result.status, 2);
    assert.match(result.stderr, /cannot safely resolve existing path entry/);
    await assert.rejects(readFile(outsideTarget, "utf8"));
  } finally {
    await rm(temp, { recursive: true, force: true });
    await rm(outside, { recursive: true, force: true });
  }
});
