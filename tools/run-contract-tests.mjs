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
  "tests/contracts/assignments.test.mjs",
  "tests/contracts/online-action-gate.test.mjs",
  "tests/contracts/path-safety.test.mjs",
  "tests/lab/agent-install.test.mjs",
  "tests/lab/project-bootstrap.test.mjs",
  "tests/lab/lab-controller.test.mjs",
  "tests/lab/release-package.test.mjs",
].map((file) => path.join(root, file));

// --docker reruns this suite on Linux (node:22) from a copy without generated lab state.
// A linked worktree's .git file points at a host path, so the copy gets a snapshot repository.
const dockerScript = [
  "mkdir /w && tar -C /src --exclude=./.aihaus-lab -cf - . | tar -C /w -xf - && cd /w",
  "if [ -f .git ]; then rm .git && git init -q && git add -A && git -c user.name=aihaus -c user.email=aihaus@local.invalid commit -qm snapshot; fi",
  "node tools/run-contract-tests.mjs",
].join(" && ");
const [command, args] = process.argv.includes("--docker")
  ? ["docker", ["run", "--rm", "-v", `${root}:/src:ro`, "node:22", "sh", "-c", dockerScript]]
  : [process.execPath, ["--test", ...tests]];
const result = spawnSync(command, args, { cwd: root, stdio: "inherit" });

if (result.error) throw result.error;
process.exitCode = result.status ?? 1;
