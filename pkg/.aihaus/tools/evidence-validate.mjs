#!/usr/bin/env node

import { realpathSync } from "node:fs";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const usage = "Usage: node .aihaus/tools/evidence-validate.mjs <evidence.json>\nHelp: --help or -h as the only argument.";

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
    if (item.evidence.length === 0) errors.push(`${prefix}.evidence must contain at least one rung`);

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
        errors.push(`${prefix} lacks trusted ran/verified evidence: needs source "tool" or "ci", a command, and exit_code 0`);
      }
    }
    if (document.verdict === "PASS" && item.executable === false) {
      const supported = item.evidence.some((evidence) =>
        evidence && ["written", "ran", "verified"].includes(evidence.rung)
        && [evidence.artifact, evidence.detail].some((value) => typeof value === "string" && value.trim() !== "")
      );
      if (!supported) errors.push(`${prefix} lacks non-blocked supporting evidence with artifact or detail`);
    }
  }

  return { ok: errors.length === 0, errors };
}

async function main() {
  const args = process.argv.slice(2);
  const help = args.find((arg) => arg === "--help" || arg === "-h");
  if (help && args.length === 1) {
    process.stdout.write(`${usage}\n`);
    return;
  }

  try {
    if (help) throw new Error(`unknown option: ${help}`);
    const [file] = args;
    if (!file) throw new Error("evidence file is required");
    if (file.startsWith("-")) throw new Error(`unknown option: ${file}`);
    if (args.length > 1) throw new Error(`unknown argument: ${args[1]}`);
    const document = JSON.parse((await readFile(path.resolve(file), "utf8")).replace(/^\uFEFF/, ""));
    const result = validateEvidenceDocument(document);
    process.stdout.write(`${JSON.stringify(result)}\n`);
    if (!result.ok) process.exitCode = 2;
  } catch (error) {
    process.stderr.write(`${JSON.stringify({ ok: false, errors: [error.message], usage })}\n`);
    process.exitCode = 2;
  }
}

function isEntryPoint() {
  try {
    return realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

if (isEntryPoint()) {
  await main();
}
