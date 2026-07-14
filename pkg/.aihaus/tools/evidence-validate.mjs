#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const STATUSES = new Set(["satisfied", "partial", "not_satisfied"]);
const RUNGS = new Set(["written", "ran", "verified", "blocked"]);
const TRUSTED_EXECUTION_SOURCES = new Set(["tool", "ci"]);

export function validateEvidenceDocument(document) {
  const errors = [];

  if (!document || typeof document !== "object" || Array.isArray(document)) {
    return { ok: false, errors: ["document must be an object"] };
  }
  if (document.schema !== "aihaus.evidence.v1") {
    errors.push("schema must be aihaus.evidence.v1");
  }
  if (!["PASS", "BLOCKED", "FAIL"].includes(document.verdict)) {
    errors.push("verdict must be PASS, BLOCKED, or FAIL");
  }
  if (!Array.isArray(document.acceptance) || document.acceptance.length === 0) {
    errors.push("acceptance must contain at least one criterion");
    return { ok: errors.length === 0, errors };
  }

  for (const [index, item] of document.acceptance.entries()) {
    const prefix = `acceptance[${index}]`;
    if (!item || typeof item !== "object") {
      errors.push(`${prefix} must be an object`);
      continue;
    }
    if (typeof item.criterion !== "string" || item.criterion.trim() === "") {
      errors.push(`${prefix}.criterion must be non-empty`);
    }
    if (!STATUSES.has(item.status)) {
      errors.push(`${prefix}.status must be satisfied, partial, or not_satisfied`);
    }
    if (typeof item.executable !== "boolean") {
      errors.push(`${prefix}.executable must be boolean`);
    }
    if (!Array.isArray(item.evidence)) {
      errors.push(`${prefix}.evidence must be an array`);
      continue;
    }

    for (const [evidenceIndex, evidence] of item.evidence.entries()) {
      if (!evidence || typeof evidence !== "object" || !RUNGS.has(evidence.rung)) {
        errors.push(`${prefix}.evidence[${evidenceIndex}].rung is invalid`);
      }
    }

    if (document.verdict === "PASS" && item.status !== "satisfied") {
      errors.push(`${prefix} must be satisfied when verdict is PASS`);
    }

    if (document.verdict === "PASS" && item.executable === true) {
      const credible = item.evidence.some((evidence) =>
        evidence
        && ["ran", "verified"].includes(evidence.rung)
        && TRUSTED_EXECUTION_SOURCES.has(evidence.source)
        && typeof evidence.command === "string"
        && evidence.command.trim() !== ""
        && Number.isInteger(evidence.exit_code)
        && evidence.exit_code === 0
      );
      if (!credible) {
        errors.push(`${prefix} lacks trusted ran/verified evidence with command and exit_code 0`);
      }
    }
  }

  return { ok: errors.length === 0, errors };
}

async function main() {
  const file = process.argv[2];
  if (!file) {
    process.stderr.write("usage: evidence-validate.mjs <evidence.json>\n");
    process.exitCode = 2;
    return;
  }

  try {
    const document = JSON.parse(await readFile(path.resolve(file), "utf8"));
    const result = validateEvidenceDocument(document);
    process.stdout.write(`${JSON.stringify(result)}\n`);
    if (!result.ok) process.exitCode = 2;
  } catch (error) {
    process.stderr.write(`${JSON.stringify({ ok: false, errors: [error.message] })}\n`);
    process.exitCode = 2;
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url))) {
  await main();
}
