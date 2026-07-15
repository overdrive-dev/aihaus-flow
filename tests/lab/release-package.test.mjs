import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const builder = path.join(root, "tools", "build-package-release.mjs");
const packageVersion = (await readFile(path.join(root, "pkg", "VERSION"), "utf8")).trim();
const releaseTag = `v${packageVersion}`;
const npmCommand = process.platform === "win32" ? process.execPath : "npm";
const npmPrefix = process.platform === "win32"
  ? [path.join(path.dirname(process.execPath), "node_modules", "npm", "bin", "npm-cli.js")]
  : [];

function run(command, args, cwd, env = process.env) {
  const result = spawnSync(command, args, { cwd, env, encoding: "utf8" });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`${command} ${args.join(" ")} failed: ${result.stderr || result.stdout}`);
  }
  return result;
}

function initializeGit(repository) {
  run("git", ["init", "-b", "main"], repository);
  run("git", ["config", "user.name", "aihaus lab"], repository);
  run("git", ["config", "user.email", "aihaus-lab@local.invalid"], repository);
}

test("release package metadata exposes one lifecycle-free aihaus command", async () => {
  const manifest = JSON.parse(await readFile(path.join(root, "pkg", "package.json"), "utf8"));
  assert.equal(manifest.name, "aihaus-flow");
  assert.equal(manifest.version, packageVersion);
  assert.deepEqual(manifest.bin, { aihaus: "cli.mjs" });
  assert.equal(manifest.engines.node, ">=22");
  assert.deepEqual(manifest.scripts, undefined);
  assert.deepEqual(manifest.dependencies, undefined);
});

test("GitHub Release tarball runs aihaus setup without a visible clone", async () => {
  const labRoot = await mkdtemp(path.join(os.tmpdir(), "aihaus-release-package-"));
  const dist = path.join(labRoot, "dist");
  const consumer = path.join(labRoot, "consumer");
  const cache = path.join(labRoot, "npm-cache");
  const commit = "0123456789abcdef0123456789abcdef01234567";

  try {
    await mkdir(dist);
    const built = run(
      process.execPath,
      [builder, "--tag", releaseTag, "--commit", commit, "--out", dist, "--json"],
      root,
    );
    const release = JSON.parse(built.stdout);
    assert.equal(release.ok, true);
    assert.equal(release.tag, releaseTag);
    assert.equal(release.version, packageVersion);
    assert.equal(path.basename(release.asset), `aihaus-flow-${releaseTag}.tgz`);

    const archive = await readFile(release.asset);
    const digest = createHash("sha256").update(archive).digest("hex");
    assert.equal(
      await readFile(release.checksum, "utf8"),
      `${digest}  aihaus-flow-${releaseTag}.tgz\n`,
    );

    await mkdir(consumer);
    initializeGit(consumer);
    await writeFile(path.join(consumer, "AGENTS.md"), "# Existing consumer instructions\n", "utf8");
    await writeFile(path.join(consumer, "README.md"), "# Customer repository\n", "utf8");
    run("git", ["add", "."], consumer);
    run("git", ["commit", "-m", "seed consumer"], consumer);
    await writeFile(
      path.join(consumer, "README.md"),
      "# Customer repository\n\nUncommitted customer work.\n",
      "utf8",
    );

    const environment = { ...process.env, npm_config_cache: cache };
    const command = [
      "exec",
      "--yes",
      `--package=${release.asset}`,
      "--",
      "aihaus",
      "setup",
      "--target",
      consumer,
      "--json",
    ];
    const installed = JSON.parse(run(npmCommand, [...npmPrefix, ...command], consumer, environment).stdout);
    assert.equal(installed.ok, true);
    assert.equal(installed.scope, "repository-local");
    assert.equal(installed.source.distribution, "github-release");
    assert.equal(installed.source.version, packageVersion);
    assert.equal(installed.source.ref, releaseTag);
    assert.equal(installed.source.commit, commit);
    assert.equal(installed.source.pinned, true);
    assert.equal(installed.verification.ok, true);
    assert.deepEqual(installed.cleanup, { path: null, pending: false });
    assert.equal(installed.hostCapabilities.claudeCode.invoke, "/aih-init");
    assert.equal(installed.hostCapabilities.claudeCode.status, "created");
    assert.equal(installed.hostCapabilities.claudeCode.available, true);
    assert.equal(installed.hostCapabilities.codex.invoke, "$aih-init");
    assert.equal(installed.hostCapabilities.codex.status, "created");
    assert.equal(installed.hostCapabilities.codex.available, true);
    assert.equal(installed.hostCapabilities.codex.customSlash, false);

    const bootstrap = JSON.parse(
      run(
        process.execPath,
        [
          path.join(consumer, ".aihaus", "tools", "init.mjs"),
          "--repo",
          consumer,
          "--dry-run",
          "--json",
        ],
        consumer,
      ).stdout,
    );
    assert.equal(bootstrap.ok, true);
    assert.equal(bootstrap.mode, "dry-run");
    assert.deepEqual(bootstrap.wouldCreate, [".aihaus/state/bootstrap/discovery.json"]);

    assert.match(await readFile(path.join(consumer, "AGENTS.md"), "utf8"), /Existing consumer/);
    assert.match(await readFile(path.join(consumer, "README.md"), "utf8"), /Uncommitted customer work/);
    assert.equal(
      await readFile(path.join(consumer, ".aihaus", "VERSION"), "utf8"),
      `${packageVersion}\n`,
    );
    assert.match(
      await readFile(
        path.join(consumer, ".claude", "skills", "aih-init", "SKILL.md"),
        "utf8",
      ),
      /name: aih-init/,
    );
    assert.match(
      await readFile(
        path.join(consumer, ".agents", "skills", "aih-init", "SKILL.md"),
        "utf8",
      ),
      /name: aih-init/,
    );

    const updated = JSON.parse(run(npmCommand, [...npmPrefix, ...command], consumer, environment).stdout);
    assert.deepEqual(updated.created, []);
    assert.deepEqual(updated.refreshed, []);
    assert.deepEqual(updated.unchanged, updated.installed);
    assert.equal(updated.changesRequired, false);
    assert.equal(updated.adapters["AGENTS.md"], "unchanged");
    assert.equal(updated.hostCapabilities.claudeCode.status, "unchanged");
    assert.equal(updated.hostCapabilities.codex.status, "unchanged");

    const help = run(
      npmCommand,
      [...npmPrefix, "exec", "--yes", `--package=${release.asset}`, "--", "aihaus", "--help"],
      consumer,
      environment,
    );
    assert.match(help.stdout, /aihaus setup/);
    assert.match(help.stdout, /--check/);
    assert.match(help.stdout, /--force/);
  } finally {
    await rm(labRoot, { recursive: true, force: true });
  }
});

test("release builder rejects a tag that does not match pkg/VERSION", async () => {
  const result = spawnSync(
    process.execPath,
    [builder, "--tag", "v9.9.9", "--commit", "0123456789abcdef0123456789abcdef01234567"],
    { cwd: root, encoding: "utf8" },
  );
  assert.equal(result.status, 2);
  assert.match(result.stderr, new RegExp(`release tag must be ${releaseTag.replaceAll(".", "\\.")}`));
});

test("package release workflow publishes the tarball and checksum", async () => {
  const workflow = await readFile(path.join(root, ".github", "workflows", "package-release.yml"), "utf8");
  assert.match(workflow, /tags:\s*\n\s*- 'v\*'/);
  assert.match(workflow, /build-package-release\.mjs/);
  assert.match(workflow, /softprops\/action-gh-release@v2/);
  assert.match(workflow, /aihaus-flow-\*\.tgz\.sha256/);
});
