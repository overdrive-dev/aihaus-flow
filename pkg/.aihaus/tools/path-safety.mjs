import { lstat, realpath } from "node:fs/promises";
import path from "node:path";

async function exists(target) {
  try {
    await lstat(target);
    return true;
  } catch {
    return false;
  }
}

async function realpathAllowMissing(target) {
  let probe = path.resolve(target);
  const suffix = [];

  while (!(await exists(probe))) {
    const parent = path.dirname(probe);
    if (parent === probe) {
      throw new Error(`no existing ancestor for path: ${target}`);
    }
    suffix.unshift(path.basename(probe));
    probe = parent;
  }

  try {
    return path.resolve(await realpath(probe), ...suffix);
  } catch (error) {
    throw new Error(`cannot safely resolve existing path entry ${probe}: ${error.message}`);
  }
}

function samePath(left, right) {
  if (process.platform === "win32") {
    return left.toLowerCase() === right.toLowerCase();
  }
  return left === right;
}

export async function assertPathWithin({ root, candidate, allowRoot = false }) {
  const resolvedRoot = await realpathAllowMissing(root);
  const resolvedCandidate = await realpathAllowMissing(candidate);

  if (samePath(resolvedRoot, resolvedCandidate)) {
    if (!allowRoot) {
      throw new Error(`refusing operation on allowed root itself: ${resolvedRoot}`);
    }
    return { root: resolvedRoot, candidate: resolvedCandidate };
  }

  const relative = path.relative(resolvedRoot, resolvedCandidate);
  if (relative === "" || relative === ".." || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) {
    throw new Error(`refusing operation outside allowed root: ${resolvedCandidate}`);
  }

  return { root: resolvedRoot, candidate: resolvedCandidate };
}
