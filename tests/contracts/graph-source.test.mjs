import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");

async function text(relative) {
  return readFile(path.join(root, relative), "utf8");
}

test("aih-graph indexes the portable instruction surface", async () => {
  const [main, extractor, types] = await Promise.all([
    text("aih-graph/cmd/aih-graph/main.go"),
    text("aih-graph/internal/extract/instruction.go"),
    text("aih-graph/internal/types/types.go"),
  ]);
  assert.match(main, /ParseInstructionsDir/);
  for (const nodeType of ["Map", "Convention", "Role", "Room", "Contract", "Tool"]) {
    assert.match(extractor + types, new RegExp(`"${nodeType}"`), nodeType);
  }
  for (const removed of ["pkg/.aihaus/agents", "pkg/.aihaus/skills", "pkg/.aihaus/hooks", "pkg/.aihaus/protocols"]) {
    assert.doesNotMatch(main + extractor + types, new RegExp(removed.replaceAll(".", "\\.")), removed);
  }
});

test("aih-graph reads decisions and rules from typed project memory", async () => {
  const main = await text("aih-graph/cmd/aih-graph/main.go");
  assert.match(main, /"memory", "project", "decisions\.md"/);
  assert.match(main, /"memory", "project", "business-rules\.md"/);

  const [rules, decisions] = await Promise.all([
    text("pkg/.aihaus/memory/project/business-rules.md"),
    text("pkg/.aihaus/memory/project/decisions.md"),
  ]);
  assert.doesNotMatch(rules, /^### BR-[A-Za-z0-9-]+\s/m, "seed must not create a phantom Rule node");
  assert.doesNotMatch(decisions, /^## ADR-[A-Za-z0-9-]+\s/m, "seed must not create a phantom Decision node");
});
