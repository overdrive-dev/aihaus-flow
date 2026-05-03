# Expected output — F-RECONCILE-CAP-49

**Scenario:** A worktree whose HEAD is exactly 49 commits ahead of every integration ref
(i.e., none of the integration refs are ancestors of the worktree HEAD, and the worktree
has 49 commits not reachable from the closest integration ref).

**Expected hook output (stdout):**
```
[CATEGORY B] <worktree-path> — clean but 49 commit(s) not on origin/staging.
Cherry-pick recipe:
```bash
# Cherry-pick 49 commits from <branch-label> onto origin/staging:
git cherry-pick <sha1> <sha2> ... <sha49>
# Then prune the worktree:
git worktree remove --force <worktree-path>
` ``
```

**Expected NOT present in output:**
- No `[INTEGRATION-LAG]` line

**Rationale:** `AIHAUS_RECONCILE_CAP` defaults to 50. When the commit count (49) is at or
below the cap, the hook emits a full `[CATEGORY B]` cherry-pick recipe containing all 49
commit SHAs. The `[INTEGRATION-LAG]` path is NOT triggered.

**AC reference:** AC-02 (FR-30, NFR-07), outcome gate C-11.

**Verification method:** Manual integration test or future `tools/test-reconcile.sh` harness.
See SETUP.md for construction instructions.
