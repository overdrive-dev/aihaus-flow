# Architectural Decision Records

## ADR-001: Files are state — no inter-agent messaging primitive

Date: 2026-04-13
Status: Superseded (partial) by ADR-003 (2026-04-14); amended by ADR-004 (2026-04-14)

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

## ADR-003: Agent→Skill invocation via last-line marker protocol (partial supersession of ADR-001)

Date: 2026-04-14
Status: Accepted

### Context

ADR-001 closed with an explicit clause: "if a real-time collaboration
primitive becomes necessary, this ADR must be explicitly superseded."
ADR-002's Consequences section (lines 97-101) tightened that clause:
"any Tier 2 effort that adds preToolUse-hook enforcement of ADR-001's
single-writer invariant MUST be filed as an ADR-001 amendment or
supersession — not silently shipped."

Milestone M003 surfaces the concrete need. plan-checker and reviewer
regularly identify semantic-design CRITICAL findings during adversarial
review — findings that require an ADR stub to preserve the decision
trail. Today the agent returns the finding as prose and the user must
manually copy it, open a fresh `/aih-quick draft-adr` invocation, paste
the finding, wait, review, commit. Hand-off friction is constant; ADR
drafts are frequently deferred or lost. A prior session log (F6) cites
this exact gap.

A mid-flight invocation primitive is necessary. Per ADR-001's closing
clause and ADR-002's anti-silent-rewrite clause, supersession must be
filed explicitly — not retrofitted into skill prose.

### Decision

Adopt a **last-line XML-ish marker protocol** for agent-to-skill
invocation requests. This is a **partial** supersession of ADR-001:
ADR-001's file-based handoff remains the default path for ordinary
multi-agent workflows; the marker protocol opens one narrow channel for
agents to request mid-flight skill re-dispatch.

**Marker schema:**

```
<AIHAUS_INVOKE skill="aih-<slug>" args="<string-≤200>" rationale="<string-≤200>" blocking="true|false"/>
```

**Rules:**

- MUST be the last non-empty line of the agent's return string (same
  contrarian.md terminator idiom at `pkg/.aihaus/agents/contrarian.md`
  lines 100-109).
- `invoke-guard.sh` inspects ONLY that last non-empty line — sidesteps
  fenced-code-block false positives and prose-embedded markers.
- `args` ≤ 200 chars; `rationale` ≤ 200 chars and non-empty;
  `blocking` ∈ {true, false}; else `INVOKE_REJECT <reason>`.
- **Allowlist:** `aih-quick`, `aih-bugfix`, `aih-feature`, `aih-plan`,
  `aih-plan-to-milestone`, `aih-run`.
- **Excluded:** `aih-init`, `aih-milestone`, `aih-sync-notion`,
  `aih-update`, `aih-brainstorm`, `aih-help`, `aih-resume` —
  lifecycle-bootstrap / external-system / interactive-only skills.
- **Depth cap at 3.** File-based counter reads row count of
  `## Invoke stack` section of RUN-MANIFEST.md (see ADR-004). Env vars
  do not propagate reliably across the Agent tool's subprocess boundary
  on Windows / Git Bash — `session-start.sh` is the precedent for
  file-based state.
- **Self-invocation refused.** If marker's `skill` equals top-of-stack
  skill, `invoke-guard.sh` emits `INVOKE_REJECT self-invocation`
  (defense-in-depth alongside each target skill's own on-entry guard,
  e.g., `aih-quick`'s story-06 self-invocation prose).

**Emit / parse / dispatch separation — this is load-bearing:**

- **Agents EMIT** the marker as text in their return string. They do
  not parse, do not dispatch, do not call any skill or hook. Frontmatter
  on the 10 locked adversarial agents (`plan-checker`, `reviewer`,
  `code-reviewer`, `security-auditor`, `integration-checker`, `verifier`,
  `contrarian`, `assumptions-analyzer`, `pattern-mapper`, `architect`)
  stays byte-identical — no agent gains `Skill` in its `tools:` line.
- **Parent skills PARSE** via `invoke-guard.sh` (hook takes stdin, emits
  one of `INVOKE_OK skill|args|rationale|blocking`, `INVOKE_REJECT <reason>`,
  or `NO_INVOKE`).
- **Parent skills DISPATCH** via their own `Skill` tool (skills have
  `Skill` by default per Claude Code platform). On `INVOKE_OK`: push a
  frame via `manifest-append.sh --field invoke-push`, dispatch, pop on
  return.

**Confirmation default:** prompt user before dispatch. Override via
`aihaus.autoInvoke: true` in `.claude/settings.local.json`. Open question
1 resolved this way in M003 CONTEXT.md.

### Options Considered

| # | Option | Pros | Cons | Why Not |
|---|--------|------|------|---------|
| 1 | **(Chosen)** Last-line XML-ish marker parsed by parent skill | Greppable; unambiguous (no English prose emits `<AIHAUS_INVOKE`); agents' audit trail preserved; file-based depth counter matches existing session-start.sh precedent | Requires emit/parse/dispatch discipline; one new hook | Minimum ADR-001 blast radius — preserves files-as-state invariant in every other path |
| 2 | Grant `Skill` tool to specific agents via frontmatter allowlist | Simplest protocol | Unverified propagation (GitHub #17283 reports `Skill` tool in subagents is fragile); breaks ADR-001 more invasively; recursion harder to cap; Frontmatter-lock contract forbids | User-verified: no in-repo precedent; zero of 43 agents list `Skill` today |
| 3 | Plain-text marker (`INVOKE_SKILL: aih-quick args`) | Simpler to emit | Easier to accidentally emit inside documentation / prose; harder to cap rationale length at parse time | XML-ish tag is grep-robust + last-line contract sidesteps collision |
| 4 | Env var `AIHAUS_INVOKE_DEPTH` for recursion cap | Simpler flag | F-C2: env vars do not propagate across Agent tool subprocesses on Git Bash + Windows; `session-start.sh` already proves file-based state is how aihaus does this | File-based depth counter is the only reliable option |
| 5 | Fenced JSON block (`` ```json {...} ``` ``) as the marker | Structured, parseable | Agents emit code-block examples constantly — high false-positive rate | Last-line contract + XML-ish tag is unique enough |
| 6 | No mid-flight mechanism; keep manual hand-off forever | Zero protocol surface | Hand-off friction is constant; ADR drafts get lost (F6 session-log evidence) | The user gap is real; shipping the minimum-viable primitive is the correct response |

### Consequences

- **Audit trail preserved.** Every INVOKE decision logs one JSON line
  to `.claude/audit/invoke.jsonl` (`ts`, `verdict`, `skill`, lengths,
  depth, reject_reason). Matches the existing `.claude/audit/` pattern.
- **ADR-001 interpretation updated.** The supersession is **partial**:
  files remain the primary state channel; the marker opens one bounded
  text-return channel with explicit emit/parse/dispatch separation.
  Consumers of ADR-001 reading after 2026-04-14 see the status line
  pointer to ADR-003 and know to check for the marker-protocol
  exception.
- **Emitter agents gain output-contract prose.** plan-checker, reviewer,
  architect, assumptions-analyzer get "INVOKE marker emission" sections
  added to their definitions (story 09). Frontmatter-lock honored —
  `tools:` lines byte-identical to pre-milestone snapshot. No agent
  gains `Skill`.
- **Parent-skill dispatch logic lives in aih-run, aih-plan,
  aih-plan-to-milestone** (story 11). Other allowlist entries
  (aih-quick, aih-bugfix, aih-feature) are allowlist-valid targets but
  do not themselves parse markers — they are the ones being dispatched
  TO, not dispatching FROM.
- **Self-invocation guard in aih-quick** (story 06) is defense-in-depth
  — if invoke-guard's REJECT fails, aih-quick's own on-entry guard
  catches the recursion.
- **Inline-ADR mode in aih-quick** (story 19) is the first concrete
  consumer: `aih-quick draft-adr <summary>` runs INLINE on the
  orchestrator branch (no new worktree, no new commit) and invokes
  `architect` with the `draft-adr` handler (story 20) to write a stub
  with `Status: Accepted`.

### Follow-up work

- **ADR-004 is load-bearing on this ADR.** ADR-003's depth counter reads
  ADR-004's `## Invoke stack` section. The two are interlocked — the
  marker protocol cannot function without the single-writer manifest,
  and the single-writer manifest's phase-advance refusal depends on the
  marker protocol's stack semantics. Accept both together; revert both
  together.
- **Allowlist expansion.** If a future milestone adds `aih-feature` or
  `aih-bugfix` as active dispatch targets (today they are allowlist-valid
  but not yet exercised), that's a prose change to the consuming skill
  — not a new ADR.
- **Auto-invoke default** may flip from confirm-first to auto-dispatch
  in a future milestone once operational data justifies. Flip requires
  ADR amendment (this one) — not silent skill prose change.
- **Cursor compat note (ADR-002 interaction):** the marker protocol is
  Claude-Code-only by default. Skills `aih-run`, `aih-plan`,
  `aih-plan-to-milestone` are Claude-Code-primary per ADR-002's compat
  matrix. Cursor users running aihaus on the `.claude/*` compat paths
  will see markers in agent returns but no dispatch happens — graceful
  degrade.

## ADR-004: Single-writer discipline for RUN-MANIFEST.md + STATUS.md projection (amendment to ADR-001)

Date: 2026-04-14
Status: Accepted

### Context

ADR-002 Consequences (lines 97-101) mandate: "any Tier 2 effort that
adds preToolUse-hook enforcement of ADR-001's single-writer invariant
MUST be filed as an ADR-001 amendment or supersession — not silently
shipped as a Cursor-port implementation detail." This ADR satisfies
that requirement for M003.

The ADR-001-stated invariant — "files are state; parent skill is the
sole writer of CONVERSATION.md" — was expressed as prose discipline
with tool-level denial on agents only. Hook-level enforcement was
flagged as Follow-up work on ADR-001 itself (`file-guard.sh` extension).
ADR-001's Consequences explicitly note: "tool-level denial ... only
covers agents defined in this plan. Future skills that spawn agents
with Write access rely on prose convention until a file-guard hook
lands."

Two concrete defects in the current aihaus flow make the hook-level
enforcement load-bearing now:

1. **RUN-MANIFEST.md and STATUS.md are two files describing one state
   machine with disjoint vocabularies.** STATUS.md takes values
   `gathering`, `ready`; RUN-MANIFEST.md Phase takes `planning`,
   `execute-stories`, etc. No single source of truth; drift is silent
   and crash-triggered.
2. **Six write sites in `aih-run/SKILL.md` alone** mutate RUN-MANIFEST.md
   via free-form Edit / Write — not append-only, not atomic. A crash
   mid-write leaves the file half-rewritten and `/aih-resume` parses
   garbage.

### Decision

Adopt **RUN-MANIFEST.md v2 as the single source of truth** for milestone
state. STATUS.md becomes a **derived projection**, written only by
`phase-advance.sh`. Enforce with three new hooks:

**Schema v2 (RUN-MANIFEST.md):**

```
## Metadata
milestone: M0XX
branch: milestone/M0XX-...
started: <ISO-8601-UTC>
schema: v2

## Invoke stack
(empty when no invocation in flight; max 3 rows; LIFO)

## Story Records (append-only, pipe-delimited)
story_id|status|started_at|commit_sha|verified|notes
S01|complete|2026-04-14T10:20:00Z|a1b2c3d|true|
```

Full grammar at `pkg/.aihaus/templates/RUN-MANIFEST-schema-v2.md`
(story 03).

**Enforcement surface:**

- **`manifest-append.sh` is the sole writer of RUN-MANIFEST.md.**
  Supports three modes: `story-record` (append-only), `invoke-push` /
  `invoke-pop` (bounded stack mutation via tmp+replace, max 3 rows).
  Uses `mkdir`-mutex (`flock(1)` is not available on Git Bash), 30s
  stale-reclaim, `trap 'rmdir ...' EXIT INT TERM` release.
- **`phase-advance.sh` is the sole writer of STATUS.md.** Writes
  `STATUS.md.tmp` then atomically replaces via `mv` with Python
  `os.replace` fallback on OneDrive-path detection (Git Bash `mv` is
  not reliably atomic on NTFS under OneDrive interception). Also
  updates PLAN.md Status frontmatter via same tmp+replace pattern.
  **Refuses to advance when `## Invoke stack` non-empty** — prevents
  phase-crossing mid-invocation.
- **`manifest-migrate.sh` converts v1 → v2** on `aih-resume` entry and
  before first `aih-run` `manifest-append`. Backs up to `.v1.bak`;
  idempotent (second run detects `schema: v2` header and no-ops).
- **Worktree-refusal.** All three hooks call
  `git rev-parse --show-superproject-working-tree` on entry. Non-empty
  → exit 3 with explicit refusal. Canonical-state mutations from
  implementer/frontend-dev/code-fixer worktrees are forbidden (K-002
  discipline).

**Projection invariant (STATUS.md):**

- Contains only: current phase, current story_id, last-updated
  ISO timestamp.
- Line 1 is verbatim marker: `<!-- DERIVED FROM RUN-MANIFEST.md — DO NOT EDIT BY HAND -->`.
- Legacy STATUS.md without this marker → `phase-advance.sh` backs up
  to `STATUS.md.handwritten.bak` before overwriting.

### Migration

`manifest-migrate.sh` is a v1→v2 schema detector + converter. Detection
heuristic: grep for `^schema: v2$` inside the first `## Metadata` block.
Absent → v1 path. On v1 detection:

1. Copy original to `<path>.v1.bak` BEFORE any mutation.
2. Convert best-effort: `Status:` / `Phase:` / `Milestone:` prose lines
   → Metadata keys; `## Progress Log` entries → pipe-delimited Story
   Records rows; unparseable lines → `story_id=unknown` rows with
   `notes=<raw>` preserving the raw text.
3. Insert empty `## Invoke stack` section between Metadata and Story
   Records.
4. Stamp `schema: v2` at end of Metadata block.

Fixture pair `tools/.fixtures/run-manifest-legacy.md` (v1 input) +
`run-manifest-v2-expected.md` (byte-equal golden output) gates
correctness. Smoke-test runs the round-trip.

Idempotent — second run exits 0 `already-v2` without any mutation.

`aih-resume` calls the migrator on entry, BEFORE any read of
RUN-MANIFEST.md. `aih-run` calls it ONCE at run start (no-op on v2
manifests; applies on the NEXT run after M003 merges for in-flight
milestones).

### Options Considered

| # | Option | Pros | Cons | Why Not |
|---|--------|------|------|---------|
| 1 | **(Chosen)** RUN-MANIFEST.md v2 authoritative; STATUS.md projection; three hooks enforce single-writer + atomic replace | Single source of truth; projection invariant testable; hook-level enforcement survives prose drift | New hooks + schema migration required | ADR-002 mandates the amendment path; prose-only enforcement has already drifted |
| 2 | Keep RUN-MANIFEST + STATUS as-is; just add a reconciliation step | Less invasive | Doesn't solve race on mid-file rewrites; silent drift stays possible; reconciliation step itself is a new write site that can race | RESEARCH.md Q2 recommends projection model explicitly |
| 3 | Make STATUS.md authoritative, RUN-MANIFEST.md derived | Fewer write sites (1 line per transition) | Loses append-only Story Records + Invoke stack + Progress Log — these need a place to live | RUN-MANIFEST.md already holds them; moving them to STATUS.md is a bigger rewrite |
| 4 | Use env var `AIHAUS_INVOKE_DEPTH` instead of `## Invoke stack` counter | One fewer file read | F-C2: env vars don't propagate across Agent tool subprocesses on Git Bash + Windows; session-start.sh precedent | File-based is the only reliable option on primary dev env |
| 5 | Skip schema migration; require users to reset in-flight milestones | Simpler hook | Data loss during adoption; hostile to existing users | Migration detector is ~30 lines; `.v1.bak` preserves original |
| 6 | Use `flock(1)` instead of `mkdir`-mutex | Standard POSIX idiom | Not available on Git Bash — primary dev env | mkdir-mutex is atomic, cross-platform, and the only option |

### Consequences

- **Projection invariant enforced.** STATUS.md is derived; hand-edits
  are lost on next `phase-advance.sh` run (with `.handwritten.bak`
  preservation). Operators who need to edit state do so via
  RUN-MANIFEST.md → `manifest-append.sh`.
- **In-flight v1 manifests auto-migrate** on next `aih-resume` or
  `aih-run`. Users with crashed v1 manifests can restore from `.v1.bak`
  if migration outputs unexpected Story Records.
- **Atomic write discipline via mkdir-mutex + Python os.replace.**
  `flock(1)` unavailable on Git Bash; `mv` atomic-replace unreliable on
  NTFS + OneDrive. Python's `os.replace` is atomic on NTFS even with
  OneDrive interception. K-003 documents the rationale (story 22).
- **OneDrive compatibility.** `phase-advance.sh` and
  `manifest-migrate.sh` detect OneDrive paths and prefer the Python
  fallback immediately. One-time advisory logged to
  `.claude/audit/hook.jsonl`.
- **Worktree refusal is defense-in-depth.** K-002 already mandates
  that worktrees branch off `main`, not the milestone branch. A
  misconfigured worktree that tries to mutate RUN-MANIFEST.md or
  STATUS.md now exits 3 with explicit refusal, rather than silently
  corrupting cross-worktree state.
- **ADR-001 body remains intact.** This ADR amends the Consequences
  surface (hook-level enforcement now exists), does not replace
  ADR-001's Decision body. Files-as-state remains the primary model;
  the single-writer invariant is now hook-enforced for RUN-MANIFEST.md
  and STATUS.md specifically.
- **Bootstrap caveat.** This milestone's OWN `/aih-run` invocation
  writes v1-shape RUN-MANIFEST.md because it uses the OLD skill code.
  The migration activates on the NEXT `/aih-run` after M003 merges.
  Stated explicitly in PRD "Out of scope" so reviewers do not expect
  mid-milestone self-activation.

### Follow-up work

- **ADR-003's marker protocol depends on this ADR's Invoke stack.**
  The depth counter is the row count of `## Invoke stack`; without
  single-writer discipline on that section, the counter races. Accept
  both ADRs together; revert both together.
- **file-guard.sh extension for CONVERSATION.md** (Follow-up work from
  ADR-001) remains tracked separately. This ADR's scope is RUN-MANIFEST.md
  + STATUS.md only; CONVERSATION.md protection is a distinct patch.
- **Schema v3 evolution.** If future milestones need more Metadata
  fields (e.g., parent-milestone back-reference, branch-protection
  flag), extend the Metadata block and bump schema version with a
  migrator for v2→v3. Grammar + migrator pattern is established here.
- **Benchmark invoke-stack contention.** One lock protects both Story
  Records and Invoke stack. Under high invoke-push/pop churn,
  throughput may degrade. Open question 2 from M003 CONTEXT.md
  deferred this to N.2 smoke-test; not a go/no-go for the current
  milestone.
- **Cross-ref ADR-003.** The `## Invoke stack` section is where
  ADR-003's marker-protocol depth counter reads from. ADR-003's
  emitter/parser/dispatcher separation keeps agents away from this
  file entirely — only parent skills ever write via
  `manifest-append.sh`.
