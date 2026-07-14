#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { realpath } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { assertPathWithin } from "./path-safety.mjs";

function git(args, cwd) {
  const result = spawnSync("git", args, { cwd, encoding: "utf8" });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`git ${args.join(" ")} failed: ${result.stderr.trim()}`);
  return result.stdout.split(/\r?\n/).filter(Boolean);
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

async function changedFiles(repo) {
  const groups = [
    git(["diff", "--name-only", "--diff-filter=ACMR"], repo),
    git(["diff", "--cached", "--name-only", "--diff-filter=ACMR"], repo),
    git(["ls-files", "--others", "--exclude-standard"], repo),
  ];
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
  const options = { allow: [], json: false };
  for (let index = 0; index < args.length; index += 1) {
    if (args[index] === "--allow") options.allow.push(args[++index] ?? "");
    else if (args[index] === "--json") options.json = true;
    else throw new Error(`unknown option: ${args[index]}`);
  }
  return options;
}

async function main() {
  try {
    const options = parseArgs(process.argv.slice(2));
    const repo = await realpath(git(["rev-parse", "--show-toplevel"], process.cwd())[0]);
    await validateAllowlist(repo, options.allow);
    const changed = await changedFiles(repo);
    const outside = changed.filter((file) => !isAllowed(file, options.allow));
    const result = { ok: outside.length === 0, changed, allow: options.allow, outside };
    process.stdout.write(`${JSON.stringify(result, null, options.json ? 2 : 0)}\n`);
    if (outside.length) process.exitCode = 2;
  } catch (error) {
    process.stderr.write(`${JSON.stringify({ ok: false, error: error.message })}\n`);
    process.exitCode = 2;
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url))) {
  await main();
}
