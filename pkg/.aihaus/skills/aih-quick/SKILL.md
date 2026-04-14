---
name: aih-quick
description: Fast-track for small, well-understood changes. Skips full planning — analyze, implement, and review in one shot.
disable-model-invocation: true
allowed-tools: Read Write Edit Grep Glob Bash
argument-hint: "[what to fix or change]"
---

## Task
This is a small, well-understood change. Skip the full planning pipeline.

$ARGUMENTS

## Self-invocation guard (on entry)
Before anything else — check the active Invoke stack (ADR-003/ADR-004):
1. If `$MANIFEST_PATH` env is set AND the file exists → count rows in the `## Invoke stack` section where `skill` field equals `aih-quick`.
2. Else if `~/.aihaus/run-state/$$.json` exists and `skill == aih-quick` → count = 1.
3. Else count = 0.

Rules:
- 0 → fresh invocation → proceed.
- 1 → dispatched from a parent via INVOKE marker (e.g., inline-ADR mode, see "Inline-ADR mode" below) → proceed.
- ≥ 2 → recursion → refuse with: `aih-quick: refused — recursive invocation detected. Exit and re-enter from a fresh shell to bypass.` Exit cleanly, no commits.

Defense-in-depth with `invoke-guard.sh` (which rejects self-invocation at marker-parse time).

## Inline-ADR mode (draft-adr args)
If `$ARGUMENTS` begins with `draft-adr ` AND active phase ∈ {planning, ready, running}: run INLINE on the orchestrator's current branch. No worktree, no commit.
1. Determine next ADR-NNN by reading `pkg/.aihaus/decisions.md` (max existing + 1, zero-padded).
2. Spawn `architect` with subagent_type `architect` and the invocation path `draft-adr <summary>` + `target_id: ADR-NNN`.
3. Architect RETURNS the ADR stub text (Frontmatter-lock: architect has no Write tool — cannot write directly).
4. Append the returned text to `pkg/.aihaus/decisions.md` with `Status: Proposed`. Do NOT `git commit` — parent skill's next commit boundary scoops it up.
5. Placeholder prose uses `(Filled by operator — ...)` so stubs are greppable.
If phase ∈ {gathering, complete} → refuse: `aih-quick draft-adr: refused — phase '<phase>' not eligible (need planning|ready|running)`.

## Protocol
1. **Understand**: Read relevant code, understand the change needed
2. **Check decisions**: Read `.aihaus/decisions.md` (if present) — don't contradict ADRs. Also read `.aihaus/project.md` (if present) for project context.
3. **Implement**: Make the change
4. **Verify**: Run relevant tests and type checks
5. **Adversarial sanity check**: Spawn `code-reviewer` with `subagent_type: "code-reviewer"` for a single pass on the staged diff. No fix loop — reviewer reports findings inline, user decides whether to address before commit. Keeps `/aih-quick` fast while preventing trivial bugs from slipping through.
6. **Commit**: Atomic commit with descriptive message

## Attachment Handling
If the user pastes an image/file, persist to `.aihaus/features/[YYMMDD]-[slug]/attachments/` (or a quick sibling dir) via `cp` from `~/.claude/image-cache/`. Pass the path to `code-reviewer` in Step 5. Reject > 20 MB.

## Guardrails
- If the change touches more than 5 files, STOP and suggest using `/aih-feature` instead
- If the change requires a database migration or schema change (and the project uses a database), STOP and suggest `/aih-plan` or `/aih-milestone` first
- If the change affects user-facing behavior in a meaningful way, STOP and suggest `/aih-feature` first so it gets a plan and review
