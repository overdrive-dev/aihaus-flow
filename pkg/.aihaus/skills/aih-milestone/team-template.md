# Agent Team Template for /aih-milestone

## Team Members
| Role | Agent | Owns |
|------|-------|------|
| backend-dev | `.aihaus/agents/aihaus-implementer.md` | backend source tree |
| frontend-dev | `.aihaus/agents/aihaus-frontend-dev.md` | frontend source tree |
| qa | `.aihaus/agents/aihaus-reviewer.md` | `{milestone_dir}/execution/reviews/**` |

Skip frontend-dev if backend-only (vice versa). Spawn second dev if >8 stories.

## Task Description Template
Every task MUST include:
```
Story: Read {milestone_dir}/stories/[story-file].md
Summary: Write {milestone_dir}/execution/[story-slug]-SUMMARY.md
Review: Write {milestone_dir}/execution/reviews/[story-slug]-REVIEW.md
Decisions: Append to {milestone_dir}/execution/DECISIONS-LOG.md
Knowledge: Append to {milestone_dir}/execution/KNOWLEDGE-LOG.md
Owned files: [exact list from story — no overlaps]
```

## File Ownership (no file owned by 2 agents)
- backend source tree -- backend-dev only
- frontend source tree -- frontend-dev only
- `{milestone_dir}/execution/reviews/**` -- qa only
- `{milestone_dir}/execution/*-SUMMARY.md` -- implementing agent only
- `{milestone_dir}/execution/DECISIONS-LOG.md` -- append-only, shared
- `{milestone_dir}/execution/KNOWLEDGE-LOG.md` -- append-only, shared
- `.aihaus/decisions.md`, `.aihaus/knowledge.md` -- coordinator only (completion phase)

## Conflict Prevention
1. Task descriptions list exact owned files -- never assign same file to parallel tasks
2. If two stories touch the same file, add a dependency between them
3. Teammates message lead before `git commit` to coordinate order
4. Milestones with >5 stories: use `story/[slug]` branches merged by lead after QA

## Commit Discipline (prevents cross-story attribution bugs)
The coordinator MUST NEVER blanket-add during story commits. Specifically:

1. **Explicit file add only** — stage every file by name from the story's `Owned files` list:
   ```bash
   git add frontend/app/login.tsx frontend/components/LoginForm.tsx
   ```
   NEVER `git add frontend/`, `git add .`, or `git add -A`. Directory-level adds sweep pending work from other agents that merged back during the same window.

2. **Pre-commit verification** — before `git commit`, run `git status --porcelain` and confirm that exactly the Owned files are staged. Any extra files are orphans — stash them and surface to user:
   ```bash
   git status --porcelain | grep -v "^(M |A |D )" || echo "clean"
   # If unstaged files exist outside Owned files, stash them first:
   #   git stash push -m "unowned-during-S[N]" -- <unowned-files>
   ```

3. **Post-commit verification** — after `git commit`, `git status` must show a clean working tree before releasing the next story's teammate. If dirty, the coordinator must reconcile before proceeding.

## Worktree Merge-Back Protocol
Agents with `isolation: worktree` do their work in an isolated worktree. Merge-back into main tree must be precise:

1. **Per-file copy** — coordinator copies only the exact files listed in `Owned files` from the worktree to main. Never `cp -R <worktree>/* <main>/`.
   ```bash
   cp /path/to/worktree/frontend/app/login.tsx /path/to/main/frontend/app/login.tsx
   ```
2. **Verify merge-back isolation** — after copy, `git -C <main> status` should show only the intended files changed. If other files appear modified, another agent's merge-back interleaved — serialize them.
3. **Commit immediately after merge-back** — don't let merge-backed files sit uncommitted while a next story spawns. The gap is the race window that caused the attribution bug.

## Path Override (CRITICAL)
Every task must anchor the agent to the milestone directory so it never writes to
stale or ambient paths. Override in EVERY task:
- "Read stories from `{milestone_dir}/stories/` only"
- "Write summaries to `{milestone_dir}/execution/` only"
- "Write reviews to `{milestone_dir}/execution/reviews/` only"
- "Append decisions/knowledge to `{milestone_dir}/execution/` only"
