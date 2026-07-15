#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const tests = [
  "tests/contracts/package-layout.test.mjs",
  "tests/contracts/setup.test.mjs",
  "tests/contracts/scope-check.test.mjs",
  "tests/contracts/task-tool.test.mjs",
  "tests/contracts/evidence-validate.test.mjs",
  "tests/contracts/graph-wrapper.test.mjs",
  "tests/contracts/graph-source.test.mjs",
  "tests/contracts/online-action-gate.test.mjs",
  "tests/contracts/path-safety.test.mjs",
  "tests/lab/agent-install.test.mjs",
  "tests/lab/project-bootstrap.test.mjs",
  "tests/lab/lab-controller.test.mjs",
  "tests/lab/release-package.test.mjs",
].map((file) => path.join(root, file));

const result = spawnSync(process.execPath, ["--test", ...tests], {
  cwd: root,
  stdio: "inherit",
});

if (result.error) throw result.error;
process.exitCode = result.status ?? 1;
