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

## Step 3.5: Spawn Knowledge-Curator (ADR-M013-A / Component C)
**Recursion guard:** if `AIHAUS_KNOWLEDGE_CURATOR_ACTIVE=1` is set, skip this step
silently (prevents self-invocation during M013's own completion).

Spawn the `knowledge-curator` agent with the following inputs:
- `{milestone_dir}/execution/DECISIONS-LOG.md`
- `{milestone_dir}/execution/KNOWLEDGE-LOG.md`
- `{milestone_dir}/execution/AGENT-EVOLUTION.md` (if present)
- `.claude/audit/LEARNING-WARNINGS.jsonl` — filtered to rows with `"milestone": "M0XX"`
  (substitute actual milestone ID)
- `.aihaus/decisions.md` (for dedup and next-ADR-number lookup)
- `.aihaus/knowledge.md` (for dedup and next-K-NNN lookup)
- `.aihaus/memory/**` (all files — for dedup and routing)

Instruction to the agent:
```
Curate knowledge for milestone {M0XX}-{slug}.
Read all input artifacts listed above.
Emit exactly 5 marker-fenced blocks:
  aihaus:decisions-append, aihaus:knowledge-append, aihaus:memory-append,
  aihaus:history-append, aihaus:curator-decisions.
See your agent definition for the full output contract.
```

Capture the agent's stdout verbatim to:
`{milestone_dir}/execution/CURATOR-OUTPUT.md`

If the agent fails, returns empty output, or returns malformed blocks:
- Log a `[curator-error]` entry to `.claude/audit/curator-apply.jsonl`
- Continue with Step 3.6 (advisory-mode behavior — do not block completion)

## Step 3.6: Orchestrator Parses and Applies Curator Blocks (ADR-001 preserved)
Parse `{milestone_dir}/execution/CURATOR-OUTPUT.md` for the 5 marker-fenced blocks.
Each block is delimited by `<!-- aihaus:<name> -->` ... `<!-- aihaus:<name>:end -->`.

**Extraction pattern (awk range match):**
```bash
awk '/<!-- aihaus:<name> -->/,/<!-- aihaus:<name>:end -->/' CURATOR-OUTPUT.md \
  | grep -v '<!-- aihaus:' > /tmp/block-<name>.md
```

**Application order (deterministic):**

1. **Parse block `curator-decisions`** (block 5) → compute UUID receipt set.
   This is read by the completion-gate (Component D, Step 6). No file write.

2. **Apply block `decisions-append`** (block 1):
   - Read `.aihaus/decisions.md` before editing (ADR-001 Read precondition).
   - Append extracted block content after the last existing ADR entry.
   - `git add .aihaus/decisions.md`
   - Emit audit row to `.claude/audit/curator-apply.jsonl`:
     `{"ts":"<ISO>","block":"decisions-append","target":".aihaus/decisions.md","status":"applied"}`

3. **Apply block `knowledge-append`** (block 2):
   - Read `.aihaus/knowledge.md` before editing.
   - Append extracted block content after the last existing K-NNN entry.
   - `git add .aihaus/knowledge.md`
   - Emit audit row to `.claude/audit/curator-apply.jsonl`.

4. **Apply block `memory-append`** (block 3):
   - Parse sub-sections separated by `===`. Each sub-section begins with `path: <file>` and `---`.
   - For each sub-section:
     - Read the target file at `path:` before editing.
     - Append the sub-section body to the target file.
     - `git add <target>` (explicit per-file — NEVER `git add -A` or `git add .`)
     - Emit audit row to `.claude/audit/curator-apply.jsonl`.

5. **Apply block `history-append`** (block 4):
   - Read `.aihaus/project.md` before editing.
   - Append the history row to the `## Milestone History` table in the manual section.
   - `git add .aihaus/project.md`
   - Emit audit row to `.claude/audit/curator-apply.jsonl`.

**If any block is `<!-- nothing to promote -->` or `<!-- no warnings for this milestone -->`:**
skip the corresponding append silently; still emit an audit row with `"status":"skipped-empty"`.

**ADR-001 compliance:** the orchestrator (not the curator) performs all file writes.
The curator emits blocks to stdout only. All `git add` calls are explicit per-file.

## Step 4: Update Agent Memory
Write to `.aihaus/memory/` only.
- New patterns -> `.aihaus/memory/global/patterns.md`
- New gotchas -> `.aihaus/memory/global/gotchas.md`
- Architecture changes -> `.aihaus/memory/global/architecture.md`
- Update `.aihaus/memory/MEMORY.md` index for each addition

## Step 4.5: Apply Agent Evolutions
For each milestone, read `{milestone_dir}/execution/AGENT-EVOLUTION.md` (scaffold
guaranteed by `scaffold-assert.sh` per S11a — no existence check needed):

1. Count proposal blocks in AGENT-EVOLUTION.md (`proposal_count`).
   A proposal block is a `## Proposal:` heading and its body.
   If `proposal_count` == 0, set `decision=empty`; skip to the audit-emit sub-step.
2. For each proposal with clear evidence (not speculative):
   - Edit the agent's `.aihaus/agents/[name].md` file
   - Add the new rule, read directive, or protocol step
   - Preserve YAML frontmatter structure (do not change name, tools, model)
   - Do NOT remove Conflict Prevention reads or Self-Evolution sections
   - Log the change: "Agent [name] evolved: [one-line summary]"
   - Increment `applied_count`
3. Skip proposals that are speculative or lack evidence; increment `rejected_count` for each.
4. Run `[[ -f tools/purity-check.sh ]] && bash tools/purity-check.sh || echo "purity-check unavailable (maintainer-only) — skipping"` — revert any evolution that fails (move reverted count from `applied_count` to `rejected_count`).
5. Set `decision`:
   - `applied` if `applied_count` >= 1
   - `rejected` if `proposal_count` >= 1 and `applied_count` == 0
   - `empty` if `proposal_count` == 0
6. **Emit audit row** (unconditional — runs for all three outcomes):
   Rotation check: if `.claude/audit/evolution-apply.jsonl` exists and has >= 10 000 lines
   (or is >= 10 MB), atomically `mv .claude/audit/evolution-apply.jsonl .claude/audit/evolution-apply.jsonl.old` first.
   Then append exactly one JSONL row via Edit tool:
   ```json
   {"ts":"<iso8601-utc>","milestone":"<M0XX>","decision":"applied|empty|rejected","proposal_count":<N>,"applied_count":<M>,"rejected_count":<K>,"schema_version":1}
   ```
   Single writer: orchestrator main thread at this step (ADR-M016-A writer-table).
   Never emit from a hook or sub-agent.
7. Report: "[N] agent evolutions applied, [M] deferred"

## Step 4.6: Update Living Architecture
If any ADR was superseded during execution, or a new convention emerged:
1. Update `.aihaus/decisions.md` with superseded status on old ADRs
2. Update `.aihaus/knowledge.md` with new conventions
3. This keeps architecture docs current — agents read them before every task

## Step 4.7: Emit Reviewer Memory Summaries (ADR-M013-A)
After Step 4.6, instruct the `reviewer` and `code-reviewer` agents to emit per-milestone
summaries. These agents have no Write or Edit tools — they return summary text as part
of their Task-tool payload; the orchestrator parses and applies.

1. Spawn `reviewer` with the instruction:
   `"Emit a per-milestone summary for [M0XX]-[slug]. Return a fenced markdown block
   between <!-- aihaus:reviewer-summary --> and <!-- aihaus:reviewer-summary:end -->
   suitable for writing verbatim to .aihaus/memory/reviews/[M0XX]-reviewer.md.
   Focus on recurring issues, ADR confirmations, and quality signals across all stories."`
2. Spawn `code-reviewer` with the instruction:
   `"Emit a per-milestone summary for [M0XX]-[slug]. Return a fenced markdown block
   between <!-- aihaus:code-reviewer-summary --> and <!-- aihaus:code-reviewer-summary:end -->
   suitable for writing verbatim to .aihaus/memory/reviews/[M0XX]-code-reviewer.md.
   Focus on code-quality patterns, common findings, and anything that should influence
   future implementation style in this repo."`
3. Parse each agent's return for the fenced block. Apply verbatim via Edit tool:
   - `reviewer` block → `.aihaus/memory/reviews/[M0XX]-reviewer.md`
   - `code-reviewer` block → `.aihaus/memory/reviews/[M0XX]-code-reviewer.md`
4. If either agent was NOT spawned during this milestone (e.g., no code-review stories ran),
   skip that agent's Step 4.7 sub-step silently.

**Ownership contract (ADR-M013-A):** orchestrator is sole writer of these per-milestone files
(single-writer invariant preserved — agents emit via payload, orchestrator Edit-applies).
Pre-existing cross-milestone aggregate files (`common-findings.md`, `false-positives.md`) are
NOT touched by Step 4.7; those are governed by the ADR-M013-A scoped-writer whitelist
(reviewer, code-reviewer, verifier, plan-checker may append directly).

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

## Step 6.5: Invalidate context-inject cache
`rm -f .claude/audit/context-inject.cache 2>/dev/null` — ensures M+1 milestone starts with fresh cache (M016-S07).

## Step 6.7: Append telemetry row (M016-S08; ADR-M013-A compliant per BLOCKER-2 fix)
Run `row=$(bash tools/telemetry-collect.sh <M0XX>)` (maintainer-only; script lives in `tools/`, not shipped to downstream installs — R15 known limitation).

The script is **stdout-only** — it does NOT write to `.aihaus/memory/global/architecture.md`. The orchestrator (this main thread) is the SOLE writer of `.aihaus/memory/**` per ADR-M013-A. Apply the captured row via the Edit tool:

1. Read `.aihaus/memory/global/architecture.md` (create if absent with `## Telemetry Summary` header + `<!-- telemetry-summary -->` marker + table header row).
2. Inside the marker section, find any row matching `^| <M0XX> |` and remove it (idempotent replace).
3. Append the new `$row` at the end of the table.
4. If data rows now exceed 50, drop the oldest 10 (FIFO — preserves trend visibility, prevents unbounded growth per R4).
5. Single Edit call rewrites the file.

This pattern preserves single-writer discipline by construction — the script analyzes/aggregates, the orchestrator persists. Per BLOCKER-2 mitigation surfaced at S10 mid-milestone gate (Step E5.5 first invocation).
