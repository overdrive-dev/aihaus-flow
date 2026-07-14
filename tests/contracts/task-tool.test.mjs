import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, readFile, rm } from "node:fs/promises";
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

test("file task tool uses folder as the only status source", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "aihaus-task-"));
  try {
    run("git", ["init", "-b", "main"], temp);
    run(process.execPath, [setup, "--target", temp], temp);
    const tool = path.join(temp, ".aihaus", "tools", "task.mjs");
    const created = JSON.parse(
      run(process.execPath, [tool, "create", "--title", "Fix token refresh", "--room", "bugfix", "--json"], temp).stdout,
    );
    assert.equal(created.status, "backlog");
    const body = await readFile(path.join(temp, created.file), "utf8");
    assert.doesNotMatch(body, /^status:/m);

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

    const moved = JSON.parse(run(process.execPath, [tool, "move", created.id, "doing", "--json"], temp).stdout);
    assert.equal(moved.from, "backlog");
    assert.equal(moved.status, "doing");
    const listed = JSON.parse(run(process.execPath, [tool, "list", "--json"], temp).stdout);
    assert.deepEqual(listed.tasks.map(({ id, status, room }) => ({ id, status, room })), [
      { id: created.id, status: "doing", room: "bugfix" },
    ]);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});
