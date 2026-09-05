import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { cp, link, mkdtemp, mkdir, readFile, readdir, readlink, rm, rmdir, symlink, writeFile } from "node:fs/promises";
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

async function projectSnapshot(directory, relative = "") {
  const entries = await readdir(directory, { withFileTypes: true });
  const snapshot = [];
  for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
    if (entry.name === ".git") continue;
    const name = path.join(relative, entry.name);
    const file = path.join(directory, entry.name);
    const content = entry.isSymbolicLink() ? `link:${await readlink(file)}` : entry.isDirectory() ? "directory" : await readFile(file, "utf8");
    snapshot.push([name, content]);
    if (entry.isDirectory()) snapshot.push(...await projectSnapshot(file, name));
  }
  return snapshot;
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
    assert.equal(firstResult.source.version, "1.4.0");
    assert.match(firstResult.preflight.node, /^\d+\.\d+\.\d+/);
    assert.match(firstResult.preflight.git, /^git version /);
    assert.deepEqual(firstResult.created, firstResult.installed);
    assert.deepEqual(firstResult.refreshed, []);
    assert.deepEqual(firstResult.unchanged, []);
    assert.ok(firstResult.preserved.includes("memory/project/decisions.md"));
    assert.ok(!firstResult.seeded.includes("memory/project/decisions.md"));
    assert.equal(firstResult.verification.ok, true);
    assert.ok(firstResult.verification.required.includes(".aihaus/MAP.md"));
    assert.ok(firstResult.verification.required.includes(".aihaus/REFRESH.md"));
    assert.ok(firstResult.verification.required.includes(".aihaus/memory/project/project.md"));
    assert.ok(
      firstResult.verification.required.includes(".aihaus/contracts/project-bootstrap.md"),
    );
    assert.ok(firstResult.verification.required.includes(".aihaus/tools/refresh.mjs"));
    assert.deepEqual(firstResult.cleanup, { path: null, pending: false });
    assert.equal(
      firstResult.bootstrap.command,
      "node .aihaus/tools/refresh.mjs --repo . --json",
    );
    assert.equal(firstResult.bootstrap.instruction, ".aihaus/REFRESH.md");
    assert.deepEqual(firstResult.conflicts, []);
    assert.deepEqual(firstResult.hostCapabilities.claudeCode, {
      adapter: ".claude/skills/aih-refresh/SKILL.md",
      status: "created",
      available: true,
      invoke: "/aih-refresh",
      menu: "/",
      restartMayBeRequired: true,
    });
    assert.deepEqual(firstResult.hostCapabilities.codex, {
      adapter: ".agents/skills/aih-refresh/SKILL.md",
      status: "created",
      available: true,
      invoke: "$aih-refresh",
      menu: "/skills",
      customSlash: false,
      restartMayBeRequired: true,
    });
    assert.equal(
      firstResult.hostCapabilities.universal.invoke,
      "node .aihaus/tools/refresh.mjs --repo . --json",
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
      path.join(temp, ".claude", "skills", "aih-refresh", "SKILL.md"),
      await readFile(path.join(temp, ".claude", "skills", "aih-refresh", "SKILL.md"), "utf8") +
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
    await assert.rejects(readFile(path.join(temp, ".aihaus", "skills", "aih-refresh", "SKILL.md"), "utf8"));
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
    await assert.rejects(readFile(path.join(temp, ".claude", "skills", "aih-refresh", "SKILL.md"), "utf8"));
    await assert.rejects(readFile(path.join(temp, ".agents", "skills", "aih-refresh", "SKILL.md"), "utf8"));

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
    const claudeSkill = path.join(temp, ".claude", "skills", "aih-refresh", "SKILL.md");
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
    const claudeSkill = path.join(temp, ".claude", "skills", "aih-refresh", "SKILL.md");
    const codexSkill = path.join(temp, ".agents", "skills", "aih-refresh", "SKILL.md");
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
      [".agents/skills/aih-refresh/SKILL.md", ".claude/skills/aih-refresh/SKILL.md"],
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
    const linkedHostSkill = path.join(hostRepo, ".claude", "skills", "aih-refresh", "SKILL.md");
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
    const destination = path.join(temp, ".claude", "skills", "aih-refresh", "SKILL.md");
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

test("canonical setup removes legacy graph artifacts and preserves Markdown", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "aihaus-setup-remove-graph-"));
  const artifacts = [
    ".aih-graph-consent",
    ".aihaus/bin/aih-graph",
    ".aihaus/bin/aih-graph.exe",
    ".aihaus/bin/aih-graph.install.json",
    ".aihaus/state/aih-graph.db",
    ".aihaus/state/aih-graph.db-shm",
    ".aihaus/state/aih-graph.db-wal",
    ".aihaus/state/aih-graph.db-journal",
  ];
  try {
    run("git", ["init", "-b", "main"], temp);
    for (const relative of artifacts) {
      const file = path.join(temp, ...relative.split("/"));
      await mkdir(path.dirname(file), { recursive: true });
      await writeFile(file, "legacy graph artifact\n", "utf8");
    }
    const graphWrapper = path.join(temp, ".aihaus", "tools", "graph.mjs");
    const task = path.join(temp, ".aihaus", "memory", "kanban", "doing", "T-keep.md");
    await mkdir(path.dirname(graphWrapper), { recursive: true });
    await mkdir(path.dirname(task), { recursive: true });
    await writeFile(graphWrapper, "legacy wrapper\n", "utf8");
    await writeFile(task, "# Keep this task\n", "utf8");

    const preview = JSON.parse(
      run(process.execPath, [setup, "--target", temp, "--check", "--json"], temp).stdout,
    );
    assert.deepEqual(preview.removed, []);
    assert.deepEqual(preview.wouldRemove, artifacts);
    assert.equal(await readFile(task, "utf8"), "# Keep this task\n");

    const result = JSON.parse(
      run(process.execPath, [setup, "--target", temp, "--json"], temp).stdout,
    );
    assert.deepEqual(result.removed, artifacts);
    assert.deepEqual(result.wouldRemove, []);
    for (const relative of artifacts) {
      await assert.rejects(readFile(path.join(temp, ...relative.split("/")), "utf8"));
    }
    await assert.rejects(readFile(graphWrapper, "utf8"));
    assert.equal(await readFile(task, "utf8"), "# Keep this task\n");
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});

test("upgrade retires INIT.md and aihaus-marked aih-init skills, preserving user-owned files", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "aihaus-setup-retire-init-"));
  const marker = "<!-- AIHAUS-MANAGED: repository-local-host-adapter-v1 -->";
  try {
    run("git", ["init", "-b", "main"], temp);
    const oldInit = path.join(temp, ".aihaus", "INIT.md");
    const oldClaudeSkill = path.join(temp, ".claude", "skills", "aih-init", "SKILL.md");
    const userCodexSkill = path.join(temp, ".agents", "skills", "aih-init", "SKILL.md");
    for (const file of [oldInit, oldClaudeSkill, userCodexSkill]) {
      await mkdir(path.dirname(file), { recursive: true });
    }
    await writeFile(oldInit, "# Initialize project memory\n", "utf8");
    await writeFile(oldClaudeSkill, `---\nname: aih-init\n---\n\n${marker}\n`, "utf8");
    await writeFile(userCodexSkill, "---\nname: aih-init\ndescription: User workflow\n---\n", "utf8");

    const result = JSON.parse(
      run(process.execPath, [setup, "--target", temp, "--json"], temp).stdout,
    );
    assert.ok(result.removed.includes(".aihaus/INIT.md"));
    assert.ok(result.removed.includes(".claude/skills/aih-init/SKILL.md"));
    assert.ok(!result.removed.includes(".agents/skills/aih-init/SKILL.md"));
    await assert.rejects(readFile(oldInit, "utf8"));
    await assert.rejects(readFile(oldClaudeSkill, "utf8"));
    assert.match(await readFile(userCodexSkill, "utf8"), /User workflow/);
    assert.match(await readFile(path.join(temp, ".aihaus", "REFRESH.md"), "utf8"), /refresh\.mjs/);
    assert.match(
      await readFile(path.join(temp, ".claude", "skills", "aih-refresh", "SKILL.md"), "utf8"),
      /name: aih-refresh/,
    );
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});

test("setup rejects duplicate and reversed markers in every root adapter", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "aihaus-setup-markers-"));
  const start = "<!-- AIHAUS:START -->";
  const end = "<!-- AIHAUS:END -->";
  const malformed = [
    `${start}\nUser rule\n${start}\nOld router\n${end}`,
    `${start}\nOld router\n${end}\nUser rule\n${end}`,
    `${end}\nUser rule\n${start}`,
    `${start}\nOld router\n${end}\n${start}\nSecond router\n${end}`,
  ];
  try {
    run("git", ["init", "-b", "main"], temp);
    for (const file of ["AGENTS.md", "CLAUDE.md", ".gitignore"]) {
      for (const body of malformed) {
        await writeFile(path.join(temp, file), `User prefix\n${body}\nUser suffix\n`);
        const before = await projectSnapshot(temp);
        for (const flags of [["--check"], [], ["--force"]]) {
          const result = run(process.execPath, [setup, "--target", temp, ...flags], temp, true);
          assert.equal(result.status, 2, `${file}: ${flags.join(" ")}`);
          assert.match(result.stderr, /malformed managed block/);
          assert.deepEqual(await projectSnapshot(temp), before);
        }
      }
      await rm(path.join(temp, file));
    }
  } finally {
    assert.equal(path.dirname(temp), os.tmpdir());
    await rm(temp, { recursive: true, force: true });
  }
});

test("setup validates late adapter errors before updating the installed package", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "aihaus-setup-preflight-"));
  try {
    run("git", ["init", "-b", "main"], temp);
    run(process.execPath, [setup, "--target", temp], temp);
    await writeFile(path.join(temp, ".aihaus", "VERSION"), "0.0.0\n");
    await writeFile(path.join(temp, ".aihaus", "roles", "reviewer.md"), "# Previous reviewer\n");
    await writeFile(path.join(temp, ".aihaus", "INIT.md"), "# Previous entry point\n");
    for (const file of ["AGENTS.md", "CLAUDE.md", ".gitignore"]) {
      const destination = path.join(temp, file);
      const original = await readFile(destination, "utf8");
      await writeFile(destination, "User rule\n<!-- AIHAUS:START -->\n");
      const before = await projectSnapshot(temp);
      for (const flags of [["--check"], [], ["--force"]]) {
        const result = run(process.execPath, [setup, "--target", temp, ...flags], temp, true);
        assert.equal(result.status, 2);
        assert.match(result.stderr, /malformed managed block/);
        assert.deepEqual(await projectSnapshot(temp), before);
      }
      await writeFile(destination, original);
    }
  } finally {
    assert.equal(path.dirname(temp), os.tmpdir());
    await rm(temp, { recursive: true, force: true });
  }
});

test("setup preview reports missing directories and rejects obstructions without writing", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "aihaus-setup-directories-"));
  const directories = [".aihaus/memory/kanban/todo", ".aihaus/state"];
  try {
    run("git", ["init", "-b", "main"], temp);
    run(process.execPath, [setup, "--target", temp], temp);
    for (const relative of directories) await rmdir(path.join(temp, relative));
    const before = await projectSnapshot(temp);
    const preview = JSON.parse(run(process.execPath, [setup, "--target", temp, "--check"], temp).stdout);
    assert.equal(preview.changesRequired, true);
    assert.deepEqual(preview.wouldCreateDirectories, directories);
    assert.deepEqual(preview.createdDirectories, []);
    assert.equal(preview.verification.ok, false);
    for (const relative of directories) assert.ok(preview.verification.missing.includes(relative));
    assert.deepEqual(await projectSnapshot(temp), before);
    const applied = JSON.parse(run(process.execPath, [setup, "--target", temp], temp).stdout);
    assert.deepEqual(applied.createdDirectories, directories);
    assert.deepEqual(applied.wouldCreateDirectories, []);
    assert.equal(applied.verification.ok, true);
    assert.equal(JSON.parse(run(process.execPath, [setup, "--target", temp, "--check"], temp).stdout).changesRequired, false);

    for (const relative of directories) {
      const destination = path.join(temp, relative);
      await rmdir(destination);
      await writeFile(destination, "User-owned obstruction\n");
      const obstructed = await projectSnapshot(temp);
      for (const flags of [["--check"], [], ["--force"]]) {
        const result = run(process.execPath, [setup, "--target", temp, ...flags], temp, true);
        assert.equal(result.status, 2, relative);
        assert.deepEqual(await projectSnapshot(temp), obstructed);
      }
      await rm(destination);
      await mkdir(destination);
    }
  } finally {
    assert.equal(path.dirname(temp), os.tmpdir());
    await rm(temp, { recursive: true, force: true });
  }
});

test("setup preflights incomplete sources and invalid release metadata without changing the target", async () => {
  const lab = await mkdtemp(path.join(os.tmpdir(), "aihaus-setup-source-preflight-"));
  try {
    const target = path.join(lab, "consumer");
    const source = path.join(lab, "download", "pkg");
    await mkdir(target);
    run("git", ["init", "-b", "main"], target);
    await cp(path.join(root, "pkg"), source, { recursive: true });
    run(process.execPath, [setup, "--target", target], target);
    await writeFile(path.join(target, ".aihaus", "VERSION"), "0.0.0\n");
    await rm(path.join(target, ".aihaus", "memory", "project", "glossary.md"));
    const before = await projectSnapshot(target);
    for (const relative of [".aihaus/memory/project/glossary.md", ".aihaus/rooms/feature/CONTEXT.md", "adapters/codex/skills/aih-refresh/SKILL.md", "RELEASE.json"]) {
      const file = path.join(source, relative);
      if (relative === "RELEASE.json") await writeFile(file, "invalid JSON");
      else await rm(file);
      for (const flags of [["--check"], [], ["--force"]]) {
        const result = run(process.execPath, [path.join(source, "setup.mjs"), "--target", target, ...flags], target, true);
        assert.equal(result.status, 2, relative);
        assert.deepEqual(await projectSnapshot(target), before);
      }
      if (relative !== "RELEASE.json") await cp(path.join(root, "pkg", relative), file);
    }
  } finally {
    assert.equal(path.dirname(lab), os.tmpdir());
    await rm(lab, { recursive: true, force: true });
  }
});

test("setup imports project instructions for Claude and reports Codex router shadowing", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "aihaus-setup-instructions-"));
  try {
    run("git", ["init", "-b", "main"], temp);
    const prefix = "# Project-owned instructions\n";
    const suffix = "\n# Preserve this rule\n";
    for (const file of ["AGENTS.md", "CLAUDE.md"]) {
      await writeFile(path.join(temp, file), `${prefix}<!-- AIHAUS:START -->\nOld router\n<!-- AIHAUS:END -->${suffix}`);
    }
    const override = "# Private project override\nDo not expose this rule in installer output.\n";
    await writeFile(path.join(temp, "AGENTS.override.md"), override);
    const result = run(process.execPath, [setup, "--target", temp], temp);
    const report = JSON.parse(result.stdout);
    for (const file of ["AGENTS.md", "CLAUDE.md"]) {
      const body = await readFile(path.join(temp, file), "utf8");
      assert.ok(body.startsWith(prefix));
      assert.ok(body.endsWith(suffix));
    }
    assert.match(await readFile(path.join(temp, "CLAUDE.md"), "utf8"), /<!-- AIHAUS:START -->\n@AGENTS\.md\n<!-- AIHAUS:END -->/);
    assert.match(await readFile(path.join(temp, "AGENTS.md"), "utf8"), /\.aihaus\/MAP\.md/);
    assert.equal(await readFile(path.join(temp, "AGENTS.override.md"), "utf8"), override);
    assert.deepEqual(report.instructionWarnings.map((warning) => warning.path), ["AGENTS.override.md"]);
    assert.ok(report.instructionWarnings[0].reason);
    assert.ok(report.warnings.some((warning) => warning.includes("AGENTS.override.md")));
    assert.equal(report.hostCapabilities.codex.available, true);
    assert.ok(!result.stdout.includes("Do not expose this rule"));
    await writeFile(path.join(temp, "AGENTS.override.md"), "\n");
    assert.deepEqual(JSON.parse(run(process.execPath, [setup, "--target", temp, "--check"], temp).stdout).instructionWarnings, []);
  } finally {
    assert.equal(path.dirname(temp), os.tmpdir());
    await rm(temp, { recursive: true, force: true });
  }
});

test("setup rejects non-regular memory seeds before writing", async () => {
  for (const kind of ["directory", "junction"]) {
    const temp = await mkdtemp(path.join(os.tmpdir(), "aihaus-setup-memory-kind-"));
    try {
      run("git", ["init", "-b", "main"], temp);
      const destination = path.join(temp, ".aihaus", "memory", "project", "project.md");
      if (kind === "directory") {
        await mkdir(destination, { recursive: true });
      } else {
        const manual = path.join(path.dirname(destination), "manual-memory");
        await mkdir(manual, { recursive: true });
        await symlink(manual, destination, "junction");
      }
      const before = await projectSnapshot(temp);
      for (const flags of [["--check"], [], ["--force"]]) {
        const result = run(process.execPath, [setup, "--target", temp, ...flags], temp, true);
        assert.equal(result.status, 2, `${kind}: ${flags.join(" ")}`);
        assert.match(result.stderr, /non-regular project memory/);
        assert.deepEqual(await projectSnapshot(temp), before);
      }
    } finally {
      assert.equal(path.dirname(temp), os.tmpdir());
      await rm(temp, { recursive: true, force: true });
    }
  }
});
