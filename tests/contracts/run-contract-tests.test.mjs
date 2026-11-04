import assert from "node:assert/strict";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { getCommand, runTests } from "../../tools/run-contract-tests.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");

test("native runner uses Node's test runner and includes its own contracts", () => {
  const [command, args] = getCommand([]);

  assert.equal(command, process.execPath);
  assert.equal(args[0], "--test");
  assert.ok(args.includes(path.join(root, "tests/contracts/run-contract-tests.test.mjs")));
});

test("Docker runner copies the checkout without lab state or host ownership", () => {
  const [command, args] = getCommand(["--docker"]);

  assert.equal(command, "docker");
  assert.equal(args[args.indexOf("-v") + 1], `${root}:/src:ro`);
  assert.ok(args.includes("node:22"));
  assert.match(args.at(-1), /--exclude=\.\/\.aihaus-lab/);
  assert.match(args.at(-1), /tar -C \/w --no-same-owner -xf -/);
});

test("runner returns the child status or 1 when the child has no status", () => {
  assert.equal(runTests([], () => ({ status: 3 })), 3);
  assert.equal(runTests([], () => ({ status: null })), 1);
});

test("runner throws spawn errors", () => {
  const error = new Error("spawn failed");
  assert.throws(() => runTests([], () => ({ error })), error);
});
