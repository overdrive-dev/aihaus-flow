#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const packageRoot = path.dirname(fileURLToPath(import.meta.url));
const setup = path.join(packageRoot, "setup.mjs");

function usage() {
  return [
    "Usage:",
    "  aihaus setup [--target <git-root>] [--json]",
    "  aihaus version [--json]",
    "  aihaus --help",
    "",
    "setup installs or updates the repository-local aihaus package and verifies it.",
  ].join("\n");
}

async function version(args) {
  const value = (await readFile(path.join(packageRoot, "VERSION"), "utf8")).trim();
  const json = args.includes("--json");
  if (args.some((arg) => arg !== "--json")) throw new Error("version accepts only --json");
  process.stdout.write(json ? `${JSON.stringify({ ok: true, version: value })}\n` : `${value}\n`);
}

function runSetup(args) {
  const result = spawnSync(process.execPath, [setup, ...args], {
    cwd: process.cwd(),
    stdio: "inherit",
  });
  if (result.error) throw result.error;
  process.exitCode = result.status ?? 1;
}

async function main() {
  const [command, ...args] = process.argv.slice(2);
  if (!command || command === "help" || command === "--help" || command === "-h") {
    process.stdout.write(`${usage()}\n`);
    return;
  }
  if (command === "setup") {
    runSetup(args);
    return;
  }
  if (command === "version") {
    await version(args);
    return;
  }
  throw new Error(`unknown command: ${command}\n\n${usage()}`);
}

try {
  await main();
} catch (error) {
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 2;
}
