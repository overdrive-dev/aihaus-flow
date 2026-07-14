import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, symlink } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { assertPathWithin } from "../../pkg/.aihaus/tools/path-safety.mjs";

test("accepts descendants and rejects the root itself", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "aihaus-path-root-"));
  try {
    const child = path.join(root, "consumer");
    await mkdir(child);
    const result = await assertPathWithin({ root, candidate: child });
    assert.equal(path.basename(result.candidate), "consumer");
    await assert.rejects(() => assertPathWithin({ root, candidate: root }), /root itself/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("rejects lexical escapes", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "aihaus-path-root-"));
  const outside = await mkdtemp(path.join(os.tmpdir(), "aihaus-path-outside-"));
  try {
    await assert.rejects(
      () => assertPathWithin({ root, candidate: outside }),
      /outside allowed root/,
    );
  } finally {
    await rm(root, { recursive: true, force: true });
    await rm(outside, { recursive: true, force: true });
  }
});

test("rejects a symlink or junction that escapes the allowed root", async (context) => {
  const root = await mkdtemp(path.join(os.tmpdir(), "aihaus-path-root-"));
  const outside = await mkdtemp(path.join(os.tmpdir(), "aihaus-path-outside-"));
  const link = path.join(root, "consumer");
  try {
    try {
      await symlink(outside, link, process.platform === "win32" ? "junction" : "dir");
    } catch (error) {
      if (["EPERM", "EACCES", "ENOTSUP"].includes(error.code)) {
        context.skip(`symlink creation unavailable: ${error.code}`);
        return;
      }
      throw error;
    }
    await assert.rejects(
      () => assertPathWithin({ root, candidate: link }),
      /outside allowed root/,
    );
  } finally {
    await rm(root, { recursive: true, force: true });
    await rm(outside, { recursive: true, force: true });
  }
});
