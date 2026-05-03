# Expected output — F-RECONCILE-CAP-50

**Scenario:** A worktree whose HEAD is exactly 51 commits ahead of every integration ref
(i.e., none of the integration refs are ancestors of the worktree HEAD, and the worktree
has 51 commits not reachable from the closest integration ref).

**Expected hook output (stdout):**
```
[INTEGRATION-LAG] <worktree-path> appears to be tracking an old base. Suggest: git rebase origin/staging
```

**Expected NOT present in output:**
- No `[CATEGORY B]` line
- No `Cherry-pick recipe:` block
- No list of commit SHAs

**Rationale:** `AIHAUS_RECONCILE_CAP` defaults to 50. When the commit count (51) exceeds
the cap, the hook emits exactly one `[INTEGRATION-LAG]` line and zero `[CATEGORY B]` recipe
blocks. This prevents overwhelming output for worktrees tracking a stale base.

**AC reference:** AC-03 (FR-30, NFR-07), outcome gate C-11.

**Verification method:** Manual integration test or future `tools/test-reconcile.sh` harness.
See SETUP.md for construction instructions.
