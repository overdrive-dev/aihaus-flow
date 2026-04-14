# Architectural Decision Records

## ADR-001: Files are state — no inter-agent messaging primitive

Date: 2026-04-13
Status: Accepted

### Context
aihaus needs a way for agents to read prior specialists' output during multi-step workflows. Claude Code offers two primitives: (1) Agent tool subagents (isolated, one-shot, return string), (2) Teammates with SendMessage (persistent, addressable).

### Decision
Use the Agent tool plus file-based handoff.

- **Per-agent artifact files** are the baseline: every agent writes to its own per-invocation artifact (REVIEW.md, CHALLENGES.md, VERIFICATION.md, etc.). Standard pattern for fan-out + synthesis, covers most multi-agent workflows.
- **CONVERSATION.md turn log** is an *optional* shared-log shape, used only when later rounds must read prior rounds as ordered turns. When used, the parent skill is the sole writer; agents have no Write access.

Not every multi-agent workflow needs a CONVERSATION.md. Simple fan-out + synthesis (e.g., `aih-run/SKILL.md:169-173` final-gate) uses only per-agent artifacts.

### Options Considered
1. (Chosen) Agent tool + per-agent artifact files + skill-mediated optional turn log.
2. Teammates + SendMessage — rejected: breaks audit trail, persistent sessions are heavier, inconsistent with file-based convention.
3. Agents share write access to a single shared log — rejected: write races, ordering corruption.
4. Single long-context agent plays all roles — rejected: loses specialization, adversarial stance, audit trail.

### Consequences
+ Full audit trail (every artifact and turn is persistent).
+ Resumable (crashed runs re-enter via files).
+ Stateless agents — cheap, re-runnable.
+ Per-agent artifacts alone are sufficient for the common case.
- No mid-flight agent-to-agent messaging. Parallel siblings cannot see each other's work until the skill consolidates.
- Ordering is skill-mediated, not agent-driven.
- Hardening gap: tool-level denial (no Write on CONVERSATION.md) only covers agents defined in this plan. Future skills that spawn agents with Write access rely on prose convention until a file-guard hook lands (tracked below).
- Future: if a real-time collaboration primitive becomes necessary, this ADR must be explicitly superseded.

### Follow-up work
- `pkg/.aihaus/hooks/file-guard.sh` extension to reject writes to `CONVERSATION.md` that shrink the file or alter bytes before the last `## Turn` marker. Estimated <20 lines of shell. Files as a standalone patch plan after this plan ships.

## ADR-002: aihaus is Claude-Code-primary with Cursor compat-only support

Date: 2026-04-14
Status: Accepted

### Context
A user question about porting aihaus to Cursor surfaced a brainstorm at
`.aihaus/brainstorm/260413-port-to-cursor-feasibility/` whose adversarial
`CHECK.md` flagged zero live-URL verification as CRITICAL. Story 1 of the
follow-up plan executed that verification on 2026-04-14 via WebFetch
against 7 Cursor documentation URLs (full report at
`.aihaus/research/cursor-primitives-verification.md`).

The verification produced one reality-inverting finding (X1) and two
contradictions gating the original port story:

- **Finding X1 — VERIFIED:** Cursor's Skills and Subagents subsystems
  natively read `.claude/skills/` and `.claude/agents/` as
  legacy-compatibility paths. aihaus's installer already symlinks these
  paths, so a material subset of aihaus's surface is addressable from
  Cursor with zero modifications.
- **Claim (a) — CONTRADICTED:** Cursor subagent frontmatter does not
  accept an `isolation` field; `isolation: worktree` has no Cursor
  equivalent.
- **Claim (f) — CONTRADICTED:** Cursor's only subagent permission field
  is `readonly: true`, which is the opposite of `bypassPermissions`. No
  Cursor equivalent exists for autonomous write-through.

### Decision
aihaus remains Claude-Code-primary. Cursor support ships as a
documentation-only compat layer under `cursor-preview/` at the repo root
— NOT under `pkg/`. No Cursor runtime code. No installer changes. No
`pkg/.aihaus/cursor-variants/` tree. Read-only skills and research agents
work on Cursor via the existing `.claude/*` compat paths; write-capable
worktree-isolated orchestration flows (`/aih-run`, `/aih-feature`,
`/aih-bugfix`, `/aih-resume`, and the `implementer` / `frontend-dev` /
`code-fixer` / `executor` / `nyquist-auditor` agents that back them)
remain Claude-Code-only and are documented as such in
`cursor-preview/COMPAT-MATRIX.md`.

### Rationale
- Preserves the "pure markdown package for Claude Code" identity
  (CLAUDE.md claim unbroken).
- Honors the user constraint: "leverage Cursor without impacting Claude
  Code." Zero changes to Claude-Code-invoked paths, zero installer
  surface area expanded.
- Ships reversibly in one commit: delete `cursor-preview/` + revert
  README subsection + revert the smoke-test check + revert this ADR =
  clean state.
- Measurement-first: a fixed-date decision gate at 2026-06-01
  (`.aihaus/milestones/drafts/.pending/260601-cursor-preview-decision.md`)
  governs whether the preview graduates to a Tier 2 effort, sunsets, or
  continues. ≥3 distinct GitHub Discussions engagements is the
  threshold. "Freeze" is not an option — rotting previews send false
  signals.
- Honest to Cursor users: the compat matrix documents what works, what
  doesn't, and why, rather than silently degrading.

### Consequences
- **Any Tier 2 effort that adds `preToolUse`-hook enforcement of
  ADR-001's single-writer invariant MUST be filed as an ADR-001
  amendment or supersession — not silently shipped as a Cursor-port
  implementation detail.** This is the resolution of the brainstorm
  CHECK.md F-H5 concern (silent ADR rewrite risk).
- `cursor-preview/COMPAT-MATRIX.md` must be updated when any new skill
  under `pkg/.aihaus/skills/` or agent under `pkg/.aihaus/agents/`
  ships, when an agent gains/loses `isolation` or `permissionMode`
  frontmatter, or when Cursor ships a release that changes its
  `.claude/*` compat behavior.
- If Cursor removes `.claude/*/` legacy path support in a future
  release, Finding X1 collapses and ADR-002 re-opens for review —
  likely outcome would be full sunset (delete `cursor-preview/`).
- Wedge analysis against Cursor-native incumbents (`obra/superpowers`,
  `vanzan01/cursor-memory-bank`, etc.) is explicitly out of scope at
  preview tier. If Tier 2 is ever pursued, that gap re-opens and must
  be closed before shipping anything under `pkg/.aihaus/cursor-*`.
- Self-evolution is unaffected: edits to agent definitions continue
  writing to `pkg/.aihaus/agents/`. No dual tree to drift against.

### Options Considered
1. (Chosen) Documentation-only `cursor-preview/` compat layer — leverages
   Finding X1, zero code under `pkg/`, reversible in one commit.
2. Port 3 skills into `pkg/.aihaus/cursor-variants/` (original PLAN v1).
   Rejected: Finding X1 makes "port" unnecessary for read-only skills.
   Creates identity pollution in `pkg/` that CLAUDE.md's purity check
   would have to explicitly whitelist.
3. Adapter-shim or MCP runtime (architect's Option B). Rejected:
   categorical shift from pure-markdown; no demand signal to justify
   the strategic pivot; Finding X1 makes it unnecessary for the
   read-only surface.
4. Dual-target bundle with a build transform (advisor's Option 2).
   Rejected: a build step crosses the "pure markdown" line. Finding X1
   makes the compat paths already serve as the single authoring
   surface.
5. Stay Claude-Code-only with zero Cursor acknowledgment. Rejected: the
   coexistence is real and discoverable; suppressing it is dishonest and
   will produce confused bug reports.
6. Ship `pkg/.aihaus/cursor-variants/` anyway for symmetry. Rejected:
   contradicts CLAUDE.md identity claim; pollutes `pkg/`.
7. Rules file only, no compat matrix. Rejected: the matrix is the
   load-bearing artifact; without it, users discover NOT-SUPPORTED
   flows by breaking.

### Follow-up work
- 2026-06-01 decision gate: process
  `.aihaus/milestones/drafts/.pending/260601-cursor-preview-decision.md`
  at that date. Either promote to Tier 2 (requires a new brainstorm —
  this plan is spent) or schedule a sunset milestone (deletes
  `cursor-preview/`, removes README callout, posts a short "no demand
  signal, reversing" note).
- Quarterly re-fetch of `.aihaus/research/cursor-primitives-verification.md`
  against the same 7 Cursor doc URLs, plus any new pages surfaced by
  Cursor minor-release changelogs touching subagents, hooks, skills, or
  rules.
- When any new skill or agent ships, add a row to
  `cursor-preview/COMPAT-MATRIX.md` as part of the same commit.
