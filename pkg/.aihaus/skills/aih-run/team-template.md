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

## Path Override (CRITICAL)
Every task must anchor the agent to the milestone directory so it never writes to
stale or ambient paths. Override in EVERY task:
- "Read stories from `{milestone_dir}/stories/` only"
- "Write summaries to `{milestone_dir}/execution/` only"
- "Write reviews to `{milestone_dir}/execution/reviews/` only"
- "Append decisions/knowledge to `{milestone_dir}/execution/` only"
