#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { cp, mkdir, mkdtemp, readFile, rename, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const packageRoot = path.join(root, "pkg");
const npmCommand = process.platform === "win32" ? process.execPath : "npm";
const npmPrefix = process.platform === "win32"
  ? [path.join(path.dirname(process.execPath), "node_modules", "npm", "bin", "npm-cli.js")]
  : [];

function parseArgs(args) {
  const options = { tag: "", commit: "", out: path.join(root, "dist"), json: false };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--tag") options.tag = args[++index] ?? "";
    else if (arg === "--commit") options.commit = args[++index] ?? "";
    else if (arg === "--out") options.out = args[++index] ?? "";
    else if (arg === "--json") options.json = true;
    else throw new Error(`unknown option: ${arg}`);
  }
  if (!options.tag) throw new Error("--tag is required");
  if (!options.commit) throw new Error("--commit is required");
  if (!options.out) throw new Error("--out requires a path");
  return options;
}

function runNpmPack(source, destination) {
  const result = spawnSync(
    npmCommand,
    [...npmPrefix, "pack", source, "--pack-destination", destination, "--ignore-scripts", "--json"],
    { cwd: root, encoding: "utf8" },
  );
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`npm pack failed: ${(result.stderr || result.stdout).trim()}`);
  }
  const report = JSON.parse(result.stdout);
  if (!Array.isArray(report) || report.length !== 1 || !report[0].filename) {
    throw new Error("npm pack returned an unexpected report");
  }
  return report[0];
}

async function build(options) {
  const version = (await readFile(path.join(packageRoot, "VERSION"), "utf8")).trim();
  const manifest = JSON.parse(await readFile(path.join(packageRoot, "package.json"), "utf8"));
  const expectedTag = `v${version}`;
  if (manifest.version !== version) {
    throw new Error(`pkg/package.json version ${manifest.version} does not match VERSION ${version}`);
  }
  if (options.tag !== expectedTag) {
    throw new Error(`release tag must be ${expectedTag}; received ${options.tag}`);
  }
  if (!/^[0-9a-f]{40}$/i.test(options.commit)) {
    throw new Error("--commit must be a 40-character Git SHA");
  }

  const outputRoot = path.resolve(options.out);
  await mkdir(outputRoot, { recursive: true });
  const stagingRoot = await mkdtemp(path.join(os.tmpdir(), "aihaus-package-release-"));
  const stagedPackage = path.join(stagingRoot, "pkg");

  try {
    await cp(packageRoot, stagedPackage, { recursive: true });
    await writeFile(
      path.join(stagedPackage, "RELEASE.json"),
      `${JSON.stringify({
        schema: "aihaus.release.v1",
        distribution: "github-release",
        version,
        tag: options.tag,
        commit: options.commit.toLowerCase(),
      }, null, 2)}\n`,
      "utf8",
    );

    const packed = runNpmPack(stagedPackage, outputRoot);
    const generated = path.join(outputRoot, packed.filename);
    const asset = path.join(outputRoot, `aihaus-flow-${options.tag}.tgz`);
    await rename(generated, asset);

    const digest = createHash("sha256").update(await readFile(asset)).digest("hex");
    const checksum = `${asset}.sha256`;
    await writeFile(checksum, `${digest}  ${path.basename(asset)}\n`, "utf8");

    return {
      ok: true,
      version,
      tag: options.tag,
      commit: options.commit.toLowerCase(),
      asset,
      checksum,
      files: packed.files?.length ?? null,
      size: packed.size ?? null,
    };
  } finally {
    await rm(stagingRoot, { recursive: true, force: true });
  }
}

async function main() {
  try {
    const options = parseArgs(process.argv.slice(2));
    const result = await build(options);
    process.stdout.write(`${JSON.stringify(result, null, options.json ? 2 : 0)}\n`);
  } catch (error) {
    process.stderr.write(`${JSON.stringify({ ok: false, error: error.message })}\n`);
    process.exitCode = 2;
  }
}

await main();
