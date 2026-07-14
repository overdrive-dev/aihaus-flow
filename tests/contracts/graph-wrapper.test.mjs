import assert from "node:assert/strict";
import test from "node:test";
import { withLocalDefaults } from "../../pkg/.aihaus/tools/graph.mjs";

const options = { repo: "/repo", db: "/repo/.aihaus/state/aih-graph.db" };

test("graph wrapper pins repository-local state before positional arguments", () => {
  assert.deepEqual(withLocalDefaults(["query", "auth token"], options), [
    "query",
    "--repo",
    options.repo,
    "--db",
    options.db,
    "auth token",
  ]);
  assert.deepEqual(withLocalDefaults(["callers", "Parse"], options), [
    "callers",
    "--db",
    options.db,
    "Parse",
  ]);
});

test("graph wrapper preserves explicit repo and database overrides", () => {
  assert.deepEqual(
    withLocalDefaults(["context", "--repo", "/other", "--db=/tmp/custom.db", "Symbol"], options),
    ["context", "--repo", "/other", "--db=/tmp/custom.db", "Symbol"],
  );
});

test("graph wrapper does not bypass explicit indexing consent", () => {
  const result = withLocalDefaults(["refresh", "--json"], options);
  assert.ok(!result.includes("--accept-all-repos"));
});
