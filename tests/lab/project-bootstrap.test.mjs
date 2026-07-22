import assert from "node:assert/strict";
import { access, mkdir, mkdtemp, readFile, readdir, realpath, rm, symlink, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const setup = path.join(root, "pkg", "setup.mjs");
const memoryNames = [
  "project.md",
  "business-rules.md",
  "decisions.md",
  "knowledge.md",
  "environment.md",
  "procedures.md",
  "deployment.md",
  "glossary.md",
];

function run(command, args, cwd, options = {}) {
  const result = spawnSync(command, args, {
    cwd,
    encoding: "utf8",
    env: options.env ?? process.env,
  });
  if (result.error) throw result.error;
  if (!options.allowFailure && result.status !== 0) {
    throw new Error(command + " " + args.join(" ") + " failed: " + (result.stderr || result.stdout));
  }
  return result;
}

async function exists(target) {
  try {
    await access(target);
    return true;
  } catch {
    return false;
  }
}

async function initializeGit(repository) {
  await mkdir(repository, { recursive: true });
  run("git", ["init", "-b", "main"], repository);
  run("git", ["config", "user.name", "aihaus bootstrap lab"], repository);
  run("git", ["config", "user.email", "aihaus-bootstrap@local.invalid"], repository);
}

function commitAll(repository, message) {
  run("git", ["add", "-A"], repository);
  run("git", ["commit", "-m", message], repository);
}

function install(repository) {
  const report = JSON.parse(
    run(process.execPath, [setup, "--target", repository, "--json"], repository).stdout,
  );
  assert.equal(report.ok, true);
  return path.join(repository, ".aihaus", "tools", "init.mjs");
}

test("bootstrap discovers safe local evidence, preserves memory, and is idempotent", async () => {
  const labRoot = await mkdtemp(path.join(os.tmpdir(), "aihaus-bootstrap-"));
  const repository = path.join(labRoot, "consumer with spaces");
  const fakeHome = path.join(labRoot, "fake-home");
  const outsideSentinel = path.join(labRoot, "outside-sentinel.txt");

  try {
    await initializeGit(repository);
    await mkdir(path.join(repository, ".github", "workflows"), { recursive: true });
    await mkdir(path.join(repository, ".aws"), { recursive: true });
    await mkdir(path.join(repository, "docs"), { recursive: true });
    await mkdir(path.join(repository, "secrets"), { recursive: true });
    await mkdir(path.join(repository, "src"), { recursive: true });
    await mkdir(path.join(repository, "tests"), { recursive: true });
    await writeFile(path.join(repository, "README.md"), "# Acme Billing\n\nLocal billing service.\n", "utf8");
    await writeFile(path.join(repository, "AGENTS.md"), "# Project instructions\n", "utf8");
    await writeFile(
      path.join(repository, "package.json"),
      JSON.stringify({
        name: "acme-billing",
        private: true,
        engines: { node: ">=22" },
        scripts: { build: "node build.mjs", test: "node --test" },
      }, null, 2) + "\n",
      "utf8",
    );
    await writeFile(path.join(repository, ".github", "workflows", "ci.yml"), "name: CI\n", "utf8");
    await writeFile(path.join(repository, "docs", "architecture.md"), "# Architecture\n", "utf8");
    await writeFile(path.join(repository, "src", "index.mjs"), "export const ready = true;\n", "utf8");
    await writeFile(path.join(repository, "tests", "index.test.mjs"), "// local test\n", "utf8");
    await writeFile(path.join(repository, ".env"), "SUPER_SECRET=do-not-copy-this\n", "utf8");
    await writeFile(
      path.join(repository, "credentials.json"),
      "{\"token\":\"never-copy-this-token\"}\n",
      "utf8",
    );
    await writeFile(
      path.join(repository, "secrets", "README.md"),
      "# Secret notes\n\npassword: never-copy-this-password\n",
      "utf8",
    );
    await writeFile(
      path.join(repository, ".aws", "README.md"),
      "# Cloud credentials\n\nsecret: never-copy-cloud-secret\n",
      "utf8",
    );
    commitAll(repository, "seed consumer");

    const init = install(repository);
    assert.equal(await exists(path.join(repository, ".aihaus", "INIT.md")), true);
    assert.equal(
      await exists(path.join(repository, ".aihaus", "contracts", "project-bootstrap.md")),
      true,
    );
    assert.equal(await exists(init), true);

    const decisions = path.join(repository, ".aihaus", "memory", "project", "decisions.md");
    await writeFile(decisions, "# Decisions\n\nKeep this project-owned decision.\n", "utf8");
    await mkdir(fakeHome);
    await writeFile(path.join(fakeHome, "sentinel.txt"), "user home remains unchanged\n", "utf8");
    await writeFile(outsideSentinel, "outside remains unchanged\n", "utf8");

    const environment = { ...process.env, HOME: fakeHome, USERPROFILE: fakeHome };
    const first = JSON.parse(
      run(
        process.execPath,
        [init, "--repo", repository, "--json"],
        repository,
        { env: environment },
      ).stdout,
    );
    assert.equal(first.schema, "aihaus.bootstrap.result.v1");
    assert.equal(first.ok, true);
    assert.equal(first.mode, "apply");
    assert.equal(first.readyForSynthesis, true);
    assert.equal(first.evidenceLevel, "sufficient");
    assert.equal(first.memoryReadiness, "partial");
    assert.equal(first.repo, await realpath(repository));
    assert.match(first.commit, /^[0-9a-f]{40}$/);
    assert.equal(first.packet.path, ".aihaus/state/bootstrap/discovery.json");
    assert.equal(first.packet.action, "created");
    assert.deepEqual(first.created, [".aihaus/state/bootstrap/discovery.json"]);
    assert.deepEqual(first.updated, []);
    assert.equal(first.conflicts.length, 0);
    for (const name of memoryNames) {
      assert.ok(first.preserved.includes(".aihaus/memory/project/" + name));
    }

    const packetPath = path.join(repository, ".aihaus", "state", "bootstrap", "discovery.json");
    const firstPacketText = await readFile(packetPath, "utf8");
    const packet = JSON.parse(firstPacketText);
    assert.equal(packet.schema, "aihaus.bootstrap.discovery.v1");
    assert.equal(packet.repository.root, await realpath(repository));
    assert.deepEqual(packet.facts.manifests[0].scriptNames, ["build", "test"]);
    assert.equal(packet.facts.manifests[0].projectName, "acme-billing");
    assert.ok(packet.sources.some((source) => source.path === "README.md"));
    assert.ok(packet.sources.some((source) => source.path === "AGENTS.md"));
    assert.ok(packet.sources.some((source) => source.path === "package.json"));
    assert.ok(packet.sources.some((source) => source.path === ".github/workflows/ci.yml"));
    assert.ok(packet.sources.some((source) => source.path === "docs/architecture.md"));
    assert.ok(!packet.sources.some((source) => source.path === ".env"));
    assert.ok(!packet.sources.some((source) => source.path === "credentials.json"));
    assert.ok(!packet.sources.some((source) => source.path === "secrets/README.md"));
    assert.ok(!packet.sources.some((source) => source.path === ".aws/README.md"));
    assert.ok(packet.excluded.some((entry) => entry.path === ".env"));
    assert.ok(packet.excluded.some((entry) => entry.path === "credentials.json"));
    assert.ok(packet.excluded.some((entry) => entry.path === "secrets/README.md"));
    assert.ok(packet.excluded.some((entry) => entry.path === ".aws/README.md"));
    assert.doesNotMatch(
      firstPacketText,
      /do-not-copy-this|never-copy-this-token|never-copy-this-password|never-copy-cloud-secret/,
    );
    assert.equal(packet.memoryTargets.length, memoryNames.length);
    assert.equal(
      packet.memoryTargets.find((target) => target.path.endsWith("/project.md")).status,
      "template",
    );
    assert.equal(
      packet.memoryTargets.find((target) => target.path.endsWith("/decisions.md")).status,
      "existing",
    );

    assert.equal(
      await readFile(decisions, "utf8"),
      "# Decisions\n\nKeep this project-owned decision.\n",
    );
    assert.deepEqual((await readdir(fakeHome)).sort(), ["sentinel.txt"]);
    assert.equal(await readFile(outsideSentinel, "utf8"), "outside remains unchanged\n");
    const second = JSON.parse(
      run(
        process.execPath,
        [init, "--repo", repository, "--json"],
        repository,
        { env: environment },
      ).stdout,
    );
    assert.equal(second.packet.action, "unchanged");
    assert.deepEqual(second.created, []);
    assert.deepEqual(second.updated, []);
    assert.equal(await readFile(packetPath, "utf8"), firstPacketText);

    const status = JSON.parse(
      run(
        process.execPath,
        [init, "--repo", repository, "--status", "--json"],
        repository,
        { env: environment },
      ).stdout,
    );
    assert.equal(status.mode, "status");
    assert.equal(status.status.discoveryInitialized, true);
    assert.equal(status.status.initialized, false);
    assert.equal(status.status.memoryReadiness, "partial");
    assert.equal(status.status.stale, false);
    assert.deepEqual(status.created, []);
    assert.deepEqual(status.updated, []);

    await writeFile(
      path.join(repository, "README.md"),
      "# Acme Billing\n\nLocal billing service with a reviewed change.\n",
      "utf8",
    );
    const stale = JSON.parse(
      run(
        process.execPath,
        [init, "--repo", repository, "--status", "--json"],
        repository,
        { env: environment },
      ).stdout,
    );
    assert.equal(stale.packet.action, "stale");
    assert.equal(stale.status.stale, true);
    assert.equal(await readFile(packetPath, "utf8"), firstPacketText);

    const updatePreview = JSON.parse(
      run(
        process.execPath,
        [init, "--repo", repository, "--dry-run", "--json"],
        repository,
        { env: environment },
      ).stdout,
    );
    assert.deepEqual(updatePreview.wouldUpdate, [".aihaus/state/bootstrap/discovery.json"]);
    assert.equal(updatePreview.packet.action, "would-update");
    assert.equal(await readFile(packetPath, "utf8"), firstPacketText);

    const refreshed = JSON.parse(
      run(
        process.execPath,
        [init, "--repo", repository, "--json"],
        repository,
        { env: environment },
      ).stdout,
    );
    assert.deepEqual(refreshed.updated, [".aihaus/state/bootstrap/discovery.json"]);
    assert.equal(refreshed.packet.action, "updated");
  } finally {
    await rm(labRoot, { recursive: true, force: true });
  }
});

test("bootstrap blocks synthesis in an empty repository and ignores generated adapters", async () => {
  const repository = await mkdtemp(path.join(os.tmpdir(), "aihaus-bootstrap-empty-"));
  try {
    await initializeGit(repository);
    await writeFile(path.join(repository, ".gitattributes"), "* text=auto eol=lf\n", "utf8");
    commitAll(repository, "seed empty repository");
    const init = install(repository);
    const before = new Map();
    for (const name of memoryNames) {
      before.set(
        name,
        await readFile(path.join(repository, ".aihaus", "memory", "project", name), "utf8"),
      );
    }

    const result = JSON.parse(
      run(process.execPath, [init, "--repo", repository, "--json"], repository).stdout,
    );

    assert.equal(result.ok, true);
    assert.equal(result.readyForSynthesis, false);
    assert.equal(result.evidenceLevel, "insufficient");
    assert.equal(result.memoryReadiness, "uninitialized");
    assert.deepEqual(result.sources, []);
    assert.ok(result.warnings.some((warning) => /insufficient authoritative/i.test(warning)));
    assert.ok(
      result.skipped.some(
        (entry) => entry.path === "AGENTS.md" && entry.reason === "aihaus-managed-adapter",
      ),
    );
    assert.ok(
      result.skipped.some(
        (entry) =>
          entry.path === ".claude/skills/aih-init/SKILL.md" &&
          entry.reason === "host-skill-adapter",
      ),
    );
    assert.ok(
      result.skipped.some(
        (entry) =>
          entry.path === ".agents/skills/aih-init/SKILL.md" &&
          entry.reason === "host-skill-adapter",
      ),
    );
    for (const name of memoryNames) {
      assert.equal(
        await readFile(path.join(repository, ".aihaus", "memory", "project", name), "utf8"),
        before.get(name),
      );
    }

    const status = JSON.parse(
      run(
        process.execPath,
        [init, "--repo", repository, "--status", "--json"],
        repository,
      ).stdout,
    );
    assert.equal(status.status.discoveryInitialized, true);
    assert.equal(status.status.initialized, false);
    assert.equal(status.status.readyForSynthesis, false);
    assert.equal(status.status.memoryReadiness, "uninitialized");
    assert.equal(status.status.stale, false);
  } finally {
    await rm(repository, { recursive: true, force: true });
  }
});

test("bootstrap rejects incidental files and host skills as authoritative evidence", async () => {
  const fixtures = [
    {
      name: "notes",
      seed: async (repository) => writeFile(path.join(repository, "notes.md"), "# Scratch notes\n", "utf8"),
    },
    {
      name: "empty-source-root",
      seed: async (repository) => {
        await mkdir(path.join(repository, "src"), { recursive: true });
        await writeFile(path.join(repository, "src", "empty.txt"), "placeholder\n", "utf8");
      },
    },
    {
      name: "colliding-host-skill",
      seed: async (repository) => {
        const skill = path.join(repository, ".claude", "skills", "aih-init", "SKILL.md");
        await mkdir(path.dirname(skill), { recursive: true });
        await writeFile(skill, "---\nname: aih-init\ndescription: User workflow\n---\n", "utf8");
      },
    },
  ];

  for (const fixture of fixtures) {
    const repository = await mkdtemp(path.join(os.tmpdir(), `aihaus-bootstrap-${fixture.name}-`));
    try {
      await initializeGit(repository);
      await writeFile(path.join(repository, ".gitattributes"), "* text=auto eol=lf\n", "utf8");
      await fixture.seed(repository);
      commitAll(repository, `seed ${fixture.name}`);
      const init = install(repository);

      const result = JSON.parse(
        run(process.execPath, [init, "--repo", repository, "--dry-run", "--json"], repository).stdout,
      );

      assert.equal(result.readyForSynthesis, false, fixture.name);
      assert.equal(result.evidenceLevel, "insufficient", fixture.name);
      assert.equal(result.memoryReadiness, "uninitialized", fixture.name);
      assert.deepEqual(result.memory.readiness.evidence.authoritativeSources, [], fixture.name);
      assert.equal(result.memory.readiness.evidence.applicationSourceCount, 0, fixture.name);
      assert.ok(
        !result.sources.some((source) => source.path.includes("skills/aih-init/SKILL.md")),
        fixture.name,
      );
    } finally {
      await rm(repository, { recursive: true, force: true });
    }
  }
});

test("bootstrap dry-run and status do not write and support Claude-only or no adapter", async () => {
  const repository = await mkdtemp(path.join(os.tmpdir(), "aihaus-bootstrap-dry-"));
  try {
    await initializeGit(repository);
    await writeFile(path.join(repository, "CLAUDE.md"), "# Claude-only project instructions\n", "utf8");
    await writeFile(path.join(repository, "README.md"), "# Dry run fixture\n", "utf8");
    commitAll(repository, "seed dry-run fixture");
    const init = install(repository);
    await rm(path.join(repository, "AGENTS.md"));

    const packetPath = path.join(repository, ".aihaus", "state", "bootstrap", "discovery.json");
    const dryRun = JSON.parse(
      run(
        process.execPath,
        [init, "--repo", repository, "--dry-run", "--json"],
        repository,
      ).stdout,
    );
    assert.equal(dryRun.mode, "dry-run");
    assert.equal(dryRun.packet.action, "would-create");
    assert.deepEqual(dryRun.created, []);
    assert.deepEqual(dryRun.updated, []);
    assert.deepEqual(dryRun.wouldCreate, [".aihaus/state/bootstrap/discovery.json"]);
    assert.equal(await exists(packetPath), false);
    assert.deepEqual(
      dryRun.sources
        .filter((source) => source.kinds.includes("adapter"))
        .map((source) => source.path),
      ["CLAUDE.md"],
    );

    await rm(path.join(repository, "CLAUDE.md"));
    const status = JSON.parse(
      run(
        process.execPath,
        [init, "--repo", repository, "--status", "--json"],
        repository,
      ).stdout,
    );
    assert.equal(status.status.initialized, false);
    assert.equal(status.status.stale, null);
    assert.equal(await exists(packetPath), false);
    assert.deepEqual(
      status.sources.filter((source) => source.kinds.includes("adapter")),
      [],
    );
  } finally {
    await rm(repository, { recursive: true, force: true });
  }
});

test("bootstrap rejects a non-root repository and a state path that escapes the repository", async () => {
  const labRoot = await mkdtemp(path.join(os.tmpdir(), "aihaus-bootstrap-safety-"));
  const repository = path.join(labRoot, "consumer");
  const outside = path.join(labRoot, "outside");
  try {
    await initializeGit(repository);
    await writeFile(path.join(repository, "README.md"), "# Safety fixture\n", "utf8");
    commitAll(repository, "seed safety fixture");
    const init = install(repository);
    const child = path.join(repository, "child");
    await mkdir(child);

    const nested = run(
      process.execPath,
      [init, "--repo", child, "--json"],
      repository,
      { allowFailure: true },
    );
    assert.equal(nested.status, 2);
    assert.match(JSON.parse(nested.stderr).error, /repository root/);

    await mkdir(outside);
    await writeFile(path.join(outside, "sentinel.txt"), "keep\n", "utf8");
    await symlink(
      outside,
      path.join(repository, ".aihaus", "state", "bootstrap"),
      process.platform === "win32" ? "junction" : "dir",
    );
    const escaped = run(
      process.execPath,
      [init, "--repo", repository, "--json"],
      repository,
      { allowFailure: true },
    );
    assert.equal(escaped.status, 2);
    assert.match(JSON.parse(escaped.stderr).error, /outside allowed root/);
    assert.equal(await readFile(path.join(outside, "sentinel.txt"), "utf8"), "keep\n");
    assert.equal(await exists(path.join(outside, "discovery.json")), false);
  } finally {
    await rm(labRoot, { recursive: true, force: true });
  }
});

test("bootstrap reports conflicting project identities without choosing one", async () => {
  const repository = await mkdtemp(path.join(os.tmpdir(), "aihaus-bootstrap-conflict-"));
  try {
    await initializeGit(repository);
    await writeFile(
      path.join(repository, "package.json"),
      "{\n  \"name\": \"alpha-service\"\n}\n",
      "utf8",
    );
    await writeFile(
      path.join(repository, "pyproject.toml"),
      "[project]\nname = \"beta-service\"\n",
      "utf8",
    );
    commitAll(repository, "seed conflicting manifests");
    const init = install(repository);

    const result = JSON.parse(
      run(
        process.execPath,
        [init, "--repo", repository, "--dry-run", "--json"],
        repository,
      ).stdout,
    );
    assert.equal(result.ok, true);
    const conflict = result.conflicts.find((entry) => entry.id === "project-identity");
    assert.ok(conflict);
    assert.deepEqual(
      conflict.candidates.map((candidate) => candidate.value).sort(),
      ["alpha-service", "beta-service"],
    );
    assert.equal(await exists(path.join(repository, ".aihaus", "state", "bootstrap")), false);
  } finally {
    await rm(repository, { recursive: true, force: true });
  }
});
