import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const setup = path.join(root, "pkg", "setup.mjs");

function run(command, args, cwd) {
  const result = spawnSync(command, args, { cwd, encoding: "utf8" });
  if (result.error) throw result.error;
  assert.equal(result.status, 0, result.stderr || result.stdout);
  return result;
}

function runFailure(command, args, cwd) {
  const result = spawnSync(command, args, { cwd, encoding: "utf8" });
  if (result.error) throw result.error;
  assert.equal(result.status, 2, result.stderr || result.stdout);
  return result;
}

test("file task tool uses folder as the only status source", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "aihaus-task-"));
  try {
    run("git", ["init", "-b", "main"], temp);
    run(process.execPath, [setup, "--target", temp], temp);
    const tool = path.join(temp, ".aihaus", "tools", "task.mjs");
    const created = JSON.parse(
      run(
        process.execPath,
        [tool, "create", "--title", "Fix token refresh", "--room", "bugfix", "--external-id", "NOR-123", "--json"],
        temp,
      ).stdout,
    );
    assert.equal(created.status, "backlog");
    assert.equal(created.external_id, "NOR-123");
    const body = await readFile(path.join(temp, created.file), "utf8");
    assert.match(body, /^external_id: "NOR-123"$/m);
    assert.doesNotMatch(body, /^status:/m);

    const duplicate = runFailure(
      process.execPath,
      [tool, "create", "--title", "Duplicate", "--room", "bugfix", "--external-id", "nor-123", "--json"],
      temp,
    );
    assert.match(duplicate.stderr, /external task already exists: nor-123/);
    assert.match(
      runFailure(process.execPath, [tool, "create", "--title", "Missing ID", "--room", "bugfix", "--external-id"], temp).stderr,
      /--external-id requires a value/,
    );
    assert.match(
      runFailure(process.execPath, [tool, "move", created.id, "doing", "--json"], temp).stderr,
      /fill: Acceptance, Owned files, Context or Log/,
    );

    const asked = JSON.parse(
      run(process.execPath, [tool, "question", created.id, "--text", "Can sessions overlap?", "--json"], temp).stdout,
    );
    const answered = JSON.parse(
      run(
        process.execPath,
        [
          tool,
          "answer",
          created.id,
          "--question",
          asked.question,
          "--text",
          "No, one active session per user.",
          "--draft-rule",
          "A user has at most one active session.",
          "--json",
        ],
        temp,
      ).stdout,
    );
    assert.equal(answered.promoted, false);
    const answeredBody = await readFile(path.join(temp, created.file), "utf8");
    assert.match(answeredBody, /Answer: No, one active session per user\./);
    assert.match(answeredBody, /Draft rule: A user has at most one active session\./);
    assert.doesNotMatch(
      await readFile(path.join(temp, ".aihaus", "memory", "project", "business-rules.md"), "utf8"),
      /one active session/i,
    );

    const preparedBody = answeredBody
      .replace("- [ ] Define executable acceptance evidence.", "- [ ] `node --test` exits 0.")
      .replace("## Context\n\n", "## Context\n\nWorktree: nor-123\n\n")
      .replace("## Owned files\n\n", "## Owned files\n\n- src/session.mjs\n\n");
    await writeFile(path.join(temp, created.file), preparedBody, "utf8");

    const moved = JSON.parse(run(process.execPath, [tool, "move", created.id, "doing", "--json"], temp).stdout);
    assert.equal(moved.from, "backlog");
    assert.equal(moved.status, "doing");
    assert.match(
      runFailure(process.execPath, [tool, "move", created.id, "review", "--json"], temp).stderr,
      /fill: Log, Evidence/,
    );

    const doingBody = await readFile(path.join(temp, moved.file), "utf8");
    await writeFile(
      path.join(temp, moved.file),
      doingBody
        .replace("## Log\n\n", "## Log\n\nImplemented token refresh.\n\n")
        .replace("## Evidence\n", "## Evidence\n\n- `node --test` (exit 0)\n"),
      "utf8",
    );
    const reviewed = JSON.parse(run(process.execPath, [tool, "move", created.id, "review", "--json"], temp).stdout);
    assert.equal(reviewed.status, "review");
    const done = JSON.parse(run(process.execPath, [tool, "move", created.id, "done", "--json"], temp).stdout);
    assert.equal(done.status, "done");

    const withoutExternalId = JSON.parse(
      run(process.execPath, [tool, "create", "--title", "Local task", "--room", "feature", "--json"], temp).stdout,
    );
    assert.equal(Object.hasOwn(withoutExternalId, "external_id"), false);
    const listed = JSON.parse(run(process.execPath, [tool, "list", "--json"], temp).stdout);
    assert.deepEqual(
      listed.tasks.find((task) => task.id === created.id),
      { id: created.id, title: "Fix token refresh", room: "bugfix", external_id: "NOR-123", status: "done", file: done.file },
    );
    assert.equal(Object.hasOwn(listed.tasks.find((task) => task.id === withoutExternalId.id), "external_id"), false);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});
