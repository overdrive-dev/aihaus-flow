import assert from "node:assert/strict";
import { linkSync } from "node:fs";
import { access, chmod, mkdir, mkdtemp, readFile, readdir, realpath, rename, rm, stat, symlink, writeFile } from "node:fs/promises";
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
  return path.join(repository, ".aihaus", "tools", "refresh.mjs");
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
    assert.equal(await exists(path.join(repository, ".aihaus", "REFRESH.md")), true);
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
          entry.path === ".claude/skills/aih-refresh/SKILL.md" &&
          entry.reason === "host-skill-adapter",
      ),
    );
    assert.ok(
      result.skipped.some(
        (entry) =>
          entry.path === ".agents/skills/aih-refresh/SKILL.md" &&
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
        const skill = path.join(repository, ".claude", "skills", "aih-refresh", "SKILL.md");
        await mkdir(path.dirname(skill), { recursive: true });
        await writeFile(skill, "---\nname: aih-refresh\ndescription: User workflow\n---\n", "utf8");
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
        !result.sources.some((source) => source.path.includes("skills/aih-refresh/SKILL.md")),
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

test("status reports memory gaps and stale claims as advisory signals", async () => {
  const labRoot = await mkdtemp(path.join(os.tmpdir(), "aihaus-bootstrap-insights-"));
  const repository = path.join(labRoot, "consumer");
  try {
    await initializeGit(repository);
    await mkdir(path.join(repository, ".github", "workflows"), { recursive: true });
    await mkdir(path.join(repository, "src"), { recursive: true });
    await writeFile(path.join(repository, "README.md"), "# Acme Billing\n", "utf8");
    await writeFile(path.join(repository, ".github", "workflows", "deploy.yml"), "name: Deploy\n", "utf8");
    await writeFile(path.join(repository, "src", "service.mjs"), "export const ready = true;\n", "utf8");
    commitAll(repository, "seed consumer");
    const tool = install(repository);
    run(process.execPath, [tool, "--repo", repository, "--json"], repository);

    const status = () => JSON.parse(
      run(process.execPath, [tool, "--repo", repository, "--status", "--json"], repository).stdout,
    ).status;

    let current = status();
    assert.ok(
      current.memoryGaps.some(
        (gap) =>
          gap.target === ".aihaus/memory/project/deployment.md" &&
          gap.status === "template" &&
          gap.candidateExamples.includes(".github/workflows/deploy.yml"),
      ),
    );
    assert.deepEqual(current.staleClaims, []);

    const head = run("git", ["rev-parse", "HEAD"], repository).stdout.trim();
    await writeFile(
      path.join(repository, ".aihaus", "memory", "project", "knowledge.md"),
      "# Knowledge\n\n- src/service.mjs exports ready (verified at " + head + ")\n",
      "utf8",
    );

    current = status();
    assert.ok(!current.memoryGaps.some((gap) => gap.target.endsWith("knowledge.md")));
    assert.deepEqual(current.staleClaims, []);

    await writeFile(path.join(repository, "src", "service.mjs"), "export const ready = false;\n", "utf8");
    current = status();
    assert.deepEqual(current.staleClaims, [{
      page: ".aihaus/memory/project/knowledge.md",
      source: "src/service.mjs",
      reviewed: head,
      reason: "source-changed-since-review",
    }]);

    await rm(path.join(repository, "src", "service.mjs"));
    current = status();
    assert.equal(current.staleClaims[0].reason, "source-missing");
  } finally {
    await rm(labRoot, { recursive: true, force: true });
  }
});

function bootstrapResult(repository, mode = []) {
  return JSON.parse(run(process.execPath, [
    path.join(repository, ".aihaus", "tools", "refresh.mjs"),
    "--repo", repository, ...mode, "--json",
  ], repository).stdout);
}

test("refresh checks root and hidden citations at each claim's own commit", async () => {
  const repository = await mkdtemp(path.join(os.tmpdir(), "aihaus-refresh-citations-"));
  try {
    await initializeGit(repository);
    await mkdir(path.join(repository, ".github", "workflows"), { recursive: true });
    await mkdir(path.join(repository, "src"));
    await writeFile(path.join(repository, "README.md"), "# Billing\n\nRefunds last 30 days.\n");
    await writeFile(path.join(repository, ".github", "workflows", "ci.yml"), "name: Old CI\n");
    await writeFile(path.join(repository, "src", "rule.mjs"), "export const days = 30;\n");
    commitAll(repository, "initial rules");
    const oldCommit = run("git", ["rev-parse", "HEAD"], repository).stdout.trim();
    install(repository);
    const memory = path.join(repository, ".aihaus", "memory", "project", "knowledge.md");
    await writeFile(memory, `# Knowledge\n\n- Refunds last 30 days. Source: \`README.md\` (reviewed ${oldCommit}).\n- CI is Old CI. Source: \`.github/workflows/ci.yml\` (reviewed ${oldCommit}).\n`);
    await writeFile(path.join(repository, "README.md"), "# Billing\n\nRefunds last 7 days.\n");
    await writeFile(path.join(repository, ".github", "workflows", "ci.yml"), "name: New CI\n");
    bootstrapResult(repository);
    let status = bootstrapResult(repository, ["--status"]).status;
    assert.deepEqual(status.staleClaims.map((claim) => claim.source).sort(), [".github/workflows/ci.yml", "README.md"]);

    await writeFile(path.join(repository, "src", "rule.mjs"), "export const days = 7;\n");
    await writeFile(path.join(repository, "src", "new.mjs"), "export const active = true;\n");
    run("git", ["add", "-A"], repository);
    run("git", ["commit", "-m", "new separate fact"], repository, {
      env: { ...process.env, GIT_AUTHOR_DATE: "2030-01-01T00:00:00Z", GIT_COMMITTER_DATE: "2030-01-01T00:00:00Z" },
    });
    const newCommit = run("git", ["rev-parse", "HEAD"], repository).stdout.trim();
    await writeFile(memory, `# Knowledge\n\n- Refunds last 30 days. Source: \`src/rule.mjs\` (reviewed ${oldCommit}).\n- Feature is active. Source: \`src/new.mjs\` (reviewed ${newCommit}).\n`);
    bootstrapResult(repository);
    status = bootstrapResult(repository, ["--status"]).status;
    assert.deepEqual(status.staleClaims.map(({ source, reviewed }) => ({ source, reviewed })), [
      { source: "src/rule.mjs", reviewed: oldCommit },
    ]);
    await writeFile(memory, `# Knowledge\n\nReviewed commits: ${oldCommit}, ${newCommit}.\n\nsrc/rule.mjs still says 30 days.\n`);
    assert.ok(bootstrapResult(repository, ["--status"]).status.staleClaims.some((claim) => claim.source === "src/rule.mjs"));
  } finally {
    await rm(repository, { recursive: true, force: true });
  }
});

test("refresh keeps BOM and CRLF templates uninitialized and rejects empty memory", async () => {
  const repository = await mkdtemp(path.join(os.tmpdir(), "aihaus-refresh-content-"));
  try {
    await initializeGit(repository);
    await writeFile(path.join(repository, "README.md"), "# Billing\n\nProcesses invoices.\n");
    commitAll(repository, "project evidence");
    const reviewed = run("git", ["rev-parse", "HEAD"], repository).stdout.trim();
    install(repository);
    for (const name of memoryNames) {
      const file = path.join(repository, ".aihaus", "memory", "project", name);
      await writeFile(file, "\uFEFF" + (await readFile(file, "utf8")).replace(/\r?\n/g, "\r\n"));
    }
    let result = bootstrapResult(repository);
    assert.ok(result.memory.targets.every((target) => target.status === "template"));
    assert.equal(result.memoryReadiness, "uninitialized");
    for (const text of [
      "", "# Knowledge\n\n## Rules\n", "# Knowledge\n\n- Unresolved: owner must confirm every rule.\n",
      `# Knowledge\n\n- Status: unresolved\n- Statement: owner must confirm the refund rule.\n- Source: README.md (reviewed ${reviewed}).\n`,
      `# Knowledge\n\n## Unresolved\n\nOwner must confirm the refund rule. Source: README.md (reviewed ${reviewed}).\n`,
      "# Knowledge\n\nVerified: invoices are processed.\n",
    ]) {
      for (const name of memoryNames) await writeFile(path.join(repository, ".aihaus", "memory", "project", name), text);
      bootstrapResult(repository);
      const status = bootstrapResult(repository, ["--status"]).status;
      assert.equal(status.initialized, false, JSON.stringify(text));
      assert.notEqual(status.memoryReadiness, "ready", JSON.stringify(text));
      assert.ok(status.memoryGaps.length > 0, JSON.stringify(text));
    }
    for (const name of memoryNames) {
      await writeFile(path.join(repository, ".aihaus", "memory", "project", name), `# Knowledge\n\nVerified: invoices are processed. Source: \`README.md\` (reviewed ${reviewed}).\n`);
    }
    result = bootstrapResult(repository);
    assert.equal(result.memoryReadiness, "ready");
    const status = bootstrapResult(repository, ["--status"]).status;
    assert.equal(status.initialized, true);
    assert.equal(status.stale, false);
  } finally {
    await rm(repository, { recursive: true, force: true });
  }
});

test("refresh counts only available regular application sources", async () => {
  const repository = await mkdtemp(path.join(os.tmpdir(), "aihaus-refresh-source-"));
  try {
    await initializeGit(repository);
    await mkdir(path.join(repository, "src"));
    const source = path.join(repository, "src", "main.mjs");
    await writeFile(source, "export const active = true;\n");
    commitAll(repository, "only application source");
    install(repository);
    await rm(source);
    assert.equal(bootstrapResult(repository, ["--dry-run"]).readyForSynthesis, false);
    await mkdir(source);
    assert.equal(bootstrapResult(repository, ["--dry-run"]).readyForSynthesis, false);
    await rm(source, { recursive: true });
    const target = path.join(repository, ".aihaus", "state", "link-target");
    await mkdir(target, { recursive: true });
    await symlink(target, source, process.platform === "win32" ? "junction" : "dir");
    const result = bootstrapResult(repository, ["--dry-run"]);
    assert.equal(result.readyForSynthesis, false);
    assert.ok(result.skipped.some((entry) => entry.path === "src/main.mjs" && entry.reason === "symbolic-link"));
  } finally {
    await rm(repository, { recursive: true, force: true });
  }
});

test("refresh hashes application worktree and untracked evidence and checks hash citations", async () => {
  const repository = await mkdtemp(path.join(os.tmpdir(), "aihaus-refresh-hashes-"));
  try {
    await initializeGit(repository);
    await mkdir(path.join(repository, "src"));
    const tracked = path.join(repository, "src", "rule.mjs");
    const untracked = path.join(repository, "src", "new.mjs");
    await writeFile(tracked, "export const days = 30;\n");
    run("git", ["add", "src/rule.mjs"], repository);
    install(repository);
    assert.equal(bootstrapResult(repository, ["--dry-run"]).sources.find((source) => source.path === "src/rule.mjs")?.revision, "worktree");
    commitAll(repository, "initial code");
    await writeFile(tracked, "export const days = 7;\n");
    await writeFile(untracked, "export const active = true;\n");
    let result = bootstrapResult(repository);
    const dirtySource = result.sources.find((source) => source.path === "src/rule.mjs");
    const newSource = result.sources.find((source) => source.path === "src/new.mjs");
    assert.equal(dirtySource?.revision, "worktree");
    assert.equal(newSource?.revision, "untracked");
    assert.match(dirtySource.sha256, /^[0-9a-f]{64}$/);
    assert.match(newSource.sha256, /^[0-9a-f]{64}$/);
    assert.ok(result.memory.targets.find((target) => target.path.endsWith("knowledge.md")).candidateSources.includes("src/rule.mjs"));
    const memory = path.join(repository, ".aihaus", "memory", "project", "knowledge.md");
    await writeFile(memory, `# Knowledge\n\n- Verified: refunds last 7 days. Source: \`src/rule.mjs\` (worktree; sha256: ${dirtySource.sha256}).\n- Verified: feature is active. Source: \`src/new.mjs\` (untracked; sha256: ${newSource.sha256}).\n`);
    bootstrapResult(repository);
    assert.deepEqual(bootstrapResult(repository, ["--status"]).status.staleClaims, []);
    await writeFile(untracked, "export const active = false;\n");
    assert.equal(bootstrapResult(repository, ["--status"]).status.stale, true);
    bootstrapResult(repository);
    assert.ok(bootstrapResult(repository, ["--status"]).status.staleClaims.some((claim) => claim.source === "src/new.mjs"));
    await writeFile(memory, "# Knowledge\n\nVerified: refunds last 7 days. Source: `src/rule.mjs` (worktree).\n");
    assert.ok(bootstrapResult(repository, ["--status"]).status.staleClaims.some((claim) => claim.reason === "missing-review-provenance"));
  } finally {
    await rm(repository, { recursive: true, force: true });
  }
});

test("refresh includes project override instructions as authoritative evidence", async () => {
  const repository = await mkdtemp(path.join(os.tmpdir(), "aihaus-refresh-override-"));
  try {
    await initializeGit(repository);
    await writeFile(path.join(repository, "AGENTS.override.md"), "# Project rules\n\nInvoices require owner approval.\n");
    commitAll(repository, "override project rules");
    install(repository);
    const result = bootstrapResult(repository, ["--dry-run"]);
    assert.ok(result.sources.find((source) => source.path === "AGENTS.override.md")?.kinds.includes("adapter"));
    assert.ok(result.memory.readiness.evidence.authoritativeSources.includes("AGENTS.override.md"));
  } finally {
    await rm(repository, { recursive: true, force: true });
  }
});

test("refresh preserves quoted path boundaries and sentence punctuation", async () => {
  const repository = await mkdtemp(path.join(os.tmpdir(), "aihaus-refresh-paths-"));
  try {
    await initializeGit(repository);
    await mkdir(path.join(repository, "src"));
    await writeFile(path.join(repository, "README.md"), "# Billing\n\nHandles refunds.\n");
    await writeFile(path.join(repository, "file.md"), "# Separate root document\n");
    await writeFile(path.join(repository, "src", "my file.md"), "# Refund rules\n\nRefunds last 7 days.\n");
    commitAll(repository, "source documents");
    const reviewed = run("git", ["rev-parse", "HEAD"], repository).stdout.trim();
    install(repository);
    const result = bootstrapResult(repository);
    const memory = path.join(repository, ".aihaus", "memory", "project", "knowledge.md");
    await writeFile(memory, `# Knowledge\n\nVerified: project handles refunds. Source: README.md. Reviewed ${reviewed}.\n`);
    const punctuation = bootstrapResult(repository, ["--status"]).status.staleClaims;
    const hash = result.sources.find((source) => source.path === "src/my file.md").sha256;
    await writeFile(memory, `# Knowledge\n\nVerified: refunds last 7 days. Source: \`src/my file.md\` (worktree; sha256: ${hash}).\n`);
    const quoted = bootstrapResult(repository, ["--status"]).status.staleClaims;
    assert.deepEqual({ punctuation, quoted }, { punctuation: [], quoted: [] });
  } finally {
    await rm(repository, { recursive: true, force: true });
  }
});

test("refresh flags renamed sources and ambiguous legacy review commits", async () => {
  const repository = await mkdtemp(path.join(os.tmpdir(), "aihaus-refresh-renames-"));
  try {
    await initializeGit(repository);
    await mkdir(path.join(repository, "src"));
    await writeFile(path.join(repository, "README.md"), "# Billing\n\nHandles refunds.\n");
    await writeFile(path.join(repository, "src", "rule.mjs"), "export const days = 7;\n");
    commitAll(repository, "original rule");
    const first = run("git", ["rev-parse", "HEAD"], repository).stdout.trim();
    install(repository);
    await writeFile(path.join(repository, "README.md"), "# Billing\n\nHandles invoicing and refunds.\n");
    commitAll(repository, "new documented context");
    const second = run("git", ["rev-parse", "HEAD"], repository).stdout.trim();
    const memory = path.join(repository, ".aihaus", "memory", "project", "knowledge.md");
    await writeFile(memory, `# Knowledge\n\nReviews: ${first}, ${second}.\n\nSource: src/rule.mjs.\n`);
    const ambiguous = bootstrapResult(repository, ["--status"]).status.staleClaims;
    await rename(path.join(repository, "src", "rule.mjs"), path.join(repository, "src", "refunds.mjs"));
    commitAll(repository, "rename rule source");
    const current = run("git", ["rev-parse", "HEAD"], repository).stdout.trim();
    await writeFile(memory, `# Knowledge\n\n- Verified: refunds last 7 days. Source: \`src/rule.mjs\` (reviewed ${second}).\n- Verified: billing handles invoicing. Source: \`README.md\` (reviewed ${current}).\n`);
    bootstrapResult(repository);
    const renamed = bootstrapResult(repository, ["--status"]).status.staleClaims;
    assert.ok(ambiguous.some((claim) => claim.reason === "ambiguous-review-provenance"));
    assert.ok(renamed.some((claim) => claim.source === "src/rule.mjs" && claim.reason === "source-missing"));
  } finally {
    await rm(repository, { recursive: true, force: true });
  }
});

async function packetAfterRefresh(repository) {
  const result = bootstrapResult(repository);
  const packet = JSON.parse(
    await readFile(path.join(repository, ".aihaus", "state", "bootstrap", "discovery.json"), "utf8"),
  );
  return { result, packet };
}

test("refresh replaces a hard-linked discovery packet without writing through the link", async (t) => {
  const labRoot = await mkdtemp(path.join(os.tmpdir(), "aihaus-refresh-hardlink-"));
  const repository = path.join(labRoot, "consumer");
  const outside = path.join(labRoot, "outside.json");
  try {
    await initializeGit(repository);
    await writeFile(path.join(repository, "README.md"), "# Billing\n");
    commitAll(repository, "project evidence");
    install(repository);
    const bootstrap = path.join(repository, ".aihaus", "state", "bootstrap");
    const packetPath = path.join(bootstrap, "discovery.json");
    await mkdir(bootstrap, { recursive: true });
    await writeFile(outside, "outside bytes\n");
    await chmod(outside, 0o640);
    try {
      linkSync(outside, packetPath);
    } catch {
      t.skip("hard links are unavailable");
      return;
    }
    const { result, packet } = await packetAfterRefresh(repository);
    assert.equal(result.packet.action, "updated");
    assert.equal(packet.schema, "aihaus.bootstrap.discovery.v1");
    assert.equal(await readFile(outside, "utf8"), "outside bytes\n");
    assert.deepEqual(await readdir(bootstrap), ["discovery.json"]);
    if (process.platform !== "win32") assert.equal((await stat(packetPath)).mode & 0o777, 0o640);
  } finally {
    await rm(labRoot, { recursive: true, force: true });
  }
});

test("refresh reads the Maven project artifactId, not its parent", async () => {
  const repository = await mkdtemp(path.join(os.tmpdir(), "aihaus-refresh-maven-"));
  try {
    await initializeGit(repository);
    await writeFile(
      path.join(repository, "pom.xml"),
      "<project>\n  <parent>\n    <groupId>org.example</groupId>\n    <artifactId>example-parent</artifactId>\n  </parent>\n  <artifactId>demo</artifactId>\n</project>\n",
    );
    await writeFile(path.join(repository, "package.json"), "{\n  \"name\": \"demo\"\n}\n");
    commitAll(repository, "maven and node manifests");
    install(repository);
    const { result, packet } = await packetAfterRefresh(repository);
    assert.equal(packet.facts.manifests.find((manifest) => manifest.path === "pom.xml").projectName, "demo");
    assert.deepEqual(result.conflicts, []);
  } finally {
    await rm(repository, { recursive: true, force: true });
  }
});

test("refresh layout ignores directories that hold only aihaus host skills", async () => {
  const repository = await mkdtemp(path.join(os.tmpdir(), "aihaus-refresh-layout-"));
  try {
    await initializeGit(repository);
    await writeFile(path.join(repository, "README.md"), "# Billing\n");
    commitAll(repository, "project evidence");
    install(repository);
    let directories = (await packetAfterRefresh(repository)).packet.facts.layout.topLevelDirectories;
    assert.ok(!directories.includes(".claude") && !directories.includes(".agents"), JSON.stringify(directories));
    await writeFile(path.join(repository, ".claude", "settings.json"), "{}\n");
    run("git", ["add", ".claude/settings.json"], repository);
    run("git", ["commit", "-m", "project claude settings"], repository);
    directories = (await packetAfterRefresh(repository)).packet.facts.layout.topLevelDirectories;
    assert.ok(directories.includes(".claude") && !directories.includes(".agents"), JSON.stringify(directories));
  } finally {
    await rm(repository, { recursive: true, force: true });
  }
});
