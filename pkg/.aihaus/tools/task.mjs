#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { access, readdir, readFile, realpath, rename, writeFile } from "node:fs/promises";
import path from "node:path";
import { assertPathWithin } from "./path-safety.mjs";

export const statuses = ["backlog", "todo", "doing", "review", "done"];

async function exists(target) {
  try {
    await access(target);
    return true;
  } catch {
    return false;
  }
}

function gitRoot() {
  const result = spawnSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf8" });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error("run task.mjs inside a git repository");
  return result.stdout.trim();
}

function slug(value) {
  const normalized = value
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "")
    .slice(0, 48);
  if (!normalized) throw new Error("task title must contain letters or numbers");
  return normalized;
}

function dateStamp(now = new Date()) {
  return now.toISOString().slice(2, 10).replaceAll("-", "");
}

async function taskBoard() {
  const repo = await realpath(gitRoot());
  const board = path.join(repo, ".aihaus", "memory", "kanban");
  if (!(await exists(board))) throw new Error("aihaus file kanban is not installed");
  await assertPathWithin({ root: repo, candidate: board });
  return { repo, board };
}

async function roomExists(repo, room) {
  return exists(path.join(repo, ".aihaus", "rooms", room, "CONTEXT.md"));
}

async function createTask({ title, room }) {
  const { repo, board } = await taskBoard();
  if (!title) throw new Error("create requires --title");
  if (!room || !(await roomExists(repo, room))) throw new Error(`unknown room: ${room || "(missing)"}`);
  const id = `T-${dateStamp()}-${randomBytes(3).toString("hex")}-${slug(title)}`;
  const destination = path.join(board, "backlog", `${id}.md`);
  await assertPathWithin({ root: board, candidate: destination });
  const created = new Date().toISOString();
  const body = `---\nid: ${id}\nroom: ${room}\ncreated: ${created}\n---\n\n# Goal\n\n${title.trim()}\n\n## Acceptance\n\n- [ ] Define executable acceptance evidence.\n\n## Context\n\n## Owned files\n\n## Business-rule gaps\n\n## Log\n\n## Evidence\n`;
  await writeFile(destination, body, { encoding: "utf8", flag: "wx" });
  return { ok: true, id, status: "backlog", file: path.relative(repo, destination) };
}

async function tasks() {
  const { repo, board } = await taskBoard();
  const result = [];
  for (const status of statuses) {
    const directory = path.join(board, status);
    for (const file of await readdir(directory)) {
      if (!file.endsWith(".md")) continue;
      const full = path.join(directory, file);
      const content = await readFile(full, "utf8");
      const id = content.match(/^id:\s*(.+)$/m)?.[1]?.trim() || path.basename(file, ".md");
      const room = content.match(/^room:\s*(.+)$/m)?.[1]?.trim() || null;
      const title = content.match(/^# Goal\s*\r?\n\s*\r?\n([^\r\n]+)/m)?.[1]?.trim() || id;
      result.push({ id, title, room, status, file: path.relative(repo, full) });
    }
  }
  return result.sort((left, right) => left.id.localeCompare(right.id));
}

async function locateTask(id) {
  if (!id) throw new Error("task ID is required");
  const { repo, board } = await taskBoard();
  const matches = (await tasks()).filter((task) => task.id === id || path.basename(task.file, ".md") === id);
  if (matches.length !== 1) throw new Error(`expected exactly one task for ${id}; found ${matches.length}`);
  const file = path.join(repo, matches[0].file);
  await assertPathWithin({ root: board, candidate: file });
  return { repo, board, file, task: matches[0] };
}

async function moveTask(id, status) {
  if (!id) throw new Error("move requires a task ID");
  if (!statuses.includes(status)) throw new Error(`invalid status: ${status}`);
  const { repo, board, file: source, task } = await locateTask(id);
  const destination = path.join(board, status, path.basename(source));
  await assertPathWithin({ root: board, candidate: source });
  await assertPathWithin({ root: board, candidate: destination });
  if (await exists(destination)) throw new Error(`destination already exists: ${path.relative(repo, destination)}`);
  await rename(source, destination);
  return { ok: true, id: task.id, from: task.status, status, file: path.relative(repo, destination) };
}

function oneLine(value, field) {
  const normalized = value?.replace(/\s+/g, " ").trim();
  if (!normalized) throw new Error(`${field} is required`);
  return normalized;
}

async function addQuestion(id, text) {
  const { repo, file, task } = await locateTask(id);
  const question = oneLine(text, "--text");
  const questionId = `Q-${randomBytes(3).toString("hex")}`;
  let content = await readFile(file, "utf8");
  const heading = "## Business-rule gaps";
  if (!content.includes(heading)) content = `${content.trimEnd()}\n\n${heading}\n`;
  const start = content.indexOf(heading) + heading.length;
  const nextHeading = content.indexOf("\n## ", start);
  const insertion = `\n\n### ${questionId}\n\nQuestion: ${question}\n\nAnswer: pending\n\nDraft rule: pending\n`;
  content = nextHeading < 0
    ? `${content.trimEnd()}${insertion}`
    : `${content.slice(0, nextHeading).trimEnd()}${insertion}\n${content.slice(nextHeading + 1)}`;
  await writeFile(file, content, "utf8");
  return { ok: true, id: task.id, question: questionId, file: path.relative(repo, file) };
}

async function answerQuestion(id, questionId, answerText, draftRuleText) {
  const { repo, file, task } = await locateTask(id);
  const question = oneLine(questionId, "--question");
  const answer = oneLine(answerText, "--text");
  const draftRule = oneLine(draftRuleText, "--draft-rule");
  const content = await readFile(file, "utf8");
  const start = content.indexOf(`### ${question}\n`);
  if (start < 0) throw new Error(`question not found: ${question}`);
  const next = content.indexOf("\n### ", start + 4);
  const end = next < 0 ? content.length : next;
  const block = content.slice(start, end);
  if (!/^Answer: pending$/m.test(block)) throw new Error(`question already answered: ${question}`);
  const answered = block
    .replace(/^Answer: pending$/m, `Answer: ${answer}`)
    .replace(/^Draft rule: pending$/m, `Draft rule: ${draftRule}`);
  await writeFile(file, `${content.slice(0, start)}${answered}${content.slice(end)}`, "utf8");
  return { ok: true, id: task.id, question, draft_rule: draftRule, promoted: false, file: path.relative(repo, file) };
}

function parseArgs(args) {
  const command = args.shift() || "list";
  const options = {
    command,
    json: false,
    title: null,
    room: null,
    text: null,
    question: null,
    draftRule: null,
    positionals: [],
  };
  while (args.length) {
    const arg = args.shift();
    if (arg === "--json") options.json = true;
    else if (arg === "--title") options.title = args.shift() ?? null;
    else if (arg === "--room") options.room = args.shift() ?? null;
    else if (arg === "--text") options.text = args.shift() ?? null;
    else if (arg === "--question") options.question = args.shift() ?? null;
    else if (arg === "--draft-rule") options.draftRule = args.shift() ?? null;
    else options.positionals.push(arg);
  }
  return options;
}

async function main() {
  try {
    const options = parseArgs(process.argv.slice(2));
    let result;
    if (options.command === "create") result = await createTask(options);
    else if (options.command === "move") result = await moveTask(options.positionals[0], options.positionals[1]);
    else if (options.command === "question") result = await addQuestion(options.positionals[0], options.text);
    else if (options.command === "answer") {
      result = await answerQuestion(
        options.positionals[0],
        options.question,
        options.text,
        options.draftRule,
      );
    }
    else if (options.command === "list") result = { ok: true, tasks: await tasks() };
    else throw new Error(`unknown command: ${options.command}`);
    process.stdout.write(`${JSON.stringify(result, null, options.json ? 2 : 0)}\n`);
  } catch (error) {
    process.stderr.write(`${JSON.stringify({ ok: false, error: error.message })}\n`);
    process.exitCode = 2;
  }
}

await main();
