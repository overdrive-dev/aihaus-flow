import assert from "node:assert/strict";
import { cp, mkdir, mkdtemp, readFile, realpath, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");

function run(command, args, cwd, allowFailure = false) {
  const result = spawnSync(command, args, { cwd, encoding: "utf8" });
  if (result.error) throw result.error;
  if (!allowFailure && result.status !== 0) {
    throw new Error(`${command} ${args.join(" ")} failed: ${result.stderr || result.stdout}`);
  }
  return result;
}

function initializeGit(repository) {
  run("git", ["init", "-b", "main"], repository);
  run("git", ["config", "user.name", "aihaus lab"], repository);
  run("git", ["config", "user.email", "aihaus-lab@local.invalid"], repository);
}

test("agent install stays local and reports provenance, preservation, and cleanup", async () => {
  const labRoot = await mkdtemp(path.join(os.tmpdir(), "aihaus-agent-install-"));
  const consumer = path.join(labRoot, "consumer");
  const download = path.join(consumer, ".aihaus-download");
  const sentinel = path.join(labRoot, "outside-sentinel.txt");

  try {
    await mkdir(consumer);
    initializeGit(consumer);
    await writeFile(path.join(consumer, "AGENTS.md"), "# Consumer agents\n", "utf8");
    await writeFile(path.join(consumer, "CLAUDE.md"), "# Consumer Claude instructions\n", "utf8");
    await writeFile(path.join(consumer, ".gitignore"), "*.log\n", "utf8");
    await writeFile(path.join(consumer, "README.md"), "# Consumer\n", "utf8");
    run("git", ["add", "."], consumer);
    run("git", ["commit", "-m", "seed consumer"], consumer);
    await writeFile(path.join(consumer, "README.md"), "# Consumer\n\nUser work in progress.\n", "utf8");
    await writeFile(sentinel, "outside remains untouched\n", "utf8");

    await mkdir(download);
    await cp(path.join(root, "pkg"), path.join(download, "pkg"), { recursive: true });
    initializeGit(download);
    run("git", ["add", "."], download);
    run("git", ["commit", "-m", "seed download"], download);

    const setup = path.join(download, "pkg", "setup.mjs");
    const result = run(process.execPath, [setup, "--target", consumer, "--json"], consumer);
    const report = JSON.parse(result.stdout);

    assert.equal(report.ok, true);
    assert.equal(report.scope, "repository-local");
    assert.equal(report.target, await realpath(consumer));
    assert.equal(report.source.distribution, "git");
    assert.equal(report.source.version, "1.0.0");
    assert.match(report.source.commit, /^[0-9a-f]{40}$/);
    assert.equal(report.source.pinned, false);
    assert.equal(report.source.dirty, false);
    assert.ok(report.warnings.some((warning) => /not pinned to a release tag/.test(warning)));
    assert.deepEqual(report.cleanup, { path: ".aihaus-download", pending: true });
    assert.equal(report.adapters["AGENTS.md"], "appended");
    assert.equal(report.adapters["CLAUDE.md"], "appended");
    assert.equal(report.verification.ok, true);

    assert.match(await readFile(path.join(consumer, "README.md"), "utf8"), /User work in progress/);
    assert.match(await readFile(path.join(consumer, "AGENTS.md"), "utf8"), /# Consumer agents/);
    assert.match(
      await readFile(path.join(consumer, "CLAUDE.md"), "utf8"),
      /# Consumer Claude instructions/,
    );
    assert.match(await readFile(path.join(consumer, ".gitignore"), "utf8"), /^\*\.log$/m);
    assert.equal(await readFile(path.join(consumer, ".aihaus", "VERSION"), "utf8"), "1.0.0\n");
    assert.equal(await readFile(sentinel, "utf8"), "outside remains untouched\n");
    assert.equal(run("git", ["check-ignore", ".aihaus-download"], consumer).status, 0);
    assert.doesNotMatch(run("git", ["status", "--short"], consumer).stdout, /\.aihaus-download/);
    assert.equal(await readFile(path.join(download, "pkg", "VERSION"), "utf8"), "1.0.0\n");

    run("git", ["tag", "v1.0.0"], download);
    const pinnedResult = run(process.execPath, [setup, "--target", consumer, "--json"], consumer);
    const pinnedReport = JSON.parse(pinnedResult.stdout);
    assert.equal(pinnedReport.source.distribution, "git");
    assert.equal(pinnedReport.source.pinned, true);
    assert.equal(pinnedReport.source.ref, "v1.0.0");
    assert.ok(!pinnedReport.warnings.some((warning) => /not pinned to a release tag/.test(warning)));
    assert.deepEqual(pinnedReport.created, []);
    assert.deepEqual(pinnedReport.refreshed, pinnedReport.installed);
  } finally {
    await rm(labRoot, { recursive: true, force: true });
  }
});
