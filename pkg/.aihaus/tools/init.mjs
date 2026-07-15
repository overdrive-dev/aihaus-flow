#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { access, lstat, mkdir, readFile, realpath, writeFile } from "node:fs/promises";
import path from "node:path";
import { assertPathWithin } from "./path-safety.mjs";

const minimumNodeMajor = 22;
const packetRelative = ".aihaus/state/bootstrap/discovery.json";
const maximumHashedBytes = 1024 * 1024;
const templateHashes = new Map([
  ["business-rules.md", "3dc7797922a4ad520187db053ca088196d6dc6d1aebcd6106731bc8bd5c5a73d"],
  ["decisions.md", "506547082113998a90403338337932a7864a55c74e821635a5d8db587967d98d"],
  ["deployment.md", "64645877c22c3ae527d6b9ce90e4cac6deb56c7ff21482973e8a07dd258c978b"],
  ["environment.md", "ace7cfe77a918d4d6e5fc28f86abdc10e4e6e437a136a15b31e5e183b85f01ac"],
  ["glossary.md", "0ef984b0bd9598b21a10dc98456f2fc69f9b6823d663da7d8340a301ff9b9694"],
  ["knowledge.md", "e72d76cf91aea2b1ca8091427f8ac78b3af378f9c4ddf410d78f7e9fbb0024d6"],
  ["procedures.md", "9b50f0c8e957a56e652e98df6f39ef473bd76e7a455c86c3296ccf6e2652596e"],
  ["project.md", "78d8f965d07e7f764618e3911f797b24b5f1b4f1866f6ef57fd262e3ac4f918e"],
]);
const memorySpecs = [
  {
    name: "project.md",
    kinds: ["adapter", "readme", "manifest", "architecture", "document"],
    instruction: "Summarize purpose, users, boundaries, layout, constraints, and Definition of Done from explicit evidence.",
  },
  {
    name: "business-rules.md",
    kinds: ["adapter", "readme", "architecture", "decision", "document"],
    instruction: "Record only explicit accepted behavioral rules; keep inferred candidates as unresolved gaps.",
  },
  {
    name: "decisions.md",
    kinds: ["decision", "architecture", "migration", "document"],
    instruction: "Record accepted ADRs and documented conventions with consequences; do not infer decisions from code shape.",
  },
  {
    name: "knowledge.md",
    kinds: ["adapter", "readme", "architecture", "test-config", "document"],
    instruction: "Record verified facts, behavior locks, recurring gotchas, and useful code analogs.",
  },
  {
    name: "environment.md",
    kinds: ["manifest", "lockfile", "ci", "container", "deployment"],
    instruction: "Describe local and hosted topology plus credential locations without copying credential values.",
  },
  {
    name: "procedures.md",
    kinds: ["manifest", "readme", "ci", "test-config", "deployment", "document"],
    instruction: "Record commands and procedures that are explicitly documented or actually verified.",
  },
  {
    name: "deployment.md",
    kinds: ["deployment", "ci", "container", "architecture", "document"],
    instruction: "Record build, promotion, smoke, approval, stop, and rollback evidence without executing deployment.",
  },
  {
    name: "glossary.md",
    kinds: ["readme", "architecture", "document"],
    instruction: "Record domain terms only when an authoritative source supplies a defensible meaning.",
  },
];
const manifestNames = new Map([
  ["package.json", "node"],
  ["pyproject.toml", "python"],
  ["cargo.toml", "rust"],
  ["go.mod", "go"],
  ["pom.xml", "maven"],
  ["build.gradle", "gradle"],
  ["build.gradle.kts", "gradle"],
  ["composer.json", "php"],
  ["gemfile", "ruby"],
  ["mix.exs", "elixir"],
  ["deno.json", "deno"],
  ["deno.jsonc", "deno"],
]);
const lockfileNames = new Set([
  "package-lock.json",
  "npm-shrinkwrap.json",
  "pnpm-lock.yaml",
  "yarn.lock",
  "bun.lock",
  "bun.lockb",
  "uv.lock",
  "poetry.lock",
  "cargo.lock",
  "go.sum",
  "composer.lock",
  "gemfile.lock",
]);
const ignoredSegments = new Set([
  ".git",
  ".aihaus",
  ".aihaus-download",
  "node_modules",
  "vendor",
  "dist",
  "build",
  "coverage",
  "target",
  ".venv",
  "venv",
  "__pycache__",
  ".cache",
]);
const sensitiveSegments = new Set([
  ".aws",
  ".azure",
  ".gcloud",
  ".kube",
  ".ssh",
  ".terraform",
]);
const sourceRootNames = new Set([
  "src",
  "app",
  "apps",
  "packages",
  "lib",
  "cmd",
  "internal",
  "frontend",
  "backend",
  "server",
  "client",
]);
const testRootNames = new Set(["test", "tests", "spec", "specs", "__tests__"]);

async function exists(target) {
  try {
    await access(target);
    return true;
  } catch {
    return false;
  }
}

function digest(value) {
  return createHash("sha256").update(value).digest("hex");
}

function normalize(relative) {
  return relative.replaceAll("\\", "/").replace(/^\.\//, "");
}

function samePath(left, right) {
  return process.platform === "win32"
    ? left.toLowerCase() === right.toLowerCase()
    : left === right;
}

function assertNodeRuntime() {
  const major = Number.parseInt(process.versions.node.split(".")[0], 10);
  if (!Number.isInteger(major) || major < minimumNodeMajor) {
    throw new Error("Node.js " + minimumNodeMajor + "+ is required; found " + process.versions.node);
  }
}

function git(repository, args, allowFailure = false) {
  const result = spawnSync("git", ["-C", repository, ...args], {
    encoding: "utf8",
    maxBuffer: 16 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    if (allowFailure) return null;
    throw new Error("git " + args.join(" ") + " failed: " + (result.stderr || result.stdout).trim());
  }
  return result.stdout;
}

function gitPaths(repository, args, allowFailure = false) {
  const output = git(repository, args, allowFailure);
  return output === null ? [] : output.split("\0").filter(Boolean).map(normalize);
}

async function repositoryRoot(requested) {
  const resolved = await realpath(path.resolve(requested));
  const topOutput = git(resolved, ["rev-parse", "--show-toplevel"]);
  const top = await realpath(topOutput.trim());
  if (!samePath(resolved, top)) {
    throw new Error("--repo must resolve to the Git repository root: " + top);
  }
  for (const required of [
    ".aihaus/MAP.md",
    ".aihaus/contracts/harness.md",
    ".aihaus/memory/project",
  ]) {
    const candidate = path.join(resolved, ...required.split("/"));
    await assertPathWithin({ root: resolved, candidate });
    if (!(await exists(candidate))) {
      throw new Error("repository-local aihaus is incomplete; missing " + required);
    }
  }
  return resolved;
}

function isInternal(relative) {
  return normalize(relative)
    .toLowerCase()
    .split("/")
    .some((segment) => ignoredSegments.has(segment));
}

function isSensitive(relative) {
  const lower = normalize(relative).toLowerCase();
  const base = path.posix.basename(lower);
  const sensitiveToken = /(^|[-_.])(secret|secrets|credential|credentials|password|passwords|token|tokens|private[-_]?key|test[-_]?users?)([-_.]|$)/;
  if (
    lower
      .split("/")
      .some((segment) => sensitiveSegments.has(segment) || sensitiveToken.test(segment))
  ) {
    return true;
  }
  if (base === ".env" || base.startsWith(".env.")) return true;
  if ([".npmrc", ".pypirc", ".netrc", "_netrc", "kubeconfig", "auth.json"].includes(base)) {
    return true;
  }
  if (/\.(pem|key|p12|pfx|jks|keystore|tfvars)$/.test(base)) return true;
  if (/^terraform\.tfstate(?:\.|$)/.test(base)) return true;
  return sensitiveToken.test(base);
}

function classify(relative) {
  const value = normalize(relative);
  const lower = value.toLowerCase();
  const base = path.posix.basename(lower);
  const segments = lower.split("/");
  const kinds = new Set();
  if (base === "agents.md" || base === "claude.md") kinds.add("adapter");
  if (/^readme(?:\..+)?$/.test(base)) kinds.add("readme");
  if (manifestNames.has(base)) kinds.add("manifest");
  if (lockfileNames.has(base)) kinds.add("lockfile");
  if (
    lower.startsWith(".github/workflows/") ||
    lower === ".gitlab-ci.yml" ||
    lower === "azure-pipelines.yml" ||
    lower === "jenkinsfile" ||
    lower === ".circleci/config.yml" ||
    lower.startsWith(".buildkite/")
  ) {
    kinds.add("ci");
  }
  if (/^dockerfile(?:\..+)?$/.test(base) || /^(docker-)?compose(?:\..+)?\.ya?ml$/.test(base)) {
    kinds.add("container");
  }
  if (
    segments.some((segment) => ["migrations", "migration", "db-migrate", "db-migrations"].includes(segment))
  ) {
    kinds.add("migration");
  }
  if (
    segments.some((segment) => ["adr", "adrs", "architecture", "decisions", "rfcs"].includes(segment)) ||
    /(architecture|architectural|decision|conventions?|design|rfc)/.test(base)
  ) {
    kinds.add("architecture");
  }
  if (segments.some((segment) => ["adr", "adrs", "decisions", "rfcs"].includes(segment))) {
    kinds.add("decision");
  }
  if (/(deploy|deployment|release|rollback|runbook|operations|smoke|infrastructure)/.test(lower)) {
    kinds.add("deployment");
  }
  if (
    /(^|\.)(test|spec)\.(config|setup)\./.test(base) ||
    /^(jest|vitest|playwright|cypress|pytest|phpunit|karma)\./.test(base)
  ) {
    kinds.add("test-config");
  }
  if (base.endsWith(".md") && !kinds.has("adapter") && !kinds.has("readme")) {
    kinds.add("document");
  }
  return [...kinds].sort();
}

function tomlProjectName(text, sections) {
  let section = "";
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    const sectionMatch = /^\[([^\]]+)\]$/.exec(line);
    if (sectionMatch) {
      section = sectionMatch[1].toLowerCase();
      continue;
    }
    if (!sections.includes(section)) continue;
    const nameMatch = /^name\s*=\s*["']([^"']+)["']/.exec(line);
    if (nameMatch) return nameMatch[1];
  }
  return null;
}

function parseManifest(source, text, warnings) {
  const base = path.posix.basename(source.path.toLowerCase());
  const fact = { path: source.path, type: manifestNames.get(base), projectName: null };
  try {
    if (base === "package.json") {
      const value = JSON.parse(text);
      fact.projectName = typeof value.name === "string" ? value.name : null;
      fact.private = value.private === true;
      fact.scriptNames =
        value.scripts && typeof value.scripts === "object"
          ? Object.keys(value.scripts).sort()
          : [];
      fact.engines =
        value.engines && typeof value.engines === "object"
          ? Object.fromEntries(
              Object.entries(value.engines)
                .filter(([, requirement]) => typeof requirement === "string")
                .sort(([left], [right]) => left.localeCompare(right)),
            )
          : {};
    } else if (base === "pyproject.toml") {
      fact.projectName = tomlProjectName(text, ["project", "tool.poetry"]);
    } else if (base === "cargo.toml") {
      fact.projectName = tomlProjectName(text, ["package", "workspace.package"]);
    } else if (base === "go.mod") {
      fact.projectName = /^\s*module\s+([^\s]+)\s*$/m.exec(text)?.[1] ?? null;
    } else if (base === "pom.xml") {
      fact.projectName = /<artifactId>\s*([^<]+)\s*<\/artifactId>/.exec(text)?.[1] ?? null;
    } else if (base === "composer.json") {
      const value = JSON.parse(text);
      fact.projectName = typeof value.name === "string" ? value.name : null;
    }
  } catch (error) {
    warnings.push("could not parse manifest " + source.path + ": " + error.message);
  }
  return fact;
}

function layoutFacts(paths) {
  const topLevelDirectories = new Set();
  const sourceRoots = new Set();
  const testRoots = new Set();
  for (const relative of paths) {
    const segments = normalize(relative).split("/");
    if (segments.length < 2) continue;
    topLevelDirectories.add(segments[0]);
    if (sourceRootNames.has(segments[0].toLowerCase())) sourceRoots.add(segments[0]);
    if (testRootNames.has(segments[0].toLowerCase())) testRoots.add(segments[0]);
  }
  return {
    topLevelDirectories: [...topLevelDirectories].sort(),
    sourceRoots: [...sourceRoots].sort(),
    testRoots: [...testRoots].sort(),
  };
}

function sourcePaths(sources, kind) {
  return sources.filter((source) => source.kinds.includes(kind)).map((source) => source.path);
}

function identityConflicts(manifests) {
  const candidates = manifests
    .filter((manifest) => !manifest.path.includes("/") && manifest.projectName)
    .map((manifest) => ({ source: manifest.path, value: manifest.projectName }));
  const values = new Set(candidates.map((candidate) => candidate.value.toLowerCase()));
  return values.size > 1
    ? [{
        id: "project-identity",
        message: "Root manifests declare different project identities; agent review is required.",
        candidates,
      }]
    : [];
}

async function memoryTargets(repository, sources, warnings) {
  const targets = [];
  for (const spec of memorySpecs) {
    const relative = ".aihaus/memory/project/" + spec.name;
    const file = path.join(repository, ...relative.split("/"));
    await assertPathWithin({ root: repository, candidate: file });
    let status = "missing";
    let currentDigest = null;
    if (await exists(file)) {
      const content = await readFile(file);
      currentDigest = digest(content);
      status = templateHashes.get(spec.name) === currentDigest ? "template" : "existing";
    } else {
      warnings.push("canonical memory target is missing: " + relative);
    }
    const candidates = sources
      .filter((source) => source.kinds.some((kind) => spec.kinds.includes(kind)))
      .map((source) => source.path);
    targets.push({
      path: relative,
      status,
      sha256: currentDigest,
      candidateSources: candidates,
      instruction: spec.instruction,
      provenanceRequired: true,
    });
  }
  return targets;
}

async function discover(repository) {
  const warnings = [];
  const commit = git(repository, ["rev-parse", "--verify", "HEAD"], true)?.trim() || null;
  const branch = git(repository, ["branch", "--show-current"], true)?.trim() || null;
  const tracked = new Set(gitPaths(repository, ["ls-files", "--cached", "-z"]));
  const untracked = new Set(gitPaths(repository, ["ls-files", "--others", "--exclude-standard", "-z"]));
  const changed = commit
    ? new Set(gitPaths(repository, ["diff", "HEAD", "--name-only", "-z", "--"]))
    : new Set();
  const all = [...new Set([...tracked, ...untracked])].sort();
  const safePaths = all.filter((relative) => !isInternal(relative) && !isSensitive(relative));
  const excluded = all
    .filter((relative) => !isInternal(relative) && isSensitive(relative))
    .map((relative) => ({ path: relative, reason: "sensitive-path" }));
  const sources = [];
  const sourceText = new Map();

  for (const relative of safePaths) {
    const kinds = classify(relative);
    if (kinds.length === 0) continue;
    const file = path.join(repository, ...relative.split("/"));
    await assertPathWithin({ root: repository, candidate: file });
    let info;
    try {
      info = await lstat(file);
    } catch (error) {
      if (error.code === "ENOENT") {
        excluded.push({ path: relative, reason: "missing-worktree" });
        continue;
      }
      throw error;
    }
    if (info.isSymbolicLink()) {
      excluded.push({ path: relative, reason: "symbolic-link" });
      continue;
    }
    if (!info.isFile()) continue;
    let content = null;
    let sha256 = null;
    if (info.size <= maximumHashedBytes) {
      content = await readFile(file);
      sha256 = digest(content);
      sourceText.set(relative, content.toString("utf8"));
    } else {
      warnings.push("source exceeds hash limit and was not read: " + relative);
    }
    sources.push({
      path: relative,
      kinds,
      bytes: info.size,
      sha256,
      tracked: tracked.has(relative),
      revision: tracked.has(relative)
        ? changed.has(relative) ? "worktree" : commit
        : "untracked",
    });
  }

  sources.sort((left, right) => left.path.localeCompare(right.path));
  excluded.sort((left, right) => left.path.localeCompare(right.path));
  const manifests = sources
    .filter((source) => source.kinds.includes("manifest"))
    .map((source) => parseManifest(source, sourceText.get(source.path) ?? "", warnings));
  const conflicts = identityConflicts(manifests);
  const targets = await memoryTargets(repository, sources, warnings);
  if (!commit) warnings.push("repository has no reviewed Git commit; provenance is worktree-only");
  if (sourcePaths(sources, "adapter").length === 0) {
    warnings.push("no AGENTS.md or CLAUDE.md adapter source was found");
  }
  if (sources.length === 0) warnings.push("no safe bootstrap sources were discovered");
  if (conflicts.length > 0) warnings.push("discovered evidence contains unresolved conflicts");

  const packet = {
    schema: "aihaus.bootstrap.discovery.v1",
    repository: {
      root: repository,
      name: path.basename(repository),
      commit,
      branch,
    },
    safety: {
      networkAccess: false,
      uploaded: false,
      readsSensitivePaths: false,
      writesOutsideRepository: false,
      graphConsentCreated: false,
    },
    sources,
    excluded,
    facts: {
      adapters: sourcePaths(sources, "adapter"),
      readmes: sourcePaths(sources, "readme"),
      manifests,
      lockfiles: sourcePaths(sources, "lockfile"),
      ci: sourcePaths(sources, "ci"),
      containers: sourcePaths(sources, "container"),
      migrations: sourcePaths(sources, "migration"),
      architecture: sourcePaths(sources, "architecture"),
      deployment: sourcePaths(sources, "deployment"),
      layout: layoutFacts(safePaths),
    },
    conflicts,
    memoryTargets: targets,
    nextStep: {
      instruction: ".aihaus/INIT.md",
      contract: ".aihaus/contracts/project-bootstrap.md",
      canonicalMemory: ".aihaus/memory/project/",
    },
  };
  return { packet, warnings };
}

async function packetState(repository, packet) {
  const file = path.join(repository, ...packetRelative.split("/"));
  await assertPathWithin({ root: repository, candidate: file });
  const next = JSON.stringify(packet, null, 2) + "\n";
  const present = await exists(file);
  const current = present ? await readFile(file, "utf8") : null;
  return {
    file,
    next,
    present,
    same: current === next,
    digest: digest(next),
  };
}

function baseResult(repository, mode, packet, warnings, state) {
  const preserved = packet.memoryTargets
    .filter((target) => target.status !== "missing")
    .map((target) => target.path);
  if (state.present && state.same) preserved.push(packetRelative);
  return {
    schema: "aihaus.bootstrap.result.v1",
    ok: true,
    repo: repository,
    mode,
    commit: packet.repository.commit,
    created: [],
    updated: [],
    preserved,
    skipped: packet.excluded,
    conflicts: packet.conflicts,
    warnings,
    sources: packet.sources,
    memory: {
      targets: packet.memoryTargets,
      instruction: packet.nextStep.instruction,
      contract: packet.nextStep.contract,
    },
    packet: {
      path: packetRelative,
      action: state.present ? state.same ? "unchanged" : "updated" : "created",
      sha256: state.digest,
    },
  };
}

async function execute(options) {
  assertNodeRuntime();
  const repository = await repositoryRoot(options.repo);
  const { packet, warnings } = await discover(repository);
  const state = await packetState(repository, packet);
  const mode = options.status ? "status" : options.dryRun ? "dry-run" : "apply";
  const result = baseResult(repository, mode, packet, warnings, state);

  if (options.status) {
    result.packet.action = state.present ? state.same ? "unchanged" : "stale" : "missing";
    result.status = {
      initialized: state.present,
      stale: state.present ? !state.same : null,
    };
    return result;
  }

  if (options.dryRun) {
    result.packet.action = state.present
      ? state.same ? "unchanged" : "would-update"
      : "would-create";
    result.wouldCreate = state.present ? [] : [packetRelative];
    result.wouldUpdate = state.present && !state.same ? [packetRelative] : [];
    return result;
  }

  if (!state.same) {
    await assertPathWithin({ root: repository, candidate: state.file });
    await mkdir(path.dirname(state.file), { recursive: true });
    await assertPathWithin({ root: repository, candidate: state.file });
    await writeFile(state.file, state.next, "utf8");
    if (state.present) result.updated.push(packetRelative);
    else result.created.push(packetRelative);
  }
  return result;
}

function parseArgs(args) {
  const options = {
    repo: process.cwd(),
    dryRun: false,
    status: false,
    json: false,
    help: false,
  };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--repo") options.repo = args[++index] ?? "";
    else if (arg === "--dry-run") options.dryRun = true;
    else if (arg === "--status") options.status = true;
    else if (arg === "--json") options.json = true;
    else if (arg === "--help" || arg === "-h") options.help = true;
    else throw new Error("unknown option: " + arg);
  }
  if (!options.repo) throw new Error("--repo requires a path");
  if (options.dryRun && options.status) {
    throw new Error("--dry-run and --status are mutually exclusive");
  }
  return options;
}

function usage() {
  return [
    "Usage:",
    "  node .aihaus/tools/init.mjs --repo <git-root> [--json]",
    "  node .aihaus/tools/init.mjs --repo <git-root> --dry-run [--json]",
    "  node .aihaus/tools/init.mjs --repo <git-root> --status [--json]",
    "",
    "Discovers local repository evidence without network access and writes only",
    packetRelative + ". Read .aihaus/INIT.md for the agent synthesis phase.",
  ].join("\n");
}

async function main() {
  let options = { json: false };
  try {
    options = parseArgs(process.argv.slice(2));
    if (options.help) {
      process.stdout.write(usage() + "\n");
      return;
    }
    const result = await execute(options);
    if (options.json) {
      process.stdout.write(JSON.stringify(result, null, 2) + "\n");
    } else {
      process.stdout.write(
        "aihaus bootstrap " + result.mode + ": " + result.packet.action +
        ", sources=" + result.sources.length +
        ", conflicts=" + result.conflicts.length + "\n",
      );
      process.stdout.write("Next: read " + result.memory.instruction + "\n");
    }
  } catch (error) {
    process.stderr.write(
      JSON.stringify({
        schema: "aihaus.bootstrap.result.v1",
        ok: false,
        error: error.message,
      }) + "\n",
    );
    process.exitCode = 2;
  }
}

await main();
