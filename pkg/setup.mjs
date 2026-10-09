#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { cp, lstat, mkdir, readFile, readdir, realpath, rm, rmdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { assertPathWithin } from "./.aihaus/tools/path-safety.mjs";

const packageRoot = path.dirname(fileURLToPath(import.meta.url));
const sourceCheckoutRoot = path.resolve(packageRoot, "..");
const sourceRoot = path.join(packageRoot, ".aihaus");
const managedDirectories = ["roles", "rooms", "contracts", "tools"];
const managedFiles = ["MAP.md", "conventions.md", "REFRESH.md"];
const metadataFiles = ["VERSION"];
const minimumNodeMajor = 22;
const retiredArtifacts = [
  ".aih-graph-consent",
  ".aihaus/INIT.md",
  ".aihaus/bin/aih-graph",
  ".aihaus/bin/aih-graph.exe",
  ".aihaus/bin/aih-graph.install.json",
  ".aihaus/state/aih-graph.db",
  ".aihaus/state/aih-graph.db-shm",
  ".aihaus/state/aih-graph.db-wal",
  ".aihaus/state/aih-graph.db-journal",
];
const retiredHostSkills = [
  ".claude/skills/aih-init/SKILL.md",
  ".agents/skills/aih-init/SKILL.md",
];
const requiredSurface = [
  ".aihaus/VERSION",
  ".aihaus/MAP.md",
  ".aihaus/REFRESH.md",
  ".aihaus/contracts/harness.md",
  ".aihaus/contracts/project-bootstrap.md",
  ".aihaus/roles/orchestrator.md",
  ".aihaus/rooms/feature/CONTEXT.md",
  ".aihaus/tools/refresh.mjs",
];
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
const requiredDirectories = [
  ...kanbanStatuses.map((status) => `.aihaus/memory/kanban/${status}`),
  ".aihaus/state",
];
const startMarker = "<!-- AIHAUS:START -->";
const endMarker = "<!-- AIHAUS:END -->";
const hostAdapterMarker = "<!-- AIHAUS-MANAGED: repository-local-host-adapter-v1 -->";
const hostSkillAdapters = [
  {
    host: "claudeCode",
    source: path.join(packageRoot, "adapters", "claude", "skills", "aih-refresh", "SKILL.md"),
    relative: ".claude/skills/aih-refresh/SKILL.md",
    capability: {
      invoke: "/aih-refresh",
      menu: "/",
      restartMayBeRequired: true,
    },
  },
  {
    host: "codex",
    source: path.join(packageRoot, "adapters", "codex", "skills", "aih-refresh", "SKILL.md"),
    relative: ".agents/skills/aih-refresh/SKILL.md",
    capability: {
      invoke: "$aih-refresh",
      menu: "/skills",
      customSlash: false,
      restartMayBeRequired: true,
    },
  },
];

async function exists(target) {
  try {
    await lstat(target);
    return true;
  } catch {
    return false;
  }
}

async function entryKind(target) {
  try {
    const info = await lstat(target);
    if (info.isSymbolicLink()) return "symbolic-link";
    if (info.isFile()) return "file";
    if (info.isDirectory()) return "directory";
    return "other";
  } catch (error) {
    if (error.code === "ENOENT") return "missing";
    throw error;
  }
}

function digest(value) {
  return createHash("sha256").update(value).digest("hex");
}

async function treeManifest(root, relative = "") {
  const entries = await readdir(root, { withFileTypes: true });
  const manifest = [];
  for (const entry of entries.sort((left, right) => left.name.localeCompare(right.name))) {
    const childRelative = relative ? `${relative}/${entry.name}` : entry.name;
    const child = path.join(root, entry.name);
    if (entry.isDirectory()) {
      manifest.push({ path: childRelative, type: "directory" });
      manifest.push(...await treeManifest(child, childRelative));
    } else if (entry.isFile()) {
      manifest.push({ path: childRelative, type: "file", sha256: digest(await readFile(child)) });
    } else {
      throw new Error(`refusing non-regular entry in managed directory: ${child}`);
    }
  }
  return manifest;
}

async function filesEqual(source, destination) {
  const [left, right] = await Promise.all([readFile(source), readFile(destination)]);
  return left.equals(right);
}

async function directoriesEqual(source, destination) {
  const [left, right] = await Promise.all([treeManifest(source), treeManifest(destination)]);
  return JSON.stringify(left) === JSON.stringify(right);
}

async function assertDirectoryPath(root, directory) {
  const checked = await assertPathWithin({ root, candidate: directory, allowRoot: true });
  let ancestor = checked.candidate;
  while (await entryKind(ancestor) === "missing") ancestor = path.dirname(ancestor);
  if (await entryKind(ancestor) !== "directory") {
    throw new Error(`refusing non-directory parent: ${ancestor}`);
  }
}

async function validatePackageSource() {
  for (const directory of managedDirectories) await treeManifest(path.join(sourceRoot, directory));
  const files = new Set([
    ...managedFiles.map((file) => path.join(sourceRoot, file)),
    ...metadataFiles.map((file) => path.join(packageRoot, file)),
    ...memoryFiles.map((file) => path.join(sourceRoot, "memory", file)),
    ...requiredSurface.map((file) => path.join(packageRoot, file === ".aihaus/VERSION" ? "VERSION" : file)),
    path.join(packageRoot, "adapters", "router.md"),
    ...hostSkillAdapters.map((adapter) => adapter.source),
  ]);
  for (const file of files) {
    if (await entryKind(file) !== "file") throw new Error(`missing or non-regular package source: ${file}`);
    await readFile(file);
  }
}

async function planManagedFile({ source, destination, root, check, force }) {
  await assertPathWithin({ root, candidate: destination });
  await assertDirectoryPath(root, path.dirname(destination));
  const kind = await entryKind(destination);
  if (!["missing", "file"].includes(kind)) {
    throw new Error(`refusing non-regular managed file: ${destination}`);
  }
  if (kind === "file" && (await lstat(destination)).nlink > 1) {
    throw new Error(`refusing hard-linked managed file: ${destination}`);
  }
  const status = kind === "missing"
    ? "created"
    : !force && await filesEqual(source, destination) ? "unchanged" : "refreshed";
  if (!check && status !== "unchanged") {
    await mkdir(path.dirname(destination), { recursive: true });
    await cp(source, destination, { force: true });
  }
  return status;
}

async function planManagedDirectory({ source, destination, root, check, force }) {
  await assertPathWithin({ root, candidate: destination });
  const kind = await entryKind(destination);
  if (!["missing", "directory"].includes(kind)) {
    throw new Error(`refusing non-directory managed surface: ${destination}`);
  }
  const status = kind === "missing"
    ? "created"
    : !force && await directoriesEqual(source, destination) ? "unchanged" : "refreshed";
  if (!check && status !== "unchanged") {
    if (kind === "directory") await rm(destination, { recursive: true, force: true });
    await cp(source, destination, { recursive: true });
  }
  return status;
}

function samePath(left, right) {
  return process.platform === "win32"
    ? left.toLowerCase() === right.toLowerCase()
    : left === right;
}

function assertNodeRuntime() {
  const major = Number.parseInt(process.versions.node.split(".")[0], 10);
  if (!Number.isInteger(major) || major < minimumNodeMajor) {
    throw new Error(`Node.js ${minimumNodeMajor}+ is required; found ${process.versions.node}`);
  }
  return process.versions.node;
}

function gitVersion() {
  const result = spawnSync("git", ["--version"], { encoding: "utf8" });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`Git is required: ${(result.stderr || result.stdout || "").trim()}`);
  }
  return result.stdout.trim();
}

function gitOutput(target, args) {
  const result = spawnSync("git", ["-C", target, ...args], { encoding: "utf8" });
  if (result.error || result.status !== 0) return null;
  return result.stdout.trim();
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
  const requested = await realpath(target).catch((error) => {
    throw error.code === "ENOENT" ? new Error(`target does not exist: ${target}`) : error;
  });
  const top = await realpath(gitTopLevel(target));
  if (!samePath(requested, top)) {
    throw new Error(`target must be the repository root: ${top}`);
  }
  return requested;
}

async function sourceRepositoryRoot() {
  const top = gitOutput(sourceCheckoutRoot, ["rev-parse", "--show-toplevel"]);
  if (!top) return null;
  const [checkout, repository] = await Promise.all([
    realpath(sourceCheckoutRoot),
    realpath(top),
  ]);
  return samePath(checkout, repository) ? repository : null;
}

async function releaseProvenance(version) {
  const file = path.join(packageRoot, "RELEASE.json");
  if (!(await exists(file))) return null;

  let release;
  try {
    release = JSON.parse(await readFile(file, "utf8"));
  } catch (error) {
    throw new Error(`invalid RELEASE.json: ${error.message}`);
  }
  if (release.schema !== "aihaus.release.v1") {
    throw new Error("invalid RELEASE.json schema");
  }
  if (release.distribution !== "github-release") {
    throw new Error("invalid RELEASE.json distribution");
  }
  if (release.version !== version || release.tag !== `v${version}`) {
    throw new Error("RELEASE.json version and tag do not match pkg/VERSION");
  }
  if (!/^[0-9a-f]{40}$/i.test(release.commit)) {
    throw new Error("invalid RELEASE.json commit");
  }
  return {
    distribution: release.distribution,
    version,
    commit: release.commit.toLowerCase(),
    branch: null,
    ref: release.tag,
    pinned: true,
    dirty: false,
  };
}

async function sourceProvenance() {
  const version = (await readFile(path.join(packageRoot, "VERSION"), "utf8")).trim();
  const release = await releaseProvenance(version);
  if (release) return release;

  const repository = await sourceRepositoryRoot();
  if (!repository) {
    return {
      distribution: "source",
      version,
      commit: null,
      branch: null,
      ref: null,
      pinned: false,
      dirty: null,
    };
  }

  const tags = (gitOutput(repository, ["tag", "--points-at", "HEAD"]) || "")
    .split(/\r?\n/)
    .filter(Boolean);
  const releaseTags = [`v${version}`, `aihaus-v${version}`];
  const ref = releaseTags.find((tag) => tags.includes(tag)) ?? null;
  return {
    distribution: "git",
    version,
    commit: gitOutput(repository, ["rev-parse", "HEAD"]),
    branch: gitOutput(repository, ["branch", "--show-current"]) || null,
    ref,
    pinned: ref !== null,
    dirty: (gitOutput(repository, ["status", "--porcelain"]) || "").length > 0,
  };
}

async function cleanupState(repositoryRoot) {
  const [target, source] = await Promise.all([
    realpath(repositoryRoot),
    realpath(sourceCheckoutRoot),
  ]);
  const expectedDownload = path.join(target, ".aihaus-download");
  return samePath(source, expectedDownload)
    ? { path: ".aihaus-download", pending: true }
    : { path: null, pending: false };
}

async function removeRetiredArtifacts(repositoryRoot, { check = false } = {}) {
  const matches = [];
  for (const relative of retiredArtifacts) {
    const candidate = path.join(repositoryRoot, ...relative.split("/"));
    await assertPathWithin({ root: repositoryRoot, candidate });
    const kind = await entryKind(candidate);
    if (kind === "missing") continue;
    if (kind !== "file") {
      throw new Error(`refusing non-regular retired artifact: ${candidate}`);
    }
    matches.push(relative);
    if (!check) await rm(candidate);
  }
  return matches;
}

async function removeRetiredHostSkills(repositoryRoot, { check = false } = {}) {
  const matches = [];
  for (const relative of retiredHostSkills) {
    const candidate = path.join(repositoryRoot, ...relative.split("/"));
    await assertPathWithin({ root: repositoryRoot, candidate });
    const kind = await entryKind(candidate);
    if (kind !== "file") continue;
    // only aihaus-managed skills are removed; user-owned files stay untouched
    if (!(await readFile(candidate, "utf8")).includes(hostAdapterMarker)) continue;
    matches.push(relative);
    if (!check) {
      await rm(candidate);
      try {
        await rmdir(path.dirname(candidate));
      } catch {}
    }
  }
  return matches;
}

async function verifyInstalledSurface(repositoryRoot) {
  const missing = [];
  const required = [
    ...requiredSurface,
    ...memoryFiles.map((file) => `.aihaus/memory/${file}`),
    ...requiredDirectories,
  ];
  for (const relative of required) {
    const kind = await entryKind(path.join(repositoryRoot, relative));
    const expected = requiredDirectories.includes(relative) ? "directory" : "file";
    if (kind !== expected) missing.push(relative);
  }
  return { ok: missing.length === 0, required, missing };
}

async function upsertManagedBlock(file, body, { check = false } = {}) {
  const block = `${startMarker}\n${body.trim()}\n${endMarker}`;
  if (!(await exists(file))) {
    if (!check) await writeFile(file, `${block}\n`, "utf8");
    return check ? "would-create" : "created";
  }

  const info = await lstat(file);
  if (!info.isFile() || info.isSymbolicLink()) {
    throw new Error(`refusing non-regular managed block file: ${file}`);
  }
  if (info.nlink > 1) {
    throw new Error(`refusing hard-linked managed block file: ${file}`);
  }
  const raw = await readFile(file);
  const current = raw.toString("utf8");
  // a UTF-8 rewrite would corrupt UTF-16 or legacy code-page files
  if (raw.includes(0) || !Buffer.from(current, "utf8").equals(raw)) {
    throw new Error(`refusing to rewrite ${file}: not UTF-8 text; convert it to UTF-8 first`);
  }
  const start = current.indexOf(startMarker);
  const end = current.indexOf(endMarker);
  if (
    (start >= 0) !== (end >= 0) ||
    (start >= 0 && (end < start || current.indexOf(startMarker, start + startMarker.length) >= 0)) ||
    (end >= 0 && current.indexOf(endMarker, end + endMarker.length) >= 0)
  ) {
    throw new Error(`refusing malformed managed block in ${file}`);
  }
  if (start < 0) {
    const separator = current.endsWith("\n") ? "\n" : "\n\n";
    if (!check) await writeFile(file, `${current}${separator}${block}\n`, "utf8");
    return check ? "would-append" : "appended";
  }

  const next = `${current.slice(0, start)}${block}${current.slice(end + endMarker.length)}`;
  if (next === current) return "unchanged";
  if (!check) await writeFile(file, next, "utf8");
  return check ? "would-update" : "updated";
}

async function installHostSkill(repositoryRoot, specification, { check = false, force = false } = {}) {
  const destination = path.join(repositoryRoot, ...specification.relative.split("/"));
  await assertPathWithin({ root: repositoryRoot, candidate: destination });
  await assertDirectoryPath(repositoryRoot, path.dirname(destination));
  const desired = await readFile(specification.source, "utf8");

  if (!(await exists(destination))) {
    if (!check) {
      await mkdir(path.dirname(destination), { recursive: true });
      await assertPathWithin({ root: repositoryRoot, candidate: destination });
      await writeFile(destination, desired, "utf8");
    }
    return { status: check ? "would-create" : "created", conflict: null };
  }

  const info = await lstat(destination);
  if (!info.isFile() || info.isSymbolicLink() || info.nlink > 1) {
    return {
      status: "preserved",
      conflict: {
        type: "host-skill-collision",
        path: specification.relative,
        message:
          info.nlink > 1
            ? "Existing host skill is hard-linked and cannot be safely refreshed; preserved."
            : "Existing host skill is not a regular aihaus-managed file; preserved.",
      },
    };
  }
  const current = await readFile(destination, "utf8");
  if (!current.includes(hostAdapterMarker)) {
    return {
      status: "preserved",
      conflict: {
        type: "host-skill-collision",
        path: specification.relative,
        message: "Existing user-owned host skill was preserved.",
      },
    };
  }
  if (current === desired && !force) return { status: "unchanged", conflict: null };
  if (!check) await writeFile(destination, desired, "utf8");
  return { status: check ? "would-refresh" : "refreshed", conflict: null };
}

async function install(target, { check = false, force = false } = {}) {
  const preflight = {
    node: assertNodeRuntime(),
    git: gitVersion(),
  };
  const repositoryRoot = await assertRepositoryRoot(path.resolve(target));
  const destinationRoot = path.join(repositoryRoot, ".aihaus");
  await assertPathWithin({ root: repositoryRoot, candidate: destinationRoot });
  const destinationKind = await entryKind(destinationRoot);
  if (!["missing", "directory"].includes(destinationKind)) {
    throw new Error(`refusing non-directory aihaus destination: ${destinationRoot}`);
  }
  if (!check && destinationKind === "missing") await mkdir(destinationRoot, { recursive: true });

  const installed = [
    ...managedFiles.map((file) => `.aihaus/${file}`),
    ...metadataFiles.map((file) => `.aihaus/${file}`),
    ...managedDirectories.map((directory) => `.aihaus/${directory}/`),
  ];
  const managedStatus = new Map();

  for (const directory of managedDirectories) {
    const source = path.join(sourceRoot, directory);
    const destination = path.join(destinationRoot, directory);
    managedStatus.set(
      `.aihaus/${directory}/`,
      await planManagedDirectory({
        source,
        destination,
        root: destinationRoot,
        check,
        force,
      }),
    );
  }
  for (const file of managedFiles) {
    const destination = path.join(destinationRoot, file);
    managedStatus.set(
      `.aihaus/${file}`,
      await planManagedFile({
        source: path.join(sourceRoot, file),
        destination,
        root: destinationRoot,
        check,
        force,
      }),
    );
  }
  const retiredCleanup = [
    ...await removeRetiredArtifacts(repositoryRoot, { check }),
    ...await removeRetiredHostSkills(repositoryRoot, { check }),
  ];

  const seeded = [];
  const wouldSeed = [];
  const preserved = [];
  for (const relative of memoryFiles) {
    const source = path.join(sourceRoot, "memory", relative);
    const destination = path.join(destinationRoot, "memory", relative);
    await assertPathWithin({ root: destinationRoot, candidate: destination });
    await assertDirectoryPath(destinationRoot, path.dirname(destination));
    const kind = await entryKind(destination);
    if (!["missing", "file"].includes(kind)) {
      throw new Error(`refusing non-regular project memory: ${destination}`);
    }
    if (kind === "missing") {
      if (check) {
        wouldSeed.push(`memory/${relative}`);
      } else {
        await mkdir(path.dirname(destination), { recursive: true });
        await cp(source, destination);
        seeded.push(`memory/${relative}`);
      }
    } else {
      preserved.push(`memory/${relative}`);
    }
  }
  const missingDirectories = [];
  for (const relative of requiredDirectories) {
    const destination = path.join(repositoryRoot, relative);
    await assertPathWithin({ root: repositoryRoot, candidate: destination });
    await assertDirectoryPath(repositoryRoot, path.dirname(destination));
    const kind = await entryKind(destination);
    if (!["missing", "directory"].includes(kind)) {
      throw new Error(`refusing non-directory required surface: ${destination}`);
    }
    if (kind === "missing") {
      missingDirectories.push(relative);
      if (!check) await mkdir(destination, { recursive: true });
    }
  }

  const router = await readFile(path.join(packageRoot, "adapters", "router.md"), "utf8");
  const adapters = {};
  for (const file of ["AGENTS.md", "CLAUDE.md"]) {
    const destination = path.join(repositoryRoot, file);
    await assertPathWithin({ root: repositoryRoot, candidate: destination });
    adapters[file] = await upsertManagedBlock(destination, file === "CLAUDE.md" ? "@AGENTS.md" : router, { check });
  }
  await assertPathWithin({ root: repositoryRoot, candidate: path.join(repositoryRoot, ".gitignore") });
  adapters[".gitignore"] = await upsertManagedBlock(
    path.join(repositoryRoot, ".gitignore"),
    "/.aihaus-download/\n.aihaus/state/\n.aihaus/runtime/\n.aihaus/backups/",
    { check },
  );

  const conflicts = [];
  const hostCapabilities = {
    universal: {
      invoke: "node .aihaus/tools/refresh.mjs --repo . --json",
    },
  };
  for (const specification of hostSkillAdapters) {
    const installedHostSkill = await installHostSkill(repositoryRoot, specification, { check, force });
    if (installedHostSkill.conflict) conflicts.push(installedHostSkill.conflict);
    hostCapabilities[specification.host] = {
      adapter: specification.relative,
      status: installedHostSkill.status,
      available:
        installedHostSkill.conflict === null && installedHostSkill.status !== "would-create",
      ...specification.capability,
    };
  }
  // VERSION goes last so a failed run never pairs a new version with stale files
  for (const file of metadataFiles) {
    const destination = path.join(destinationRoot, file);
    managedStatus.set(
      `.aihaus/${file}`,
      await planManagedFile({
        source: path.join(packageRoot, file),
        destination,
        root: destinationRoot,
        check,
        force,
      }),
    );
  }

  const source = await sourceProvenance();
  const warnings = [];
  const instructionWarnings = [];
  const override = path.join(repositoryRoot, "AGENTS.override.md");
  if (await entryKind(override) === "file" && (await readFile(override, "utf8")).trim()) {
    instructionWarnings.push({
      path: "AGENTS.override.md",
      reason: "Codex loads this non-empty override instead of AGENTS.md; the installed aihaus router is shadowed.",
    });
    warnings.push("AGENTS.override.md shadows the aihaus router in AGENTS.md; review the override instructions.");
  }
  if (!source.pinned) {
    warnings.push(
      `source checkout is not pinned to a release tag (v${source.version} or aihaus-v${source.version})`,
    );
  }
  if (source.dirty) warnings.push("source checkout has uncommitted changes");
  for (const conflict of conflicts) {
    warnings.push(`user-owned host skill preserved at ${conflict.path}`);
  }

  const plannedCreated = installed.filter((relative) => managedStatus.get(relative) === "created");
  const plannedRefreshed = installed.filter((relative) => managedStatus.get(relative) === "refreshed");
  const unchanged = installed.filter((relative) => managedStatus.get(relative) === "unchanged");
  const adapterChanges = Object.values(adapters).some((status) => status !== "unchanged");
  const hostChanges = Object.values(hostCapabilities).some(
    (capability) => capability.status && !["unchanged", "preserved"].includes(capability.status),
  );
  const changesRequired =
    plannedCreated.length > 0 ||
    plannedRefreshed.length > 0 ||
    seeded.length > 0 ||
    wouldSeed.length > 0 ||
    missingDirectories.length > 0 ||
    retiredCleanup.length > 0 ||
    adapterChanges ||
    hostChanges;
  const verification = await verifyInstalledSurface(repositoryRoot);
  if (!check && !verification.ok) {
    throw new Error(`installed surface verification failed: ${verification.missing.join(", ")}`);
  }

  return {
    ok: true,
    scope: "repository-local",
    mode: check ? "check" : "apply",
    forced: force,
    changesRequired,
    target: repositoryRoot,
    preflight,
    source,
    installed,
    created: check ? [] : plannedCreated,
    refreshed: check ? [] : plannedRefreshed,
    unchanged,
    wouldCreate: check ? plannedCreated : [],
    wouldRefresh: check ? plannedRefreshed : [],
    seeded,
    wouldSeed,
    createdDirectories: check ? [] : missingDirectories,
    wouldCreateDirectories: check ? missingDirectories : [],
    removed: check ? [] : retiredCleanup,
    wouldRemove: check ? retiredCleanup : [],
    preserved,
    adapters,
    hostCapabilities,
    conflicts,
    instructionWarnings,
    verification,
    bootstrap: {
      command: "node .aihaus/tools/refresh.mjs --repo . --json",
      dryRun: "node .aihaus/tools/refresh.mjs --repo . --dry-run --json",
      status: "node .aihaus/tools/refresh.mjs --repo . --status --json",
      instruction: ".aihaus/REFRESH.md",
      contract: ".aihaus/contracts/project-bootstrap.md",
    },
    cleanup: await cleanupState(repositoryRoot),
    warnings,
  };
}

function parseArgs(args) {
  const options = { target: process.cwd(), json: false, check: false, force: false };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--target") options.target = args[++index] ?? "";
    else if (arg === "--json") options.json = true;
    else if (arg === "--check") options.check = true;
    else if (arg === "--force") options.force = true;
    else if (arg === "-h" || arg === "--help") options.help = true;
    else throw new Error(`unknown option: ${arg}`);
  }
  if (!options.target) throw new Error("--target requires a path");
  if (options.check && options.force) throw new Error("--check and --force cannot be combined");
  return options;
}

async function main() {
  try {
    const options = parseArgs(process.argv.slice(2));
    if (options.help) {
      process.stdout.write(
        "Usage: node pkg/setup.mjs [--target <git-root>] [--check | --force] [--json]\n",
      );
      return;
    }
    await validatePackageSource();
    const preview = await install(options.target, { ...options, check: true });
    const result = options.check ? preview : await install(options.target, options);
    process.stdout.write(`${JSON.stringify(result, null, options.json ? 2 : 0)}\n`);
  } catch (error) {
    process.stderr.write(`${JSON.stringify({ ok: false, error: error.message })}\n`);
    process.exitCode = 2;
  }
}

await main();
