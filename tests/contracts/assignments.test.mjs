import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { validateEvidenceDocument } from "../../pkg/.aihaus/tools/evidence-validate.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const packageRoot = path.join(root, "pkg", ".aihaus");
const setup = path.join(root, "pkg", "setup.mjs");

function run(command, args, cwd) {
  const result = spawnSync(command, args, { cwd, encoding: "utf8" });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`${command} ${args.join(" ")} failed: ${result.stderr || result.stdout}`);
  }
  return result;
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

async function text(file) {
  return readFile(file, "utf8");
}

// Anchors match across line wraps, so reflowing prose never breaks them.
function assertAnchors(content, anchors, label) {
  const flat = content.replace(/\s+/g, " ");
  for (const anchor of anchors) {
    assert.match(flat, new RegExp(escapeRegExp(anchor), "i"), `${label} must mention "${anchor}"`);
  }
}

function lineCount(content) {
  return content.split(/\r?\n/).length;
}

// Mirrors refresh.mjs markdownText: strip a leading BOM and normalize CRLF/CR to LF.
function markdownText(buffer) {
  return buffer.toString("utf8").replace(/^﻿/, "").replace(/\r\n?/g, "\n");
}

// Simulates an install made by an earlier release: stale VERSION and router block.
async function simulateOlderInstall(target) {
  await writeFile(path.join(target, ".aihaus", "VERSION"), "1.6.1\n", "utf8");
  await writeFile(
    path.join(target, "AGENTS.md"),
    "# Team rules\n\n<!-- AIHAUS:START -->\nOld router\n<!-- AIHAUS:END -->\n",
    "utf8",
  );
}

async function assertRouterRefreshed(target, upgraded) {
  assert.equal(upgraded.ok, true);
  assert.equal(upgraded.adapters["AGENTS.md"], "updated");
  const agents = await text(path.join(target, "AGENTS.md"));
  assert.match(agents, /^# Team rules\n/);
  assert.doesNotMatch(agents, /Old router/);
  const router = (await text(path.join(root, "pkg", "adapters", "router.md"))).trim();
  assert.ok(agents.includes(router), "AGENTS.md must carry the current router block");
  assert.equal(
    (await text(path.join(target, ".aihaus", "VERSION"))).trim(),
    (await text(path.join(root, "pkg", "VERSION"))).trim(),
  );
}

test("harness contract names the two coordination levels and delegation fields", async () => {
  assertAnchors(
    await text(path.join(packageRoot, "contracts", "harness.md")),
    [
      "two coordination levels",
      "next recipient",
      "rework",
      "blocked",
      "escalation",
      "separate context",
      "candidate SHA",
      "degraded",
      "external tracker",
      "Assignments",
      "## Delegation",
      "optional read-only assignment",
      "returns to the",
      "selected project profile",
      "does not change or prove",
      "silently substituting",
      "authorized fallback",
      "requested capabilities",
      "Autonomy",
    ],
    "harness contract",
  );
});

test("adversarial review contract binds verdicts to a candidate SHA", async () => {
  assertAnchors(
    await text(path.join(packageRoot, "contracts", "adversarial-review.md")),
    [
      "candidate SHA",
      "recheck",
      "unrelated changes",
      "reviewer",
      "merge permission",
      "requested model alias or ID",
      "resolved model and settings",
      "resolution was unavailable",
      "never infer the resolved version",
    ],
    "adversarial review contract",
  );
});

test("evidence contract accepts commit metadata as unvalidated", async () => {
  assertAnchors(
    await text(path.join(packageRoot, "contracts", "evidence.md")),
    ["commit", "unvalidated metadata"],
    "evidence contract",
  );
});

test("MAP routes assignments, project memory, and package-owned files", async () => {
  const map = await text(path.join(packageRoot, "MAP.md"));
  assertAnchors(
    map,
    [
      "Assignments",
      "procedures.md",
      "package-owned",
      "external tracker",
      "profiles",
      "default role and profile for the user-facing session",
      "Autonomy",
      "including solo",
      "first remote write",
    ],
    "MAP.md",
  );
  assert.ok(lineCount(map) <= 50, "MAP.md must stay at or under 50 lines");
});

test("conventions name package-owned files and external trackers", async () => {
  assertAnchors(
    await text(path.join(packageRoot, "conventions.md")),
    ["external tracker", "package-owned"],
    "conventions.md",
  );
});

test("feature room explains the external tracker override", async () => {
  assertAnchors(
    await text(path.join(packageRoot, "rooms", "feature", "CONTEXT.md")),
    ["external tracker"],
    "feature room context",
  );
});

test("kanban memory explains the external tracker override", async () => {
  assertAnchors(
    await text(path.join(packageRoot, "memory", "kanban", "README.md")),
    ["external tracker"],
    "kanban README",
  );
});

test("router points project routes at project memory, not rooms", async () => {
  const router = await text(path.join(root, "pkg", "adapters", "router.md"));
  assert.doesNotMatch(router, /appropriate room/i);
  assertAnchors(
    router,
    [
      ".aihaus/memory/project/",
      "package-owned",
      "default role and profile",
      "user-facing session",
      "higher-priority instructions",
      "delegation policy",
      "existing authorization",
      "retain their assigned roles",
      "Without these defaults",
      "starts and resumes",
      ".aihaus/roles/orchestrator.md",
    ],
    "router adapter",
  );
});

test("orchestrator role carries the start/resume loop", async () => {
  const role = await text(path.join(packageRoot, "roles", "orchestrator.md"));
  assertAnchors(
    role,
    [
      "single writer",
      "start and resume",
      "explicitly reread",
      "reconcile integrated work",
      "coherent outcome",
      "disjoint files",
      "run sequentially",
      "planner assignment",
      "separate project-defined limits",
      "implementation assignments only",
      "empty terminal is",
      "real stalls",
      "scope-check.mjs",
      "--base",
      "judgment pass",
      "invalidates its prior review",
      "explicit authorization from the user or accepted",
      "first remote write",
      "post-merge procedure",
      "preserve unmerged work",
      "continue independent authorized work",
      "two unsuccessful fix cycles",
      "pre-existing failures from regressions",
      "provenance",
      "procedures.md",
    ],
    "orchestrator role",
  );
  assert.ok(lineCount(role) <= 50, "orchestrator role must stay compact");
});

test("planner role returns a read-only plan to the orchestrator", async () => {
  assertAnchors(
    await text(path.join(packageRoot, "roles", "planner.md")),
    [
      "read-only",
      "orchestrator",
      "outcome",
      "dependencies",
      "owned files",
      "self-contained",
      "unresolved gaps",
      "never dispatch",
      "receive their deliveries",
      "worktree",
      "commit",
    ],
    "planner role",
  );
});

test("README delegation section documents profiles, session defaults, and Autonomy", async () => {
  const readme = await text(path.join(root, "README.md"));
  const start = readme.indexOf("### Delegate to specialist agents");
  const end = readme.indexOf("## Update aihaus");
  assert.ok(start !== -1 && end > start, "README must have a Delegate to specialist agents section");
  assertAnchors(
    readme.slice(start, end),
    [
      "illustrative",
      "| security | reviewer |",
      "| Profile | Role | Host / provider | Model | Effort |",
      "planner (optional)",
      "Main session: orchestrator. Default profile:",
      "no kickoff prompt",
      "moving alias",
      "exact model ID",
      "resolution was unavailable",
      "allowed fallbacks by role",
      "## Autonomy",
      "first remote write",
      "Resume <task> with its recorded profile",
      "host configuration",
    ],
    "README delegation section",
  );
});

test("install via LLM covers customized installs and the init check", async () => {
  assertAnchors(
    await text(path.join(root, "INSTALL-VIA-LLM.md")),
    ["customized", "INIT.md", "wouldRefresh"],
    "INSTALL-VIA-LLM.md",
  );
});

test("README update section covers customized installs and project memory", async () => {
  const readme = await text(path.join(root, "README.md"));
  const start = readme.indexOf("## Update aihaus");
  assert.notEqual(start, -1, "README must have an Update aihaus section");
  const rest = readme.slice(start + "## Update aihaus".length);
  const next = rest.search(/^## /m);
  const section = next === -1 ? rest : rest.slice(0, next);
  assertAnchors(section, ["customized", "INIT.md", "project memory"], "README Update section");
});

test("architecture doc describes two coordination levels and assignments", async () => {
  assertAnchors(
    await text(path.join(root, "docs", "architecture.md")),
    [
      "two coordination levels",
      "Assignments",
      "star-shaped",
      "Autonomy",
      "default role and profile",
      "rereads",
      "Existing installs",
    ],
    "docs/architecture.md",
  );
});

test("release version is consistent across changelog and README install pin", async () => {
  const version = (await text(path.join(root, "pkg", "VERSION"))).trim();
  const readme = await text(path.join(root, "README.md"));
  assert.ok(readme.includes(`Current published release (\`v${version}\`)`));
  assert.ok(readme.includes(`releases/download/v${version}/aihaus-flow-v${version}.tgz`));
  const changelog = await text(path.join(root, "pkg", "CHANGELOG.md"));
  assert.match(changelog, new RegExp(`^## ${escapeRegExp(version)} - `, "m"));
});

test("root CLAUDE.md imports AGENTS.md as its first non-empty line", async () => {
  const lines = (await text(path.join(root, "CLAUDE.md"))).split(/\r?\n/).filter((line) => line.trim() !== "");
  assert.equal(lines[0], "@AGENTS.md");
});

test("refresh template hashes match the project memory templates", async () => {
  const refresh = await text(path.join(packageRoot, "tools", "refresh.mjs"));
  const block = /const templateHashes = new Map\(\[([\s\S]*?)\]\);/.exec(refresh);
  assert.ok(block, "refresh.mjs must declare templateHashes");
  const hashes = new Map(
    [...block[1].matchAll(/\["([^"]+)",\s*"([0-9a-f]{64})"\]/g)].map((match) => [match[1], match[2]]),
  );

  const projectDir = path.join(packageRoot, "memory", "project");
  const templates = (await readdir(projectDir)).filter((name) => name.endsWith(".md") && name !== "README.md").sort();
  assert.equal(templates.length, 8);
  assert.deepEqual([...hashes.keys()].sort(), templates);

  for (const name of templates) {
    const digest = createHash("sha256")
      .update(markdownText(await readFile(path.join(projectDir, name))))
      .digest("hex");
    assert.equal(hashes.get(name), digest, `${name} hash must match templateHashes in refresh.mjs`);
  }
});

test("evidence validator accepts optional commit metadata on the document and rungs", () => {
  const result = validateEvidenceDocument({
    schema: "aihaus.evidence.v1",
    verdict: "PASS",
    commit: "0123456789abcdef0123456789abcdef01234567",
    acceptance: [{
      criterion: "contract tests pass",
      status: "satisfied",
      executable: true,
      evidence: [{
        rung: "ran",
        source: "tool",
        command: "node --test",
        exit_code: 0,
        commit: "0123456789abcdef0123456789abcdef01234567",
      }],
    }],
  });
  assert.equal(result.ok, true, result.errors.join("; "));
});

test("upgrade keeps project-owned assignments and refreshes package-owned rooms", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "aihaus-assignments-"));
  try {
    run("git", ["init", "-b", "main"], temp);
    await writeFile(path.join(temp, "README.md"), "# Target project\n", "utf8");

    run(process.execPath, [setup, "--target", temp, "--json"], temp);

    const procedures = path.join(temp, ".aihaus", "memory", "project", "procedures.md");
    const projectProcedures =
      (await text(procedures)) +
      "\n## Assignments\n\nMain session: orchestrator. Default profile: claude.\n\n" +
      "| assignment | role |\n|---|---|\n| security | reviewer |\n" +
      "\n## Autonomy\n\n- May: push and open a change request.\n- Needs the owner: releases.\n";
    await writeFile(procedures, projectProcedures, "utf8");
    await writeFile(path.join(temp, ".aihaus", "rooms", "feature", "CONTEXT.md"), "custom\n", "utf8");
    await simulateOlderInstall(temp);

    const upgraded = JSON.parse(run(process.execPath, [setup, "--target", temp, "--json"], temp).stdout);
    await assertRouterRefreshed(temp, upgraded);

    assert.equal(await text(procedures), projectProcedures);
    assert.ok(
      upgraded.refreshed.some((entry) => entry.startsWith(".aihaus/rooms/")),
      `rooms must be listed under refreshed, got ${JSON.stringify(upgraded.refreshed)}`,
    );
    assert.notEqual(await text(path.join(temp, ".aihaus", "rooms", "feature", "CONTEXT.md")), "custom\n");

    const map = await text(path.join(temp, ".aihaus", "MAP.md"));
    assertAnchors(map, ["Assignments", "procedures.md", "Autonomy"], "installed MAP.md");
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});

test("install and upgrade succeed when procedures lack Assignments and Autonomy", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "aihaus-no-assignments-"));
  try {
    run("git", ["init", "-b", "main"], temp);
    await writeFile(path.join(temp, "README.md"), "# Target project\n", "utf8");

    const installed = JSON.parse(run(process.execPath, [setup, "--target", temp, "--json"], temp).stdout);
    assert.equal(installed.ok, true);

    const procedures = path.join(temp, ".aihaus", "memory", "project", "procedures.md");
    const before = await text(procedures);
    assert.doesNotMatch(before, /## (Assignments|Autonomy)/);
    await simulateOlderInstall(temp);

    const upgraded = JSON.parse(run(process.execPath, [setup, "--target", temp, "--json"], temp).stdout);
    await assertRouterRefreshed(temp, upgraded);
    assert.equal(await text(procedures), before);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});
