---
name: aih-brainstorm
description: Exploratory multi-specialist ideation with adversarial review and optional web research. Produces BRIEF.md that feeds into /aih-plan or /aih-milestone.
disable-model-invocation: true
allowed-tools: Read Grep Glob Bash Write Agent WebSearch WebFetch
argument-hint: "\"<topic>\" [--panel <roles>] [--deep] [--research]"
---

## Task
Run a brainstorm on `$ARGUMENTS`. **Default (no flags): conversational mode** — lightweight ping-pong between user and orchestrating assistant; zero agents spawned; escalations (research / panel / synthesis) proposed inline with cost transparency and consented to per step. **Flag-driven (`--panel` | `--deep` | `--research`): autonomous fan-out** — runs the full panel phases 2-7 as committed below. Either mode can produce a schema-compliant `BRIEF.md` that hands off to `/aih-plan --from-brainstorm` or `/aih-milestone --from-brainstorm`. No code edits, no branches. Read-only exploration.

$ARGUMENTS

## Load Context (silently)
- Read `.aihaus/memory/MEMORY.md` and referenced files.
- Read `.aihaus/project.md` (stack, conventions).
- Read `.aihaus/decisions.md` — ADR-001 (single-writer) is binding for this skill.
- Read `.aihaus/knowledge.md` if present.

## Inter-agent Conventions — Cite, Don't Duplicate
Turn-log schema, first-line header discriminator, and single-writer rule live in `/aih-help` under **Inter-agent Conventions**. This skill is the sole writer on `CONVERSATION.md` for the brainstorm dir. Every turn block is appended via heredoc by this skill after the subagent returns. No panelist, no contrarian, no synthesizer ever writes `CONVERSATION.md`.

## Argument Parsing
Parse from `$ARGUMENTS`:
- Quoted `<topic>` (required; anything without a `--` prefix).
- `--panel "a,b,c"` (optional; comma-separated agent `name` values; max 5).
- `--deep` (optional; enables Round 2).
- `--research` (optional; enables Phase 6).

## --panel Whitelist Validation (up-front)
Whitelist = all agents under `pkg/.aihaus/agents/` **minus the three write-capable agents** (`implementer`, `frontend-dev`, `code-fixer`). Validated at skill invocation — **before any Agent spawn**. If any `--panel` member is not on the whitelist, abort with this exact string:

```
Invalid --panel member(s): <comma-separated bad names>. Valid agents are listed in pkg/.aihaus/agents/ (excluding implementer, frontend-dev, code-fixer which are write-capable).
```

## Cost-Cap Pre-check (before any spawn)
Count planned invocations as `panelists × rounds + 1 contrarian + 1 synthesizer + (1 if --research else 0)`. Rounds is `2` with `--deep`, else `1`. Cap table (binding):

| Flow | Panelists | Invocations | Cap |
|------|-----------|-------------|-----|
| default | 3 | 5 | 5 |
| `--deep` | 3 | 8 | 8 |
| `--deep --research` | 3 | 9 | 9 |
| max (`--panel` 5 + `--deep` + `--research`) | 5 | 13 | 13 |

Hard ceilings regardless: 5 panelists, 2 rounds, 1 contrarian, 1 research agent. If the count exceeds the cap for the requested flag combination, abort with: `Invocation cap exceeded: requested <N>, cap <C> for flags <flags>. Reduce --panel size or drop --deep/--research.` Counted before spawn — not discovered mid-run.

## Phase 1 — Intake

1. **Generate slug** — format `YYMMDD-lowercase-hyphen-topic`, max 40 chars total including the `YYMMDD` prefix (same format as `aih-plan/SKILL.md` Phase 2 step 8).
2. **Create the brainstorm dir**: `mkdir -p .aihaus/brainstorm/[slug]/`.
3. **Seed `CONVERSATION.md`** via heredoc with exactly this shape:

   ```markdown
   # Conversation: [slug]
   _Append-only turn log. The parent skill is the sole writer — agents do not write to this file directly. Each turn is a distinct block, most recent last._

   ## Turn 1 — user — [ISO-8601 timestamp]
   [raw topic + any clarifying answer captured inline]

   ---
   ```

   First-line header is `# Conversation: [slug]` — NOT `# Conversation Log:`, which is reserved for the user-message log shape in `/aih-milestone` and `/aih-plan-to-milestone`.
4. **Print the stdout contract line — LOAD-BEARING, LOCKED PREFIX** (consumed by Story 8 dogfood via `grep '^Created brainstorm at \.aihaus/brainstorm/'`):

   ```
   Created brainstorm at .aihaus/brainstorm/<slug>/
   ```

   Forward slashes. Exactly one line. No variation.
5. **Ask at most 1 clarifying question**. Skip entirely if the topic is already concrete. If asked and answered, distill the answer into Turn 1's body (do not create a second turn for it — Turn 1 is the single user turn that seeds Round 1).

## Phase 1.5 — Conversational Default Mode (no flags)

**Applies when `$ARGUMENTS` contains no `--panel`, `--deep`, or `--research`.** If any flag is present, skip and fall through to Phase 2.

Enter a ping-pong loop with the user. The **orchestrating assistant** (not a spawned agent) reads loaded project context, asks focused questions, proposes framings, and riffs on the topic — zero agent spawns by default. Append each user reply to Turn 1's body; do not create Turn 2+ unless an escalation fires (ADR-001 unchanged). Watch for escalation signals per co-located `escalation.md`; propose escalations inline with **cost transparency** (state agent count + wall-clock estimate before asking consent); user consents per step. On consent, dispatch:
- **research** → spawn one of `phase-researcher` / `advisor-researcher` / `domain-researcher`; writes `RESEARCH.md`; skill appends research turn; resume ping-pong.
- **panel** → run Phases 2→5 (selection, Round 1, optional Round 2, contrarian); resume ping-pong.
- **synthesis** → run Phases 7→8 (synthesizer in lightweight mode if no `PERSPECTIVE-*.md`, validator, handoff).
- **abandon** ("not pursuing" / "nevermind") → leave artifacts, do NOT write `BRIEF.md`, print `Brainstorm ended without BRIEF.md — CONVERSATION.md preserved at <path>.`

Agents are spawned only after the conversation earns them. This matches the brainstorm's purpose as a pre-project exploration step that might lead to nothing.

## Phase 2 — Panel Selection
Default panel size: 3 agents. Pick by topic-pattern match against this table:

| Topic pattern | Default panel |
|---------------|---------------|
| Technical architecture / "how should we build X" | `architect` + `advisor-researcher` + `phase-researcher` |
| Product / UX / "how should users experience X" | `product-manager` + `ux-designer` + `analyst` |
| Domain / regulatory / "what are the rules for X" | `domain-researcher` + `analyst` + `advisor-researcher` |

**No-keyword-match fallback — LOCKED.** If the topic matches no row (e.g., `"what makes a good morning routine?"`), default to the **technical-architecture row**: `architect` + `advisor-researcher` + `phase-researcher`. Deterministic, not implementer-choice.

`--panel "a,b,c"` overrides the default (comma-separated, max 5, already whitelist-validated). **Print the panel and one-sentence rationale before spawning.**

## Phase 3 — Round 1 (PARALLEL)

**No prior precedent in the repo for this specific fan-out mechanic.** `aih-run/SKILL.md:169-173` describes end-gate parallelism in prose but does not document the single-turn multi-Agent-call pattern. Story 4 (this skill) authors it first.

**Mechanic — instruction to the operating assistant (binding):**

> In a single assistant turn, issue one Agent tool call per panelist. Wait for all to return before proceeding to Phase 4.

Per-panelist prompt scaffolds:
- Read `.aihaus/brainstorm/[slug]/CONVERSATION.md` (Turn 1 is all that is visible).
- Write your perspective to `.aihaus/brainstorm/[slug]/PERSPECTIVE-<your-role>.md` where `<your-role>` is your agent `name` field.
- Return a one-paragraph summary as your string response — the skill distills it into your turn block.

**After all panelists return**, the skill (not any agent) appends turn blocks to `CONVERSATION.md` in **alphabetical-by-role order** via heredoc. Ordering is load-bearing — Story 8 criterion 3 asserts turn counts assuming this determinism. Each block: `## Turn N — <role> — <ISO-8601>` then the distilled body then `---`.

## Phase 4 — Round 2 (SEQUENTIAL, opt-in `--deep`)
Default: **skipped.** Round 2 is flag-only (`--deep`) — no auto-enable based on contrarian or any other runtime signal. Rationale: predictable cost.

If `--deep`: for each panelist in alphabetical-by-role order, re-spawn with full `CONVERSATION.md` visible. Agent writes `PERSPECTIVE-<role>-r2.md` and returns a summary. Skill appends one turn per panelist immediately after that panelist returns (sequential, not batched — each later panelist should see prior Round 2 turns).

## Phase 5 — Contrarian
Spawn `contrarian` (`subagent_type: "contrarian"`) with full `CONVERSATION.md` + all `PERSPECTIVE-*.md` in scope. Contrarian has tools `Read, Grep, Glob` — **no Write.** It returns its findings as a string payload terminating with `CHALLENGES-FOUND: <N>` or `NO-FINDINGS-JUSTIFIED`.

**The skill** writes `.aihaus/brainstorm/[slug]/CHALLENGES.md` verbatim from the returned payload, then appends a contrarian turn block summarizing the verdict (severity counts + terminator) to `CONVERSATION.md`.

## Phase 6 — Web Research (opt-in `--research`)
Default: **skipped.** If `--research`, pick exactly one researcher by topic fit:
- `phase-researcher` — technical/unfamiliar-framework territory.
- `domain-researcher` — regulatory / domain rules.
- `advisor-researcher` — market / vendor / landscape.

Spawn. The researcher writes `.aihaus/brainstorm/[slug]/RESEARCH.md` with VERIFIED / CITED / ASSUMED provenance tags (convention from `phase-researcher.md:48`). Skill appends a research turn block.

## Phase 7 — Synthesis
Spawn `brainstorm-synthesizer` (`subagent_type: "brainstorm-synthesizer"`). It reads every `PERSPECTIVE-*.md` + `CHALLENGES.md` + `RESEARCH.md` (if present) + `CONVERSATION.md` and writes `BRIEF.md`. The synthesizer fails closed if `CONVERSATION.md` has fewer than 3 `## Turn ` lines; surface its error verbatim and halt — no partial `BRIEF.md`.

**Prompt-construction discipline — LOAD-BEARING.** The synthesizer's agent definition (`brainstorm-synthesizer.md`) owns the BRIEF.md 8-header schema as a Committed Contract. The operator MUST pass a minimal prompt that delegates schema entirely to the agent. Do NOT re-list section names, do NOT describe what to "cover," do NOT rename headers to fit the current topic. Re-specifying section names in the prompt is a contract violation — downstream `/aih-plan --from-brainstorm` and `/aih-milestone --from-brainstorm` consumers assert the exact 8 headers and will abort on drift.

Use this minimal prompt template verbatim:

```
You are the synthesizer for the brainstorm at `.aihaus/brainstorm/<slug>/`.
Read CONVERSATION.md, every PERSPECTIVE-*.md, CHALLENGES.md, and RESEARCH.md if present.
Produce .aihaus/brainstorm/<slug>/BRIEF.md per your agent definition's committed 8-header schema.
Return a one-line string after writing: the path to BRIEF.md and the Suggested Next Command line.
```

Additional context about panelist disagreements or contrarian findings belongs in the agent's *inputs* (the perspective files and CHALLENGES.md), not in the spawn prompt.

## Phase 7.5 — BRIEF.md Schema Validation
After the synthesizer returns, the skill (not the agent) reads `.aihaus/brainstorm/[slug]/BRIEF.md` and asserts the 8 H2 headers are present in exact order, spelling, and capitalization:

1. `## Problem Statement`
2. `## Perspectives Summary`
3. `## Key Disagreements`
4. `## Challenges`
5. `## Research Evidence`
6. `## Synthesis`
7. `## Open Questions`
8. `## Suggested Next Command`

Validation command (bash): `grep -n "^## " .aihaus/brainstorm/[slug]/BRIEF.md` — compare against the canonical list.

If any required header is missing or out-of-order, abort with this exact string and do NOT proceed to Phase 8:

```
BRIEF.md at <slug> failed schema validation — missing/out-of-order section(s): <list>. Re-run /aih-brainstorm <slug> or patch BRIEF.md manually before promoting.
```

Pass-through is silent — success emits no output and proceeds to Phase 8.

## Phase 8 — Handoff
Print (to stdout):
1. Absolute path to `BRIEF.md`.
2. The `Suggested Next Command` line verbatim from `BRIEF.md`.

Do NOT auto-promote. `/aih-plan --from-brainstorm <slug>` and `/aih-milestone --from-brainstorm <slug>` are explicit user actions.

## Attachment Handling
If the user pastes images or drags files during intake or clarification:
1. Source paths: pasted images live at `~/.claude/image-cache/[uuid]/[n].png`; dragged files appear as absolute paths.
2. Copy to `.aihaus/brainstorm/[slug]/attachments/[seq]-[short-desc].[ext]` via `cp`. Seq is 2-digit zero-padded.
3. Describe each in one sentence using vision.
4. Reject files > 20 MB. Remind: crop/redact if sensitive — `.aihaus/` is git-tracked.
5. Forward attachment paths into every panelist prompt (mirrors `aih-run/SKILL.md:126-133` attachment-handoff block).

## Capture, Don't Execute (intake discipline)
If during intake or panelist turns the user raises an implementable aside ("while you're at it, fix X"), capture it into the synthesizer's `BRIEF.md` under **Open Questions**. Do NOT branch, edit, or commit — brainstorms are exploration, not execution. Explicit override only: "fix this now" / "just do it" → hand off to `/aih-quick` or `/aih-bugfix`; do not inline.

## Guardrails
- MUST NOT create git branches.
- MUST NOT modify source code, tests, configs, or migrations.
- MUST NOT write outside `.aihaus/brainstorm/[slug]/`.
- Hard caps (pre-spawn enforced): 5 panelists, 2 rounds, 1 contrarian, 1 research agent.
- `/aih-resume` does NOT pick up brainstorms — brainstorm is interactive exploration, not interruptible execution.
- `/aih-sync-notion` does NOT sync brainstorms — research artifacts stay local; only promoted plans/milestones sync.
- Skill is sole writer on `CONVERSATION.md` (ADR-001). Panelists write only their own `PERSPECTIVE-<role>.md`. Contrarian writes nothing. Synthesizer writes only `BRIEF.md`.
