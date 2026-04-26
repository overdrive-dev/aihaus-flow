# M017 Smoke-Test Fixtures

## Shipped (in S08)

- `merge-back-refusal/` — exit 3 grammar verification: seeds a mock manifest +
  story file with one Owned file, then stages a second unexpected file in a temp
  worktree, invokes merge-back.sh, and asserts exit=3 + stderr contains
  `MERGE_BACK_REFUSED` with all 5 required fields (story, reason, expected,
  actual, worktree). Replays the 2026-04-12 incident scenario.

- `git-add-guard-cases/` — regex + branch-gating verification: asserts that
  `git add -A` and `git commit -am` are denied (exit 2) on a milestone branch,
  `git add explicit-file.txt` is allowed (exit 0) on a milestone branch, and
  `git add -A` is allowed (exit 0) on main (off-milestone bypass).

## Deferred (exercised live during M018+ executions)

- L1 SubagentStop A/B/C classification fixtures — require full Claude Code
  harness simulation or live SubagentStop events; impractical in smoke-test.

- L2 SessionEnd multi-worktree sweep fixtures — require live SessionEnd events
  or a harness that emits them; cannot be reproduced offline.

- L3 /aih-milestone --abort partial-milestone fixture — requires a live
  aih-milestone run reaching abort state; orchestration-layer test only.

- L4 reap kill-9-survivor + live-lock-refusal fixtures — require live processes
  and timer-gated conditions; would be flaky in a static smoke-test.

- Permission-scope degradation test — not applicable under S05 Path B (no
  worktree-branch-from.sh was shipped; path is SKIPPED per S05-FALLBACK-NOTE.md).

- Plan-checker same-file rule x3 (overlap-BLOCKER, hatch-accepted-Path-A,
  hatch-rejected-Path-B) — covered at /aih-milestone E3 live invocations where
  the plan-checker agent runs against real PLAN.md content.

- Meta-test: plan-checker re-run on M017 PLAN.md (expected: BLOCKER on the 2
  grandfathered overlaps) — requires live plan-checker agent invocation with
  M017 planning context. Exercised organically during M018 E3 planning gate.

Rationale: S02a/S02b/S02c/S02d fixtures require full Claude Code harness
simulation or live SubagentStop/SessionEnd events — impractical in smoke-test.
Live M018+ runs exercise these paths organically. S05 Path B means permission-scope
fixture is not applicable. Plan-checker x3 + meta-test are covered at
/aih-milestone E3 live invocations.
