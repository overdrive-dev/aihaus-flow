#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { access, realpath } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

async function exists(target) {
  try {
    await access(target);
    return true;
  } catch {
    return false;
  }
}

function hasFlag(args, name) {
  return args.some((arg) => arg === name || arg.startsWith(`${name}=`));
}

export function withLocalDefaults(args, { repo, db }) {
  if (args.length === 0) return args;
  const [command, ...rest] = args;
  const repoCommands = new Set([
    "refresh",
    "query",
    "context",
    "impact",
    "status",
    "rule",
    "why",
    "rule-drift",
    "mark-stale",
    "obsidian-export",
  ]);
  const dbCommands = new Set([
    ...repoCommands,
    "callers",
    "gotchas",
    "milestone",
  ]);
  const defaults = [];
  if (repoCommands.has(command) && !hasFlag(rest, "--repo")) defaults.push("--repo", repo);
  if (dbCommands.has(command) && !hasFlag(rest, "--db")) defaults.push("--db", db);
  return [command, ...defaults, ...rest];
}

async function findRepositoryRoot(start) {
  const result = spawnSync("git", ["-C", start, "rev-parse", "--show-toplevel"], {
    encoding: "utf8",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error("run graph.mjs inside a git repository");
  return realpath(result.stdout.trim());
}

async function graphCommand(repo) {
  const executable = process.platform === "win32" ? "aih-graph.exe" : "aih-graph";
  const local = path.join(repo, ".aihaus", "bin", executable);
  if (await exists(local)) return local;
  return "aih-graph";
}

async function main() {
  try {
    const args = process.argv.slice(2);
    if (args.length === 0 || args.includes("--help") || args.includes("-h")) {
      process.stdout.write(
        "Usage: node .aihaus/tools/graph.mjs <aih-graph-command> [args]\n" +
        "Adds repository-local --repo and --db defaults. Consent remains explicit.\n",
      );
      return;
    }
    const repo = await findRepositoryRoot(process.cwd());
    const db = path.join(repo, ".aihaus", "state", "aih-graph.db");
    const command = await graphCommand(repo);
    const result = spawnSync(command, withLocalDefaults(args, { repo, db }), { stdio: "inherit" });
    if (result.error) {
      if (result.error.code === "ENOENT") {
        throw new Error("aih-graph not found; place the release binary in .aihaus/bin or on PATH");
      }
      throw result.error;
    }
    process.exitCode = result.status ?? 1;
  } catch (error) {
    process.stderr.write(`${JSON.stringify({ ok: false, error: error.message })}\n`);
    process.exitCode = 2;
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url))) {
  await main();
}
