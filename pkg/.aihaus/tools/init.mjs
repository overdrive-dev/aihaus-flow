#!/usr/bin/env node

// Deprecated alias kept for pre-rename installs; init.mjs became refresh.mjs.
// Remove after one release window.
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const refresh = path.join(path.dirname(fileURLToPath(import.meta.url)), "refresh.mjs");
const result = spawnSync(process.execPath, [refresh, ...process.argv.slice(2)], {
  stdio: "inherit",
});
if (result.error) throw result.error;
process.exitCode = result.status ?? 1;
