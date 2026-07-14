import assert from "node:assert/strict";
import test from "node:test";
import { increment } from "../src/counter.mjs";

test("increments a finite number", () => {
  assert.equal(increment(1), 2);
});

test("rejects non-finite input", () => {
  assert.throws(() => increment(Number.NaN), /finite number/);
});
