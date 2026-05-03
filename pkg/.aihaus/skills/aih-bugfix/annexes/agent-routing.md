# Agent Routing — Step 9 Apply Fix Contract

Binding contract for `/aih-bugfix` Step 9. Mirror of `aih-feature/annexes/agent-routing.md` with bugfix-specific tweaks.

**Enforcement status:** Phase A (this annex): prose-only, soft mandate — orchestrator self-discipline. Phase B (deferred follow-up): hook-level advisory in `autonomy-guard.sh` + `code-reviewer` Step 9 compliance check. Until Phase B ships, the inline-edit budget is enforced by the orchestrator reading this annex and the post-hoc reviewer optionally surfacing drift.

## Routing table

| Change scope | Agent | Notes |
|---|---|---|
| Backend defect: service, schema, endpoint, migration | `implementer` | Pre-loaded with backend conventions |
| Frontend defect: component, screen, helper | `frontend-dev` | Pre-loaded with FE patterns |
| New regression test (always required) | `test-writer` (Step 10 already delegates this — see Step 10) | Tests must reproduce the bug + verify the fix |
| Test-only fix (e.g., flaky test) | `implementer` | Treat as mechanical |

## Parallelism rule

Same as feature — independent agents in parallel; dependent agents sequential. For bugfixes, parallelism is rarer (most bugs are localized).

## Inline-edit budget (bugfix variant)

The orchestrator MAY make up to **5 small edits inline** (< 5 lines each, single file each) for tiny one-line fixes (typos, off-by-one, missing-null-check, single import). The bugfix budget is more permissive than feature (3) because bugfixes are typically smaller in scope.

Beyond budget: same `deviation: inline-only-because: <reason>` flag in manifest progress log; same CRITICAL finding for Step 10.5 reviewer.

## Pre-spawn briefing checklist

Same as `aih-feature/annexes/agent-routing.md` Pre-spawn briefing checklist. Every agent prompt MUST include MANIFEST_PATH, repo root, branch, plan reference (if any), files to change, out-of-scope guards, no-commit rule, verification commands, brief report contract.

## When inline IS appropriate

- Single-line config flag flip
- Single import added
- Typo / spelling fix
- Off-by-one fix in a single function
- Missing null/empty check
- Comment-only update for clarity

When inline is NOT appropriate:
- Schema changes
- Service / endpoint logic changes
- Cross-file ripples
- Migration files
- Anything requiring new tests

## Post-return discipline (orchestrator-side)

After every `implementer`, `frontend-dev`, or `code-fixer` agent return, the orchestrator MUST do
the following BEFORE crediting the agent's work or moving to the next bugfix step:

1. **Run `git status` and `git diff --stat HEAD`** in the main worktree. If the working tree is
   unchanged after the agent reports success → silent merge-back failure. The agent's reported
   work did not flow back. Do NOT proceed.

2. **Cross-check reported paths.** Compare the agent's reported file paths against
   `git diff --name-only` output. Path mismatch (agent says `frontend/foo/bar.tsx`, git shows
   nothing or a different path) → worktree-base drift. The agent worked on a stale snapshot
   that predates a rename; nothing applied to main.

3. **Recovery when drift is detected.** Discard the agent output; do NOT credit partial work.
   Redo inline (if within the 5-edit bugfix budget) OR re-spawn with the CURRENT canonical paths
   from `git ls-tree -r HEAD --name-only`.

4. **Optional helper:** `bash pkg/.aihaus/hooks/worktree-drift-check.sh <reported-path...>` —
   exits 0 if all paths exist in the main worktree, exits 1 with a per-path diagnostic to stderr.

Source: downstream consumer audit, 2026-05-03 (recurring worktree drift on isolation agents
caused two full redo-from-scratch sessions in 24 hours).

## Same class as feature Step 7

This contract is the bugfix mirror of `aih-feature/annexes/agent-routing.md`. Both close the same antipattern: model-driven SKILL steps with no structural enforcement. Source: downstream consumer audit post-mortem `260503-aih-feature-step7-agent-delegation`.
