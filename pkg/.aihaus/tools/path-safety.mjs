#!/usr/bin/env node

import { lstat, realpath } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

async function exists(target) {
  try {
    await lstat(target);
    return true;
  } catch {
    return false;
  }
}

export async function realpathAllowMissing(target) {
  let probe = path.resolve(target);
  const suffix = [];

  while (!(await exists(probe))) {
    const parent = path.dirname(probe);
    if (parent === probe) {
      throw new Error(`no existing ancestor for path: ${target}`);
    }
    suffix.unshift(path.basename(probe));
    probe = parent;
  }

  try {
    return path.resolve(await realpath(probe), ...suffix);
  } catch (error) {
    throw new Error(`cannot safely resolve existing path entry ${probe}: ${error.message}`);
  }
}

function samePath(left, right) {
  if (process.platform === "win32") {
    return left.toLowerCase() === right.toLowerCase();
  }
  return left === right;
}

export async function assertPathWithin({ root, candidate, allowRoot = false }) {
  const resolvedRoot = await realpathAllowMissing(root);
  const resolvedCandidate = await realpathAllowMissing(candidate);

  if (samePath(resolvedRoot, resolvedCandidate)) {
    if (!allowRoot) {
      throw new Error(`refusing operation on allowed root itself: ${resolvedRoot}`);
    }
    return { root: resolvedRoot, candidate: resolvedCandidate };
  }

  const relative = path.relative(resolvedRoot, resolvedCandidate);
  if (relative === "" || relative === ".." || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) {
    throw new Error(`refusing operation outside allowed root: ${resolvedCandidate}`);
  }

  return { root: resolvedRoot, candidate: resolvedCandidate };
}

function parseArgs(args) {
  const out = { root: null, candidate: null, allowRoot: false, json: false };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--root") out.root = args[++index] ?? null;
    else if (arg === "--candidate") out.candidate = args[++index] ?? null;
    else if (arg === "--allow-root") out.allowRoot = true;
    else if (arg === "--json") out.json = true;
    else throw new Error(`unknown argument: ${arg}`);
  }
  if (!out.root || !out.candidate) {
    throw new Error("--root and --candidate are required");
  }
  return out;
}

async function main() {
  try {
    const options = parseArgs(process.argv.slice(2));
    const result = await assertPathWithin(options);
    process.stdout.write(`${JSON.stringify({ ok: true, ...result })}\n`);
  } catch (error) {
    process.stderr.write(`${JSON.stringify({ ok: false, error: error.message })}\n`);
    process.exitCode = 2;
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url))) {
  await main();
}
