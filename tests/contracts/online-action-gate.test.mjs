import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import {
  classifyOnlineAction,
  evaluateOnlineAction,
} from "../../pkg/.aihaus/tools/online-action-gate.mjs";

test("classifies local checks separately from online mutation", () => {
  assert.equal(classifyOnlineAction("node --test").online, false);
  assert.equal(classifyOnlineAction("git status --short").online, false);
  assert.equal(classifyOnlineAction("git push origin main").kind, "git-push");
  assert.equal(classifyOnlineAction("kubectl apply -f deploy.yml").online, true);
});

test("classifies chained, subshell, and global-option promotion spellings", () => {
  for (const command of [
    "npm test\ngit push",
    "(git push)",
    "echo $(git push)",
    "echo `git push`",
    "git -C . push",
    "git --no-pager push",
    "git -c k=v push origin main",
    "git --git-dir .git push",
    "git --git-dir=.git push",
    "git --work-tree . push origin main",
    'git -C "repo with spaces" push',
    "  git push",
  ]) {
    assert.equal(classifyOnlineAction(command).kind, "git-push", command);
  }
  assert.equal(classifyOnlineAction("flyctl deploy").kind, "cloud-deploy");
  for (const command of ["git -C . status", "git --git-dir .git status", "git commit -m push", "echo git push", "git log --grep=push"]) {
    assert.equal(classifyOnlineAction(command).online, false, command);
  }
});

test("ignores host-specific sentinels", async () => {
  const repo = await mkdtemp(path.join(os.tmpdir(), "aihaus-online-gate-"));
  try {
    const state = path.join(repo, ".claude", "_state");
    await mkdir(state, { recursive: true });
    await writeFile(path.join(state, "active-flow"), "T-260714-test\n");
    const result = await evaluateOnlineAction({ command: "git push origin main", repo });
    assert.equal(result.allowed, false);
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("blocks online actions without an active-flow sentinel", async () => {
  const repo = await mkdtemp(path.join(os.tmpdir(), "aihaus-online-gate-"));
  try {
    const result = await evaluateOnlineAction({ command: "npm publish", repo });
    assert.equal(result.allowed, false);
    assert.equal(result.reason, "online-action-without-active-flow");
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});

test("allows online actions when the deterministic sentinel exists", async () => {
  const repo = await mkdtemp(path.join(os.tmpdir(), "aihaus-online-gate-"));
  try {
    const state = path.join(repo, ".aihaus", "state");
    await mkdir(state, { recursive: true });
    await writeFile(path.join(state, "active-flow"), "T-260714-test\n");
    const result = await evaluateOnlineAction({ command: "gh release create v1.0.0", repo });
    assert.equal(result.allowed, true);
    assert.equal(result.reason, "active-flow");
  } finally {
    await rm(repo, { recursive: true, force: true });
  }
});
