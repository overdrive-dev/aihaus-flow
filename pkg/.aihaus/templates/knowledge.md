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
