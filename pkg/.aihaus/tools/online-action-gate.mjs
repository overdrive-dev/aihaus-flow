#!/usr/bin/env node

import { access } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ONLINE_PATTERNS = [
  { kind: "git-push", pattern: /(?:^|[;&|]\s*)git\s+push\b/i },
  { kind: "github-release", pattern: /\bgh\s+release\s+(?:create|upload|delete)\b/i },
  { kind: "package-publish", pattern: /\b(?:npm|pnpm|yarn)\s+publish\b/i },
  { kind: "container-push", pattern: /\bdocker\s+(?:image\s+)?push\b/i },
  { kind: "kubernetes-mutate", pattern: /\bkubectl\s+(?:apply|create|delete|patch|replace|rollout)\b/i },
  { kind: "terraform-mutate", pattern: /\bterraform\s+(?:apply|destroy|import)\b/i },
  { kind: "cloud-deploy", pattern: /\b(?:vercel|fly|wrangler|railway|heroku)\b[^\n]*(?:deploy|--prod|up|release)\b/i },
];

async function exists(target) {
  try {
    await access(target);
    return true;
  } catch {
    return false;
  }
}

export function classifyOnlineAction(command) {
  const text = String(command ?? "");
  const match = ONLINE_PATTERNS.find(({ pattern }) => pattern.test(text));
  return match ? { online: true, kind: match.kind } : { online: false, kind: "local-or-read-only" };
}

export async function evaluateOnlineAction({ command, repo = process.cwd() }) {
  const classification = classifyOnlineAction(command);
  if (!classification.online) {
    return { allowed: true, reason: classification.kind, ...classification };
  }

  const sentinels = [
    path.join(repo, ".aihaus", "state", "active-flow"),
    path.join(repo, ".claude", "_state", "active-flow"),
  ];
  const activeFlow = (await Promise.all(sentinels.map(exists))).some(Boolean);
  return activeFlow
    ? { allowed: true, reason: "active-flow", ...classification }
    : { allowed: false, reason: "online-action-without-active-flow", ...classification };
}

function parseArgs(args) {
  const out = { command: null, repo: process.cwd() };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--command") out.command = args[++index] ?? null;
    else if (arg === "--repo") out.repo = args[++index] ?? null;
    else if (arg === "--json") continue;
    else throw new Error(`unknown argument: ${arg}`);
  }
  if (!out.command) throw new Error("--command is required");
  return out;
}

async function main() {
  try {
    const result = await evaluateOnlineAction(parseArgs(process.argv.slice(2)));
    process.stdout.write(`${JSON.stringify(result)}\n`);
    if (!result.allowed) process.exitCode = 2;
  } catch (error) {
    process.stderr.write(`${JSON.stringify({ allowed: false, reason: error.message })}\n`);
    process.exitCode = 2;
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url))) {
  await main();
}
