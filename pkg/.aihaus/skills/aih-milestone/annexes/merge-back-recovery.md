# merge-back-recovery.md — Recovery paths for merge-back.sh failures

**Applies to:** `pkg/.aihaus/hooks/merge-back.sh` (M017/S03 / ADR-M017-A).

When `merge-back.sh` exits non-zero, the coordinator MUST halt the story and surface the refusal to the user. This document documents all recovery options.

---

## Exit codes

| Code | Meaning | Recovery |
|------|---------|----------|
| 0 | ok | Proceed to next story |
| 2 | bad-args or manifest/story-file missing | Fix invocation; re-run |
| 3 | file-set mismatch (refusal) | See "Refusal paths" below |
| 6 | lock-timeout | Wait and retry; check for stale `.lock` files |
| 12 | worktree-dir-missing | Restore or re-create worktree; then re-run |

---

## Refusal grammar (exit 3)

When the staged file set does not match the story's Owned Files exactly, `merge-back.sh` emits this to stderr (stable format — future tools parse it):

```
MERGE_BACK_REFUSED story=S<NN> reason=<unexpected-files|missing-files|cross-story-spill> expected=<f1,f2> actual=<f1,f2,f3> worktree=<path>
```

**Reason codes:**
- `unexpected-files` — staged set is a strict superset of Owned Files (extra files staged, likely from another agent's work bleeding in).
- `missing-files` — staged set is a strict subset of Owned Files (some Owned Files were not copied or staged).
- `cross-story-spill` — staged set differs from Owned Files in both directions simultaneously.

---

## Recovery option 1: Accept unexpected files (edit Owned Files in manifest)

**Use when:** the extra file is legitimately part of this story but was omitted from the `## Owned Files` section in the story file.

1. Edit `stories/<story-id>.md` → `## Owned Files` section to add the unexpected file.
2. Unstage all files: `git reset HEAD -- .`
3. Re-run `merge-back.sh --story S<NN> --manifest <path> --worktree <path>`.

**Caution:** only do this if you are certain the file belongs to this story. If it belongs to another story's scope, use option 2 instead.

---

## Recovery option 2: Drop unexpected file (--drop)

**Use when:** the extra file was staged by accident and should not be committed with this story. It will be moved to a quarantine directory and must be handled separately.

```bash
bash .aihaus/hooks/merge-back.sh \
  --story S<NN> \
  --manifest <path> \
  --worktree <path> \
  --drop path/to/unexpected/file.sh
```

The file is moved to `.claude/audit/rejected/S<NN>-<ts>/path/to/unexpected/file.sh`. After the drop, re-run without `--drop` to complete the merge-back. The quarantined file must be reconciled manually (re-stage in the correct story's commit, or discard).

---

## Recovery option 3: Abort (--abort)

**Use when:** the worktree state is unrecoverable in the current run, or there is an investigation needed before proceeding.

```bash
bash .aihaus/hooks/merge-back.sh \
  --story S<NN> \
  --manifest <path> \
  --worktree <path> \
  --abort
```

Effect:
- Emits checkpoint `merge-back:S<NN>` with `result=ERR` to RUN-MANIFEST.
- Appends `preserved-for-inspection` note to the progress log.
- Leaves the worktree intact (no files moved or deleted).
- Does NOT stage or commit anything.
- Exits 0 (non-disruptive to the coordinator process).

After `--abort`, surface the issue to the user. The worktree remains at its path for inspection. Resume via `/aih-resume` after the root cause is resolved.

---

## Shell-alias limitation (S04 gap)

`git-add-guard.sh` (S04) blocks dangerous `git add` invocations by intercepting the `Bash` tool's PreToolUse event. However, this interception is **not effective against**:

- Shell aliases (`git aa`, `git ap` — common aliases for `git add --all` or `git add --patch`)
- Shell functions (e.g., `gadd() { git add -A; }`)
- Subshell wrappers that call git internally

These constructs bypass PreToolUse because Claude Code only inspects the literal command string before shell expansion; aliases and functions are resolved by the shell after the hook runs.

`merge-back.sh` is the **structural fix** for this gap: even if a shell alias or function slips through `git-add-guard.sh`, the post-add `git diff --cached --name-only` comparison in `merge-back.sh` will detect the extra staged files and emit exit 3 with the refusal grammar.

---

## Opt-out (emergency bypass)

If `merge-back.sh` itself is the problem (e.g., a bug in this version), bypass it entirely:

```bash
AIHAUS_MERGE_BACK_GUARD=0 bash .aihaus/hooks/merge-back.sh --story S<NN> ...
```

or export for the session:

```bash
export AIHAUS_MERGE_BACK_GUARD=0
```

When `AIHAUS_MERGE_BACK_GUARD=0`, the script exits 0 immediately with a warning. The coordinator falls back to the pre-M017 operator discipline (manual per-file `cp` + explicit `git add`). This is a bridge bypass — do not leave it set persistently.

**Rollback:** `git revert` the S03 commit to remove `merge-back.sh` entirely (last-resort; see architecture.md rollback matrix).
