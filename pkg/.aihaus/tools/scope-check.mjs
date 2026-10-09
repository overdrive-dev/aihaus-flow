#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { realpathSync } from "node:fs";
import { realpath } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { assertPathWithin } from "./path-safety.mjs";

function git(args, cwd, { nul = false } = {}) {
  const result = spawnSync("git", args, { cwd, encoding: "utf8", maxBuffer: 16 * 1024 * 1024 });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`git ${args.join(" ")} failed: ${result.stderr.trim()}`);
  return result.stdout.split(nul ? "\0" : /\r?\n/).filter(Boolean);
}

function normalize(relative) {
  return relative.replaceAll("\\", "/").replace(/^\.\//, "");
}

export function isAllowed(file, allow) {
  const candidate = normalize(file);
  return allow.some((entry) => {
    const rule = normalize(entry).replace(/\/$/, "");
    return candidate === rule || candidate.startsWith(`${rule}/`);
  });
}

async function changedFiles(repo, base) {
  const groups = [
    git(["diff", "--no-renames", "--name-only", "-z"], repo, { nul: true }),
    git(["diff", "--cached", "--no-renames", "--name-only", "-z"], repo, { nul: true }),
    git(["ls-files", "--others", "--exclude-standard", "-z"], repo, { nul: true }),
  ];
  if (base) {
    git(["rev-parse", "--verify", `${base}^{commit}`], repo);
    groups.push(git(["diff", "--no-renames", "--name-only", "-z", `${base}...HEAD`, "--"], repo, { nul: true }));
  }
  return [...new Set(groups.flat().map(normalize))].sort();
}

async function validateAllowlist(repo, entries) {
  if (entries.length === 0) throw new Error("at least one --allow path is required");
  for (const entry of entries) {
    if (!entry || path.isAbsolute(entry)) throw new Error(`--allow must be repository-relative: ${entry}`);
    await assertPathWithin({ root: repo, candidate: path.join(repo, entry) });
  }
}

function parseArgs(args) {
  const options = { allow: [], json: false, base: null };
  for (let index = 0; index < args.length; index += 1) {
    if (args[index] === "--allow") options.allow.push(args[++index] ?? "");
    else if (args[index] === "--base") options.base = args[++index] ?? "";
    else if (args[index] === "--json") options.json = true;
    else throw new Error(`unknown option: ${args[index]}`);
  }
  if (options.base !== null && (!options.base || options.base.startsWith("-"))) {
    throw new Error(`--base must name a commit: ${options.base}`);
  }
  return options;
}

async function main() {
  try {
    const options = parseArgs(process.argv.slice(2));
    const repo = await realpath(git(["rev-parse", "--show-toplevel"], process.cwd())[0]);
    await validateAllowlist(repo, options.allow);
    const changed = await changedFiles(repo, options.base);
    const outside = changed.filter((file) => !isAllowed(file, options.allow));
    const result = { ok: outside.length === 0, changed, allow: options.allow, outside };
    process.stdout.write(`${JSON.stringify(result, null, options.json ? 2 : 0)}\n`);
    if (outside.length) process.exitCode = 2;
  } catch (error) {
    process.stderr.write(`${JSON.stringify({ ok: false, error: error.message })}\n`);
    process.exitCode = 2;
  }
}

function isEntryPoint() {
  try {
    return realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

if (isEntryPoint()) {
  await main();
}
