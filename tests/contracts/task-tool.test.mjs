import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { linkSync } from "node:fs";
import { mkdtemp, readdir, readFile, rm, symlink, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { assertPathWithin } from "../../pkg/.aihaus/tools/path-safety.mjs";

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
    await writeFile(path.join(temp, "evidence.json"), JSON.stringify({
      schema: "aihaus.evidence.v1",
      verdict: "PASS",
      acceptance: [{
        criterion: "`node --test` exits 0.", status: "satisfied", executable: true,
        evidence: [{ rung: "ran", source: "tool", command: "node --test", exit_code: 0 }],
      }],
    }));
    await writeFile(path.join(temp, reviewed.file), (await readFile(path.join(temp, reviewed.file), "utf8"))
      .replace("- [ ] `node --test`", "- [x] `node --test`")
      .replace("## Evidence\n", "## Evidence\n\nArtifact: evidence.json\n"));
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
    await assertPathWithin({ root: os.tmpdir(), candidate: temp });
    await rm(temp, { recursive: true, force: true });
  }
});

test("done requires matching PASS evidence and resolved business-rule gaps", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "aihaus-task-done-"));
  const outside = await mkdtemp(path.join(os.tmpdir(), "aihaus-task-evidence-"));
  try {
    run("git", ["init", "-b", "main"], temp);
    run(process.execPath, [setup, "--target", temp], temp);
    const tool = path.join(temp, ".aihaus", "tools", "task.mjs");
    const created = JSON.parse(run(process.execPath, [tool, "create", "--title", "Complete outcome", "--room", "feature"], temp).stdout);
    let file = path.join(temp, created.file);
    const prepared = (await readFile(file, "utf8"))
      .replace("- [ ] Define executable acceptance evidence.", "- [x] Feature works.")
      .replace("## Owned files\n", "## Owned files\n\n- src/feature.mjs\n")
      .replace("## Log\n", "## Log\n\nImplementation awaits verification.\n")
      .replace("## Evidence\n", "## Evidence\n\nBLOCKED: no checks ran.\n");
    await writeFile(file, prepared);
    runFailure(process.execPath, [tool, "move", created.id, "done"], temp);
    const review = JSON.parse(run(process.execPath, [tool, "move", created.id, "review"], temp).stdout);
    file = path.join(temp, review.file);
    const ready = prepared.replace("BLOCKED: no checks ran.", "Artifact: evidence.json");
    await writeFile(file, ready);
    const pass = {
      schema: "aihaus.evidence.v1", verdict: "PASS",
      acceptance: [{ criterion: "Feature works.", status: "satisfied", executable: true,
        evidence: [{ rung: "ran", source: "tool", command: "node --test", exit_code: 0 }] }],
    };
    const save = (document) => writeFile(path.join(temp, "evidence.json"), JSON.stringify(document));
    runFailure(process.execPath, [tool, "move", created.id, "done"], temp);
    await writeFile(path.join(temp, "evidence.json"), "{invalid");
    runFailure(process.execPath, [tool, "move", created.id, "done"], temp);
    for (const document of [
      { ...pass, verdict: "BLOCKED" },
      { ...pass, schema: "wrong" },
      { ...pass, acceptance: [] },
      { ...pass, acceptance: [{ ...pass.acceptance[0], criterion: "A different feature works." }] },
      { ...pass, acceptance: [pass.acceptance[0], pass.acceptance[0]] },
      { ...pass, acceptance: [{ ...pass.acceptance[0], evidence: [{ rung: "written" }] }] },
    ]) {
      await save(document);
      runFailure(process.execPath, [tool, "move", created.id, "done"], temp);
    }
    await save(pass);
    await writeFile(path.join(outside, "evidence.json"), JSON.stringify(pass));
    await symlink(outside, path.join(temp, "external"), process.platform === "win32" ? "junction" : "dir");
    for (const body of [
      ready.replace("- [x] Feature works.", "- [ ] Feature works."),
      ready.replace("- [x] Feature works.", "- [x] Feature works.\n- [x] Another criterion."),
      ready.replace("- [x] Feature works.", "- [x] Feature works.\n- [x] Feature works."),
      ready.replace("Artifact: evidence.json", `Artifact: ${path.relative(temp, path.join(outside, "evidence.json"))}`),
      ready.replace("Artifact: evidence.json", `Artifact: ${path.join(temp, "evidence.json")}`),
      ready.replace("Artifact: evidence.json", "Artifact: external/evidence.json"),
      ready.replace("Artifact: evidence.json", "Artifact: evidence.json\nArtifact: evidence.json"),
    ]) {
      await writeFile(file, body);
      runFailure(process.execPath, [tool, "move", created.id, "done"], temp);
    }
    await writeFile(file, ready);
    const asked = JSON.parse(run(process.execPath, [tool, "question", created.id, "--text", "Can this delete client data?"], temp).stdout);
    runFailure(process.execPath, [tool, "move", created.id, "done"], temp);
    run(process.execPath, [tool, "answer", created.id, "--question", asked.question, "--text", "No", "--draft-rule", "Preserve client data."], temp);
    await writeFile(file, (await readFile(file, "utf8")).replaceAll("\n", "\r\n"));
    assert.equal(JSON.parse(run(process.execPath, [tool, "move", created.id, "done"], temp).stdout).status, "done");
  } finally {
    await assertPathWithin({ root: os.tmpdir(), candidate: temp });
    await rm(temp, { recursive: true, force: true });
    await assertPathWithin({ root: os.tmpdir(), candidate: outside });
    await rm(outside, { recursive: true, force: true });
  }
});

test("question answers accept CRLF tasks without changing unrelated content", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "aihaus-task-crlf-"));
  try {
    run("git", ["init", "-b", "main"], temp);
    run(process.execPath, [setup, "--target", temp], temp);
    const tool = path.join(temp, ".aihaus", "tools", "task.mjs");
    const created = JSON.parse(run(process.execPath, [tool, "create", "--title", "Windows task", "--room", "feature"], temp).stdout);
    const asked = JSON.parse(run(process.execPath, [tool, "question", created.id, "--text", "Keep behavior?"], temp).stdout);
    const file = path.join(temp, created.file);
    const body = (await readFile(file, "utf8")).replaceAll("\n", "\r\n");
    await writeFile(file, body);
    const answer = "Keep literal $& and $' tokens.";
    const rule = "Preserve $` and $$ in customer text.";
    run(process.execPath, [tool, "answer", created.id, "--question", asked.question, "--text", answer, "--draft-rule", rule], temp);
    assert.equal(await readFile(file, "utf8"), body.replace("Answer: pending", () => `Answer: ${answer}`).replace("Draft rule: pending", () => `Draft rule: ${rule}`));
  } finally {
    await assertPathWithin({ root: os.tmpdir(), candidate: temp });
    await rm(temp, { recursive: true, force: true });
  }
});

async function withRepo(prefix, callback) {
  const temp = await mkdtemp(path.join(os.tmpdir(), prefix));
  try {
    run("git", ["init", "-b", "main"], temp);
    run(process.execPath, [setup, "--target", temp], temp);
    await callback(temp, path.join(temp, ".aihaus", "tools", "task.mjs"));
  } finally {
    await assertPathWithin({ root: os.tmpdir(), candidate: temp });
    await rm(temp, { recursive: true, force: true });
  }
}

test("multi-line titles cannot inject task sections", () => withRepo("aihaus-task-title-", async (temp, tool) => {
  const title = "Fix login\n## Acceptance\n- [x] Works.\n## Owned files\n- src/a.mjs\n## Context\nctx\n## Log\nlog\n## Evidence\nok";
  const created = JSON.parse(run(process.execPath, [tool, "create", "--title", title, "--room", "feature"], temp).stdout);
  const body = await readFile(path.join(temp, created.file), "utf8");
  assert.match(body, /^# Goal\n\nFix login ## Acceptance - \[x\] Works\. ## Owned files .* ## Evidence ok\n\n## Acceptance\n/m);
  assert.equal(body.match(/^## Acceptance$/gm).length, 1);
  assert.match(runFailure(process.execPath, [tool, "move", created.id, "todo"], temp).stderr, /fill: Acceptance, Owned files/);
  assert.match(
    runFailure(process.execPath, [tool, "move", created.id, "doing"], temp).stderr,
    /fill: Acceptance, Owned files, Context or Log/,
  );
}));

test("identity fields are read only from leading frontmatter", () => withRepo("aihaus-task-front-", async (temp, tool) => {
  const injected = JSON.parse(
    run(process.execPath, [tool, "create", "--title", "Sync accounts\nexternal_id: NOR-777", "--room", "feature"], temp).stdout,
  );
  const injectedFile = path.join(temp, injected.file);
  await writeFile(
    injectedFile,
    (await readFile(injectedFile, "utf8")).replace("## Context\n", "## Context\n\nexternal_id: NOR-999\nroom: bugfix\n"),
  );
  const backlog = path.join(temp, ".aihaus", "memory", "kanban", "backlog");
  await writeFile(
    path.join(backlog, "manual.md"),
    "\uFEFF---\r\nid: T-manual\r\nroom: feature\r\nexternal_id:\r\ncreated: 2026-01-01T00:00:00.000Z\r\n---\r\n\r\n# Goal\r\n\r\nManual\r\n",
  );
  const listed = JSON.parse(run(process.execPath, [tool, "list"], temp).stdout).tasks;
  assert.deepEqual(listed.find((task) => task.id === injected.id), {
    id: injected.id, title: "Sync accounts external_id: NOR-777", room: "feature", status: "backlog", file: injected.file,
  });
  assert.deepEqual(listed.find((task) => task.id === "T-manual"), {
    id: "T-manual", title: "Manual", room: "feature", status: "backlog", file: path.relative(temp, path.join(backlog, "manual.md")),
  });
  const external = JSON.parse(
    run(process.execPath, [tool, "create", "--title", "Real external", "--room", "feature", "--external-id", "NOR-777"], temp).stdout,
  );
  assert.equal(external.external_id, "NOR-777");
}));

test("missing status folders read as empty and are recreated on write", () => withRepo("aihaus-task-dirs-", async (temp, tool) => {
  const kanban = path.join(temp, ".aihaus", "memory", "kanban");
  await rm(path.join(kanban, "todo"), { recursive: true, force: true });
  assert.deepEqual(JSON.parse(run(process.execPath, [tool, "list"], temp).stdout), { ok: true, tasks: [] });
  for (const status of ["backlog", "todo", "doing", "review", "done"]) {
    await rm(path.join(kanban, status), { recursive: true, force: true });
  }
  const created = JSON.parse(run(process.execPath, [tool, "create", "--title", "Fresh clone", "--room", "feature"], temp).stdout);
  const file = path.join(temp, created.file);
  await writeFile(file, (await readFile(file, "utf8"))
    .replace("- [ ] Define executable acceptance evidence.", "- [ ] Clone works.")
    .replace("## Owned files\n", "## Owned files\n\n- src/clone.mjs\n"));
  const moved = JSON.parse(run(process.execPath, [tool, "move", created.id, "todo"], temp).stdout);
  assert.equal(moved.status, "todo");
  assert.match(await readFile(path.join(temp, moved.file), "utf8"), /- src\/clone\.mjs/);
}));

test("done accepts a BOM-prefixed evidence artifact", () => withRepo("aihaus-task-bom-", async (temp, tool) => {
  const created = JSON.parse(run(process.execPath, [tool, "create", "--title", "BOM evidence", "--room", "feature"], temp).stdout);
  const file = path.join(temp, created.file);
  await writeFile(file, (await readFile(file, "utf8"))
    .replace("- [ ] Define executable acceptance evidence.", "- [x] Feature works.")
    .replace("## Owned files\n", "## Owned files\n\n- src/feature.mjs\n")
    .replace("## Log\n", "## Log\n\nDone.\n")
    .replace("## Evidence\n", "## Evidence\n\nArtifact: evidence.json\n"));
  await writeFile(path.join(temp, "evidence.json"), `\uFEFF${JSON.stringify({
    schema: "aihaus.evidence.v1", verdict: "PASS",
    acceptance: [{ criterion: "Feature works.", status: "satisfied", executable: true,
      evidence: [{ rung: "ran", source: "tool", command: "node --test", exit_code: 0 }] }],
  })}`);
  assert.equal(JSON.parse(run(process.execPath, [tool, "move", created.id, "done"], temp).stdout).status, "done");
}));

test("non-ASCII titles fall back to the task slug", () => withRepo("aihaus-task-slug-", async (temp, tool) => {
  const created = JSON.parse(run(process.execPath, [tool, "create", "--title", "Исправить вход", "--room", "feature"], temp).stdout);
  assert.match(created.id, /^T-\d{6}-[0-9a-f]{6}-task$/);
  assert.match(await readFile(path.join(temp, created.file), "utf8"), /^# Goal\n\nИсправить вход$/m);
  assert.match(runFailure(process.execPath, [tool, "create", "--title", " \n ", "--room", "feature"], temp).stderr, /--title is required/);
}));

test("question and answer replace hard-linked task files without touching other links", (t) => withRepo("aihaus-task-link-", async (temp, tool) => {
  const outside = await mkdtemp(path.join(os.tmpdir(), "aihaus-task-link-out-"));
  try {
    const created = JSON.parse(run(process.execPath, [tool, "create", "--title", "Linked task", "--room", "feature"], temp).stdout);
    const file = path.join(temp, created.file);
    const linked = path.join(outside, "linked.md");
    try {
      linkSync(file, linked);
    } catch (error) {
      t.skip(`hard links unavailable: ${error.code}`);
      return;
    }
    const original = await readFile(linked);
    const asked = JSON.parse(run(process.execPath, [tool, "question", created.id, "--text", "Shared file?"], temp).stdout);
    run(process.execPath, [tool, "answer", created.id, "--question", asked.question, "--text", "No", "--draft-rule", "Keep links."], temp);
    const body = await readFile(file, "utf8");
    assert.match(body, /Question: Shared file\?/);
    assert.match(body, /Draft rule: Keep links\./);
    assert.deepEqual(await readFile(linked), original);
    assert.deepEqual((await readdir(path.dirname(file))).filter((name) => name.endsWith(".tmp")), []);
  } finally {
    await assertPathWithin({ root: os.tmpdir(), candidate: outside });
    await rm(outside, { recursive: true, force: true });
  }
}));
