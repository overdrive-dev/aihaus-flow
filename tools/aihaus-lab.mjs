#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import {
  access,
  cp,
  mkdir,
  readFile,
  realpath,
  rm,
} from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { assertPathWithin } from "../pkg/.aihaus/tools/path-safety.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const defaultLabRoot = path.join(root, ".aihaus-lab");
const labRoot = path.resolve(process.env.AIHAUS_LAB_ROOT || defaultLabRoot);
const projectRoot = path.join(labRoot, "consumer");
const fixtureRoot = path.join(root, "tools", "lab", "fixture");
const appBaseline = "aihaus-lab-app-baseline";
const readyBaseline = "aihaus-lab-ready-baseline";

async function exists(target) {
  try {
    await access(target);
    return true;
  } catch {
    return false;
  }
}

function run(command, args, { cwd = root, allowFailure = false } = {}) {
  const result = spawnSync(command, args, {
    cwd,
    encoding: "utf8",
    env: process.env,
  });
  if (result.error) throw result.error;
  if (!allowFailure && result.status !== 0) {
    throw new Error(
      `${command} ${args.join(" ")} failed (${result.status}): ${(result.stderr || result.stdout).trim()}`,
    );
  }
  return result;
}

async function assertOuterIgnore() {
  const ignore = await readFile(path.join(root, ".gitignore"), "utf8");
  if (!ignore.split(/\r?\n/).includes("/.aihaus-lab/")) {
    throw new Error("outer .gitignore must contain /.aihaus-lab/");
  }
}

async function assertLabProjectPath() {
  await mkdir(labRoot, { recursive: true });
  return assertPathWithin({ root: labRoot, candidate: projectRoot });
}

async function assertNestedRepository() {
  await assertLabProjectPath();
  if (!(await exists(path.join(projectRoot, ".git")))) {
    throw new Error(`lab consumer is not a nested git repository: ${projectRoot}`);
  }

  const nestedTop = run("git", ["rev-parse", "--show-toplevel"], { cwd: projectRoot }).stdout.trim();
  const outerTop = run("git", ["rev-parse", "--show-toplevel"], { cwd: root }).stdout.trim();
  const [nestedReal, projectReal, outerReal] = await Promise.all([
    realpath(nestedTop),
    realpath(projectRoot),
    realpath(outerTop),
  ]);

  const normalize = (value) => process.platform === "win32" ? value.toLowerCase() : value;
  if (normalize(nestedReal) !== normalize(projectReal)) {
    throw new Error(`nested git top-level mismatch: ${nestedReal} != ${projectReal}`);
  }
  if (normalize(nestedReal) === normalize(outerReal)) {
    throw new Error("lab consumer resolved to the outer repository");
  }
}

async function installCurrentPackage() {
  run(process.execPath, [path.join(root, "pkg", "setup.mjs"), "--target", projectRoot, "--json"]);
}

async function initialize({ force = false } = {}) {
  await assertOuterIgnore();
  await assertLabProjectPath();

  if (await exists(projectRoot)) {
    if (!force) {
      throw new Error("lab already exists; use init --force only when you intend to rebuild it");
    }
    await assertPathWithin({ root: labRoot, candidate: projectRoot });
    await rm(projectRoot, { recursive: true, force: true });
  }

  await cp(fixtureRoot, projectRoot, { recursive: true });
  run("git", ["init", "-b", "main"], { cwd: projectRoot });
  run("git", ["config", "user.name", "aihaus lab"], { cwd: projectRoot });
  run("git", ["config", "user.email", "aihaus-lab@local.invalid"], { cwd: projectRoot });
  run("git", ["add", "."], { cwd: projectRoot });
  run("git", ["commit", "-m", "lab: seed consumer"], { cwd: projectRoot });
  run("git", ["tag", "-f", appBaseline], { cwd: projectRoot });

  await installCurrentPackage();
  run("git", ["add", "."], { cwd: projectRoot });
  run("git", ["commit", "-m", "lab: install aihaus baseline"], { cwd: projectRoot });
  run("git", ["tag", "-f", readyBaseline], { cwd: projectRoot });

  return status();
}

async function reset() {
  await assertOuterIgnore();
  await assertNestedRepository();
  run("git", ["reset", "--hard", readyBaseline], { cwd: projectRoot });
  run("git", ["clean", "-fdx"], { cwd: projectRoot });
  await installCurrentPackage();
  return status();
}

async function verify() {
  await assertNestedRepository();
  const checks = run(process.execPath, ["--test", "eval/counter.test.mjs"], { cwd: projectRoot });
  const required = [
    ".aihaus/MAP.md",
    ".aihaus/contracts/harness.md",
    ".aihaus/contracts/evidence.md",
    ".aihaus/roles/orchestrator.md",
    ".aihaus/rooms/feature/CONTEXT.md",
  ];
  for (const relative of required) {
    if (!(await exists(path.join(projectRoot, relative)))) {
      throw new Error(`installed package missing ${relative}`);
    }
  }
  return {
    ok: true,
    projectRoot,
    command: `${process.execPath} --test eval/counter.test.mjs`,
    exit_code: checks.status,
  };
}

async function status() {
  if (!(await exists(projectRoot))) {
    return { ok: true, initialized: false, projectRoot };
  }
  await assertNestedRepository();
  const changes = run("git", ["status", "--short"], { cwd: projectRoot }).stdout
    .split(/\r?\n/)
    .filter(Boolean);
  return {
    ok: true,
    initialized: true,
    projectRoot,
    clean: changes.length === 0,
    changes,
    appBaseline,
    readyBaseline,
  };
}

function parseArgs(args) {
  const command = args[0] ?? "status";
  const options = { force: false, json: false };
  for (const arg of args.slice(1)) {
    if (arg === "--force") options.force = true;
    else if (arg === "--json") options.json = true;
    else throw new Error(`unknown lab option: ${arg}`);
  }
  return { command, options };
}

async function main() {
  try {
    const { command, options } = parseArgs(process.argv.slice(2));
    let result;
    if (command === "init") result = await initialize(options);
    else if (command === "reset") result = await reset();
    else if (command === "verify") result = await verify();
    else if (command === "status") result = await status();
    else throw new Error(`unknown lab command: ${command}`);
    process.stdout.write(`${JSON.stringify(result, null, options.json ? 2 : 0)}\n`);
  } catch (error) {
    process.stderr.write(`${JSON.stringify({ ok: false, error: error.message })}\n`);
    process.exitCode = 2;
  }
}

await main();
