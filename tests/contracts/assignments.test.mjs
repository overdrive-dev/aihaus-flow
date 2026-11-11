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
      "base or candidate SHA",
      "path and revision",
      "assigns each required pass",
      "self-check",
      "never satisfies a required pass",
      "not a delegated executor may start the separate context",
      "## Working style",
      "The agent chooses how to carry out each request",
      "or through a host multi-agent workflow engine when the host enables one",
      "a recorded delegation policy, and concurrency limits",
      "The task records who implemented, who reviewed, and the profile used",
      "A behavior change gets a judgment pass on its candidate SHA before completion or integration",
      "a covered, low-risk mechanical edit on the feature room's quick path needs none",
      "The profile's reviewer, or the reviewer the user names, runs it",
      "preferably from another model family when one is available",
      "Only the user's request skips a required pass",
      "reports the result as unreviewed and names each skipped pass",
      "a skipped pass satisfies no Autonomy condition",
      "a valid receipt for the unchanged candidate SHA still does",
      "A requirement resolved silently passes its own tests",
      "they are not a stop",
      "Record on the task each decision assumed on an ambiguous requirement that changes behavior users or callers can observe",
      "including ambiguities a spec review reports as unlisted",
      "and continue",
      "Technical mechanics follow `conventions.md` and are not listed",
      "Every judgment pass's brief includes the list, the reviewer checks each decision against the request",
      "the result reports the list so the user can overturn any decision",
      "Ambiguity that no reasonable reading resolves, or that needs owner authority, is a business-rule question instead",
      "A read-only planner (profile planner model) returns the spec as `roles/planner.md` describes",
      "the orchestrator saves it",
      "links it by path and revision",
      "Before any dispatch, a judgment pass reviews the spec",
      "its findings return to the planner in a fresh context",
      "at most two cycles",
      "Executors (profile executor model) implement the packets in parallel",
      "each in its own files, running their own tests",
      "After all packets, the orchestrator runs the full deterministic suite",
      "one rework from its output",
      "a final judgment pass then reviews the candidate SHA",
      "Past either limit, the affected work pauses",
      "Review fixes run in a fresh context",
      "an executor or a new session briefed with the candidate diff and the findings",
      "never by resuming the authoring session",
      "counts as resuming",
      "A spec amended after its review, by anyone, needs a new spec review",
      "count across runs against their limits",
      "Spec reviews, their verdict receipts, and rechecks follow `adversarial-review.md`",
      "A task runs to completion and stops only for a business-rule question",
      "before the first remote write without authorization",
      "Keep orchestration thin",
      "one subagent, CLI run, or host workflow agent per packet or outcome",
      "rely on summaries and `tools/scope-check.mjs`",
      "fills only a role whose profile model is the session's",
      "is not a separate context",
      "directly or as a step of its host run",
      "Run `node .aihaus/tools/refresh.mjs --repo . --status` for a short summary",
      "If the packet is missing or stale, rebuild it by running the same command without `--status`, then check status again",
      "Add `--json` only when the summary counts a conflict or warning, or names a gap or stale claim on a page or source this task depends on",
      "The feature room's quick path needs only its log record",
      "The feature room's quick path carries no acceptance criteria or evidence document: one `tools/task.mjs log` record, repeated in the result, lists the changed files and each command with its exit code",
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
      "capacity (",
      "every earlier finding fixed on this task",
      "across all rounds",
      "reruns their reproductions",
      "cannot reach the state it requires",
      "historical state the candidate cannot recreate",
      "Check each assumed decision recorded on the task against the request",
      "## Spec review",
      "When a spec drives executors, review it before dispatch",
      "against the request and the code",
      "not against tests derived from it",
      "a wrong spec passes its own suite",
      "For each criterion, check the cited root cause, the exact behavior, the case table, and the tests to add",
      "Report every ambiguous requirement the spec resolves",
      "without listing it under Assumed decisions",
      "check that packets own disjoint files",
      "for a plan or spec review, the spec's path and revision",
      "(commit SHA or content hash) instead",
      "candidate SHA or spec revision",
      "Any later product or spec change needs a new pass",
    ],
    "adversarial review contract",
  );
});

test("evidence contract accepts commit metadata as unvalidated", async () => {
  assertAnchors(
    await text(path.join(packageRoot, "contracts", "evidence.md")),
    ["commit", "unvalidated metadata", "clean checkout or export", "not a degraded check", "The feature room's quick path makes no evidence document: its log record and result list each command and exit code"],
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
      "and concurrency limits",
      "the harness Working style says how work runs",
      "feature room, use its quick path (one log record, no evidence document)",
    ],
    "MAP.md",
  );
  assert.ok(lineCount(map) <= 50, "MAP.md must stay at or under 50 lines");
});

test("conventions name package-owned files and external trackers", async () => {
  assertAnchors(
    await text(path.join(packageRoot, "conventions.md")),
    ["external tracker", "package-owned", "THIRD-PARTY-NOTICES.md", "is an assumed decision: record it on the task and continue", "missing business rule that materially changes the outcome is a rule gap"],
    "conventions.md",
  );
});

test("conventions and review carry the reuse-first change ladder", async () => {
  assertAnchors(
    await text(path.join(packageRoot, "conventions.md")),
    [
      "Code changes take the first option that fully works",
      "skip what nobody asked for and name it in the report",
      "reuse what the repository already has",
      "then the standard library or platform",
      "never a new one for a few lines",
      "Finish every caller, test, fixture, and export",
      "A vague request gets the smallest version that does its core job",
      "between options of equal size, pick the one correct on edge cases",
      "Add no abstraction, wrapper, type conversion",
      "keep values in the form the platform returns",
      "Comments explain only the why that the code cannot show",
      "Never trade away, even in moved or merged code, validation at trust boundaries",
      "calibration that physical hardware needs",
      "`shortcut: <the limit>, <when to upgrade>`",
    ],
    "conventions.md",
  );
  const notices = await text(path.join(packageRoot, "THIRD-PARTY-NOTICES.md"));
  assertAnchors(notices, [
    "The change ladder in `conventions.md` and the complexity lens in `contracts/adversarial-review.md` are adapted from",
    "Copyright (c) 2026 DietrichGebert",
    "The above copyright notice and this permission notice shall be included",
  ], "THIRD-PARTY-NOTICES.md");
  const license = await text(path.join(root, "pkg", "LICENSE"));
  assert.equal(notices.slice(notices.indexOf("MIT License")).trim(), license.slice(license.lastIndexOf("MIT License")).trim());
  assert.doesNotMatch(await text(path.join(packageRoot, "conventions.md")), /Copyright \(c\) 2026 DietrichGebert|Permission is hereby granted/);
  assertAnchors(
    await text(path.join(root, "pkg", "LICENSE")),
    ["Copyright (c) 2026 DietrichGebert"],
    "package license",
  );
  assertAnchors(
    await text(path.join(packageRoot, "contracts", "adversarial-review.md")),
    ["complexity (code that need not exist", "a `shortcut:` comment that names its limit is a decision"],
    "adversarial review contract",
  );
  assertAnchors(
    await text(path.join(packageRoot, "roles", "implementer.md")),
    ["what you skipped or left unchecked"],
    "implementer role",
  );
});

test("feature room explains the external tracker override", async () => {
  assertAnchors(
    await text(path.join(packageRoot, "rooms", "feature", "CONTEXT.md")),
    [
      "external tracker",
      "Quick path: for a covered, low-risk, mechanical edit",
      "without acceptance criteria, an evidence document, status moves, or planning artifacts",
      "unless an accepted project rule requires a full task for every change",
      "Run the checks that cover the edit, then log it with one call",
      "node .aihaus/tools/task.mjs log --title <what changed> --text <changed files; each command with its exit code; assumed decisions; what was skipped>",
      "Report the same in the result",
      "A delegated executor returns that text to the task writer instead of logging it",
      "`contracts/evidence.md`; add adversarial review before completion (the quick path loads neither)",
      "With an accepted external tracker, log it where that decision says",
      "An edit that turns out not to be covered, low-risk, and mechanical leaves the quick path: create the task and follow the Path",
      "Auth, payments, destructive actions, schema migrations, secrets, and production work never qualify as quick",
    ],
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
      "existing authorization",
      "retain their assigned roles",
      "Without these defaults",
      "starts and resumes",
      ".aihaus/roles/orchestrator.md",
      "Choose how to carry out the request under Working style in the harness",
      "node .aihaus/tools/refresh.mjs --repo . --status`",
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
      "failed status read is unknown",
      "decision rule and a case table",
      "counting a fix that opens a new case",
      "brief rewritten as a decision rule",
      "affected work pauses",
      "never act on it",
      "Choose how to carry out the request (harness, Working style): plan directly when scope is known",
    ],
    "orchestrator role",
  );
  assert.ok(lineCount(role) <= 50, "orchestrator role must stay compact");
});

test("implementer and verifier roles carry the review-fix rules", async () => {
  assertAnchors(
    await text(path.join(packageRoot, "roles", "implementer.md")),
    ["regression test that fails before the fix"],
    "implementer role",
  );
  assertAnchors(
    await text(path.join(packageRoot, "roles", "verifier.md")),
    ["clean checkout or export of the candidate SHA"],
    "verifier role",
  );
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
      "When the plan will drive executors (harness, Working style), return it as a spec",
      "Split it into packets that own disjoint files inside the task worktree",
      "For each acceptance criterion, give the root cause at `path:line`, the exact behavior",
      "a case table for a rule over open inputs",
      "and the tests to add",
      "End with an \"Assumed decisions\" list",
      "naming every decision taken on an ambiguous requirement",
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
      "With these defaults no kickoff prompt is needed: you talk in natural language",
      "moving alias",
      "exact model ID",
      "resolution was unavailable",
      "allowed fallbacks by role",
      "## Autonomy",
      "first remote write",
      "Resume <task> with its recorded profile",
      "host configuration",
      "| `claude` | executors | Claude Code / Anthropic | `haiku` | max | one subagent per packet or outcome |",
      "| `openai` | executors | Codex / OpenAI | `gpt-6.1-sol` | xhigh | one `codex exec` run per packet or outcome |",
      "| `mixed` | executors | Claude Code / Anthropic | `haiku` | max | one subagent per packet or outcome |",
      "| `luna` | orchestrator | Claude Code / Anthropic | `opus` | xhigh | the session you talk to |",
      "| `luna` | planner | Claude Code / Anthropic | `opus` | xhigh | read-only subagent that returns the spec |",
      "| `luna` | reviewer | Codex / OpenAI | `gpt-6.1-sol` | xhigh | `codex exec ... -s read-only` |",
      "| `luna` | executors | Codex / OpenAI | `gpt-6-luna` | max | one `codex exec` run per packet |",
      "Executors must be able to run the project's tests",
      "On Windows, the Codex unelevated sandbox blocks child processes",
      "spawn EPERM",
      "run each Codex executor in an isolated worktree with `-s danger-full-access`, or use the elevated sandbox",
      "Default profile: claude. Limits: up to 4 executors; tests run one at a time.",
      "The agent chooses how to carry out each request",
      "A behavior change gets a review in a separate context, by the profile's reviewer or one you name",
      "Only you can skip a review, by asking in the request",
      "The agent does not stop to confirm its assumptions",
      "records each decision it assumed on an ambiguous requirement that changes what users or callers can observe",
      "the result lists them so you can overturn any",
      "When a planner's spec drives parallel executors, the spec is reviewed before dispatch",
      "The task runs end to end",
      "A recorded `Delegation:` policy in Assignments, such as everything except trivial requests, still applies",
      "These triggers apply whenever the work uses a planner or executors",
      "the planner also runs for large or unfamiliar scope under orchestrator step 3",
      "the agent decides how to use them, and the rules above still apply",
      "Fix the typo in the install section. No review.",
      "Profile: luna. Fix the findings listed in docs/audit.md, in parallel.",
      "preferably from another model family when one is available",
      "Review fixes run in a fresh context",
      "rechecks follow `adversarial-review.md`",
      "integrates within Autonomy unless you direct otherwise",
      "It still asks when a missing business rule would materially change the outcome",
      "yields no verdict",
      "Review fixes run in a fresh context, not in the session that wrote the code",
    ],
    "README delegation section",
  );
  const executorRows = readme.slice(start, end).match(/^\|[^\n]*\| executors \|[^\n]*$/gm) ?? [];
  assert.ok(executorRows.length >= 4, "README must list an executor row per example profile");
  for (const row of executorRows) {
    assert.doesNotMatch(row, /multi-agent workflow/i, `executors are dispatched directly: ${row}`);
    if (/`(haiku|gpt-6-luna)`/.test(row)) {
      assert.match(row, /\| max \|/, `Haiku and Luna executors run at max: ${row}`);
    }
  }
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
      "The agent chooses how to carry out each request",
      "only the user can skip it",
      "a requirement resolved silently passes its own tests",
      "which v1.14.0 removed",
      "a spec error reaches every executor and every test derived from the spec",
      "The rules are under Working style in the harness",
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

test("1.16.0 changelog documents lean startup and its migration opt-out", async () => {
  const changelog = await text(path.join(root, "pkg", "CHANGELOG.md"));
  const start = changelog.indexOf("## 1.16.0 - 2026-11-11");
  assert.notEqual(start, -1, "1.16.0 changelog entry must exist");
  const end = changelog.indexOf("\n## ", start + 1);
  assertAnchors(changelog.slice(start, end === -1 ? undefined : end), [
    "Migration:",
    "one log record in `memory/kanban/done/` via `task.mjs log`",
    "without acceptance criteria, evidence documents, status moves, or planning artifacts",
    "the quick path uses one `task.mjs log` record in `memory/kanban/done/` instead of a full task with acceptance criteria, status moves, and evidence JSON",
    "an accepted project rule requiring a full task for every change",
    "`task.mjs` and `evidence-validate.mjs` now reject unknown options and extra arguments they previously ignored",
    "The text of `--status` without `--json` changed; `--status --json` is unchanged",
    "accept `--help` or `-h` as the only argument",
    "THIRD-PARTY-NOTICES.md",
    "Project memory templates are unchanged.",
  ], "1.16.0 changelog entry");
  for (const file of ["README.md", "docs/architecture.md"]) {
    assertAnchors(await text(path.join(root, file)), [
      "quick path: one kanban log record via `task.mjs log`, instead of acceptance criteria and an evidence document",
      "an accepted project rule can require a full task for every change",
    ], file);
  }
});

test("assumed decisions are recorded and reported, never a confirmation stop", async () => {
  const stop = /get the user's confirmation|unconfirmed assumed decision|Assumed decisions: accept|waits for your answer/;
  for (const file of [
    path.join(packageRoot, "contracts", "harness.md"),
    path.join(packageRoot, "conventions.md"),
    path.join(root, "pkg", "adapters", "router.md"),
    path.join(root, "README.md"),
    path.join(root, "docs", "architecture.md"),
  ]) {
    assert.doesNotMatch(await text(file), stop, file);
  }
  const changelog = await text(path.join(root, "pkg", "CHANGELOG.md"));
  const start = changelog.indexOf("## 1.15.0 - ");
  assert.notEqual(start, -1, "1.15.0 changelog entry must exist");
  const end = changelog.indexOf("\n## ", start + 1);
  assertAnchors(
    changelog.slice(start, end === -1 ? undefined : end),
    [
      "`Assumed decisions: accept.` is no longer needed and has no effect",
      "To review the assumptions before any code is written, ask for that in the request",
    ],
    "1.15.0 changelog entry",
  );
});

test("package guidance names no execution mode", async () => {
  const executionMode = /`(pure|normal|workflow|auto)`|[Ee]xecution modes?|Default mode|\bMode:\s*`?(pure|normal|workflow|auto)\b/;
  for (const mode of ["pure", "normal", "workflow", "auto"]) {
    assert.match(`Mode: ${mode}.`, executionMode);
    assert.match(`Mode:\`${mode}\`.`, executionMode);
    assert.match(`Mode:  \`${mode}\`.`, executionMode);
  }
  const files = [
    path.join(packageRoot, "MAP.md"),
    path.join(packageRoot, "contracts", "harness.md"),
    path.join(packageRoot, "contracts", "adversarial-review.md"),
    path.join(packageRoot, "roles", "orchestrator.md"),
    path.join(packageRoot, "roles", "planner.md"),
    path.join(root, "pkg", "adapters", "router.md"),
  ];
  for (const file of files) {
    assert.doesNotMatch(await text(file), executionMode, file);
  }
});

test("1.14.0 changelog documents migration from execution modes", async () => {
  const changelog = await text(path.join(root, "pkg", "CHANGELOG.md"));
  const start = changelog.indexOf("## 1.14.0 - ");
  assert.notEqual(start, -1, "1.14.0 changelog entry must exist");
  const end = changelog.indexOf("\n## ", start + 1);
  assertAnchors(
    changelog.slice(start, end === -1 ? undefined : end),
    [
      "`Default mode:` lines in Assignments no longer have an effect; delete them",
      "`Default mode: delegation.` becomes the recorded `Delegation:` policy, which still applies",
      "`Mode: pure.` means work alone without review, reported as unreviewed",
      "To fix how work runs for a project, record a `Delegation:` policy in Assignments",
    ],
    "1.14.0 changelog entry",
  );
});

test("1.13.0 changelog documents migration for the removed CLAUDE.md", async () => {
  const changelog = await text(path.join(root, "pkg", "CHANGELOG.md"));
  const start = changelog.indexOf("## 1.13.0 - ");
  assert.notEqual(start, -1, "1.13.0 changelog entry must exist");
  const end = changelog.indexOf("\n## ", start + 1);
  assertAnchors(
    changelog.slice(start, end === -1 ? undefined : end),
    [
      "a CLAUDE.md that holds only the aihaus block is removed",
      "A CLAUDE.md with your own text keeps its import",
      "need a CLAUDE.md with your own `@AGENTS.md` line; setup keeps it",
    ],
    "1.13.0 changelog entry",
  );
});

test("1.12.0 changelog documents migration and opt-out", async () => {
  const changelog = await text(path.join(root, "pkg", "CHANGELOG.md"));
  const start = changelog.indexOf("## 1.12.0 - ");
  assert.notEqual(start, -1, "1.12.0 changelog entry must exist");
  const end = changelog.indexOf("\n## ", start + 1);
  assertAnchors(
    changelog.slice(start, end === -1 ? undefined : end),
    [
      "the ladder applies to every code change",
      "To keep a different rule, state it in repository instructions or an accepted project rule",
    ],
    "1.12.0 changelog entry",
  );
});

test("1.11.0 changelog documents migration and opt-out", async () => {
  const changelog = await text(path.join(root, "pkg", "CHANGELOG.md"));
  const start = changelog.indexOf("## 1.11.0 - ");
  assert.notEqual(start, -1, "1.11.0 changelog entry must exist");
  const end = changelog.indexOf("\n## ", start + 1);
  assertAnchors(
    changelog.slice(start, end === -1 ? undefined : end),
    [
      "Under a standing host opt-in, `normal` no longer delegates " +
        "implementation to host-run agents; request `Mode: workflow.` " +
        "to delegate.",
      "A standing host opt-in now counts as asking for a host run; " +
        "to keep host runs per request, turn the opt-in off and ask " +
        "per prompt.",
    ],
    "1.11.0 changelog entry",
  );
});

test("1.10.0 changelog documents migration and opt-out", async () => {
  const changelog = await text(path.join(root, "pkg", "CHANGELOG.md"));
  const start = changelog.indexOf("## 1.10.0 - ");
  assert.notEqual(start, -1, "1.10.0 changelog entry must exist");
  const end = changelog.indexOf("\n## ", start + 1);
  assertAnchors(
    changelog.slice(start, end === -1 ? undefined : end),
    [
      "Projects that record a `Delegation:` policy and no `Default mode:` " +
        "move to `auto` on update unless they record it",
      "`Default mode: delegation.` keeps the project's delegation policy",
    ],
    "1.10.0 changelog entry",
  );
});

test("maintainer repository has no root CLAUDE.md, so Claude reads AGENTS.md", async () => {
  await assert.rejects(text(path.join(root, "CLAUDE.md")), { code: "ENOENT" });
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
