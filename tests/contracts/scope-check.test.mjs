import assert from "node:assert/strict";
import test from "node:test";
import { isAllowed } from "../../pkg/.aihaus/tools/scope-check.mjs";

test("scope check accepts exact files and directory descendants", () => {
  assert.equal(isAllowed("src/auth/token.mjs", ["src/auth/"]), true);
  assert.equal(isAllowed("README.md", ["README.md"]), true);
  assert.equal(isAllowed("src/authz/token.mjs", ["src/auth/"]), false);
});

test("scope check normalizes separators without widening a rule", () => {
  assert.equal(isAllowed("src\\auth\\token.mjs", ["src/auth"]), true);
  assert.equal(isAllowed("other/auth/token.mjs", ["src/auth"]), false);
});
