# Knowledge Base (template)

Seeded at install. Append per-project gotchas here. Entries are promoted from milestone retrospectives.

---

## K-003: File-based recursion depth, not env vars

**Promoted from:** M003 (2026-04-14).
**Area:** Agent-to-skill marker protocol / ADR-003.

**Finding:** Claude Code's Agent tool spawns subagents as isolated subprocesses. Shell env vars (e.g., `AIHAUS_INVOKE_DEPTH`) do NOT propagate across the Agent-tool boundary — the child agent runs under a fresh shell hierarchy. This means env-var-based recursion caps are no-ops.

**Pattern:** Use **file-based state** for anything that needs to cross the Agent tool boundary. ADR-003's recursion cap reads the `## Invoke stack` section of `RUN-MANIFEST.md` (row count). Matches the `session-start.sh` precedent of using `CLAUDE_ENV_FILE` as a side-channel file.

**Impact:** Always store cross-agent coordination state in a file, never in env vars. Applies to depth counters, session IDs, correlation tokens, lock state, etc.

---

## K-004: Sub-agent parallelism is worth the token cost

**Promoted from:** M003 (2026-04-14) + an adopter project's session log F3.
**Area:** Multi-agent coordination / planning phase.

**Finding:** Spawning `assumptions-analyzer` and `pattern-mapper` in parallel for plan research produces some redundant reads (both access `decisions.md`, similar file sets). Session log observed ~30% overlap.

**Pattern:** Keep them parallel anyway. The cross-validation is load-bearing: in the an adopter project's T6 case, assumptions-analyzer falsely concluded "string not found" on a template-literal dynamic bug; the agent re-ran the grep with broader terms and found it. Two independent perspectives catch each other's misses.

**Impact:** Do NOT serialize planning-phase sub-agents for token savings. Parallel fan-out is a quality feature, not a performance bug. Document this trade-off when someone proposes "optimizing" by serializing.

---

## K-005: OneDrive intercepts atomic rename; Python os.replace is the fallback

**Promoted from:** M003 (2026-04-14) / ADR-004 hook implementation.
**Area:** Cross-platform hooks / Git Bash on Windows with OneDrive.

**Finding:** On Windows + Git Bash with repo under OneDrive-synced directory, `mv -f tmp dest` via coreutils eventually calls `MoveFileEx`. On NTFS with OneDrive sync interception, destination-replacing rename is NOT race-free — OneDrive may hold an opportunistic lock on the destination. `flock(1)` is also unavailable on Git Bash.

**Pattern:** When writing hooks that atomically replace existing files:
- Lock via `mkdir <path>.lock/` mutex (racing mkdir succeeds for exactly one writer).
- Add 30s stale-lock reclaim: compare `stat` mtime; if older, rmdir + retry.
- Always register `trap 'rmdir <lock> 2>/dev/null' EXIT INT TERM` BEFORE acquiring the lock.
- For atomic replace, detect OneDrive path prefix (`*OneDrive*`, `*One Drive*`, `*Dropbox*`, `*iCloud*`) and use Python `os.replace` fallback: `python3 -c "import os,sys; os.replace(sys.argv[1], sys.argv[2])" tmp dest`. Atomic across NTFS regardless of OneDrive interception.
- Emit one-per-day advisory marker file under `.claude/audit/` so users know their path is a known hazard.

**Impact:** Implemented in `manifest-append.sh`, `manifest-migrate.sh`, `phase-advance.sh`. Template for any future hook that writes state files.

---

## K-006: Attachment temp-slug flow prevents loss on conversation drop

**Promoted from:** M004 (2026-04-14) / story H / F5.
**Area:** Attachment handling across aih-plan, aih-quick, aih-bugfix, aih-milestone.

**Finding:** Pre-M004, attachments stayed in `~/.claude/image-cache/[uuid]/` until Phase 2 finalized the plan/bugfix slug. If the conversation dropped between Phase 1 and Phase 2 (common in long sessions), attachments were lost.

**Pattern:** Copy IMMEDIATELY on first attachment mention into a temp-slug dir `<prefix>/YYMMDD-wip-HHMMSS-<rand4>/attachments/`. On slug finalization, `mv` the temp dir to the final slug. Same-day concurrent sessions disambiguated by seconds precision + 4-char random tail.

**Crash recovery:** on skill entry, scan `<prefix>/` for `*-wip-*` directories alongside matching finalized slugs. Prompt user (keep finalized / keep wip / abort to inspect).

**Impact:** Implemented in aih-plan (via annexes/attachments.md), aih-quick, aih-milestone, aih-bugfix. 7-day orphan flag in smoke-test warns on abandoned temp dirs.

---

## K-007: OneDrive is load-bearing for cross-platform hooks (reiteration + checklist)

**Promoted from:** M004 (2026-04-14) / cross-cutting.
**Area:** Hook authoring on Windows / Git Bash / OneDrive.

**Finding:** K-005 established the Python `os.replace` fallback. M004 adds the full cross-platform checklist every new hook must pass (story H pattern, now canonical for all future hooks):

1. **Locking**: mkdir-mutex (flock unavailable on Git Bash) with 30s stale reclaim + trap release.
2. **Atomic replace**: OneDrive path detection + Python fallback.
3. **Worktree refusal**: `git rev-parse --show-superproject-working-tree` non-empty → exit 3.
4. **Audit dir**: `mkdir -p "$(dirname "$AUDIT_LOG")"` before every append — audit dir may not exist on fresh installs.
5. **OneDrive advisory**: one-per-day marker under `.claude/audit/` when paths are cloud-synced.

Any new hook that fails to implement all 5 will fail under the realistic dev environment of aihaus's primary maintainer.

**Impact:** Architectural constraint baked into hook-authoring conventions. Mentor pattern: show a new hook author the `manifest-append.sh` + `phase-advance.sh` combo — those are the canonical implementations.

---

## K-005: TaskCreate reminder during planning is Claude Code harness noise

**Promoted from:** M004 (2026-04-14) / story M / F9.
**Area:** Harness integration / planning skills.

**Finding:** During `/aih-plan` gathering + `/aih-milestone --plan` promotion, the Claude Code harness emits system reminders suggesting `TaskCreate` usage. These reminders are irrelevant — planning is a capture phase, not a task-execution phase. They create noise without adding value.

**Pattern:** aihaus cannot directly suppress harness reminders (it's the harness's own behavior). Workaround: the forward-looking placeholder key `aihaus.suppress.taskCreateReminder: true` in `.claude/settings.local.json` serves as a marker for future harness-level support. Claude Code currently ignores unknown top-level keys, so this is safe to ship.

**Impact:**
- `pkg/.aihaus/templates/settings.local.json` ships the key by default.
- `pkg/.aihaus/skills/aih-plan/annexes/intake-discipline.md` notes: "ignore TaskCreate reminders during gathering."
- If a future Claude Code release rejects unknown keys, this fails cleanly — remove the `aihaus` top-level object in one commit.
- File an upstream issue on `anthropics/claude-code` requesting native suppression if noise becomes pervasive.

**Rollback:** delete the `"aihaus"` key from `.claude/settings.local.json` — no other aihaus code depends on it.

