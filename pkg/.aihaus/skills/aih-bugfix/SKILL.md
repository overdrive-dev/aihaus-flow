---
name: aih-bugfix
description: Triage and fix a bug — root cause analysis, branch, fix, test, commit. Use for defects and errors.
disable-model-invocation: true
allowed-tools: Read Write Edit Grep Glob Bash
argument-hint: "[bug description, error message, or symptom]"
---

## Task

Triage and fix a bug. Two phases: first diagnose and get approval, then fix autonomously.

$ARGUMENTS

## Phase 1 — Question & Approval

### 1. Load Context
- Read `.aihaus/memory/MEMORY.md` (if it exists) for prior patterns and gotchas
- Read `.aihaus/project.md` (if present) for project-level context
- Read `.aihaus/decisions.md` (if present) — do not contradict any ADR
- Read `.aihaus/knowledge.md` (if present) — avoid known pitfalls

### 2. Triage
- Parse the bug description, error message, or symptom from the arguments above
- Search the codebase for the root cause:
  - Grep for error messages, function names, keywords from the symptom
  - Read the files that surface as likely culprits
  - Trace the call chain to identify the actual defect
- Identify all affected files (with full paths)

### 3. Present Findings
Provide a structured summary to the user:

```
## Bug Triage

**Symptom:** [what the user reported]
**Root Cause:** [what is actually broken and why]
**Affected Files:**
- path/to/file1 (line ~N — description of issue)
- path/to/file2 (line ~N — related impact)

**Proposed Fix:**
[concise description of what you will change]

**Verification Plan:**
- [ ] [test command] — covers the defect
- [ ] [smoke/build/typecheck command]

**Estimated Scope:** N files modified, N tests added/updated
```

### 4. Escalation Check
If the root cause spans multiple subsystems (e.g., data model + API + frontend + migrations), this may be systemic. In that case, add:

```
**Note:** This bug has a systemic root cause spanning [subsystems]. You may
want to use `/aih-feature` or `/aih-milestone` for a more thorough fix.
You can proceed with /aih-bugfix if you prefer a targeted patch.
```

This is a soft suggestion — the user decides. Do not refuse to proceed.

### 5. Check Git State
Run `git status` and `git branch --show-current`.
- If there are uncommitted changes, warn: "Your working tree has uncommitted changes. I can stash them before branching, or you can ask me to stay on the current branch."
- Report the current branch name.

### 6. STOP and Wait
Present the triage summary. Ask:
> "Approve this fix? I will create branch `fix/[slug]` and apply the changes above.
> Say 'go' to proceed, 'stay on branch' to skip branching, or provide adjustments."

**Do NOT proceed to Phase 2 until the user approves.**

---

## Phase 2 — Autonomous Execution

After the user approves:

### 7. Derive Slug
From the bug description, create a slug: lowercase, hyphens for spaces, strip special characters, max 40 characters. Example: "500-error-null-user-id"

### 8. Branch (unless user said "stay on branch")
```bash
git checkout -b fix/[slug]
```
If branching fails (e.g., branch exists), append a short suffix: `fix/[slug]-2`.

### 9. Apply Fix
- Edit the identified files to resolve the root cause
- Follow existing code patterns in neighboring files
- Keep changes minimal and focused on the defect

### 10. Add or Update Tests
- Write or update tests that reproduce the bug and verify the fix
- Follow the project's existing test conventions — do not introduce mocking patterns the codebase avoids
- Place tests in the appropriate test directory following existing conventions

### 11. Verify
Run the verification commands appropriate to the area touched (build, typecheck, unit tests, smoke tests). Use whatever the project already defines in its README or CONTRIBUTING docs.
If any verification fails, fix the issue and re-run. Do not skip failing tests.

### 12. Commit Atomically
Stage only the files you changed. Write a descriptive commit message:
```bash
git add [specific files]
git commit -m "fix: [concise description of the bug fix]"
```

### 13. Write Artifacts
Create `.aihaus/bugfixes/[YYMMDD]-[slug]/` with two files:

**TRIAGE.md** — the triage findings from Phase 1 (root cause, affected files, analysis)

**SUMMARY.md** — execution summary: what was changed, tests added, verification results

If you made any non-obvious decisions during the fix, also create **decisions.md** in the same directory documenting the choice, alternatives, and rationale.

### 14. Promote Learnings
If you discovered a non-obvious pattern, gotcha, or architectural insight during triage:
- Append it to `.aihaus/memory/global/gotchas.md` or `.aihaus/memory/global/patterns.md`
- Update `.aihaus/memory/MEMORY.md` index if a new entry was added

Only promote genuinely reusable knowledge — not fix-specific details.

### 15. Update project.md if structural changes were made
Runs AFTER the commit. If `.aihaus/project.md` does not exist, print
`"project.md not found, skipping update"` and continue to Step 16.

1. Collect changed paths: `git show --name-only --pretty=format: HEAD | sort -u`.
2. Detect structural change by checking if any changed path falls within
   directories listed in the **Inventory** table of `.aihaus/project.md`.
   If `project.md` is not available, match against these common fallback
   patterns: `models/`, `entities/`, `schemas/`, `routes/`, `api/`,
   `endpoints/`, `controllers/`, `handlers/`, `pages/`, `screens/`,
   `views/`, `components/`, `src/domain/`, `src/app/`, `pkg/`, `cmd/`,
   `internal/`, `lib/`.
3. If ANY match (rare for bugfixes, but the hook is consistent), spawn
   `subagent_type: "project-analyst"` with the instruction
   `"Run in --refresh-inventory-only mode and rewrite .aihaus/.init-scratch.md"`.
   Then merge ONLY the block between `<!-- AIHAUS:AUTO-GENERATED-START -->`
   and `<!-- AIHAUS:AUTO-GENERATED-END -->` in `.aihaus/project.md` (preserve
   the manual header/footer byte-for-byte; back up to `project.md.bak` first).
4. Always append to `## Milestone History` in the manual section:
   `- [YYYY-MM-DD] fix/[slug] — [one-line summary]`.

### 16. Report Completion
Summarize what was done:
- Branch name (or "stayed on [branch]")
- Files changed
- Tests added/updated
- Verification results
- Artifact location: `.aihaus/bugfixes/[YYMMDD]-[slug]/`
