# Global Gotchas

Persistent record of traps that cost work in any area of the codebase. All agents read this before acting. Append-only — entries explain the trap, the symptom, and how to avoid.

---

## `.aihaus/auto.sh` is a 4-line DSP launcher, not a daemon

**Symptom suspected:** HEAD silently switching branches, edits silently reverted, work appearing on the wrong branch — and `.aihaus/auto.sh` shows up in `git status` (untracked) so it looks like the cause.

**Reality:** `auto.sh` symlinks to `pkg/scripts/launch-aihaus.sh`, which is exactly four lines:

```bash
#!/usr/bin/env bash
# launch-aihaus.sh -- exec claude with DSP for full aihaus autonomy
# Created M014/S03. DSP launcher — replaces the old permission-mode skill toggle.
exec claude --dangerously-skip-permissions "$@"
```

It does not poll, does not switch branches, does not stash, does not commit. Per ADR-M014-A.

**If HEAD switches silently, the cause is upstream of aihaus:**

1. **Concurrent claude session.** Run `pgrep -af 'claude.*--dangerously'` — if more than one is alive, that's your culprit. Each session writes to the same working tree without an inter-process mutex.
2. **Claude's own confused recovery git ops.** A self-narrating stash message like *"WIP: X work accidentally merged into Y branch"* was written by Claude, not by aihaus.
3. **IDE auto-checkout** (some IDE integrations checkout on file-tree click).
4. **The `bash-guard.sh` branch-switch warn (ADR-260427-B)** writes `.claude/audit/branch-switch-warn.jsonl` for any `git checkout <ref>` while a manifest is running. Check there first.

---

## Concurrent `claude` sessions on the same working tree race on `git checkout -b`

**Symptom:** edits silently revert mid-session, HEAD switches to a parallel branch, commits land on the wrong branch.

**Cause:** two `claude --dangerously-skip-permissions` processes editing the same repo. Aihaus has no inter-process mutex on `.aihaus/{features,bugfixes}/*/RUN-MANIFEST.md`. The M017 L1-L4 lock-leak prevention stack is **milestone-scoped only** (per ADR-M017-B); feature/bugfix flows have only the soft-warn (ADR-260427-B) + pre-flight collision check (ADR-260427-C).

ADR-260427-B is a PreToolUse hook (runtime enforcement on the actual `git checkout` command); ADR-260427-C is a SKILL.md prose reference (prompt-time, depends on Claude reading the annex before issuing branch ops). They are complementary layers, not redundant.

**Diagnosis:**

```bash
pgrep -af 'claude.*--dangerously'    # how many sessions?
git stash list | grep aihaus         # any session-end stashes pending?
ls .aihaus/{features,bugfixes,milestones}/*/RUN-MANIFEST.md   # any running peer?
cat .claude/audit/branch-switch-warn.jsonl   # any warns logged?
```

**Mitigation:**

- Run only one `claude` session per working tree at a time. If you need a second window, use a separate clone or `git worktree add` to isolate.
- Heed the pre-flight collision warn from `/aih-feature` and `/aih-bugfix`. It's a single sentence; don't dismiss without thinking.
- Run `git status && git branch --show-current` before every `git commit` during a multi-skill workflow.

**True fix (not yet shipped):** inter-process mutex covering the feature/bugfix RUN-MANIFEST surfaces (analog to L1-L4 milestone stack). Filed as follow-up under ADR-260427-C scope rationale.

---

## `git stash --include-untracked` captures `.aihaus/.effort` and `.aihaus/.calibration`

**Symptom:** after a session restart, agent effort/model overrides reset to defaults. Calibration "lost".

**Cause:** these files are user-owned per ADR-M009-A (never committed, live at `.aihaus/` root). When `session-end.sh` (or any other stash op) runs `--include-untracked`, the sidecar files get captured. If the stash is never popped (pop failure, dirty tree, label mismatch), they stay stashed and the next session reads default values.

**Mitigation:**

- The M018/S5 + ADR-260427-A pattern auto-pops on clean tree, so the common path restores them.
- On dirty-tree exit, the SHA is logged to `.claude/audit/session-end-stash-pending.jsonl` and surfaced via session-start `additionalContext`. Manually `git stash pop <sha>` to restore.
- Never run `git stash drop` blindly on an `aihaus session-end *`-labeled stash without checking what's in it (`git stash show -p <ref>`).

---

## Don't blanket `git add` during milestone story commits

**Symptom:** a story's commit captures files owned by *another* story, breaking merge-back.

**Cause:** `git add -A` / `git add .` / `git add <dir>/` on a milestone branch stages spillover files that aren't in the current story's `## Owned Files`. The `merge-back.sh` per-file `cp` + explicit `git add <file>` discipline (ADR-M017-A) is the only safe path. `git-add-guard.sh` PreToolUse blocks the destructive shapes on `milestone/*` and `feature/*` branches.

**Mitigation:**

- Always use explicit file paths: `git add path/to/file.ts path/to/other.ts`.
- For milestone stories: `bash .aihaus/hooks/merge-back.sh --story S<NN>` is the canonical path.
- Opt-out only with `AIHAUS_GIT_ADD_GUARD=0` and a clear rationale in the commit body.
