#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { access, cp, mkdir, readFile, realpath, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { assertPathWithin } from "./.aihaus/tools/path-safety.mjs";

const packageRoot = path.dirname(fileURLToPath(import.meta.url));
const sourceRoot = path.join(packageRoot, ".aihaus");
const managedDirectories = ["roles", "rooms", "contracts", "tools"];
const managedFiles = ["MAP.md", "conventions.md"];
const memoryFiles = [
  "project/README.md",
  "project/project.md",
  "project/business-rules.md",
  "project/decisions.md",
  "project/knowledge.md",
  "project/environment.md",
  "project/procedures.md",
  "project/deployment.md",
  "project/glossary.md",
  "kanban/README.md",
];
const kanbanStatuses = ["backlog", "todo", "doing", "review", "done"];
const startMarker = "<!-- AIHAUS:START -->";
const endMarker = "<!-- AIHAUS:END -->";

async function exists(target) {
  try {
    await access(target);
    return true;
  } catch {
    return false;
  }
}

function samePath(left, right) {
  return process.platform === "win32"
    ? left.toLowerCase() === right.toLowerCase()
    : left === right;
}

function gitTopLevel(target) {
  const result = spawnSync("git", ["-C", target, "rev-parse", "--show-toplevel"], {
    encoding: "utf8",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`target must be a git repository: ${(result.stderr || "").trim()}`);
  }
  return result.stdout.trim();
}

async function assertRepositoryRoot(target) {
  const [requested, top] = await Promise.all([realpath(target), realpath(gitTopLevel(target))]);
  if (!samePath(requested, top)) {
    throw new Error(`target must be the repository root: ${top}`);
  }
  return requested;
}

async function upsertManagedBlock(file, body) {
  const block = `${startMarker}\n${body.trim()}\n${endMarker}`;
  if (!(await exists(file))) {
    await writeFile(file, `${block}\n`, "utf8");
    return "created";
  }

  const current = await readFile(file, "utf8");
  const start = current.indexOf(startMarker);
  const end = current.indexOf(endMarker);
  if ((start >= 0) !== (end >= 0) || (start >= 0 && end < start)) {
    throw new Error(`refusing malformed managed block in ${file}`);
  }
  if (start < 0) {
    const separator = current.endsWith("\n") ? "\n" : "\n\n";
    await writeFile(file, `${current}${separator}${block}\n`, "utf8");
    return "appended";
  }

  const next = `${current.slice(0, start)}${block}${current.slice(end + endMarker.length)}`;
  if (next !== current) await writeFile(file, next, "utf8");
  return next === current ? "unchanged" : "updated";
}

async function install(target) {
  const repositoryRoot = await assertRepositoryRoot(path.resolve(target));
  const destinationRoot = path.join(repositoryRoot, ".aihaus");
  await mkdir(destinationRoot, { recursive: true });
  await assertPathWithin({ root: repositoryRoot, candidate: destinationRoot });

  for (const directory of managedDirectories) {
    const source = path.join(sourceRoot, directory);
    const destination = path.join(destinationRoot, directory);
    await assertPathWithin({ root: destinationRoot, candidate: destination });
    await rm(destination, { recursive: true, force: true });
    await cp(source, destination, { recursive: true });
  }
  for (const file of managedFiles) {
    const destination = path.join(destinationRoot, file);
    await assertPathWithin({ root: destinationRoot, candidate: destination });
    await cp(path.join(sourceRoot, file), destination);
  }

  const seeded = [];
  for (const relative of memoryFiles) {
    const source = path.join(sourceRoot, "memory", relative);
    const destination = path.join(destinationRoot, "memory", relative);
    await assertPathWithin({ root: destinationRoot, candidate: destination });
    if (!(await exists(destination))) {
      await mkdir(path.dirname(destination), { recursive: true });
      await cp(source, destination);
      seeded.push(`memory/${relative}`);
    }
  }
  for (const status of kanbanStatuses) {
    const destination = path.join(destinationRoot, "memory", "kanban", status);
    await assertPathWithin({ root: destinationRoot, candidate: destination });
    await mkdir(destination, { recursive: true });
  }
  const state = path.join(destinationRoot, "state");
  await assertPathWithin({ root: destinationRoot, candidate: state });
  await mkdir(state, { recursive: true });

  const router = await readFile(path.join(packageRoot, "adapters", "router.md"), "utf8");
  const adapters = {};
  for (const file of ["AGENTS.md", "CLAUDE.md"]) {
    const destination = path.join(repositoryRoot, file);
    await assertPathWithin({ root: repositoryRoot, candidate: destination });
    adapters[file] = await upsertManagedBlock(destination, router);
  }
  await assertPathWithin({ root: repositoryRoot, candidate: path.join(repositoryRoot, ".gitignore") });
  adapters[".gitignore"] = await upsertManagedBlock(
    path.join(repositoryRoot, ".gitignore"),
    ".aihaus/state/\n.aihaus/runtime/\n.aihaus/backups/",
  );

  return {
    ok: true,
    target: repositoryRoot,
    installed: [
      ...managedFiles.map((file) => `.aihaus/${file}`),
      ...managedDirectories.map((directory) => `.aihaus/${directory}/`),
    ],
    seeded,
    adapters,
  };
}

function parseArgs(args) {
  const options = { target: process.cwd(), json: false };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--target") options.target = args[++index] ?? "";
    else if (arg === "--json") options.json = true;
    else if (arg === "-h" || arg === "--help") options.help = true;
    else throw new Error(`unknown option: ${arg}`);
  }
  if (!options.target) throw new Error("--target requires a path");
  return options;
}

async function main() {
  try {
    const options = parseArgs(process.argv.slice(2));
    if (options.help) {
      process.stdout.write("Usage: node pkg/setup.mjs [--target <git-root>] [--json]\n");
      return;
    }
    const result = await install(options.target);
    process.stdout.write(`${JSON.stringify(result, null, options.json ? 2 : 0)}\n`);
  } catch (error) {
    process.stderr.write(`${JSON.stringify({ ok: false, error: error.message })}\n`);
    process.exitCode = 2;
  }
}

await main();
