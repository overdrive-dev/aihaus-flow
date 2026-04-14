# Completion Protocol

Run after all stories are implemented and QA-approved.
`{milestone_dir}` = `.aihaus/milestones/[M0XX]-[slug]`

## Step 1: Write Milestone Summary
Create `{milestone_dir}/execution/MILESTONE-SUMMARY.md`:
```
# Milestone [M0XX]: [Title]
**Status:** Completed | Completed-with-concerns
**Started:** [ISO date]  **Completed:** [ISO date]
**Branch:** milestone/[M0XX]-[slug]
## Stories Completed
| # | Story | Status | Key files |
## Decisions Made
[List D-NNN entries from DECISIONS-LOG.md]
## Tests Added
[New test files and what they cover]
## Files Changed
[Group by affected area — models, endpoints, schemas, services, frontend, etc.]
## Known Issues
[Deferred items, tech debt, or follow-up needed]
```

## Step 2: Promote Decisions
Read `{milestone_dir}/execution/DECISIONS-LOG.md`. For each decision worth
preserving permanently, determine the next ADR-NNN number from
`.aihaus/decisions.md` and append an entry following the existing format
(Date, Status, Context, Options Considered, Decision, Rationale, Consequences).
Skip milestone-local or already-obsolete decisions.

If `.aihaus/decisions.md` does not yet exist, create it with an
"# Architectural Decisions" header before appending.

## Step 3: Promote Knowledge
Read `{milestone_dir}/execution/KNOWLEDGE-LOG.md`. For each reusable finding,
determine the next K-NNN number from `.aihaus/knowledge.md` and append
with Area, Finding, and Impact fields. Skip milestone-specific entries.

If `.aihaus/knowledge.md` does not yet exist, create it with a
"# Knowledge Base" header before appending.

## Step 4: Update Agent Memory
Write to `.aihaus/memory/` only.
- New patterns -> `.aihaus/memory/global/patterns.md`
- New gotchas -> `.aihaus/memory/global/gotchas.md`
- Architecture changes -> `.aihaus/memory/global/architecture.md`
- Update `.aihaus/memory/MEMORY.md` index for each addition

## Step 4.5: Apply Agent Evolutions
If `{milestone_dir}/execution/AGENT-EVOLUTION.md` exists and has proposals:
1. Read each proposal
2. For each proposal with clear evidence (not speculative):
   - Edit the agent's `.aihaus/agents/[name].md` file
   - Add the new rule, read directive, or protocol step
   - Preserve YAML frontmatter structure (do not change name, tools, model)
   - Do NOT remove Conflict Prevention reads or Self-Evolution sections
   - Log the change: "Agent [name] evolved: [one-line summary]"
3. Skip proposals that are speculative or lack evidence
4. Run `[[ -f tools/purity-check.sh ]] && bash tools/purity-check.sh || echo "purity-check unavailable (maintainer-only) — skipping"` — revert any evolution that fails
5. Report: "[N] agent evolutions applied, [M] deferred"

## Step 4.6: Update Living Architecture
If any ADR was superseded during execution, or a new convention emerged:
1. Update `.aihaus/decisions.md` with superseded status on old ADRs
2. Update `.aihaus/knowledge.md` with new conventions
3. This keeps architecture docs current — agents read them before every task

## Step 5: Report Completion
Present to the user:
```
Milestone [M0XX] complete.
- Stories: [N] completed, [N] with concerns
- Decisions promoted: [N] new ADRs
- Knowledge entries: [N] added
- Branch: milestone/[M0XX]-[slug] -- ready for review/merge
```

## Step 6: Update project.md if structural changes were made
Runs AFTER the completion report. Skips cleanly when `.aihaus/project.md` is absent.

1. **Check project.md exists.** If `.aihaus/project.md` is missing, print
   `"project.md not found, skipping update"` and return. Do NOT crash.
2. **Collect committed paths.** Run:
   `git diff --name-only milestone/[M0XX]-[slug]~$(git rev-list --count HEAD ^origin/HEAD 2>/dev/null || echo 1)..HEAD`
   or, if that fails, `git log --name-only --pretty=format: [merge-base]..HEAD | sort -u`.
3. **Detect structural changes.** Check if any changed path falls within
   directories listed in the **Inventory** table of `.aihaus/project.md`.
   If `project.md` is not available, match against these common fallback
   patterns: `models/`, `entities/`, `schemas/`, `routes/`, `api/`,
   `endpoints/`, `controllers/`, `handlers/`, `pages/`, `screens/`,
   `views/`, `components/`, `src/domain/`, `src/app/`, `pkg/`, `cmd/`,
   `internal/`, `lib/`.
4. **If ANY match -> refresh inventory.** Spawn the `project-analyst` agent
   with `subagent_type: "project-analyst"` and the instruction
   `"Run in --refresh-inventory-only mode and rewrite .aihaus/.init-scratch.md"`.
   When it completes, merge ONLY the block between
   `<!-- AIHAUS:AUTO-GENERATED-START -->` and `<!-- AIHAUS:AUTO-GENERATED-END -->`
   in `.aihaus/project.md` (preserve the header and the manual footer byte-for-byte).
   Back up to `.aihaus/project.md.bak` first. Do NOT touch sections outside the
   AUTO-GENERATED block (Glossary and other manual content stay intact).
5. **Always append Milestone History.** Find the `## Milestone History` heading
   in the manual section of `.aihaus/project.md` (create it if absent, just
   above the closing manual marker). Append:
   `- [YYYY-MM-DD] [M0XX]-[slug] — [one-line summary from MILESTONE-SUMMARY.md]`
6. **Refresh Active Milestones.** Spawn `project-analyst` with `--refresh-active-milestones`. Merge `.aihaus/.active-milestones-scratch.md` between the `ACTIVE-MILESTONES-START/END` markers — the completed milestone disappears from all three tables.

7. **Refresh Recent Decisions + Knowledge.** Spawn `project-analyst` with `--refresh-recent-decisions`. Merge `.aihaus/.recent-decisions-scratch.md` between `RECENT-DECISIONS-START/END` markers, and `.aihaus/.recent-knowledge-scratch.md` between `RECENT-KNOWLEDGE-START/END` markers.

8. **Report.** Print a concise summary of what was refreshed:
   `"project.md refreshed: inventory + history + active-milestones + recent-decisions"`
   or the subset that actually ran.
