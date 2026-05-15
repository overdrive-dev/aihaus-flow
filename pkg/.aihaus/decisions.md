# Architectural Decision Records

## ADR-001: Files are state — no inter-agent messaging primitive

Date: 2026-04-13
Status: Superseded (partial) by ADR-003 (2026-04-14); amended by ADR-004 (2026-04-14); further superseded (partial) by ADR-006 (2026-04-14 — RUN-MANIFEST.md ownership transferred from aih-run/SKILL.md to aih-milestone/SKILL.md + annexes/execution.md)

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
Status: Superseded by ADR-005 on 2026-04-14 (multi-platform stance — both Cursor and Claude Code are first-class install targets)

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
Status: Accepted — Superseded (partial) by ADR-006 (2026-04-14 — ALLOWLIST + parent-dispatcher list updated; aih-run and aih-plan-to-milestone removed; aih-milestone + aih-feature added as dispatchers); amended by ADR-007 (2026-04-14 — disable-model-invocation removed from the 5 allowlist skills to make Skill-tool dispatch operational; Skill added to allowed-tools as defense-in-depth)

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
Status: Accepted — Superseded (partial) by ADR-006 (2026-04-14 — single-writer site for RUN-MANIFEST.md moves from aih-run/SKILL.md to aih-milestone/SKILL.md + annexes/execution.md; all hook-call pairings preserved verbatim)

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

---

## ADR-005: aihaus is multi-platform — Cursor and Claude Code are both first-class install targets

Date: 2026-04-14
Status: **Superseded by ADR-M015-A (2026-04-22)** — Cursor support fully removed in v0.19.0.

Supersedes ADR-002 (2026-04-14) which framed aihaus as Claude-Code-primary with Cursor as preview/compat-only.

### Context

ADR-002 was written before the Cursor plugin format was verified. It treated Cursor as a compat-only environment reachable via `.claude/` legacy paths, with a `cursor-preview/` scaffolding directory and a sunset-by-signal review clause. The v0.8.0 verification report (`.aihaus/research/cursor-primitives-verification.md`) and the 2026-04-14 plugin-format refresh (`.aihaus/research/cursor-plugin-format.md`) together produced enough evidence to elevate Cursor to a first-class target:

- Cursor ships a documented plugin format (`.cursor-plugin/plugin.json`) that bundles rules, skills, agents, hooks, commands, and MCP servers — the same conceptual surface aihaus already ships.
- Local install is a git-backed directory at `~/.cursor/plugins/local/<name>` — the same symlink pattern aihaus already uses for `.claude/`.
- Two primitives stay contradicted on Cursor (`isolation: worktree`, `permissionMode: bypassPermissions`) and their dependents remain NOT-SUPPORTED — but this is now a documented partial-coverage matrix, not a reason to gate out the entire plugin surface.

### Decision

1. **Cursor is a first-class install target.** Users run `install.sh --platform cursor` (or `--platform both`) and get a functional aihaus plugin on Cursor. The `--platform claude` default preserves pre-v0.10.0 behavior (byte-identical install path).
2. **File layout (Strategy B).** `.cursor-plugin/plugin.json` lives at `pkg/.aihaus/.cursor-plugin/plugin.json`. `pkg/.aihaus/` is the plugin root. `rules/`, `skills/`, `agents/`, `hooks/` sit as siblings of `.cursor-plugin/` — matching Cursor's documented example layout. No repo-root symlinks into `pkg/`. See `.aihaus/milestones/M006-cursor-native-install/execution/S1-DECISION.md` for the Strategy A vs B trade-off.
3. **Cursor rules file is shipped, not preview.** `cursor-preview/` is deleted; its contents live at `pkg/.aihaus/rules/` with PREVIEW framing removed. The compatibility matrix stays authoritative for per-skill verdicts.
4. **Authoring convention.** New skills and agents are authored platform-aware. If a skill or agent depends on a Cursor-contradicted primitive, the COMPAT-MATRIX.md row is updated in the same commit (NOT-SUPPORTED). CLAUDE.md documents this expectation.
5. **Marketplace submission out of scope** for M006. Local install is the deliverable. A future milestone may cover marketplace packaging, signing, and submission.

### Options Considered

| # | Option | Pros | Cons | Why Not |
|---|--------|------|------|---------|
| 1 | Keep ADR-002 preview stance | No churn; conservative | Cursor users stay second-class; signal threshold in ADR-002 is arbitrary | Evidence (plugin format verified) removes the rationale for preview framing |
| 2 | Strategy A — plugin.json at repo root with path-override field | Single manifest location | No documented path-override field; risks silent breakage on Cursor updates | Strategy B aligns with documented pattern |
| 3 | Multi-platform via environment auto-detect (implicit) | No user-facing flag | Opaque; users can't force a target on dual-tool machines | `--platform` is explicit and reversible |

### Consequences

- Version bump v0.10.0 (M006).
- `cursor-preview/` directory removed from repo.
- `pkg/.aihaus/.cursor-plugin/plugin.json`, `pkg/.aihaus/.cursor-plugin/README.md` created.
- `pkg/.aihaus/rules/` created with migrated content (PREVIEW framing dropped).
- `pkg/scripts/install.sh` + `uninstall.sh` gain `--platform` flag.
- `CLAUDE.md` Package Contents updated; authoring convention documented.
- Two unresolved sub-questions tracked as UNVERIFIED (hot-reload, strict JSON validation) — non-blocking; documented in install README and re-checked on quarterly Cursor-doc cadence.

### Follow-up work

- Marketplace submission (future milestone).
- Live hot-reload verification once a maintainer with Cursor installed can run a sandbox.
- Per-platform smoke test (install → verify plugin loads → uninstall).

## ADR-006: Command surface consolidation — `/aih-run` and `/aih-plan-to-milestone` retired

Date: 2026-04-14
Status: Accepted

### Context

Running aihaus in production (post-M005 + M006 v0.10.0) surfaced a user report: the command surface has two structurally redundant skills that don't add unique capability over their siblings.

- **`/aih-run`** is a scope-router. It scans `.aihaus/plans/` + `.aihaus/milestones/drafts/`, picks a candidate, then dispatches to either feature-inline logic (small scope, `feature/[slug]` branch, `.aihaus/features/[YYMMDD]-[slug]/` artifacts) or milestone-execution logic (large scope, agent team, RUN-MANIFEST lifecycle). The two branches have natural homes in sibling skills: `/aih-feature` (which already owns the `feature/[slug]` branch + artifact contract) and `/aih-milestone` (which already owns milestone drafts).
- **`/aih-plan-to-milestone`** pre-flights milestone creation from a plan (M### auto-proposal, force-split gate, PLAN→CONTEXT mapping, backlink footer). `/aih-milestone` already exposed a DEPRECATED `--plan [slug]` flag that forwarded here — the pattern was half-done.

M005 autonomy work (threshold gate, single-candidate skip, tiered git-dirty, autonomy-protocol annex) stabilized the execution primitives. The remaining friction is surface-level: users hit the redundant skills and lose time reasoning about why they exist.

### Decision

Retire both skills. Consolidate their functionality into the sibling skills whose contracts already fit the absorbed logic:

1. **`/aih-plan-to-milestone` → `/aih-milestone --plan [slug]`.** The `--plan` flag moves from DEPRECATED to first-class, delegating to `pkg/.aihaus/skills/aih-milestone/annexes/promotion.md` for the 5-step promotion logic. `/aih-plan`'s large-scope threshold dispatch retargets from `aih-plan-to-milestone [slug]` to `aih-milestone --plan [slug]`.
2. **`/aih-run` milestone-execution path → `/aih-milestone` via `annexes/execution.md`.** Triggered by `--execute` flag or start-intent ("start"/"go"/"kick off") on a ready draft. Ports the full Phase 3 execution pipeline (agent team, RUN-MANIFEST lifecycle, hook orchestration, completion protocol) verbatim, including the three M005 canonical invariants (tiered git-dirty auto-decide with renamed `aih-milestone pre-run stash` label, single-candidate silent proceed, 3-bullet pre-flight). `completion-protocol.md` and `team-template.md` relocated from `aih-run/` to `aih-milestone/` via `git mv`.
3. **`/aih-run` feature-inline path → `/aih-feature --plan [slug]`.** `/aih-feature` already has the `--plan` flag, `feature/[slug]` branch, and `.aihaus/features/[YYMMDD]-[slug]/` artifact contract. `/aih-plan`'s small-scope threshold dispatch retargets from `aih-run [slug]` to `aih-feature --plan [slug]`.

`invoke-guard.sh` ALLOWLIST updated: removes `aih-run` and `aih-plan-to-milestone`; retains `aih-feature` and `aih-milestone` as valid dispatch targets (alongside `aih-plan`, `aih-quick`, `aih-bugfix`).

`/aih-update` Step 12 migration notice gains a new block gated `prev_version < v0.11.0` announcing the retirements and naming the new homes.

### Rationale

- **Contract fit.** `/aih-run`'s two code paths map cleanly to existing siblings — no new skill needed, no functionality lost. Absorbing into the correct target (not `/aih-quick`, which has a 5-file cap and no branch creation) preserves each skill's semantic identity.
- **M005 invariants survive.** The three canonical phrases from M005 S04/S05/S08 are ported verbatim into `annexes/execution.md`. Smoke-test Check 20 greps for them — any drift fails CI.
- **Hook orchestration integrity.** ADR-004's phase-advance contract depends on exact `--field invoke-push` / `--field invoke-pop` pairings. `annexes/execution.md` documents the hook-call table verbatim; implementer ports word-for-word rather than paraphrasing.
- **Migration channel.** `/aih-update`'s new notice block fires for any v0.10.x → v0.11.0+ upgrade. Users with muscle memory or CI scripts referencing `/aih-run` or `/aih-plan-to-milestone` see the replacement commands on next update.
- **No new convention invented.** Status-line supersession follows the existing ADR-001 → ADR-003 / ADR-002 → ADR-005 pattern. No `## Amendment` subsection added. Prior ADRs amended via single status-line change.
- **Breaking change accepted.** `invoke-guard.sh` rejects markers naming the retired skills (`INVOKE_REJECT allowlist`). Users on v0.10.x who keep typing `/aih-run [slug]` get "skill not found" with migration-notice guidance on next update.

### Options Considered

| # | Option | Why Not |
|---|--------|---------|
| 1 | Keep both skills — refactor prose only | Preserves redundancy; user explicitly asked for removal |
| 2 | Fold `/aih-run` into `/aih-quick` (literal archived Epic E3) | `/aih-quick` has 5-file cap, no branch creation; milestone-execution (130+ lines of hook orchestration) doesn't fit its semantic |
| 3 | Directory-level tombstone stubs for 1 release, hard delete later | Zero prior art (`git log --diff-filter=D` on skills/ is empty); `/aih-update` migration notice delivers same muscle-memory safety with less surface area |
| 4 | Alias `aih-run` → `aih-milestone --execute` | Aliases rot; users never learn new commands; ALLOWLIST + smoke-test still need updates |
| 5 | Ship all remaining archived Epics E/F/G at once | No production pain signal for Haiku validators (G) or slug-less default (F); user explicitly deferred pending real usage evidence |

### Consequences

- **Version bump v0.11.0** (breaking command-surface change; minor since pre-1.0).
- **Skill count 13 → 11.** `pkg/.aihaus/skills/aih-run/` and `pkg/.aihaus/skills/aih-plan-to-milestone/` deleted; `pkg/.aihaus/skills/aih-milestone/annexes/{promotion,execution}.md` created (mandatory annex split per M004 story G pattern).
- **Two new smoke-test checks** (Check 19, Check 20) enforce annex presence and M005 canonical-phrase preservation. Regression-proof against silent drift.
- **COMPAT-MATRIX delta.** `aih-run` row deleted. `aih-milestone` flipped from WORKS-WITH-CAVEAT to NOT-SUPPORTED on Cursor (the skill now runs `Agent` + worktree-isolated subagents, violating Cursor's primitive model). Skill totals: 11 rows = 2 WORKS + 5 WORKS-WITH-CAVEAT + 4 NOT-SUPPORTED.
- **`/aih-update` persistence.** New migration-notice block fires on any upgrade from v0.10.x, preserved through the v0.11.0 → v1.0 window.
- **Hook ALLOWLIST shrinks** from 6 entries to 5 (retains aih-quick, aih-bugfix, aih-feature, aih-plan, aih-milestone).
- **Dangling symlinks on upgrade are benign.** `pkg/scripts/update.sh` bulk-replaces `.aihaus/skills/` per dir (`rm -rf ${dst}; cp -R ${src}`), so stale `aih-run/` and `aih-plan-to-milestone/` symlinks in target repos auto-cleanup on next `/aih-update`.
- **Rollback path: `git revert` the 3 story commits (S01/S02/S03).** No database, no external state, no persistent user-visible artifacts beyond the migration-notice text. Version bump reverses by editing `VERSION` back to `0.10.0` in the revert commit.
- **Self-referential bootstrap paradox documented.** The plan that retires these skills was written via `/aih-plan` and initially suggested promoting via `/aih-plan-to-milestone`. Resolved by running as inline 3-story plan (no milestone draft promotion) — a one-time exception for a self-referential retirement.

### Follow-up work

- Future milestone may revisit archived Epics F (slug-less default auto-detect) and G (Haiku inter-step validators) once production usage produces pain signal for either area.
- `pkg/scripts/install.sh` could be extended to prune retired skill symlinks explicitly (rather than relying on the per-dir bulk replace). Low priority — current behavior is correct, just leaves brief dangling state between script steps.

## ADR-007: Remove `disable-model-invocation` from ADR-003 allowlist skills

Date: 2026-04-14
Status: Accepted — Amends ADR-003 (skill chaining via Skill tool is now directly operational, not merely prose-prescribed)

### Context

ADR-003 designed parent-skill → child-skill dispatch via the Skill
tool. Every `aih-*` SKILL.md shipped with `disable-model-invocation:
true` since v0.1.0. The flag blocks both NL-auto-trigger AND
programmatic Skill-tool invocation (empirically confirmed by user
error: *"Skill aih-milestone cannot be used with Skill tool due to
disable-model-invocation"*). ADR-006 updated the invoke-guard
allowlist to add `aih-milestone` + `aih-feature` but left the flag
in place — breaking the chain whose success ADR-003 assumed.

ADR-006's Decision text (L552-562) and Consequences (L584-593) are
silent on `disable-model-invocation`. We treat that silence as
oversight (no decision text in ADR-006 rejects the flag removal)
and frame this ADR as an amendment, not a supersession. If a future
researcher finds intent-preserving text we missed, escalate to
supersession.

### Decision

Remove `disable-model-invocation: true` from the five ADR-003
allowlist skills: `aih-plan`, `aih-milestone`, `aih-feature`,
`aih-bugfix`, `aih-quick`. Keep the flag on the six non-allowlist
skills: `aih-init`, `aih-help`, `aih-resume`, `aih-brainstorm`,
`aih-update`, `aih-sync-notion`.

The allowlist IS the policy perimeter: skills that can be dispatched
programmatically are the same skills that can be NL-triggered. The
two are coupled on purpose — any skill reachable from parent skills
must be reachable by user prose without platform protection.

**Defense-in-depth:** add `Skill` to `allowed-tools:` on the same 5
skills. Platform auto-injection of the `Skill` tool into skill
contexts is HIGH-confidence-but-unverified per ASSUMPTIONS.md Area
2. Explicit whitelisting protects against version drift: if the
auto-injection assumption proves wrong, the chain no-ops instead of
silently failing.

**Monitoring:** codify "allowlist = NL-policy boundary" as a
smoke-test check — assert the 6 excluded skills retain
`disable-model-invocation: true`. Regression-proof against sloppy
future edits or missing-flag contributions.

### Options Considered

| # | Option | Pros | Cons | Why Not |
|---|--------|------|------|---------|
| 1 | **(Chosen)** Remove flag from 5 allowlist skills + add `Skill` to `allowed-tools:` (defense-in-depth) | Minimum blast radius; allowlist = NL-match policy boundary; no prose edits to shared protocol; explicit whitelisting closes unverified platform-injection gap | Two NL-match surfaces may collide in edge cases | Least disruption; mirrors invoke-guard.sh allowlist; addresses F-3 defense |
| 2 | Remove flag from all 11 skills | Simplest mental model | Opens NL-trigger on init/brainstorm/sync-notion (high blast radius) | Violates ADR-003 §L205–209 exclusion intent |
| 3 | Keep flag; replace Skill-tool dispatch with marker-protocol emission from parent skills | Preserves all flags | Rewrites autonomy-protocol + 4 skills' Phase 4 prose; duplicates invoke-guard logic | High churn; contradicts ADR-003 design |
| 4 | Introduce narrower custom flag (e.g., `disable-natural-language-trigger: true`) | Theoretical perfect gate | Not a documented Claude Code platform field; requires upstream platform change | Out of scope — revisit via follow-up ADR if platform ships such a flag |
| 5 | Remove flag from 5 callees ONLY (no `allowed-tools:` edit) | Cleanest frontmatter diff | Relies on HIGH-confidence-but-unverified "Skill is platform-injected" assumption; fails silently on platform version drift | Defense-in-depth won; Chosen Option 1 absorbs this as a cheaper-together-than-apart edit |

### Consequences

- `/aih-plan` Phase 4 Step 12 threshold gate now executes: `y`/`sim`/
  `go` dispatches `aih-milestone --plan [slug]` or `aih-feature
  --plan [slug]` via Skill tool with no intermediate keyboard step.
  (Silent `aih-feature --plan` chain requires the Phase 1
  short-circuit shipped alongside this ADR in plan
  `260414-enable-skill-chaining` Story 2.)
- The five dispatch-participant skills are now model-invocable.
  Casual NL mentions of "milestone", "bugfix", "plan", "quick fix"
  may surface skill auto-matching; the intent-specific `description:`
  fields mitigate but do not eliminate this.
- The ADR-003 marker-protocol path (invoke-guard → parent dispatches
  via Skill tool) becomes functional end-to-end — was previously
  blocked at the final Skill-tool call.
- COMPAT-MATRIX rows for all five skills gain NL-trigger widening
  notes on Cursor — Cursor honors the flag identically per
  `.aihaus/research/cursor-primitives-verification.md:106-109`.
  `--no-chain` opt-out (autonomy-protocol L103-106) remains the
  Cursor escape when chaining to NOT-SUPPORTED targets.
- **Quantitative rollback trigger:** if ≥3 NL-auto-trigger false
  positives are reported via user issues within 7 days post-merge,
  the fix is reverted and re-architected toward Option 3
  (marker-protocol only). Note: NL-auto-trigger events are not
  currently captured in `.claude/audit/invoke.jsonl`; the rollback
  trigger is therefore conditioned on user reports. A follow-up
  story may add NL-match telemetry if false positives materialize.
- Version bump `0.11.1 → 0.12.0` (minor — widens NL-trigger surface
  on Cursor, amends an Accepted ADR).

### Follow-up work

- Monitor NL-auto-trigger false positives via user reports. If
  casual conversation auto-invokes a skill, tighten `description:`
  copy (low-cost mitigation) or revisit Option 3
  (marker-protocol only).
- Cursor chain degradation: `--no-chain` already exists
  (autonomy-protocol L103-106). Document prominently in COMPAT-
  MATRIX notes (done alongside this ADR).
- NL-match telemetry: if needed, add a hook to log NL-initiated
  skill invocations to `.claude/audit/invoke.jsonl`.
- Re-evaluate awk/sed for `auto-approve-bash.sh` SAFE_PATTERNS
  (excluded in v0.11.1 for security) once `bash-guard.sh` extends
  its regex to catch `awk 'BEGIN{system(...)}'` and `sed -i` on
  system paths.

## ADR-008: Claude Code 3-layer permission surface and aihaus's defense stance

Date: 2026-04-15
Status: Accepted — Supersedes the follow-up work entry at
`pkg/.aihaus/decisions.md:699-702` (ADR-007 Follow-up: "extend
bash-guard.sh to catch `awk 'BEGIN{system(...)}'` and `sed -i`").
That follow-up is now closed at layer 2 by `auto-approve-bash.sh`
DANGEROUS_PATTERNS (see §3 below), not by extending bash-guard's
regex.

### Context

Between milestones M001 and M006, aihaus accumulated tactical fixes
for individual permission prompts on Claude Code. M007's triage
revealed that the prompts were not a single pattern — they were
four distinct classes driven by three independent permission
layers. The reactive fixes had been targeting the wrong layer each
time.

#### The four prompt classes (observed 2026-04-15 on Git Bash / Windows)

1. **Bash allowlist miss on quoted-path + redirect shapes** —
   `dir "C:\Users\..." 2>&1`. `Bash(dir *)` in `permissions.allow`
   failed to prefix-match; escalated to PermissionRequest hook
   which had no `^dir\b` entry in SAFE_PATTERNS.
2. **Bash matcher miss on env-var-prefixed commands** —
   `MANIFEST_PATH=foo.md bash hook.sh`. `^bash\b` anchoring in
   SAFE_PATTERNS never fired because the first token was not
   `bash`.
3. **Bash matcher miss on compound-no-spaces shapes** —
   `ls;rm -rf /`. The compound-splitter at
   `auto-approve-bash.sh:78-82` only split on ` && ` / ` ; ` with
   surrounding spaces.
4. **Filesystem-sandbox directory authorization** —
   `echo x > .aihaus/milestones/drafts/M037-polish-v5/STATUS.md`
   surfaced the Claude Code dialog "always allow access to `X\`
   from this project". Per-session path-authorization cache, fires
   BEFORE PermissionRequest hooks (see RESEARCH.md in milestone
   plan dir, citing [Configure permissions → Working
   directories](https://code.claude.com/docs/en/permissions#working-directories)
   and [Issue
   #7472](https://github.com/anthropics/claude-code/issues/7472)).

#### The broken-gate discovery

Plan-checker review (CHECK.md Finding #1) surfaced a pre-existing
regex bug in `pkg/.aihaus/hooks/bash-guard.sh:15-22`. Seven
`'pattern'` tokens were passed as separate positional arguments to
`grep -qiE`; grep treats args 2..N as FILENAMES. End-to-end test
`echo '{"tool_input":{"command":"rm -rf /"}}' | bash bash-guard.sh`
exited 0 (NOT BLOCKED) — the defense-in-depth for catastrophic
commands was a silent illusion. M007 fixes this (S01) so that
M007's S02 deny-list flip inherits a genuine first-line gate.

### Decision

aihaus addresses the permission surface as three distinct layers
with separate mitigations.

#### Layer 1 — Bash command allowlist

`permissions.allow` in `.claude/settings.local.json`. The template
ships `"Bash(*)"` (at `pkg/.aihaus/templates/settings.local.json:14`)
to widen the allowlist to a universal matcher. Granular entries
(`Bash(dir *)`, `Bash(kubectl *)`, etc.) are explicitly
discouraged: they create whack-a-mole churn every time a new tool
enters the workflow, and user preference memory
(`feedback_bash_permissions.md`) documents the `Bash(*)` policy.

**How M007 addresses it:** `Bash(*)` remains in the template. S02
does NOT touch `permissions.allow`.

#### Layer 2 — PermissionRequest hooks (Bash matcher + write matcher)

When layer-1 does not match directly, Claude Code escalates via
the `PermissionRequest` hook chain. Two hooks participate:

- **`auto-approve-bash.sh`** — matcher `Bash`. Inverted in M007 S02
  from fail-closed SAFE_PATTERNS allow-list (~45 entries) to
  fail-open compact DANGEROUS_PATTERNS deny-list (~24 entries).
  Pre-compiled single `-E` regex (R-NEW-7 latency mitigation).
  Compound-splitter tightened (CHECK.md Finding #5) to split on
  bare `;` / `&&` / `||`, inclusive-OR semantics (any dangerous
  segment → fall through).
- **`auto-approve-writes.sh`** — matcher `Write|Edit`. Unchanged in
  M007. Auto-approves writes inside `$CLAUDE_PROJECT_DIR`; denies
  writes outside.

`bash-guard.sh` (PreToolUse matcher `Bash`) is the CATASTROPHIC-
command layer — fixed in M007 S01 to consolidate its 7 patterns
into a single `-E` argument. Exits 2 on match, blocking the tool
invocation before PermissionRequest is even consulted. This is
belt-and-braces: bash-guard catches the canonical destructive set
(`rm -rf /`, `git push --force` to prod, `mkfs.`, `dd if=`, `drop
table`, `truncate`, `git clean -fd`) via PreToolUse; S02's
DANGEROUS_PATTERNS extends the deny surface to sandbox-escape
shapes (`awk 'BEGIN{system(...)}'`, `sed -i`, `curl | bash`),
supply-chain destructives (`npm/pnpm/yarn/pip/cargo publish`),
privilege escalation, Windows destructive `del /F /S /Q`, and the
fork bomb. **Each catches what the other misses by design.**

**How M007 addresses it:** S01 restores bash-guard; S02 flips
auto-approve-bash.

#### Layer 3 — Filesystem-sandbox directory authorization

A per-session path-authorization cache populated at session start.
When Bash redirects or Write/Edit touch a subdirectory NOT in the
cache, Claude Code fires the dialog "Yes, and always allow access
to `X\` from this project". This layer is **separate** from
`permissions.allow` (per-tool) and PermissionRequest hooks
(per-tool-event): it runs FIRST for filesystem writes to unseen
subdirs, so hooks cannot intercept it.

Per docs ([Configure permissions → Working
directories](https://code.claude.com/docs/en/permissions#working-directories)),
the ONLY documented suppression mechanism is the top-level
`additionalDirectories` array in `settings.local.json`. Paths
inside listed roots "become readable without prompts, and file
editing permissions follow the current permission mode".

**How M007 addresses it:** S03 adds
`"additionalDirectories": [".aihaus", ".claude"]` to the template.
S04 live-tests that dynamic subdirs under `.aihaus/` and `.claude/`
no longer prompt, with a negative control at `/tmp/` to confirm
narrow preauth. `permissions.deny` entries (e.g., `Read(//**/.env)`)
still win — they are evaluated per-tool AFTER the sandbox check.

### Defense-in-depth reasoning (ADR-007 Follow-up supersession)

The follow-up work entry at `pkg/.aihaus/decisions.md:699-702`
suggested extending `bash-guard.sh`'s regex to catch
`awk 'BEGIN{system(...)}'` and `sed -i` on system paths. That
proposal is **superseded** by layer-2's DANGEROUS_PATTERNS
(S02) for these reasons:

1. **One curation surface, not two.** DANGEROUS_PATTERNS already
   enumerates the destructive class. Duplicating the list in
   bash-guard would create two regex sources to keep in sync —
   maintenance tax with no safety gain.
2. **bash-guard is narrowly-scoped by design.** The original
   bash-guard regex covers catastrophic whole-command intent
   (`rm -rf /`, `dd if=...`). Sandbox-escape shapes
   (`awk 'BEGIN{system}'`) are layer-2 concerns because they can
   be embedded in otherwise-legitimate command wrappers; bash-guard's
   anchored patterns are the wrong tool for them.
3. **Defense-in-depth preserved.** bash-guard hard-blocks the
   canonical set at PreToolUse (exit 2, before PermissionRequest
   even fires). DANGEROUS_PATTERNS catches the extended sandbox-
   escape set at PermissionRequest (fall-through to user prompt,
   not auto-block). Each layer operates at the right granularity;
   together they cover both "must never run" and "requires user
   review" classes.

### Options Considered

| # | Option | Pros | Cons | Why Not |
|---|--------|------|------|---------|
| 1 | **(Chosen)** Three layers, three mitigations (S01+S02+S03) | Matches documented Claude Code permission model; each layer independently owned; bisect-ready; defense-in-depth between bash-guard and DANGEROUS_PATTERNS | Four commits to land vs. two for narrower scopes | Directly addresses the 4 observed prompt classes; no layer left unaddressed |
| 2 | Hook-only: fix bash-guard + flip auto-approve-bash; skip `additionalDirectories` | Narrower blast radius; simpler to review | Leaves layer-3 prompt firing on every dynamic subdir under `.aihaus/` — this is the MOST FREQUENT class in user's M037-polish-v5 workflow | Rejected — doesn't solve the user's actual pain |
| 3 | Settings-only: add `additionalDirectories`, keep SAFE_PATTERNS allow-list | Zero hook changes; fewest moving parts | Layer-2 whack-a-mole continues; `dir`, `findstr`, env-var-prefixed, compound-no-spaces all still prompt | Rejected — the user's stated preference (`Bash(*)` + deny-list) is the opposite |
| 4 | Extend bash-guard to catch awk/sed (per ADR-007 Follow-up) + keep SAFE_PATTERNS | Layered deny in bash-guard preserves single-file simplicity | Two regex sources; SAFE_PATTERNS allow-list growth continues; deny-list is the load-bearing policy either way | Rejected — duplicate curation surface |
| 5 | Full shell-parser AST for `auto-approve-bash.sh` compound-splitter | Eliminates quoted-`;` false-positives | Heavy dependency (node/python parser); breaks zero-runtime package invariant | Rejected — chose sed-regex tightening in §4.6 of architecture doc; acceptable limitation documented |

### Cursor compatibility caveat

aihaus is multi-platform since ADR-005 (M006). Cursor's rule
surface at `pkg/.aihaus/rules/aihaus.mdc:46-52` documents
`preToolUse` / `postToolUse` parity but says nothing about
`PermissionRequest` or `additionalDirectories`. Both are
Claude-Code-specific primitives as of 2026-04-15; their behavior
on Cursor is **UNVERIFIED**. Users running aihaus under Cursor may
still encounter prompts for shapes that M007 suppresses on Claude
Code.

This ADR is therefore **Claude-Code-primary**. The four
permission-surface hooks (`bash-guard.sh`, `auto-approve-bash.sh`,
`auto-approve-writes.sh`, `permission-debug.sh`) are candidates
for NOT-SUPPORTED / UNVERIFIED rows in
`pkg/.aihaus/rules/COMPAT-MATRIX.md`. Architect recommends adding
those rows in S05's commit (trivial cost, prevents future
surprise); alternatively, file as M008 item (already captured in
`.aihaus/milestones/M007-260415-autoapprove-windows-cmds/BACKLOG.md`
under "Cursor COMPAT-MATRIX row for S01/S02 hooks").

### Consequences

- **Positive:** all four observed prompt classes closed on Claude
  Code. Triage model documented; next contributor can locate the
  right layer in minutes.
- **Positive:** bash-guard + DANGEROUS_PATTERNS defense-in-depth is
  now intentional and bidirectional. Neither layer is redundant.
- **Negative:** DANGEROUS_PATTERNS is opinionated. Novel
  catastrophic commands not covered by the list would auto-approve
  — this is the inherent trade-off the user has accepted via
  `Bash(*)` preference. Mitigation: quarterly DANGEROUS_PATTERNS
  review (deferred to ADR-009 P2 follow-up).
- **Negative:** Layer 3's `additionalDirectories` preauthorizes ALL
  Read/Write/Edit inside `.aihaus/**` and `.claude/**`.
  `permissions.deny` still gates sensitive-file patterns
  (`Read(//**/.env)` etc.), so the effective risk is low — BUT
  S04 step 7 audits that no `secrets*`, `credentials*`, `*.pem`,
  `.env*` files live inside the newly-preauthorized trees before
  declaring M007 clean.
- **Neutral:** Claude-Code-primary. Cursor surface unchanged.

### Follow-up

- **PowerShell parity.** DANGEROUS_PATTERNS is Git-Bash-shaped.
  `Remove-Item -Recurse -Force`, `Get-ChildItem`, etc. not covered.
  User evidence (HA-9) says Git Bash is primary; file for future
  only.
- **Cursor empirical test.** Run a dogfood Cursor session against
  the post-M007 settings to verify whether `additionalDirectories`
  and `PermissionRequest` intercept behave identically. Captured in
  `.aihaus/milestones/M007-260415-autoapprove-windows-cmds/BACKLOG.md`
  (M008-S04 candidate).
- **COMPAT-MATRIX rows** for the 4 permission-surface hooks per
  §Cursor caveat above. Architect recommends S05 commit;
  implementer may defer.
- **Systemic mitigations catalog** — see ADR-009 (the sibling ADR
  landed in S06). ADR-009 catalogs all known and latent prompt
  classes, RCA hypotheses, and ranked P0/P1/P2 mitigations. It also
  ships the observability keystone `permission-debug.sh` hook.

### Related ADRs

- **ADR-001** (Files are state) — unaffected; M007 changes do not
  alter cross-agent communication primitives.
- **ADR-003** (Agent→Skill invocation marker protocol) — unaffected.
- **ADR-005** (Claude Code + Cursor first-class) — THIS ADR
  inherits the Claude-Code-primary caveat from ADR-005 §4
  authoring convention.
- **ADR-007** (`disable-model-invocation` removal) — Follow-up
  work entry at `pkg/.aihaus/decisions.md:699-702` is **SUPERSEDED**
  by this ADR's §Defense-in-depth reasoning (S02 DANGEROUS_PATTERNS
  closes the awk/sed gap at layer 2).
- **ADR-009** (this decision's systemic-mitigations sibling — lands
  in S06).

## ADR-009: Prompt-prevention systemic mitigations catalog

Date: 2026-04-15
Status: Proposed — P0 and one P1 item (permission-debug.sh) land
in M007 alongside this ADR; remaining P1 + all P2 items deferred to
`M008-permission-observability` (captured in
`.aihaus/milestones/M007-260415-autoapprove-windows-cmds/BACKLOG.md`).
This ADR stays Proposed until M008 lands — at which point a
supplementary ADR may promote to Accepted.

### Context

M007's triage (ADR-008) closed four observed Claude Code prompt
classes. That is necessary but not sufficient. The pattern that
keeps recurring across aihaus milestones is **reactive whack-a-mole**:
a user hits a prompt → a granular allow-list entry is added → the
cycle repeats on the next shape. This pattern failed spectacularly
in M007 — the SAFE_PATTERNS list in `auto-approve-bash.sh` had
grown to ~45 entries without catching `dir`, `findstr`, env-var-
prefixed commands, or compound-no-spaces shapes; meanwhile
`bash-guard.sh` silently returned 0 on `rm -rf /` for ~weeks
because a grep-invocation bug (CHECK.md Finding #1) had never been
end-to-end tested.

The user's directive for M007 ("pesquisa de causa raiz") demands
systemic answers, not more patches. Analysis-brief §8 Q1 and
CONVERSATION.md L22-28 asked:

- Why does this class keep surfacing?
- What observability do we have to catch the NEXT class faster?
- What forward-work would make the problem domain well-understood
  instead of continually rediscovered?

This ADR answers those questions with a catalog, a root-cause
analysis, and a ranked mitigation table.

### Prompt-class catalog

Classes 1-4 are **observed on Git Bash / Windows** during M007.
Classes 5-10 are **latent** — plausible per the 3-layer model
(ADR-008) and Claude Code docs, but not yet empirically triggered.

| # | Class | Fired-by layer | Reproduction | Mitigation |
|---|-------|----------------|--------------|------------|
| 1 | Bash allowlist miss on quoted-path + redirect | L1 → L2 | `dir "C:\foo" 2>&1` | M007 S02 DANGEROUS_PATTERNS deny-list (`dir` auto-approves via fall-through) |
| 2 | Bash matcher miss on env-var-prefixed | L1 → L2 | `MANIFEST_PATH=foo.md bash hook.sh` | M007 S02 (`^bash\b` anchoring no longer required; `bash` segment is safe and auto-approves) |
| 3 | Bash matcher miss on compound-no-spaces | L1 → L2 | `ls;rm -rf /` | M007 S02 compound-splitter tightening (inclusive-OR segment semantics) |
| 4 | Filesystem-sandbox first-time-seen subdir | L3 | `echo x > .aihaus/milestones/drafts/M037-polish-v5/STATUS.md` | M007 S03 `additionalDirectories: [".aihaus", ".claude"]` |
| 5 | Write-tool prompt on paths outside `additionalDirectories` | L3 + L2 | `Write(/tmp/out.md)` | Intended behavior. Document; do not mitigate. `auto-approve-writes.sh` denies writes outside project by design. |
| 6 | Read-tool prompt on sensitive-file patterns | L2 | `Read(/c/Users/X/.env)` | Intended behavior. `permissions.deny` owns this class; ADR-008 §Layer 3 Consequences confirms deny still wins. |
| 7 | MCP tool prompts | L2 (matcher extension) | Hit MCP server with stored-auth needed | Out of M007 scope; investigate when first MCP server ships. File as M008+ |
| 8 | WebFetch / WebSearch domain prompts | L2 | `WebFetch(<new-domain>)` | Intended behavior on first access. Deferred: domain allowlist investigation. |
| 9 | Agent / Task spawn prompts | L2 | Spawn unknown subagent | Intended. `Agent` tool is in `permissions.allow` (template L13), so this is Cursor-surface territory (ADR-005). |
| 10 | Skill invocation prompts (ADR-003 territory) | L2 | Programmatic Skill dispatch | ADR-003 invoke-guard + ADR-007 removal of `disable-model-invocation` closed this for allowlist skills. Cross-reference ADR-007. |

**Note on classes 5-6.** These are listed with the explicit
decision "document, do NOT mitigate" because they represent
intended Claude Code security behavior. Users who want to suppress
them are doing the wrong thing; the prompt IS the feature.

### Root-cause analysis — why this pattern recurs

Five hypotheses, annotated with evidence and mitigation:

#### Hypothesis 1 — Claude Code permission docs are layered but not unified

Each layer's escape hatch is documented separately. RESEARCH.md
L65-66 notes the layer-3 mechanism is buried at "Configure
permissions → Working directories", while PermissionRequest
semantics live in the "Hooks guide → Decision rules" page. No
single doc maps all three layers.

**Mitigation:** ADR-008 IS the unified doc (for aihaus users and
contributors). P2 follow-up: file an upstream issue on
anthropics/claude-code requesting a consolidated permission-surface
page.

#### Hypothesis 2 — No observability into which layer fired a prompt

When a prompt fires, the user sees the UI dialog but has no record
of which hook fired (or no hook fired). Triage starts from scratch
each time: re-read the hook source, re-read the settings, re-read
the docs, guess.

**Mitigation:** `permission-debug.sh` (P1, **IN-SCOPE this
milestone**, S06 Part 2). Writes one JSONL record per
PermissionRequest event to `.aihaus/audit/permission-log.jsonl`
when `AIHAUS_DEBUG_PERMISSIONS=1`. Silent no-op when disabled.

#### Hypothesis 3 — aihaus's historical approach has been reactive allowlist growth

Every prior prompt → SAFE_PATTERNS entry added. Never a step back
to ask "are we using the right model?" Result: ~45 allow entries
that still miss `dir`, `findstr`, env-var-prefixed commands.

**Mitigation:** M007 S02 flips to fail-open deny-list. Future
additions curate ~24 DANGEROUS_PATTERNS (stable) instead of
N hundred SAFE_PATTERNS (growing).

#### Hypothesis 4 — No regression test validates "stock install prompts zero"

There is no automated test that simulates common aihaus flows
(milestone seed, plan write, hook append) and asserts zero
PermissionRequest events. New contributions can accidentally
reintroduce a class without CI catching it.

**Mitigation:** "Stock install prompts zero" regression fixture
(P1, **DEFERRED** to `M008-permission-observability`). Offline mock
— pipe payloads through hooks directly, no live Claude Code
session required. Estimated ~60 LOC shell.

#### Hypothesis 5 — Template drift from documented-sufficient settings

Users on old installs may have granular `Bash(...)` entries that
`update.sh` template-wins-replaces on next update. The migration
hint at `pkg/scripts/lib/merge-settings.sh:139-146` is advisory;
users can miss or ignore it. Settings drift in the other direction
(user installs have fewer safety features than template) is
undetected today.

**Mitigation:** `tools/settings-audit.sh` CLI (P1, **DEFERRED** to
`M008-permission-observability`). Compares installed
`.claude/settings.local.json` against template + "minimum
competent settings" manifest, flags gaps.

### Mitigation catalog — ranked P0 / P1 / P2

Each row annotated with M007 status per PRD §4.3 locked decisions.

| Mitigation | Class addressed | Cost | Impact | Priority | M007 status |
|------------|-----------------|------|--------|----------|-------------|
| Flatten 3-layer doc into ADR | Discoverability (all classes) | XS | M | P0 | **LANDED** in S05 / ADR-008 |
| Permission-debug hook (permission-log) | Diagnostics (classes 1-3, 5-10) | XS | M | P1 | **IN-SCOPE** — S06 Part 2 (this ADR's sibling story) |
| "Stock install prompts zero" regression test | All classes; regression gate | S (~60 LOC) | H | P1 | **DEFERRED** → `M008-permission-observability` |
| `tools/settings-audit.sh` CLI | Drift (existing installs) | S (~80 LOC) | H | P1 | **DEFERRED** → `M008-permission-observability` |
| Prompt-diagnostic CLI (explain which layer would prompt for `<cmd>`) | Triage speed | M | M | P2 | **DEFERRED** — M008+ |
| Upstream issue to anthropics/claude-code for unified permission docs | Ecosystem | S | L-M (depends on Anthropic) | P2 | **DEFERRED** — file GH issue separately, not in milestone |
| Version-compat matrix (which Claude Code version introduces/removes prompts) | Forward-compat | M | M | P2 | **DEFERRED** |
| Deny-list hardening loop (quarterly review of new Claude Code versions + DANGEROUS_PATTERNS) | Forward-compat | S (recurring) | M | P2 | **DEFERRED** — process work, not code |
| PowerShell parity for DANGEROUS_PATTERNS | Windows prompt class (latent) | S | M | P2 | **DEFERRED** — HA-9 evidence says Git Bash is primary |
| Cursor empirical `additionalDirectories` + `PermissionRequest` test | Cursor parity | M | M | P2 | **DEFERRED** → M008+ |

### M007 in-scope lock (per PRD §4.3)

Explicitly:

- **IN-SCOPE:** ADR-008 (P0), ADR-009 (this P0 catalog), and
  `permission-debug.sh` (P1 observability keystone).
- **DEFERRED to `M008-permission-observability`:** "Stock install
  prompts zero" regression test (P1), `tools/settings-audit.sh`
  CLI (P1). Estimated total ~140 LOC.
- **DEFERRED indefinitely (P2):** prompt-diagnostic CLI, upstream
  docs issue, version-compat matrix, deny-list hardening loop,
  PowerShell parity, Cursor empirical test.

Rationale per PRD §4.3: the debug hook alone gives the next
triage a full audit trail — which is what was MISSING for M007
itself (HA-6 scope uncertainty). Regression test + settings-audit
are useful but not load-bearing for the NEXT triage cycle (the
debug hook is). Shipping all three here would bust M007's
120-180 LOC envelope.

### Systemic vs tactical split

- **Tactical (M007):** S01 bash-guard fix, S02 auto-approve-bash
  flip, S03 additionalDirectories, S04 validate + propagate.
  These are **layer-specific** fixes.
- **Documentation keystone (M007):** ADR-008 — the unified 3-layer
  model.
- **Systemic catalog (M007):** ADR-009 — this ADR.
- **Systemic tooling (M007):** `permission-debug.sh` — ships in
  S06 Part 2.
- **Forward-work (M008+):** regression test + settings-audit CLI.
- **Process work (P2):** quarterly DANGEROUS_PATTERNS review,
  upstream docs issue, version-compat matrix.

### Options Considered

| # | Option | Pros | Cons | Why Not |
|---|--------|------|------|---------|
| 1 | **(Chosen)** Land ADR + debug hook now; defer regression test + settings-audit to M008 | Fits M007 envelope; debug hook unblocks the next triage | Takes one more milestone to close P1 | Rational scope-budgeting per PRD §4.3 |
| 2 | Ship nothing systemic — leave as future work | Zero M007 scope increase; all tactical fixes already land | Next triage repeats this milestone's research tax; ADR knowledge decays quickly | Rejected — the user's root-cause directive is explicit |
| 3 | Bundle regression test + settings-audit into M007 too | Closes all P1 in one shot | ~140 extra LOC; stretches milestone past HA-6 scope estimate; delays S01-S04 merge | Rejected — load-bearing fixes come first |
| 4 | Skip debug hook; just write the ADR | Paperwork-only M007 systemic surface | No observability; the hypothesis-2 gap persists | Rejected — debug hook is the load-bearing diagnostic for the NEXT triage |

### Consequences

#### Positive

- **Observability without noise.** `permission-debug.sh` ships
  disabled (`AIHAUS_DEBUG_PERMISSIONS=0` default). Triage-active
  operators enable it, reproduce, tail the log, triage in minutes.
  Silent for everyone else.
- **Forward work is scoped.** `M008-permission-observability` has
  concrete story seeds (BACKLOG.md entries M008-S01, M008-S02,
  M008-S03, M008-S04). Not vague TODOs.
- **The catalog becomes a living artifact.** When the next prompt
  class is reported, the first step is to locate it in classes
  1-10 above (or add class 11). This ADR supplants the "guess and
  grep" triage mode.

#### Negative

- **Proposed status means partial commitment.** If
  `M008-permission-observability` never ships, two P1 items remain
  open indefinitely. Mitigation: M008 is already named and seeded
  in BACKLOG.md; the planning work is done.
- **Observability via log file, not structured telemetry.**
  `.aihaus/audit/permission-log.jsonl` is grep-able but not
  queryable. Good enough for triage, poor for dashboards. Future
  work if telemetry ever becomes a need.
- **The debug hook runs for every PermissionRequest event (even
  when disabled, it pays the fork cost of ~5-10ms).** Hot-path
  impact is negligible on Git Bash; on slower or restricted
  environments, operators can remove the matcher `""` entry from
  their settings. Documented as an opt-out route.

#### Neutral

- Claude-Code-primary, same as ADR-008. Cursor users do not see
  `permission-debug.sh` effects (the hook registers via
  `PermissionRequest` matcher, which Cursor may or may not
  support). Cursor empirical test captured as deferred work.

### Related ADRs

- **ADR-007** (remove `disable-model-invocation`) — its Follow-up
  work entry at `pkg/.aihaus/decisions.md:699-702` is superseded
  by ADR-008 §Defense-in-depth reasoning. This ADR files the
  supersession as a prompt-class inventory observation (class 10).
- **ADR-008** (the 3-layer model this catalog lives atop) — each
  catalog row's "Fired-by layer" column maps to ADR-008's layer
  enumeration.
- **ADR-003** (marker protocol) — class 10 cross-references ADR-003
  for skill-invocation prompts.
- **ADR-005** (Claude Code + Cursor parity) — Cursor caveat in
  Consequences §Neutral inherits ADR-005 §4 authoring convention.

### Follow-up work

- **M008-permission-observability** milestone (seeded): regression
  test fixture + settings-audit CLI. Two stories, estimated S + S,
  total ~140 LOC. File upstream issue in parallel. See
  `.aihaus/milestones/M007-260415-autoapprove-windows-cmds/BACKLOG.md`
  for seed entries.
- **Upstream GH issue** to anthropics/claude-code requesting a
  unified permission-surface docs page. Estimated XS (file issue,
  link ADR-008). Do separately from M008.
- **Quarterly DANGEROUS_PATTERNS review** (process item). Schedule
  a recurring 30-min review: any new Claude Code versions shipped?
  Any new catastrophic command shapes emerged in the ecosystem?
  Any false-positives reported on current patterns?
- **PowerShell parity** for DANGEROUS_PATTERNS. Trigger on first
  user report of a PowerShell-specific prompt. Evidence today
  says Git Bash is primary (HA-9 strong).
- **Cursor empirical test** — run dogfood Cursor session against
  post-M007 settings, document whether `additionalDirectories` and
  `PermissionRequest` behave identically. File findings into
  COMPAT-MATRIX.md.
- **Promote to Accepted** — when `M008-permission-observability`
  lands, write a supplementary ADR (or an amendment to this one)
  recording that the deferred P1 items have shipped and promoting
  this ADR's Status to Accepted.

## ADR-M014-A — DSP wrapper supersedes the multi-layer permission stack

**Status:** Accepted
**Date:** 2026-04-22
**Milestone:** M014
**Supersedes:** ADR-M008-B (`bypassPermissions` default + `/aih-automode` opt-in skill)
**Reconciles:** ADR-008 (M007 3-layer permission surface), ADR-009 (deny-list ordering / prompt-prevention catalog)
**Pattern:** ADR-M010-A reference-and-extend grammar (ADR-M008-C → M010-A → M012-A precedent)

### Context

Between M007 and M013, aihaus accumulated a 7-layer permission stack: `settings.permissionMode` (L1) + `permissions.allow` (L2) + `permissions.deny` (L3) + 3 PermissionRequest hooks `auto-approve-bash` / `auto-approve-writes` / `permission-debug` (L4-L5) + subagent frontmatter `permissionMode: bypassPermissions` (L6) + `/aih-automode` skill toggling between modes (L7). Each layer addressed a real prompt class catalogued in ADR-009; the cumulative surface, however, became disproportionate to the actual user intent — **autonomous execution under user-explicit acknowledgement of risk**.

Claude Code ships `--dangerously-skip-permissions` (DSP) as a CLI flag that suppresses all permission prompts for the spawned process tree. Launching aihaus via a thin `bash .aihaus/auto.sh` wrapper that `exec`s `claude --dangerously-skip-permissions` collapses L1-L5 into a single user gesture (running the wrapper) and renders L7 (`/aih-automode` toggle) redundant — the wrapper IS the toggle. The remaining safety surface (catastrophic-command blocking, project-dir scope enforcement, sensitive-file read denial) migrates to PreToolUse hooks (`bash-guard` / `file-guard` / `read-guard`), which run BEFORE the suppressed PermissionRequest event and are therefore unaffected by DSP.

This ADR supersedes the M008-B decision that `bypassPermissions` stays the default + `auto` is opt-in via `/aih-automode --enable`. The four caveats M008-B raised against `auto` (`Bash(*)` silent drop; subagent frontmatter ignored; plan/provider/version restrictions; 3-strikes pause) all remain true; M014's answer is to leave `auto` mode entirely unused and instead use DSP, which has none of those caveats. The user's directive — "single-user repo, BREAKING accepted, hard pivot" — locks this as a single-shot replacement, not a phased migration.

This ADR also reconciles ADR-008 (M007 3-layer permission model) and ADR-009 (prompt-prevention catalog) by stating: M007's catalog and layered model REMAIN canonical references for understanding Claude Code's permission surface; M014 changes the **aihaus default response** to the surface from "fence the layers with hooks + a toggle skill" to "shortcircuit the prompt path with DSP and rely on PreToolUse for safety." The ADR-009 prompt classes 1-4 are ALL handled correctly by the new architecture: classes 1-3 (Bash matcher misses) are now moot because DSP prevents the prompt entirely; class 4 (filesystem-sandbox first-time-seen subdir) is also moot under DSP.

### Decision

Adopt DSP via wrapper as the autonomous-launch path; delete the 7-layer stack except the PreToolUse safety net and subagent frontmatter (kept as defense-in-depth):

(a) **Wrapper-as-launcher.** `pkg/scripts/launch-aihaus.sh` (Bash) and `pkg/scripts/launch-aihaus.ps1` (PowerShell) `exec` claude with `--dangerously-skip-permissions`. `install.sh` / `install.ps1` create `<target>/.aihaus/auto.sh` and `<target>/.aihaus/auto.ps1` symlinks (junction / copy on Windows fallback) pointing at the wrappers. `bash .aihaus/auto.sh` is the auto path; bare `claude` is the non-auto path. **No skill toggle exists.**

(b) **PermissionRequest layer DELETED.** `pkg/.aihaus/hooks/auto-approve-bash.sh`, `auto-approve-writes.sh`, `permission-debug.sh` removed. `permissions.{defaultMode,allow,deny}` block removed from `pkg/.aihaus/templates/settings.local.json`. The entire `PermissionRequest` hooks block removed from settings.

(c) **`/aih-automode` skill DELETED.** `pkg/.aihaus/skills/aih-automode/` removed in full. `pkg/scripts/lib/restore-automode.sh` deleted. `update.sh` / `update.ps1` lose the restore-automode chain. Skill count 13 → 12. Typing `/aih-automode` returns skill-not-found (M012 hard-rename precedent — no shim).

(d) **PreToolUse safety migrated.** `bash-guard.sh` absorbs the full M007 DANGEROUS_PATTERNS list (~30 patterns) plus its existing 6 catastrophic patterns. `file-guard.sh` gains a `$CLAUDE_PROJECT_DIR` scope check. NEW `read-guard.sh` covers sensitive-file deny patterns (`.env`, `*.pem`, `*.key`, `id_rsa*`, etc.). All three are PreToolUse hooks — they run BEFORE PermissionRequest (which DSP suppresses) and are unaffected by DSP. The Read matcher syntax ships dual-path (LD-4) gated by `READ_GUARD_MODE` constant; S01 selects the active mode.

(e) **Subagent frontmatter RETAINED as defense-in-depth.** `permissionMode: bypassPermissions` stays on `implementer.md` / `frontend-dev.md` / `code-fixer.md` regardless of A17 outcome. M015 may revisit if S01 confirms full DSP propagation.

(f) **Sidecar dropped.** No `.aihaus/.dsp` or `.aihaus/.automode` sidecar persists DSP state — the wrapper IS the persistence (filesystem presence of `auto.sh`). The `.aihaus/.automode` sidecar from M012/ADR-M012-A is orphaned by the skill deletion; `update.sh` no longer reads or writes it.

(g) **Cursor incompatibility.** `install.sh` / `install.ps1` hard-reject `--platform cursor` and `--platform both` (when cursor is included). DSP is Claude-Code-CLI-only; ADR-005 boundary applies. `pkg/.aihaus/rules/COMPAT-MATRIX.md` gains a NOT-SUPPORTED row citing this ADR + ADR-005.

### Rationale

DSP collapses the user-intent surface ("I am running aihaus autonomously and accept the risk") into a single, observable, reversible gesture. The wrapper is a 1-line script — auditable in seconds; the launch path is a single grep across the user's shell history. Compare this to the prior 7-layer state, which required reading `settings.local.json`, three hook bodies, four agent frontmatters, and the `/aih-automode` SKILL.md to fully understand what the user had opted into. The reduction is not just code-line; it is mental-model debt being repaid.

The PreToolUse migration preserves every safety property M007/ADR-008 captured. The DANGEROUS_PATTERNS coverage (catastrophic commands, sandbox-escape shapes, supply-chain destructives, privilege escalation, fork bomb) lands in `bash-guard.sh` byte-equivalent. The `$CLAUDE_PROJECT_DIR` scope check in `file-guard.sh` reproduces the `auto-approve-writes.sh` semantic. The new `read-guard.sh` reproduces the `permissions.deny` Read coverage that M008 added. **Net safety surface is unchanged**; the suppression of L1-L5 is a representational change, not a relaxation. This matches ADR-009's spirit (systemic mitigations over reactive whack-a-mole) by reducing the count of layers a future contributor must reason about.

The BREAKING acceptance is licensed by the user-locked threshold gate (single-user repo, active testing context). M012 set the precedent for hard-rename without shim; M014 extends the same discipline to skill DELETE.

### Consequences

**Positive.**
- Autonomy contract reduced to 1 line: `bash .aihaus/auto.sh`.
- 7 layers → 2 layers (PreToolUse safety net + subagent frontmatter defense-in-depth).
- Skill count 13 → 12 (deletion of `/aih-automode`).
- Hook count: −3 PermissionRequest hooks deleted, +1 PreToolUse `read-guard.sh` added; net −2.
- Faster cold-start (DSP path bypasses classifier-style mode switching from M008-B's `auto`).
- `.aihaus/.automode` sidecar abandoned (orphaned and ignored — `update.sh` no longer reads/writes it; user can delete manually).
- Mental model: one directory grep (`grep -r dangerously-skip pkg/`) tells a contributor the entire autonomy story.

**Negative — BREAKING.**
- `/aih-automode` typing returns skill-not-found (no shim; M012 precedent).
- Users on pre-DSP Claude Code versions see a soft warning at install (LD-3); install completes but autonomous launch may behave differently.
- MCP server tool calls under DSP: future-only concern (no MCP in current aihaus); CLAUDE.md gets a caveat note.
- Cursor users on `--platform cursor` see a hard-reject on install; documented in COMPAT-MATRIX.md.

**Neutral.**
- Subagent frontmatter `bypassPermissions` retained — same byte-state as pre-M014 (defense-in-depth pending A17 outcome). M015 may drop it if A17 confirms full propagation.
- ADR-008 / ADR-009 catalog remains valid as historical documentation of Claude Code's permission surface.
- No data migration needed (no sidecar carries forward).

### Migration

Single-shot during M014; no phased rollout. Order:

1. **S01 GATING** — live A17 + A31 test in scratch repo; outcome selects `READ_GUARD_MODE` and informs whether subagent frontmatter is strictly necessary (kept either way per (e)).
2. **S02** — install full PreToolUse safety net (bash-guard expansion + file-guard scope + NEW read-guard); register read-guard NOT YET in settings (S04 does it).
3. **S03** — ship `launch-aihaus.{sh,ps1}` wrapper; DELETE `/aih-automode` skill, `restore-automode.sh`, restore-automode invocation in update scripts; K-009 grep sweep BEFORE delete.
4. **S04** — strip permissions block from settings.local.json; DELETE 3 PermissionRequest hooks; register read-guard in settings PreToolUse. **Hard-ordering: requires S02 green** (safety-regression window mitigation).
5. **S05** — installer changes (symlink wrapper, hard-reject `--platform cursor`, soft-warn on DSP version mismatch); dogfood `bash install.sh --target . --update`.
6. **S10** — append THIS ADR + ADR-M014-B to `pkg/.aihaus/decisions.md`; rewrite CLAUDE.md "Calibration and Permission Modes" section; rewrite README.md quickstart to `bash install.sh && bash .aihaus/auto.sh`.
7. **Rollback recipe** (PLAN.md): bare `claude` (no wrapper) restores pre-DSP launch behavior; `git revert <S04 commit-range>` restores the permission template; `bash install.sh --update` re-applies.

Single-user repo: no migration assistant needed; no SAFE_PATTERNS user-customization carry-over.

### Related

- **ADR-M008-B** (superseded): `bypassPermissions` default + `/aih-automode` opt-in. Both halves of that contract are obsolete under M014.
- **ADR-008** (reconciled — kept as historical reference): M007 3-layer permission model. M014 does not remove the document; it changes the default response from "fence each layer with hooks" to "shortcircuit prompts with DSP and rely on PreToolUse for safety."
- **ADR-009** (reconciled — kept as historical reference): prompt-prevention catalog. Classes 1-4 are now moot under DSP; class 5-10 remain documented behavior of Claude Code.
- **ADR-M014-B** (sibling): Resume substrate. Cross-link: M014 ships both ADRs in one commit (S10).
- **ADR-005** (reconciled): Cursor multi-platform support; install.sh hard-rejects `--platform cursor` for DSP per (g).
- **K-009** (driven): exhaustive grep target list per LD-7 enforces stale-reference cleanup before delete.

## ADR-M014-B — Resume substrate: schema v3 Checkpoints + agent classification + worktree reconciliation

**Status:** Accepted
**Date:** 2026-04-22
**Milestone:** M014
**Extends:** ADR-004 (RUN-MANIFEST.md schema v2 + single-writer discipline) — additive v2→v3 evolution
**Pattern:** ADR-M010-A reference-and-extend grammar; K-008 additive-schema-versioning

### Context

`/aih-resume` (`pkg/.aihaus/skills/aih-resume/SKILL.md:50-66`) operated at story-level granularity and used file-existence heuristics to infer past phase. Five concrete failure modes (analysis-brief §1.2):

1. **Sub-story crash → re-spawn from zero.** Implementer wrote 3 of 7 files of a story; resume re-spawned implementer from file 1; collisions or silent overwrites on the partially-completed work.
2. **Phase inference fragile.** "PRD exists → past PM" — partial PRD from a crashed architect breaks the heuristic; resume skips the architect and dispatches the next phase against an incomplete artifact.
3. **Worktrees opaque.** K-002: implementer worktrees branch off `main`. Resume did not run `git worktree list`, did not know about orphan branches, uncommitted work, or unmerged commits.
4. **TaskCreate/TaskList state evaporates cross-session.** Manifest and TaskList desynchronise; cross-check fails silently.
5. **Stateless re-spawn ≠ continuation.** Each agent is stateless by design; "resume" meant "re-spawn at same phase with same input", not "continue from byte where we stopped."

ADR-004 already locked RUN-MANIFEST.md as the single source of truth for milestone state via schema v2. The defect is not in ADR-004's discipline — it is in the granularity. Schema v2 records `Metadata.phase` and `## Story Records` (one row per story); it has no sub-story checkpoint mechanism. Resume cannot do better than story-level because there is no finer-grained ground truth to read.

This ADR introduces sub-story checkpoints as an **additive** schema v3 evolution — preserving every v2 invariant (single-writer discipline, append-only Story Records, manifest-migrate idempotency) and layering a new optional `## Checkpoints` section on top. Combined with two new agent frontmatter fields (`resumable` + `checkpoint_granularity`) and a new `worktree-reconcile.sh` hook, the substrate enables `/aih-resume` to read authoritative state and dispatch stateful agents with a `--resume-from <substep>` continuation contract.

### Decision

Adopt the resume substrate as four orthogonal but interlocking components:

(a) **Schema v3 = v2 + optional `## Checkpoints` section.** 7-column table; column types and enums per LD-1:

```
| ts (ISO-8601 UTC) | story (S\d{2}) | agent (slug) | substep (<kind>:<id>) | event (enter|exit|resumed) | result (OK|ERR|SKIP) | sha (7-char) |
```

`## Checkpoints` is optional — a v2 manifest with no Checkpoints section is a valid v3 manifest after `manifest-migrate.sh` v2→v3 (which appends only the heading + column header + separator if absent). v2 ADR-004 single-writer discipline EXTENDS to the new section: `manifest-append.sh` is the sole writer; two new modes `--checkpoint-enter <story> <agent> <substep>` and `--checkpoint-exit <story> <agent> <substep> <result> [<sha>]` append rows. Rate-limit guard: drop duplicate `enter` events for identical `(story, agent, substep)` within 1 second (mitigates emission spam). **Missing-section rule (F-09):** if the `## Checkpoints` section is missing when `--checkpoint-enter` / `--checkpoint-exit` fires, the hook MUST either (i) auto-create the section under a file-lock (`flock` on the manifest path) to preserve the single-writer invariant, OR (ii) fail-closed with stderr message `run manifest-migrate.sh first` and non-zero exit. Implementer picks (i) by default (defense-in-depth); (ii) is the explicit override if the file-lock primitive is unavailable.

(b) **Agent frontmatter classification.** Two new YAML frontmatter fields on every agent in `pkg/.aihaus/agents/*.md`:

```yaml
resumable: true | false
checkpoint_granularity: story | file | step
```

Default classification per LD-6:
- **Idempotent** `(true, story)` — ~42 agents (analyst, architect, planner, plan-checker, contrarian, reviewer, code-reviewer, security-auditor, integration-checker, verifier, eval-auditor, ui-checker, ui-auditor, doc-verifier, debugger, project-analyst, codebase-mapper, intel-updater, pattern-mapper, assumptions-analyzer, framework-selector, advisor-researcher, ai-researcher, brainstorm-synthesizer, context-curator, knowledge-curator, learning-advisor, doc-writer, domain-researcher, executor, eval-planner, notion-sync, nyquist-auditor, phase-researcher, project-researcher, research-synthesizer, roadmapper, test-writer, ui-researcher, user-profiler, ux-designer, product-manager). Re-spawn is safe; fresh run produces equivalent output; partial work loss acceptable.
- **Stateful** `(false, file)` — `implementer`, `frontend-dev`, `code-fixer` (3). Atomic per-file writes; re-spawn risks collision or silent overwrite.
- **Multi-cycle** `(false, step)` — `debug-session-manager` (1). Loop-driven; per-step state needs explicit recovery.

`tools/smoke-test.sh` Check 6 (frontmatter validation) is extended to require both new fields and validate the enums (`resumable` in `{true,false}`; `checkpoint_granularity` in `{story,file,step}`).

(c) **Worktree reconciliation as a dedicated hook.** NEW `pkg/.aihaus/hooks/worktree-reconcile.sh` iterates `git worktree list --porcelain` and classifies each non-main worktree:
- **Category A** (clean + HEAD reachable from main): silently prune via `git worktree remove`.
- **Category B** (clean + commits not on main): emit a fenced-block cherry-pick recipe to stdout; **never auto-execute** — user is the executor.
- **Category C** (dirty — `git status --porcelain` non-empty): preserve untouched; emit 1-line summary `[CATEGORY C] <path> — <N> uncommitted file(s); preserved.`

Ambiguity falls through to category C (safe default). Hook is safe to invoke standalone (`bash worktree-reconcile.sh`) and via `/aih-resume` dispatch.

(d) **`/aih-resume` rewrite.** Phase 1 reads checkpoints authoritatively (no more file-existence inference): glob RUN-MANIFEST → migrate v1/v2 → v3 → read `## Checkpoints` last row → invoke `worktree-reconcile.sh` → cross-check checkpoint vs worktree state. Phase 2 branches on `agent.frontmatter.resumable`: `true` → re-spawn agent normally; `false` → dispatch with `--resume-from <substep>` (free-text echo per LD-2). After dispatch, append `event=resumed` checkpoint via `manifest-append.sh`. Stateful agent SKILL.md / agent.md prose includes a top-of-file "Resume handling" section: "If `--resume-from` is provided, read RUN-MANIFEST `## Checkpoints` for the matching substep, skip all prior substeps, continue from the next un-completed substep." Legacy logic preserved as a `<!-- LEGACY MODE — REMOVE in M015 if no usage reported -->` comment block at the bottom of SKILL.md (or `annexes/legacy-mode.md` if the 200-line cap is hit per M004 annex pattern); reachable only via `--legacy-mode` flag (LD-10).

### Rationale

Five failure modes (Context §1-5) all have one root cause: **resume reads a coarser ground truth than the work it is resuming**. Story-level state cannot answer "where in story S03 did the implementer stop?". The fix is to record finer-grained ground truth + give resume a structured way to consume it; everything else (worktree reconciliation, agent classification, `--resume-from` contract) flows from that primitive.

Schema v3 is **additive** — the rationale is identical to K-008 (additive schema versioning) and ADR-M010-A's schema-bump approach (v1 readers degrade gracefully; v2 readers parse both). A v2 manifest with no Checkpoints section migrates to v3 by gaining a header-only Checkpoints table; behavior is byte-identical to v2 until a checkpoint is appended. ADR-004's single-writer discipline EXTENDS naturally — `manifest-append.sh` was already the sole writer of `## Story Records`; gaining `--checkpoint-enter` / `--checkpoint-exit` modes preserves the invariant.

Agent classification via frontmatter (LD-6) chooses **declarative-per-agent** over **central-registry-of-stateful-agents**. This matches the existing `tools:` and `permissionMode:` patterns — those are also per-agent declarations consumed by orchestration.

Worktree reconciliation as a separate hook keeps the classification logic testable in isolation and lets future skills reuse the hook. Safe-default-to-C prevents a misclassified dirty worktree from being silently destroyed.

The `--resume-from <substep>` contract is **free-text echo** of the manifest substep column (LD-2). The substep ID is whatever the agent itself wrote when entering the sub-step; round-trip equality is the simplest possible parse contract.

Finally, the `--legacy-mode` retention (LD-10) buys cheap insurance. The legacy code path is preserved as comment block (zero-runtime-cost); a future M015 may delete if dogfood proves the new path stable.

### Consequences

**Positive.**
- Sub-story resume is now possible. The CORE deliverable of M014 (Bloco 2) becomes a measurable acceptance criterion (S10 dogfood).
- ADR-004 single-writer discipline extends cleanly; no new write-path discipline introduced.
- Schema v3 is forward+backward compatible (additive).
- Worktree opacity (failure mode 3) becomes explicit: every worktree is classified and surfaced. K-002 worktree-branched-off-main pattern gets a first-class reconciliation primitive.
- Agent frontmatter classification is auditable (smoke-test Check 6) and self-documenting.
- `/aih-resume` no longer relies on file-existence heuristics — every state transition is read from manifest or computed from git, never inferred.
- Legacy-mode escape buys safe rollout.

**Negative.**
- 46 agents gain 2 new frontmatter fields each (mass mechanical edit; S07). Risk: 1+ agent missed → Check 6 fails → revert + re-edit.
- Stateful agents (implementer, frontend-dev, code-fixer, debug-session-manager) gain a new "Resume handling" prose section.
- `## Checkpoints` rows are append-only and grow without bound. Acceptable per analyst (resume reads the LAST row only).
- `manifest-append.sh` gains 2 new modes — surface area grows. Rate-limit guard prevents emission spam.
- Checkpoint emission requires agent prose discipline. Mitigation: `_shared/checkpoint-protocol.md` is binding; S10 dogfood is the gate.

**Neutral.**
- ADR-004 schema v2 contract preserved verbatim — v3 adds a new section; nothing in v2 is removed or renamed.
- `/aih-resume --legacy-mode` flag retains the old behavior indefinitely (LD-10); zero-runtime-cost.
- `worktree-reconcile.sh` is invoked by `/aih-resume` but standalone-safe; future skills may reuse.

### Migration

Single-shot during M014 Bloco 2 (S06-S10); no phased rollout for the substrate. Order:

1. **S06 (CORE-1)** — schema v3 doc + `manifest-migrate.sh` v2→v3 (additive, idempotent) + `manifest-append.sh` `--checkpoint-{enter,exit}` modes + NEW `_shared/checkpoint-protocol.md` binding annex + smoke-test Check 24 (v2→v3 migration fixture).
2. **S07 (CORE-2)** — 46 agents gain `resumable` + `checkpoint_granularity` frontmatter per LD-6; smoke-test Check 6 extended to enforce both new fields with enum validation.
3. **S08 (CORE-3)** — NEW `pkg/.aihaus/hooks/worktree-reconcile.sh` with A/B/C classification; smoke-test fixture covering all 3 categories. Hook is standalone-safe.
4. **S09 (CORE-4)** — REWRITE `aih-resume/SKILL.md` Phase 1+2; add "Resume handling" prose to implementer / frontend-dev / code-fixer / debug-session-manager; preserve legacy as commented block (or `annexes/legacy-mode.md` if 200-line cap hit); smoke-test Check 25 (crash-mid-implementer + resume fixture).
5. **S10** — append THIS ADR + ADR-M014-A to `pkg/.aihaus/decisions.md`; new CLAUDE.md "Resume Substrate" section; dogfood resume on a real follow-up milestone (acceptance gate).

**Existing manifests:** `manifest-migrate.sh` is idempotent + additive — running it on a v2 manifest produces a v3 manifest with header-only `## Checkpoints` section; running again is a no-op.

**Rollback:** `/aih-resume --legacy-mode` flag bypasses the new substrate and runs the file-existence heuristic preserved in the comment block (LD-10). For full rollback, `git revert <S06 commit>` + `git revert <S09 commit>` restores both the schema and the skill.

### Related

- **ADR-004** (extended, not superseded): RUN-MANIFEST.md schema v2 + single-writer discipline. Schema v2 → v3 is additive; manifest-append.sh remains the sole writer; new modes preserve the invariant. ADR-004 Decision body is unchanged.
- **ADR-M014-A** (sibling): DSP wrapper supersedes permission stack. Cross-link: M014 ships both ADRs in one commit (S10); the substrate (this ADR) is the user-facing payoff promised in CONTEXT.md "Problem 2."
- **ADR-M011-A / B** (analog substrate): state-driven gates + statusLine reads RUN-MANIFEST as ground truth. M014's resume substrate extends the same "manifest-as-ground-truth" architecture to sub-story granularity.
- **K-002** (worktree-branched-off-main): formalized into category-A/B/C reconciliation per (c).
- **K-008** (additive schema versioning): the v2→v3 evolution follows the K-008 reader-accepts-both / writer-emits-latest discipline.
- **PRD LD-1, LD-2, LD-6, LD-9, LD-10** (locked decisions): this ADR codifies all five into the substrate contract.

## ADR-M015-A: Drop Cursor support -- aihaus is Claude Code-only

**Status:** Accepted
**Date:** 2026-04-22
**Milestone:** M015
**Supersedes:** ADR-002 (Cursor compat-only, 2026-04-14), ADR-005 (Cursor first-class install, 2026-04-14)

### Context

- M014/ADR-M014-A made `claude --dangerously-skip-permissions` (DSP) launch via `bash .aihaus/auto.sh` the sole autonomy path.
- Cursor has no equivalent CLI flag; M014 already hard-rejected `--platform cursor` for DSP-related installs.
- Maintenance cost of cross-platform stubs (`rules/`, `.cursor-plugin/`, `--platform` parser, `COMPAT-MATRIX`, multi-platform-authoring section in `CLAUDE.md`) exceeded value for the current single-user / abandoned-upstream context.
- ADR-M014-B's `--legacy-mode` note flagged M015 as the removal gate; this ADR confirms the decision.

### Decision

- Delete `pkg/.aihaus/rules/` and `pkg/.aihaus/.cursor-plugin/` directories entirely.
- Remove `--platform` flag from `install.sh`, `install.ps1`, `uninstall.sh`, `uninstall.ps1`.
- Remove Cursor cleanup block from `uninstall.sh` (the `~/.cursor/plugins/local/aihaus` symlink removal).
- Remove `.aihaus/.install-platform` sidecar write from installers (sidecar files that persist on existing installs are no longer read or written; harmless if present).
- Rewrite/strip Cursor mentions in `CLAUDE.md`, `README.md`, `tools/smoke-test.sh`, brainstorm escalation annex, `manifest-append.sh` benign comment.
- Supersede ADR-002 + ADR-005 explicitly.

### Consequences

- **BREAKING.** Users with `.aihaus/.install-platform` other than `claude` no longer have any Cursor install path.
- The historical CHANGELOG entries for v0.8.0 (M002 Cursor coexistence) and v0.10.0 (M006 Cursor native install) remain as factual history -- not retroactively edited.
- `COMPAT-MATRIX.md` is deleted (was the per-skill/per-agent Cursor compatibility table; orphaned without Cursor target).
- `tools/smoke-test.sh` `check_cursor_plugin` (was Check 16, M002) is removed entirely; remaining checks renumber automatically since `_start_check` auto-increments at runtime — no explicit renumbering needed.
- Check 36 (learning-advisor) drops its COMPAT-MATRIX sub-assertion; the agent/hook/template checks remain.

### References

- Supersedes ADR-002 (M002, 2026-04-14)
- Supersedes ADR-005 (M006, 2026-04-14)
- Reconciles ADR-M014-A (M014/S05 already partially removed Cursor via DSP hard-reject)
- ADR-M014-B LD-10 note: "REMOVE legacy-mode in M015 if no usage reported" -- this milestone is the removal gate

---

## ADR-M017-A — Merge-back as script, not prose (C3)

**Status:** Accepted
**Date:** 2026-04-24
**Milestone:** M017
**Extends:** ADR-M014-B §F.(c) (worktree reconciliation) — extended with dedicated merge-back writer; ADR-004 single-writer discipline (checkpoint wrapping reused)
**Pattern:** ADR-M014-B reference-and-extend grammar; K-004 mapfile/awk Owned-Files parsing

### Context

- Pre-M017, merge-back from `isolation: worktree` agents to `main` was **100% operator narrative** — `pkg/.aihaus/skills/aih-milestone/team-template.md:38-64` and `pkg/.aihaus/skills/aih-milestone/annexes/execution.md:337-338` described per-file `cp` + explicit `git add` in prose; no code enforced it.
- **2026-04-12 incident recurrence:** during a prior milestone, an implementer ran `git add frontend/` from a worktree also holding another story's WIP. The sweep crossed story boundaries. Feedback memory `worktree_merge_back_race.md` recorded the lesson but not a structural fix.
- K-002 documented the root cause (worktrees branch off `main`) but left cross-story file-set detection to operator eyeballing.
- ADR-M014-B §F.(c) classified A/B/C at resume time but did not prescribe the merge-back path itself.

### Decision

(a) **`pkg/.aihaus/hooks/merge-back.sh` (S03, `fb7a36a`) is the sole merge-back path.** Invocation: `bash .aihaus/hooks/merge-back.sh --story S<NN> --manifest <path>`. Reads Owned Files via `mapfile -t` + awk; per-file `cp`; explicit `git add <file>` loop; diffs `git diff --cached --name-only` against expected before committing.

(b) **Stable refusal grammar on exit 3:** `MERGE_BACK_REFUSED story=S<NN> reason=<unexpected-files|missing-files|cross-story-spill> expected=<...> actual=<...> worktree=<path>`. Machine-stable. Additional exit codes: 0 ok, 2 bad args, 6 lock-timeout, 12 worktree-dir-missing.

(c) **Checkpoint wrapping extends ADR-004 single-writer.** Every invocation bracketed by `manifest-append.sh --checkpoint-enter/exit merge-back:S<NN>`. `manifest-append.sh` remains sole writer of `## Checkpoints`.

(d) **Companion defense: `git-add-guard.sh` (S04, `657cbe1`)** — registered AFTER `bash-guard.sh`. Blocks `git add -A`, `--all`, `.`, `<dir>/`, `-u`, `-p`, `git commit -am`, `git commit -a` on `milestone/*`/`feature/*` branches. Opt-out `AIHAUS_GIT_ADD_GUARD=0`.

(e) **Recovery paths in `pkg/.aihaus/skills/aih-milestone/annexes/merge-back-recovery.md`:** `--drop <file>`, `--abort`, MANIFEST edit + retry.

### Consequences

**Positive.** 2026-04-12 incident class structurally prevented. Single writer of file-set contract. Checkpoint wrapping gives `/aih-resume` visibility.

**Negative.** 2 new hooks + 1 annex. `git add -p` blocked on milestone/feature branches (per-command opt-out). Shell-alias bypass not solved.

**Neutral.** ADR-004 preserved; ADR-M014-B classification unchanged.

### Rollback

Env bypass `AIHAUS_MERGE_BACK_GUARD=0` + `AIHAUS_GIT_ADD_GUARD=0` restores pre-M017 prose. Full revert: `git revert fb7a36a 657cbe1`.

### Migration

Single-shot within M017. Existing worktrees handled by ADR-M017-B §L4 reap.

### Related

ADR-004 (extended); ADR-M014-B (extended); ADR-M017-B (sibling); ADR-M017-C (sibling); K-002 (updated); K-004; S01 RESEARCH-harness.md.

---

## ADR-M017-B — Lock-leak prevention stack (C1)

**Status:** Accepted
**Date:** 2026-04-24
**Milestone:** M017
**Extends:** ADR-M011-A (`paused` precedent → `aborted`); ADR-M014-B §F.(c) (reconcile classification reused)
**Pattern:** 4-layer defense-in-depth; per-layer env bypass

### Context

- 11 stranded `locked` worktrees observed 2026-04-24 at M010/M011/M012 HEADs; `worktree-reconcile.sh:117-120` skipped `locked` → orphans accumulated invisibly.
- User direction 2026-04-24 "não da pra tratar como exceção" — reframes reap-only strategy as the bug.
- S01 P1 VERIFIED-yes: external `git worktree unlock` works. Harness writes `.git/worktrees/<name>/locked` at spawn and never clears it on non-graceful exit.
- ADR-M011-A precedent: `paused` first-class state; `aborted` analogous but terminal.

### Decision

(a) **L1 SubagentStop** via `worktree-release.sh` (S02a, `99ae69f`). Parses stdin JSON, `classify_only` from reconcile.sh, acts A/B/C, releases lock LAST. Exit 0 always. Identity-agnostic across 5 worktree-isolated agents.

(b) **L2 SessionEnd** via `worktree-release-all.sh` (S02b, `3eec338`). Reads `.claude/worktrees/.session-<pid>.owned` sentinel, reuses S02a routine. Idempotent.

(c) **L3 explicit `/aih-milestone --abort`** (S02c, `6a3bec2`) via `phase-advance.sh --to aborted --reason`. `aborted` new terminal; `aborted → complete` REJECTED; `aborted → paused` sole resurrection via `/aih-resume`.

(d) **L4 catastrophic-crash fallback** via `worktree-reap.sh` (S02d, `a654e95`). Two-phase UX: Phase A scan-default; Phase B `--confirm-reap` prunes mtime ≥ 14d. Windows path-lock fallthrough inherits reconcile.sh:146-147.

(e) **Session-sentinel write-wiring** in 4 skill entries (S02d).

### Consequences

**Positive.** 11-orphan backlog reap-able. Future steady-state ≈ 0. Defense-in-depth. L1/L2 silent success path.

**Negative.** 4 new hooks + state-machine addition. L4 reap destructive (safeguarded). Sentinels don't self-clean on crashed sessions.

**Neutral.** ADR-M011-A unchanged. ADR-M014-B §F.(c) unchanged (L1/L2 source `classify_only` via K-001/K-003 idiom).

### Rollback

Per-layer env: `AIHAUS_RELEASE_L1=0`, `_L2=0`, `AIHAUS_L3_DISABLED=1`, `AIHAUS_REAP_DISABLED=1`. Full revert: `git revert 99ae69f 3eec338 6a3bec2 a654e95`.

### Migration

First install post-M017: reap scan detects pre-existing orphans; user runs `--confirm-reap` once. Steady-state ≈ 0 thereafter.

### Related

ADR-M011-A (extended); ADR-M014-B (extended); ADR-M017-A (sibling); ADR-M017-C (sibling); K-001/K-003 (source-with-flag-suspension); K-002 (extended); S01 P1.

---

## ADR-M017-C — Stale-base + same-file cross-story rule (C2 + D2 + D3 non-viable)

**Status:** Accepted
**Date:** 2026-04-24
**Milestone:** M017
**Extends:** K-002 promoted to PERMANENT state
**Pattern:** plan-time BLOCKER; D3-viability heuristic as feature-flag

### Context

- K-002 documents worktrees-off-main race. Pre-M017 "known hazard" — operator eyeballing.
- S01 three probes: P1 VERIFIED-yes; **P2 VERIFIED-no** (issue #27749 CLOSED / not-planned); **P3 VERIFIED-no** (issue #50850 CLOSED). NON-UNANIMOUS → S05 Path B.
- M017 PLAN declared two cross-story-file overlaps BEFORE S01 proved D3 non-viable. Grandfather clause required.

### Decision

(a) **D3 Path B (S05):** no `worktree-branch-from.sh`. K-002 PERMANENT until Anthropic ships primitive.

(b) **D2 same-file rule (S06, `5b9442e`)** via plan-checker fan-out at `/aih-milestone` E3. Overlap → BLOCKER unless `cross-story-file:` declaration AND D3 viable. Grammar in `pkg/.aihaus/skills/aih-milestone/annexes/same-file-rule.md` for documentary purposes.

(c) **D3 viability heuristic (file-existence gate):** hatch ACCEPTED iff `pkg/.aihaus/hooks/worktree-branch-from.sh` exists AND K-002 state reads "structurally handled". Under Path B neither holds → **hatch DISABLED**. File-existence gate means future re-enablement needs only shipping hook + flipping K-002; no plan-checker edit.

(d) **Grandfather clause (M017 self-inclusion):** M017's two overlaps (`settings.local.json` S02a→S02b→S04; `aih-milestone/SKILL.md` S02c→S02d) are documented historical artifacts. S08 meta-test asserts BLOCKER as correct-but-not-actionable. Post-M017 milestones MUST merge overlapping stories.

(e) **Re-enablement path (deferred):** if Claude Code issue #27749 OR #50850 is re-opened and resolved, a follow-up milestone ships `worktree-branch-from.sh`, flips K-002 state, and heuristic re-enables hatch globally.

### Consequences

**Positive.** Cross-story conflicts caught at plan time. K-002 gets concrete state + re-enablement path. File-existence heuristic single-check. Grandfather prevents M017 meta-test failure.

**Negative.** Multi-story plans needing cross-story refs must merge stories. K-002 PERMANENT admits aihaus can't fix at hook layer.

**Neutral.** S05 Path B pure documentation. Grammar preserved for future. M017 dogfood grandfathered.

### Rollback

Env bypass `AIHAUS_CROSS_STORY_RULE_DISABLED=1`. Full revert: `git revert 5b9442e` + remove this ADR. Re-enablement is forward path conditional on Anthropic primitive.

### Migration

Existing drafts/plans unaffected. M017 two overlaps grandfathered. Fresh installs: hook absent → hatch disabled.

### Related

K-002 (updated to PERMANENT); ADR-M014-B (extended — unaddressable state marker); ADR-M017-A (sibling); ADR-M017-B (sibling); S01 RESEARCH-harness.md; S05-FALLBACK-NOTE.md; Claude Code issues #27749, #50850.


---

## ADR-260427-A: session-end.sh follows M018/S5 safe-auto-pop pattern

**Date:** 2026-04-27
**Status:** Accepted
**Milestone/feature:** feature/auto-interference-audit (260427)

### Context

Audit dated 2026-04-27 reported that uncommitted edits silently disappeared between sessions. Root cause: `pkg/.aihaus/hooks/session-end.sh` (M-pre-M018 implementation) ran `git stash push --include-untracked` immediately followed by `git stash pop 2>/dev/null || true` — the trailing `|| true` swallowed pop failures, stranding work in the stash without surfacing it.

M018/S5 already solved the analogous problem at the milestone surface (`pkg/.aihaus/skills/aih-milestone/completion-protocol.md:6-37` §Stash Recovery): stash with a slug-validated label, attempt pop only on a clean tree, surface `STASH PENDING <SHA>` for manual resolve when dirty. SHA-stable reference (not index name) is invariant across concurrent stash mutations.

The session-end surface was the only stash code-site not aligned with this pattern.

### Decision

`session-end.sh` adopts the M018/S5 safe-auto-pop contract:

1. Stash with label `aihaus session-end ${CLAUDE_SESSION_ID:-<ts>}` and `--include-untracked`.
2. Resolve stash SHA via `git rev-parse stash@{0}` (not the ref name).
3. Cross-validate the stash message contains the session label before pop.
4. Auto-pop **only** when `git status --porcelain` is empty AND label-cross-validates.
5. On dirty tree, label-mismatch, or pop-failure: append a JSON line to `.claude/audit/session-end-stash-pending.jsonl` with `{ts, session_id, branch, stash_sha, reason, label}`. `session-start.sh` surfaces this to the user via the `additionalContext` JSON payload.
6. Session-start sweep drops `aihaus session-end *` stashes older than 14 days; caps total at 50.

### Consequences

**Positive.** No silent strand. Symmetry with milestone surface. ADR-M009-A sidecars (`.aihaus/.effort`) protected by auto-pop on clean tree; visible on dirty tree.

**Negative.** Stashes can accumulate up to 50 if user never reviews them. Mitigated by the 14-day reaper.

**Neutral.** Behavior identical to milestone surface — operators learn one pattern, applied twice.

### Rollback

`git revert` the S1 commit. No data loss possible — the new behavior is strictly more conservative than the old.

### Related

M018/S5 (`completion-protocol.md` §Stash Recovery — sibling implementation).
ADR-M009-A (calibration sidecar ownership — protected by this contract).

---

## ADR-260427-B: branch-switch detection is soft-warn, not hard-block

**Date:** 2026-04-27
**Status:** Accepted
**Milestone/feature:** feature/auto-interference-audit (260427)

### Context

Same audit reported HEAD silently switching to a parallel branch mid-task. Hypothesized cause: a second `claude --dangerously-skip-permissions` process running on the same working tree, or Claude's own confused recovery git ops. No aihaus mutex defends `git checkout <branch>` while a feature/bugfix/milestone RUN-MANIFEST shows `status: running`.

Considered hard-block via `bash-guard.sh` PreToolUse: rejected. False-positive surface is too large — `git checkout HEAD~N -- file` (file-mode), `git switch --detach`, `git switch -c new-branch <ref>` (where the ref is the source, not the target) all need allow-paths. Hard-block also breaks legitimate user-driven branch hops (verifying main, cherry-picking from elsewhere).

### Decision

`bash-guard.sh` extends with a soft-warn branch-switch detector:

1. Detects `git checkout <ref>` / `git switch <ref>` excluding: `-b`, `--orphan`, `-c <name>`, `--detach`, `-` (previous-branch), `.` (path), and tracked-pathspec args (test via `git ls-files --error-unmatch <arg>`).
2. Globs `.aihaus/{milestones,features,bugfixes}/*/RUN-MANIFEST.md` and parses lowercase `status:` from each Metadata block.
3. If any manifest has `status: running`, emit stderr warning: `aihaus: branch switch detected while <manifest-path> is running on <other-branch>; continue only if intentional`. The warn fires on ANY branch-switch while a manifest is running — leaving the manifest's branch mid-work IS the collision; switching elsewhere while a peer manifest runs is also worth surfacing. Narrower "current ≠ manifest" framing was considered and rejected as undercoverage.
4. Append audit row to `.claude/audit/branch-switch-warn.jsonl` (8 fields: ts, session_id, from_branch, target_ref, manifest_path, manifest_status, decision=warn-allow, command_hash). `command_hash` is the first 12 chars of `sha256sum` of the full command string.
5. Never block the command. Opt-out: `AIHAUS_BRANCH_SWITCH_GUARD=0`.

### Consequences

**Positive.** Surfaces cross-session collisions without blocking legitimate flows. Mirrors `git-add-guard.sh` segment-and-deny grammar — operators learn one pattern.

**Negative.** Can be dismissed inattentively. Documented in gotchas.md as a class of self-inflicted error.

**Neutral.** Audit log is orthogonal to RUN-MANIFEST single-writer (ADR-004); no contention.

### Rollback

Remove the new block from `bash-guard.sh`. Single hook file.

### Related

ADR-M017-A (`git-add-guard.sh` — sibling segment-and-deny grammar, source of the pattern).

---

## ADR-260427-C: cross-skill pre-flight collision is feature/bugfix-scoped, not extending L1-L4

**Date:** 2026-04-27
**Status:** Accepted
**Milestone/feature:** feature/auto-interference-audit (260427)

### Context

ADR-M017-B's L1-L4 lock-leak prevention stack is **milestone-scoped only**: it relies on milestone RUN-MANIFEST schema (lock files, abort semantics, reap discipline) that feature/bugfix manifests do not carry. Extending L1-L4 to features/bugfixes would require schema parity — a milestone-sized effort by itself.

The audit's primary unmitigated surface is two concurrent skills running on the same working tree. A pre-flight check (read-only inspection of running manifests + dirty-tree state) is the proportional first move.

### Decision

`/aih-feature` and `/aih-bugfix` skills add a one-line reference to a new annex (`pkg/.aihaus/skills/aih-feature/annexes/pre-flight-collision.md`) that defines the check:

1. Glob `.aihaus/{milestones,features,bugfixes}/*/RUN-MANIFEST.md`.
2. For each manifest with `status: running`, capture its `branch:` field.
3. If current branch differs AND working tree dirty (`git status --porcelain` non-empty), surface ONE concrete sentence to the user: *"Aihaus detected a running manifest at `<path>` on branch `<branch>`. Continuing on `<current>` may collide. Continue?"*
4. Wait for affirmative ("y/sim/vai/go/Enter") per autonomy-protocol.md. Do not enumerate options.

The dirty-but-not-mine heuristic is intentionally weaker than the milestone's `## Owned Files` parse, because feature/bugfix manifests do not carry `## Owned Files` (that section is a milestone convention per `aih-milestone/annexes/same-file-rule.md` + `merge-back.sh`).

### Consequences

**Positive.** Cross-session collisions surface before branch ops. Feature/bugfix flows get a proportional first defense without a full L1-L4 port.

**Negative.** Heuristic is weaker than milestone's owned-files check. False-positives possible when user has unrelated dirty edits.

**Neutral.** If S3 proves insufficient across two more sessions, file-existence-gated escalation to extending L1-L4 (per ADR-M017-B's heuristic pattern).

### Rollback

Delete the annex file; revert the one-line reference in each SKILL.md.

### Related

ADR-M017-B (L1-L4 lock-leak stack — sibling, milestone-scoped).
ADR-M017-C (same-file rule — sibling, milestone-scoped, source of the `## Owned Files` convention).

---

## ADR-M019-A — Parallel projection of milestone progress (RUN-STATUS.md)

**Status:** Accepted
**Date:** 2026-05-01
**Milestone:** M019
**Extends:** ADR-001 (filesystem state primitive — preserved); ADR-004 (single-writer per file — extended, not superseded; per-file rule unchanged); ADR-M014-B (manifest-append.sh sole-writer precedent for section-extension)
**Pattern:** ADR-M017-A reference-and-extend grammar; sibling-projection structure mirrored on `STATUS-projection-contract.md`

### Decision

**STATUS owns phase only; RUN-STATUS owns progress only — non-overlapping projections of disjoint state.**

`phase-advance.sh` remains sole writer of `STATUS.md`; `STATUS.md` carries `Metadata.phase` (one of `gathering | planning | ready | running | complete | paused | aborted`) and nothing else. `manifest-append.sh` becomes the sole writer of a new sibling projection `RUN-STATUS.md`; `RUN-STATUS.md` carries story-level progress (slice tree, slice grid `[✓][→][ ]`, recent-activity log) and nothing else. The two projection files are non-overlapping derivatives of the same source-of-truth (`RUN-MANIFEST.md`), with disjoint trigger surfaces (`phase-advance.sh` fires on phase transitions; `manifest-append.sh` fires on every story-record / invoke-push / invoke-pop / progress-log / phase / status / checkpoint mutation).

### Context

- ADR-004 is letter-valid: each of `STATUS.md` and `RUN-STATUS.md` has exactly one writer. The per-file rule is preserved verbatim.
- ADR-004 spirit-collision risk surfaced by contrarian #1 ("two projection files of the same source-of-truth confuses readers"): mitigated by the canonical disjoint-projections sentence above + the applicability examples below.
- Trigger naturalness wins: `phase-advance.sh` fires ~5-7 times per milestone (phase transitions only); `manifest-append.sh` fires on every story-record / invoke / checkpoint event (typically 50-700+ times per milestone). Extending `STATUS.md` to carry progress would require awkward `--refresh-projection` no-op invocations from `manifest-append.sh` into `phase-advance.sh`'s lock domain.
- ADR-M014-B established `manifest-append.sh` as the sole-writer precedent for section-extension (M014 `## Checkpoints`). RUN-STATUS.md regen is a sibling section-write inside the same critical section, governed by the same single-writer discipline.
- M019 dogfood pain (Victor's M041 45-slice run on an external host repo): `M041 · S22/?` statusLine + no scrollback-stable surface. RUN-STATUS.md is the scrollback-stable surface (`tail -F`-able, VS Code on second monitor).

### Options Considered

| # | Option | Pros | Cons | Why Not |
|---|--------|------|------|---------|
| A | Extend STATUS.md (one writer for all projection content) | One writer per concept; preserves the "1 file, 1 writer" mental model | `phase-advance.sh` fires only ~5-7×/milestone; story-level progress would lag arbitrarily long; awkward `--refresh-projection` no-op invocations needed | Trigger naturalness wrong; M014 precedent ignored |
| B | (Chosen) Parallel RUN-STATUS.md under `manifest-append.sh` sole-writer | Natural triggers (every story-record event); M014 precedent reused; tail-F ergonomic; spirit-justification closes the contradiction | Two projection files of same source-of-truth (contrarian #1) | Letter-valid under ADR-004; spirit risk mitigated by canonical sentence + applicability examples + threat-model Non-goal |
| C | Daemon dashboard (Vue+SQLite+WebSocket per disler precedent) | Real-time UI, multi-window | Violates aihaus's markdown+bash distribution constraint | Hard rejection; out of scope |

### Applicability Examples

The canonical applicability test for any future "should this be a new projection file?" question is whether the new file:
1. Has exactly ONE existing sole-writer hook whose natural trigger surface aligns with the projection's update cadence.
2. Carries a NON-OVERLAPPING slice of source-of-truth state (not a copy of, or alternate representation of, an existing projection's slice).

If both hold, the parallel-projection pattern fits. If either fails, the projection is multi-source aggregate and the pattern does NOT fit.

**Worked example #1 — FITS the rule.** A future maintainer wants to surface "currently-paused stories" as a fast-read projection (`BLOCKED.md`) so external dashboards can poll for stuck work without parsing the full manifest. The natural trigger is `manifest-append.sh --field status` — which already fires on every story status change. The projected slice (paused-stories list) is non-overlapping with `STATUS.md` (phase only) and `RUN-STATUS.md` (progress grid; doesn't enumerate paused subset). **Fits.** New ADR-M0XX-Y extends ADR-M019-A; `manifest-append.sh` gets a third sibling section-write helper `_regen_blocked` inside the existing critical section, behind the same lock; new template `BLOCKED-projection-contract.md` mirrors RUN-STATUS-projection-contract.md.

**Worked example #2 — HITS the multi-source carve-out.** A future maintainer wants to surface "agent activity summary across milestones, decisions, and per-agent memory" as a single projection file (`AGENTS.md`) for at-a-glance answer to "which agents have done what lately?" The desired content aggregates `RUN-MANIFEST.md` (story records), `decisions.md` (ADR authorship metadata), and `.aihaus/memory/agents/<name>.md` (per-agent memory). **Does NOT fit.** No single existing sole-writer hook covers all three sources; the natural triggers are disjoint (manifest mutations, ADR appends, agent-memory writes by curator). Tying the projection to one writer's critical section would either (a) force the chosen writer to read files outside its lock domain (race-prone), or (b) require synthetic re-trigger calls into the chosen writer, which is exactly the pattern Option A above was rejected for. Correct answer for AGENTS.md: a separate periodic-rebuild tool (e.g., `tools/rebuild-agents-summary.sh` invoked on demand or from a SessionEnd hook), NOT a parallel projection under the ADR-M019-A pattern.

The carve-out test in one sentence: **if your projection's content cannot be tied to a single existing sole-writer hook's critical section, it is a multi-source aggregate and ADR-M019-A does NOT apply.**

### Consequences

**Positive.** `tail -F RUN-STATUS.md` answers "where am I and what's left?" without parsing the manifest. M014/M017 precedents extend additively. Spirit-justification closes contrarian #1. ADR-001 preserved. ADR-004 per-file rule preserved. Projection-file pattern is now established and reusable (BLOCKED.md hypothetical).

**Negative.** Two projection files of the same source-of-truth — readers must internalize "STATUS authoritative on phase, RUN-STATUS authoritative on progress." A future maintainer who skims this ADR may apply the pattern to a multi-source case (worked example #2) and create a coupling bug. Mitigation: the carve-out test above is the binding rubric; smoke-test asserts ADR-M019-A presence + canonical sentence + applicability-examples header so the test cannot be silently dropped.

**Neutral.** Lock-hold time on `manifest-append.sh` doubles per call (RUN-MANIFEST tmp+mv + RUN-STATUS tmp+mv). Worst-case checkpoint storm (M014 saw 720 rows) measured under M019 dogfood load via D5 outcome gate (zero `manifest-append.sh` exit-6 across 2 consecutive runs). If D5 fails, Backout Plan applies: comment out `_regen_run_status` (~1 LOC); ADR stays accepted with implementation deferred.

### Migration

Single-shot within M019. First mutating `manifest-append.sh` call on any active milestone post-M019 organically generates `RUN-STATUS.md`; pre-existing milestones without `RUN-STATUS.md` are acceptable (it generates on next activity). No retroactive regeneration. No schema-version bump on `RUN-MANIFEST.md`.

### Rollback

Comment out the `_regen_run_status` call inside `manifest-append.sh`'s critical section (~1 LOC). RUN-MANIFEST.md continues sole source-of-truth; STATUS.md continues unchanged. ADR-M019-A stays accepted with Implementation Status marked "deferred — see M019 retrospective." S01/S02/S04/S05 individually valuable.

### Threat-model Non-goal (D7 — see RUN-STATUS-projection-contract.md for full text)

No secrets in story slugs / commit messages. RUN-STATUS.md exposes story slugs, commit SHAs, agent activity timestamps. The file is intentionally human-readable and lives at a path that may be auto-synced by OneDrive / Dropbox / iCloud. Treat its contents as externally readable. This is **discipline, not enforcement**: M019 ships no redaction layer.

### Related

ADR-001 (filesystem state primitive — preserved); ADR-004 (extended, not superseded); ADR-M014-B (manifest-append.sh sole-writer precedent — extended); ADR-M017-A (merge-back substrate — preserved); ADR-M017-C (cross-story file-set isolation — zone-level exception documented for S04 ↔ S05 on `autonomy-guard.sh`); STATUS-projection-contract.md (sibling); RUN-STATUS-projection-contract.md (new — `pkg/.aihaus/templates/RUN-STATUS-projection-contract.md`).

### References

- Scope: `.aihaus/milestones/M019-260501-improve-auto-mode-feedback/PRD.md` (FR-010..FR-014)
- Architecture: `.aihaus/milestones/M019-260501-improve-auto-mode-feedback/architecture.md` (§"manifest-append.sh extension", §"RUN-STATUS.md schema")
- Plan: `.aihaus/plans/260501-improve-auto-mode-feedback/PLAN.md` (D1, D7)
- Patterns: `.aihaus/plans/260501-improve-auto-mode-feedback/PATTERNS.md` §2 + §4 + §5
- Stories: S03 (RUN-STATUS.md projection + projection-contract template + this ADR), S04 (resolve_manifest_path helper + outside-exec-skip audit row), S05 (forensic schema bump + smoke-test + outcome-gate validator)

## ADR-260502-A — Manifest auto-close enforcement protocol (R1)

**Status:** Accepted
**Date:** 2026-05-02
**Milestone:** M020
**Extends:** ADR-001 (filesystem state primitive — preserved); ADR-004 (single-writer per file — preserved verbatim; M020 adds NO new writers); ADR-M011-A (autonomy-guard `paused` TRUE-blocker — preserved; `paused` and `paused-user-input` are never auto-closed); ADR-M014-B (resume substrate / `## Checkpoints` — extended; the crash-resume guard reads checkpoint enter/exit pairs); ADR-M017-A (merge-back-as-script — extended; merge-back gains a release-before-spawn invocation of the new hook); ADR-M019-A (parallel-projection pattern — preserved; `manifest-append.sh` remains sole writer of RUN-STATUS.md, byte-unchanged)
**Pattern:** Deterministic enforcement hook supersedes model-driven prose at the manifest-close moment. Provable-done = 5-condition conjunction. Single-writer discipline preserved by routing all mutations through `update_metadata_kv` inside `acquire_coarse_lock`.

### Decision

**Ship `manifest-auto-close.sh` as a deterministic enforcement hook fired at three deterministic moments — `merge-back.sh` end-of-success, `session-start.sh` boot, `/aih-resume` Phase 1 step 4b — that flips a feature/bugfix/milestone manifest's `Status` to `completed` IFF five provable-done conditions hold simultaneously.**

The 5-condition provable-done definition (binding):

1. `Status` is in the eligible set: `running | awaiting-approval` (PR 1 baseline) plus `awaiting-merge` (PR 2 / S07 extension).
2. `Branch:` field exists locally (`git rev-parse --verify`) OR remotely.
3. `is_branch_merged_into_any <branch> <integration-refs>` returns 0 — i.e., the branch is an ancestor of at least one integration ref (resolved by `lib/integration-refs.sh::detect_integration_refs`).
4. `SUMMARY.md` exists in the run directory **OR** the last `## Story Records` data row's `verified` column is `true`.
5. **Crash-resume guard:** `## Checkpoints` contains no `event=enter` row lacking a paired `event=exit` row for the same `(story, agent, substep)` triple. Protects against auto-closing a crash-mid-execution run that happens to have a stale SUMMARY.md from an earlier session.

When all five conditions hold, the hook acquires the per-manifest coarse lock (`lib/manifest-helpers.sh::acquire_coarse_lock`, lines 111-140), routes the mutation through `update_metadata_kv` (lines 30-42) — the M019-anchored single-writer primitive — and emits a single line to `.claude/audit/hook.jsonl`. **No new writers are introduced.** ADR-004 single-writer-per-file rule is preserved verbatim.

**Migration-before-parse pre-condition.** For every manifest examined (full-sweep OR `--manifest`), the hook FIRST invokes `MANIFEST_PATH=<f> bash manifest-migrate.sh` before parsing metadata. v1 markdown-bullet manifests in user repos migrate forward (v1→v2→v3→v4) on first touch; without this pre-condition, the hook silently skips v1 manifests because the markdown-bullet shape does not parse as YAML.

**Audit-log schema (Q-8 resolved).** Field set: `{ts, hook, manifest_path, branch, integration_ref, result, reason}`. `hook=manifest-auto-close` is constant. `result ∈ {closed, skipped, refused}`. `reason` is a short free-form text drawn from a recommended enum: `branch-missing | not-merged | unmatched-enter | already-terminal | paused-explicit | no-integration-ref | awaiting-merge-promotion | running-promotion | awaiting-approval-promotion`. One JSON line per decision in `.claude/audit/hook.jsonl`. Greppable by `hook=manifest-auto-close` and `result=closed|skipped|refused` (NFR-04).

**Wire-up at three sites.** The hook fires at deterministic moments:

- **`merge-back.sh` end-of-success.** Single-target invocation `manifest-auto-close.sh --manifest <milestone-manifest-path>`. The merge-back hook releases its coarse lock BEFORE the spawn — **release-before-spawn discipline** — and the spawned auto-close re-acquires its own lock. Without release-before-spawn, the parent and child deadlock on the same per-manifest mutex (R-1 / NFR-02).
- **`session-start.sh` boot.** Full-sweep invocation `manifest-auto-close.sh` (no `--manifest`). Glob `.aihaus/{milestones,features,bugfixes}/*/RUN-MANIFEST.md`. Failures are non-blocking; session-start always exits 0 regardless of auto-close exit code.
- **`/aih-resume` Phase 1 step 4b.** Inserted between current step 4 (`Cross-check checkpoint vs worktree state`) and step 5 (`Candidate selection`). For each manifest with `Status != completed` collected in step 2, invoke `manifest-auto-close.sh --manifest <path>`. Auto-closed manifests are removed from the candidate set; the skill emits `Auto-closed N manifests (drift cleanup).` if N > 0, silent if N = 0.

**Subscriber (advisory only).** `session-end.sh` appends a non-blocking advisory after the existing `jq` event-emit block. Tests `[ -x "$AIHAUS_DIR/hooks/manifest-auto-close.sh" ]` first; if false, silently no-ops (NFR-05 / R-3). Otherwise runs `--dry-run` with stderr swallowed; if count > 0, prints `advisory: $count manifest(s) eligible for auto-close — run /aih-close --bulk` to stderr. Never propagates a non-zero exit.

**L4 — `/aih-close --bulk --yes` requires explicit terminal flag.** The manual override skill (S10) MUST refuse to close in bulk mode without an explicit `--deferred|--completed|--cancelled|--awaiting-merge` flag when `--yes` is passed. Prevents accidental mass-close to `completed` for manifests that should be `deferred` or `cancelled`. Stderr text: `/aih-close: --yes requires explicit terminal flag (--deferred|--completed|--cancelled|--awaiting-merge)`.

### Context

- The model-driven Step 13 (`aih-feature/SKILL.md:190-196`) and Step 16 (`aih-bugfix/SKILL.md:178-184`) are the only places today that flip Status to terminal. They are pure prose, executed by the model at end-of-run. The model commonly skips this prose on session-end, CI-handoff, phased-work, and code-reviewer-iteration paths.
- Concrete evidence (downstream consumer audit, 2026-05-02): 9/9 feature/bugfix runs were merged into `origin/staging` with SUMMARY.md or final commit present, yet all 9 had `Phase: implement|apply-fix|planning` and `Status: running|awaiting-approval` in their manifest headers. `worktree-reconcile.sh` separately emitted 8 Category-B 1000-commit cherry-pick recipes — all false positives.
- The post-mortem identified seven recommendations (R1–R7). R1 (`manifest-auto-close.sh`) is the leverage point because it is the only one that *removes the model from the loop*. R2 (`/aih-resume` step 4b) and R7 (session-end advisory) are the visibility loop closers that R1 leaves open.
- The 5-condition conjunction is intentionally narrow. Each condition guards a distinct false-positive class: condition 1 prevents auto-close of paused/cancelled/deferred work; condition 2 prevents auto-close when the branch was force-deleted; condition 3 is the "merged" core; condition 4 prevents auto-close of runs that never produced a SUMMARY (incomplete work); condition 5 prevents auto-close of crash-mid-execution runs. Removing any one condition opens a new false-positive surface; adding more would over-narrow and create false negatives.
- ADR-004 single-writer discipline is preserved because `manifest-auto-close.sh` is a *caller* of `update_metadata_kv`, not a writer. The byte-mutating helper still has exactly one entry point per manifest path, governed by the same lock.
- Migration-before-parse is mandatory for backward compat with v1 markdown-bullet manifests (NFR-09 / R-5). Without it, users with in-flight v1 manifests in their repos would never see those manifests auto-close — silent regression.

### Options Considered

| # | Option | Pros | Cons | Why Not |
|---|--------|------|------|---------|
| A | Keep dual-format parser in `manifest-auto-close.sh` (parse v1 markdown-bullet AND v3 YAML directly) | No SKILL.md changes; no migration path needed | Perpetuates schema bifurcation; future hooks have to choose-one-or-both forever | Adds permanent maintenance debt; v1→v3 migration path already exists and is lock-safe |
| B | Make auto-close an explicit user action only (`/aih-close --bulk` as the sole path) | Simpler — no enforcement hook; user-driven only | Adds another command users must remember; doesn't solve the forgetting problem (post-mortem root cause) | Defeats the purpose; the bug is precisely that humans + models forget terminal steps |
| C | (Chosen) Deterministic enforcement hook fired at three sites + manual override skill | Removes the model from the loop architecturally; same class of bug becomes architecturally impossible; manual override exists for edge cases | New file (~250 LOC); requires migration-before-parse pre-condition; release-before-spawn discipline at one wire-up site | Highest leverage; closes 80% of post-mortem cases automatically; remaining 20% addressed by `/aih-close` |
| D | Require `Status: awaiting-merge` for the branch-merged auto-promotion path (don't promote `running` → `completed` via merge detection) | Stricter semantics | Defeats the purpose: the bug is precisely that humans/models leave manifests at `running` | Auto-close treats `running`, `awaiting-approval`, `awaiting-merge` as equally eligible when merge evidence exists |
| E | Add `Status: cancelled` auto-detection (e.g., branch deleted from remote + no merge) | Closes another drift class | Too hostile to in-flight work that pushed an exploratory branch then deleted it | Cancellation should remain explicit (`/aih-close --cancelled`) |

### Applicability Examples

**Worked example #1 — FITS the pattern.** A future maintainer wants to ship a "stale-bug auto-close" hook that flips `Status: running` to `Status: archived` after 90 days of inactivity for bugfix manifests. The natural enforcement moment is `session-start.sh` boot. The provable-done conjunction has analogous shape: (1) `Status: running`, (2) `last_updated:` field exists, (3) `last_updated < now - 90d`, (4) no recent activity in `## Progress Log`. The mutation routes through `update_metadata_kv` inside `acquire_coarse_lock`. Audit emits `hook=stale-bug-archive result=archived|skipped|refused`. **Fits.** New ADR-M0XX-Y extends ADR-260502-A; the pattern (deterministic hook, conjunction-based eligibility, single-writer mutation, audit-log greppability) replays cleanly.

**Worked example #2 — DOES NOT FIT (model judgment required).** A future maintainer wants to "auto-close" manifests where the user verbally said "I'm done with this" in a chat transcript. The eligibility condition is non-deterministic — it requires NLP/LLM judgment on free-form text. **Does NOT fit.** ADR-260502-A's pattern explicitly requires deterministic conjunction conditions; the moment a condition becomes "model decides," the architectural guarantee ("removes the model from the loop") is voided. Correct answer: this belongs in `aih-feature/SKILL.md` Step 13 prose (model-driven), not in an enforcement hook.

### Consequences

**Positive.** Same class of stale-manifest bug becomes architecturally impossible regardless of model behavior, session boundary, or how many code-reviewer loops ran. `/aih-resume` candidate selection becomes self-healing on every invocation. `manifest-append.sh --field status` becomes the sole atomic mutation path — easier to audit, easier to test. ADR-001 / ADR-004 / ADR-M019-A all preserved verbatim. Audit-log greppability gives operators forensic recovery.

**Negative.** Net new ~600 LOC in PR 1 (hook + helper + 14 fixtures + harness). Migration-before-parse adds one `manifest-migrate.sh` invocation per scanned manifest — measurable but acceptable cost (NFR-08 budget: full sweep <3s on ≤30 manifests). Release-before-spawn is a discipline burden — not enforced by the type system, only by code review and the deadlock test (NFR-02). Crash-resume guard depends on `## Checkpoints` correctness — if the M014-anchored checkpoint logic ever drifts, the guard's false-negative rate grows.

**Neutral.** Schema v3 → v4 is one byte. `## Story Records` `verified` column already exists (M014 anchored). The hook is ~250 LOC including comments and audit; the helper is ~80 LOC. Total surface is small enough to inspect by reading.

### Threat Model

**Class 1: false-positive close (auto-closing work that is NOT actually merged).** Mitigated by 5-condition conjunction — all five must hold. Each condition guards a distinct false-positive class. The audit log captures every decision; a false-positive close is recoverable by `manifest-append.sh --field status --payload running`.

**Class 2: race-induced corruption (concurrent writers torn manifest).** Mitigated by ADR-004 inheritance + release-before-spawn discipline (I-03 in architecture.md). The lock domain is per-manifest; a single coarse-lock cycle covers the entire mutation. `update_metadata_kv` uses `mktemp` + `mv -f` (atomic on same-filesystem POSIX; mkdir-atomic on Windows).

**Class 3: hostile manifest forgery.** A user who forges `verified=true` in `## Story Records` can trigger a false-positive auto-close. **Acknowledged not mitigated.** The hook trusts the manifest as a source of truth; manifest integrity is a separate problem solved at the M019/M017 single-writer layer. Audit trail provides forensic recovery.

**Class 4: stale external editor buffer.** A user editing a manifest in VS Code while merge-back fires can overwrite the auto-close mutation with their stale buffer. **Acknowledged not mitigated.** External editors are outside the lock domain. Idempotency saves the user on the next session-start sweep — the manifest re-promotes. Documented as a known interaction in the architecture.md threat-model section.

**Class 5: crash-mid-execution + stale SUMMARY.** A crash that leaves an unmatched `event=enter` checkpoint with a stale SUMMARY.md from an earlier session would auto-close in a naive implementation. Mitigated by FR-08 / I-06 — the crash-resume guard refuses auto-close in this exact case. Verified by F-CRASH-RESUME fixture.

### Migration

Single-shot within M020 Phase A. First session-start sweep post-PR-1 organically migrates all in-flight v1 markdown-bullet manifests to v3 YAML (and post-PR-2 to v4). Backups land at `<manifest>.v1.bak`. No retroactive regeneration required. No user-visible action.

### Rollback

Comment out the three wire-up invocations in `merge-back.sh`, `session-start.sh`, and `aih-resume/SKILL.md` step 4b. The hook stays installed but never fires. ADR-260502-A stays accepted with Implementation Status marked "wire-up reverted — see M020 retrospective." `/aih-close --bulk` remains available for manual cleanup. `manifest-auto-close.sh --dry-run` works for diagnosis.

### References

- Scope: `.aihaus/milestones/M020-260502-stale-manifest-auto-close/PRD.md` (FR-05..FR-13, FR-18..FR-22, FR-32..FR-35; NFR-01..NFR-06)
- Architecture: `.aihaus/milestones/M020-260502-stale-manifest-auto-close/architecture.md` (§2 Component diagram, §4 Q-8 audit-log schema, §6 Data model + API design, §7 Threat model, §10 Migration strategy)
- Plan: `.aihaus/plans/260502-stale-manifest-auto-close/PLAN.md` (PR 1 §1a–§1f, PR 2 §2d, PR 3 §3b)
- Stories: S01 (`lib/integration-refs.sh`), S02 (hook + audit + 14 fixtures), S05 (wire-up at three sites + advisory), S07 (`awaiting-merge` auto-promotion)
- Outcome gates satisfied: C-1, C-2, C-3, C-4, C-6, C-7, C-10

## ADR-260502-B — Integration-branch awareness (R4) + closest-ancestor reconcile

**Status:** Accepted
**Date:** 2026-05-02
**Milestone:** M020
**Extends:** ADR-001 (filesystem state primitive — preserved); ADR-260502-A (companion ADR; both share `lib/integration-refs.sh` as a foundation); ADR-M017-A (merge-back-as-script — preserved; `worktree-reconcile.sh` is a sibling tool, not the merge-back path itself)
**Pattern:** Single source of truth for "what counts as merged into integration." Closest-ancestor classification supersedes single-`MAIN_BRANCH` reachability. Hard-cap on cherry-pick recipe length with explicit env override.

### Decision

**Ship `lib/integration-refs.sh` as the single source of truth for integration-ref detection in aihaus, consumed by `manifest-auto-close.sh`, `worktree-reconcile.sh`, and `/aih-close`. Detection priority: (1) `.aihaus/project.md` `integration_branches:` MANUAL field, (2) `git symbolic-ref refs/remotes/origin/HEAD` target, (3) defaults `[origin/staging, origin/main, origin/develop, origin/dev]`. Every emitted ref MUST pass `git rev-parse --verify` before emission. Empty-list result is valid (caller treats as `result=skipped reason=no-integration-ref`).**

**`worktree-reconcile.sh` measures against closest integration ancestor, not main only.** Pre-M020 behavior at line 318 (`commits_not_on_main="$(git rev-list --count "${MAIN_BRANCH}..${wt_sha}" 2>/dev/null || echo "1")"`) is replaced with closest-integration-ancestor logic. For each worktree: iterate the cached integration-ref list; the FIRST ref where `git merge-base --is-ancestor <wt_sha> <ref>` succeeds is the **closest integration ancestor**. If any ref contains the worktree HEAD, classify Category A (clean+merged) and prune silently. If no ref contains it, fall through to existing Category B logic against the closest non-containing ref (which becomes the rebase target).

**Hard cap on cherry-pick recipes at `AIHAUS_RECONCILE_CAP` (default 50).** If Category-B recipe would emit `>cap` commits, the hook emits exactly ONE line:

```
[INTEGRATION-LAG] <worktree-path> appears to be tracking an old base. Suggest: git rebase <closest-integration-ref>
```

and emits ZERO `[CATEGORY B]` recipe blocks for that worktree (Q-5 resolved: hard cap, env override). `AIHAUS_RECONCILE_CAP=0` is treated as "no cap" (uncapped recipe) — explicit user opt-in. Independent of `AIHAUS_RECONCILE_INTEGRATION_REFS=0` (the broader opt-out preserving pre-M020 single-`MAIN_BRANCH` behavior byte-identically).

**`git rev-parse --verify` filter on every emitted ref.** A symbolic-ref that no longer resolves (e.g., `origin/HEAD` pointing at a deleted branch on a stale clone) is silently dropped. The function exits 0 with an empty list when no refs verify (NFR-06 / R-4). This is the only architectural defense against the "no `origin/HEAD` set on cloned repo" failure mode.

### Context

- Pre-M020 `worktree-reconcile.sh:318` compared every worktree HEAD only to `MAIN_BRANCH` (resolved via the chain at lines 62–81). In a `staging → main` GitFlow, every staging-merged worktree appears as Category B with a 1000-commit cherry-pick recipe — pure noise.
- The post-mortem evidence: 8 Category-B recipes spanning 893–1177 commits each in the downstream consumer's audit, all of them staging-merged (already on `origin/staging`, not yet on `origin/main`). Operator response is to mute the tool entirely; the genuine "orphaned commits" detection path becomes invisible.
- The fix is structural: stop comparing to "main" and start comparing to "any integration ref." A list, ordered by priority, is the right shape because GitFlow naming varies: some repos use `staging`, some use `develop`, some use `release/<sprint>`, some have no staging at all.
- `lib/integration-refs.sh` becomes the single source of truth. Three consumers (`manifest-auto-close.sh`, `worktree-reconcile.sh`, `/aih-close`) all classify "merged" identically — a precondition for cross-tool consistency. Without a shared helper, each tool would drift its own detection logic.
- The hard-cap-with-env-override pattern is borrowed from M017's `AIHAUS_RECONCILE_LIMIT` (worktree-reap policy). Same shape, same opt-out grammar.
- Q-2 placement decision (architect-resolved): `integration_branches:` lives in the MANUAL section of project.md (`<!-- AIHAUS:MANUAL-START -->` … `<!-- AIHAUS:MANUAL-END -->`). This is per-repo policy — by definition human-controlled. The starter template `pkg/.aihaus/templates/project.md` ships a commented-out example.

### Options Considered

| # | Option | Pros | Cons | Why Not |
|---|--------|------|------|---------|
| A | Keep single `MAIN_BRANCH` and add a list-mode flag | Minimal refactor; one branch of code path | Doesn't solve cross-tool consistency (auto-close + reconcile + aih-close need shared logic); flag explosion | Per-tool drift inevitable; cross-tool consistency degrades |
| B | (Chosen) Single shared helper + closest-ancestor classification + hard cap | Cross-tool consistency; one source of truth; hard cap forces actionable signal; env override for paranoid users | New file (~80 LOC); migration of `worktree-reconcile.sh` line 318 + surrounding 30 LOC | Best long-term shape; extensible to future hooks |
| C | "Any integration ref" vs "specific named ref" (post-mortem R4 said singular) | Simpler — one ref to compare against | GitFlow naming varies (`staging`, `develop`, `release/2026`); naming a specific ref forces user config | Extended to a list because user repo naming is variable |
| D | Soft cap on cherry-pick recipes (emit recipe + escalation line both) | More information per worktree | Doubles output volume; doesn't resolve user's "what do I do?" question | Hard cap is the binary decision the user wants |
| E | Hard cap with no env override | Strictly enforced; no escape hatch | Rare cases (post-mortem reconstruction, forensic) need full recipe | `AIHAUS_RECONCILE_CAP=0` is the explicit opt-in for those rare cases |

### Applicability Examples

**Worked example #1 — FITS the pattern.** A future maintainer wants to add a `lib/feature-flags.sh` shared helper that resolves enabled feature flags from priority sources: (1) `.aihaus/project.md` MANUAL field, (2) env vars, (3) compiled defaults. Three consumers (skill A, hook B, agent prompt C) need consistent feature-flag state. **Fits the ADR-260502-B pattern.** Single source of truth, priority-ordered detection, every emitted flag verified before emission, empty-result handling. Pattern replays cleanly.

**Worked example #2 — DOES NOT FIT (mutable state, not detection).** A future maintainer wants to add a `lib/recent-activity.sh` shared helper that returns "the most recent commit SHAs touching aihaus files." This is *mutable state* — the answer changes on every git commit. ADR-260502-B's pattern is for *detection of static configuration* (integration refs are stable across a session). For mutable state, a per-call git query is the right pattern, not a cached helper. **Does NOT fit.** Correct answer: inline `git log` calls at each consumer; no shared helper because there's no shared state to deduplicate.

### Consequences

**Positive.** Cross-tool consistency on "merged" classification — auto-close, reconcile, and aih-close all agree. 8 Category-B 1000-commit alerts in the downstream consumer's audit drop to 0 (all 8 worktrees become Category A — clean+merged-to-staging — and prune silently). Truly orphaned worktrees still flag with ≤50-commit useful recipes. Hard cap forces actionable signal. `AIHAUS_RECONCILE_INTEGRATION_REFS=0` preserves pre-M020 behavior byte-identically for paranoid users.

**Negative.** Silent prunes extend to staging-merged worktrees (Category A growth). A user who wanted to inspect a staging-merged worktree might find it pruned; recoverable via `git worktree add` against the same SHA, but a friction point. Mitigation: the env opt-out (`AIHAUS_RECONCILE_INTEGRATION_REFS=0`) is documented in ADR-260502-B and in `worktree-reconcile.sh` header comments. Helper file is POSIX-`sh` only — no bash-isms. Implementer must avoid `[[ ... ]]`, arrays, and other bashisms in `lib/integration-refs.sh`.

**Neutral.** New file ~80 LOC. `worktree-reconcile.sh` MOD ~120 LOC (line 318 replacement + surrounding). Two new fixtures (F-RECONCILE-CAP-49 / F-RECONCILE-CAP-50). The cap default 50 is a round number from the post-mortem; nothing forensic about it.

### Threat Model

**Class 1: false-positive prune (silent pruning of a worktree the user wanted to keep).** Mitigated by `AIHAUS_RECONCILE_INTEGRATION_REFS=0` env opt-out. Recoverable via `git worktree add` against the same SHA — Git preserves the commits regardless of worktree presence.

**Class 2: false-negative classification (wrong integration ref picked).** Mitigated by explicit `integration_branches:` field in project.md (priority 1). Defaults are conservative: if no symbolic-ref and no project.md field, the four-default fallback covers the common GitFlow shapes. Empty-result exit-0 prevents catastrophic misclassification on weird-clone repos (NFR-06).

**Class 3: stale `origin/HEAD` symbolic-ref.** A symbolic-ref pointing at a deleted branch is a real failure mode. Mitigated by `git rev-parse --verify` filter — every emitted ref must verify before emission. Stale refs are silently dropped.

**Class 4: cap evasion via large `AIHAUS_RECONCILE_CAP`.** A user setting `AIHAUS_RECONCILE_CAP=10000` explicitly opts in to large recipes. Acknowledged not mitigated; this is user-controlled escape-hatch by design.

### Migration

Single-shot within M020 Phase C. First post-PR-3 invocation of `worktree-reconcile.sh` uses the new logic. The `MAIN_BRANCH` resolution chain (lines 62–81) is preserved as the fallback path inside the same hook. No retroactive regeneration. No user action required.

### Rollback

Set `AIHAUS_RECONCILE_INTEGRATION_REFS=0` globally to revert to pre-M020 single-`MAIN_BRANCH` behavior byte-identically. ADR-260502-B stays accepted with Implementation Status marked "user opted out — see M020 retrospective." `lib/integration-refs.sh` continues to serve `manifest-auto-close.sh` (which has its own opt-out path).

### References

- Scope: `.aihaus/milestones/M020-260502-stale-manifest-auto-close/PRD.md` (FR-01..FR-04, FR-29..FR-31; NFR-06, NFR-07)
- Architecture: `.aihaus/milestones/M020-260502-stale-manifest-auto-close/architecture.md` (§4 Q-2 + Q-5 resolution, §6.3 lib/integration-refs.sh API, §7 Threat model)
- Plan: `.aihaus/plans/260502-stale-manifest-auto-close/PLAN.md` (PR 3 §3a)
- Stories: S01 (`lib/integration-refs.sh` shared helper), S09 (`worktree-reconcile.sh` integration-ref switch + cap + escalation), S08 (this ADR)
- Outcome gates satisfied: C-8, C-11

---

## ADR-260503-A — SKILL enforcement-layer audit framework + move rule

**Status:** Accepted
**Date:** 2026-05-03
**Milestone:** M021
**Extends:** ADR-001 (filesystem state primitive — preserved; the audit is markdown-only); ADR-260502-A (deterministic enforcement gate — eligibility constraint inherited verbatim; see Worked example #2 quoted below); ADR-004 (single-writer per file — preserved; canonical `enforcement-audit.md` has S08 as sole writer)
**Pattern:** Per-step classification of every binding contract step in every aih-* SKILL into A model-driven / B agent-delegated / C hook-enforced primary layer + actor/gate/escape tag-set + leverage/reversibility/drift-detectability score axes + eligibility column. The move rule promotes A → B/C iff `leverage=high AND (reversibility=irrev OR drift-detectability=hard) AND eligibility=deterministic`. Per-skill fragments + S08 sole-writer canonical concat preserves ADR-004.

### Decision

**Ship a package-shipped, audit-only living document at `pkg/.aihaus/skills/_shared/enforcement-audit.md` classifying every step in every `pkg/.aihaus/skills/aih-*/SKILL.md` (13 SKILLs) and every binding annex (~20-25 files) into a 13-column row schema; lock the framework, scoring axes, move rule, step-counting rubric, and refresh triggers in this ADR; gate promotion eligibility through the ADR-260502-A determinism inheritance.**

The 13-column row schema (binding):

```
| SKILL | Location | Step | Label | Primary | Actor | Gate | Escape | Leverage | Reversibility | Drift Risk | Eligibility | Notes |
```

**Three-layer primary classification (binding enum).** Every step has exactly one Primary value drawn from `{A, B, C, A+C, B+C, A+B+C}`. Composite values are permitted for steps where actors are layered (e.g., agent invokes hook; model writes prose backed by hook detection):

- `A` model-driven — prose-only, model is the actor + gate.
- `B` agent-delegated — explicit `subagent_type` spawn, agent is the actor, agent's checklist is the gate.
- `C` hook-enforced — script (PreToolUse / PostToolUse / Stop / SessionStart) is the actor and gate.

**Tag-set columns (composite reality).** Three orthogonal columns capture composite cases:

- `actor ∈ {model, agent, hook, multi}` — when Primary is composite (`B+C` etc.), actor is `multi`.
- `gate ∈ {none, advisory, blocking, advisory+blocking}` — `advisory+blocking` for hooks emitting advisory at one site + blocking at another.
- `escape ∈ {none, opt-out-env, manual-override}` — `opt-out-env` = `AIHAUS_*=0` envs; `manual-override` = explicit user command.

**Score axes (binding enum).** Three orthogonal columns capture risk:

- `leverage ∈ {low, med, high}` — magnitude of correctness-cost when the step's enforcement drifts (blast-radius), independent of step size or input volume.
- `reversibility ∈ {rev, irrev}` — `irrev` = once committed/landed, requires forensic recovery (revert + audit).
- `drift-detectability ∈ {easy, med, hard}` — `easy` = caught by smoke / hook / reviewer; `hard` = silent / surfaces only via incident.

**Eligibility column (ADR-260502-A inheritance).** `eligibility ∈ {deterministic, model-judgment, partial}` — gates promotion eligibility per ADR-260502-A "Worked example #2 — DOES NOT FIT" (decisions.md:1863, quoted verbatim):

> **Worked example #2 — DOES NOT FIT (model judgment required).** A future maintainer wants to "auto-close" manifests where the user verbally said "I'm done with this" in a chat transcript. The eligibility condition is non-deterministic — it requires NLP/LLM judgment on free-form text. **Does NOT fit.** ADR-260502-A's pattern explicitly requires deterministic conjunction conditions; the moment a condition becomes "model decides," the architectural guarantee ("removes the model from the loop") is voided. Correct answer: this belongs in `aih-feature/SKILL.md` Step 13 prose (model-driven), not in an enforcement hook.

**Move rule (binding).** Promote A → B/C iff `leverage=high AND (reversibility=irrev OR drift-detectability=hard) AND eligibility=deterministic`. The third axis is the ADR-260502-A "deterministic-only" gate inherited verbatim — A-classified high-leverage steps requiring model judgment must STAY A (no enforcement available, by ADR).

**Leverage definition (binding prose, FR-06).** `leverage = magnitude of correctness-cost when the step's enforcement drifts (blast-radius), independent of step size or input volume`. Two implementer worktrees scoring the same step against this prose must agree.

**Step-counting rubric (locked in `tools/audit-skill-enforcement.sh`).** Per-format regex set covering all 4 SKILL formats:

- `### Step N(\.\d+)?[ —:]` — H3 colon/dash format (aih-feature, aih-milestone/annexes/execution.md).
- `## Step N(\.\d+)?[ —:]` — H2 step format (aih-milestone/SKILL.md, aih-milestone/annexes/promotion.md).
- `### N(\.\d+)?\.[ ]` — numbered H3 (aih-bugfix, aih-init, aih-resume, aih-update).
- D2 fallback for SKILLs with zero numbered-H3 (aih-quick, aih-close, aih-plan): count H2 mode/phase headers EXCLUDING named-section list (`## Task`, `## Modes`, `## Autonomy`, `## Guardrails`, `## Annexes`, `## Inputs`, `## Required output`, `## Constraints`, `## Acceptance criteria`, `## Hard rules`).

`## Phase N` headers are EXCLUDED — they are groupings, not steps. Phases become parent groupings within audit fragments (visual structure only); they do NOT contribute rows.

**Per-skill fragment + S08 sole-writer architecture (preserves ADR-004).** Each story owns ONE fragment file under `pkg/.aihaus/skills/_shared/enforcement-audit/<skill>.md`; S08 is the SOLE writer of the canonical concat `pkg/.aihaus/skills/_shared/enforcement-audit.md`. K-002 same-file rule respected — zero same-file overlap across S02-S07.

**Smoke Check 62 (structural-from-day-one + monotone ratchet).** Asserts (a) canonical `enforcement-audit.md` exists with ≥4 H2 headers, (b) per-skill fragment dir exists, (c) row coverage cannot regress across commits. Substantive coverage assertion engages at S08 close (every rubric-matched step appears as ≥1 row). Lightweight Check 17 shape per PATTERNS Pattern 5; never copy Check 6's awk-parse rigor.

### Context

Three consecutive 2026-05-02/03 post-mortems surfaced one structural root cause:

> "Anywhere the SKILL says 'the model will catch this,' there's drift. Anywhere there's an explicit agent step with a checklist, there isn't drift."
> — *260503 getShift-completion §"Cross-cutting"*

Each remediation cost ~5h; ~15h total bleed in 48h. Specific incidents:

- **v0.24.0** — closure-step drift: `aih-feature` Step 13 / `aih-bugfix` Step 16 model-driven terminal-vocabulary prose. Remediated via M020 ADR-260502-A: deterministic enforcement hook supersedes model-driven prose at the manifest-close moment.
- **v0.24.1 + v0.24.2** — Step 7 / Step 9 routing drift: model inline-edited instead of delegating to specialty agents. Remediated via 260503-step7-agent-delegation: SKILL prose rewrite + new annex `agent-routing.md` (binding contract) + Phase B autonomy-guard advisory.
- **v0.24.3** — worktree drift: cross-story file ownership violations and reviewer-prompt drift. Remediated via M017 four-layer lock-leak prevention stack + worktree-drift-check hook.

The pattern is structural, not local. There are likely 5-10 more drift-prone steps in other SKILLs that have not yet fired post-mortems. M021 surfaces them via inventory + classification + scoring + a prioritized remediation backlog. Audit-only: remediation execution moves to M022+ via `enforcement-audit-backlog.md`.

The framework draws on three precedents:
- `pkg/.aihaus/skills/aih-effort/annexes/cohorts.md` — per-entity classification table (PATTERNS Pattern 1; the structural shape model).
- `pkg/.aihaus/skills/_shared/autonomy-protocol.md` — binding governance annex (PATTERNS Pattern 3; the publication location model).
- ADR-260502-A — deterministic enforcement gate (the eligibility column's authority).

Cost recovery: if backlog promotions prevent 3 future post-mortems of similar shape, ~15h paid back. Break-even at the third prevented incident.

### Options Considered

| # | Option | Pros | Cons | Why Not |
|---|--------|------|------|---------|
| A | Per-step frontmatter on each SKILL.md | Inline; no new doc | Pushes multiple SKILLs past 199-line ceiling (Check 5 / 57); requires schema change to SKILL frontmatter; PATTERNS Pattern 5 explicit "What NOT to copy" call | High cost, low payoff; structural conflict with line ceiling |
| B | Run audit-only without producing a backlog | Simpler; one milestone | Post-mortem author explicitly cited a "backlog of moves" — leaves next post-mortems unstaged | Defeats the purpose; the inventory without the prioritization is half the work |
| C | Bundle audit + remediations in one milestone | Single deliverable | Remediation cost varies wildly per migration class (A→B ~120 LOC, A→C ~150 LOC + hook + ADR); discovering bundled with audit table is risk-stacking | Decoupling makes remediation-milestone shape data-driven |
| D | Maintainer-only doc at `tools/skill-audit.md` (not shipped) | Keeps package surface clean | Users running `/aih-init` in their own repos won't discover the framework when authoring custom SKILLs | Defeats discoverability; the framework should ship with the package |
| E | A/B/C single-enum classification (per orchestrator brainstorm) | Simpler | Too coarse for composite steps (`aih-feature` Step 7 is `B+C` — agent + hook); ASSUMPTIONS finding #1 surfaced this early | Refined to A/B/C primary + actor/gate/escape tag-set |
| F | Auto-generate via static analysis | Fully reproducible | Score axes (leverage / reversibility / drift-detectability) require human judgment grep cannot infer; classification accuracy degrades sharply on composite cases | Kept grep as a row-coverage assertion only (`audit-skill-enforcement.sh --coverage`) |
| G | (Chosen) Per-skill fragments + S08 sole-writer canonical + 13-column schema + move rule with eligibility gate | Preserves ADR-004 single-writer; preserves K-002 same-file rule; composite-friendly schema; eligibility column inherits ADR-260502-A; framework is informational (no auto-promotion) | New 13-column schema + new tooling (~150 LOC) + 14 fragment files; rubric-correctness depends on per-format regex + golden-rows fixture | Highest leverage; closes the structural drift loop without forcing remediation cost into the audit milestone |

### Applicability Examples

**Worked example #1 — FITS the pattern.** A future maintainer wants to audit and remediate enforcement-layer drift for the auto-close staleness logic — there are several heuristics around `manifest-auto-close.sh` 5-condition conjunction that may have drifted across `merge-back.sh`, `session-start.sh`, and `/aih-resume` step 4b wire-up sites since M020. The auto-close logic lives in 3 known wire-up sites + 1 hook + 1 helper + 5 conditions — bounded inventory ≈10-15 step-rows. A new directory `pkg/.aihaus/skills/_shared/enforcement-audit-autoclose/` holds per-site fragments; a sole reconciler story emits canonical `enforcement-audit-autoclose.md`. The 13-column schema replays cleanly; `Eligibility` inherits ADR-260502-A determinism gate (the auto-close is the canonical example). A new structural+monotone Check 63 mirrors Check 62. **Fits.** The pattern (per-fragment + sole-writer + ratchet smoke check + bounded SKILL inventory) replays.

**Worked example #2 — DOES NOT FIT.** A naive scenario: "Audit user code style (variable names, function lengths, comment density) across all consumer projects that have aihaus installed." The pattern requires a **bounded, owned set of inputs** — here aihaus has no canonical SKILL inventory in consumer repos (consumer projects are open-ended). The scoring axes also require per-format deterministic rubrics (SC-10 byte-identical reproducibility); naming-style scoring fails this gate. Cross-repo single-writer is impossible (ADR-004 is per-file in one repo). And the eligibility gate (ADR-260502-A) explicitly disallows promotion to a deterministic enforcement layer for naming-style — it requires NLP/LLM judgment on free-form text (the canonical "DOES NOT FIT" example, quoted in §Decision above). **Does NOT fit.** Correct answer: style audits belong to a different pattern entirely — per-project linter configs, code-review checklists, or model-driven SKILL.md prose at the consumer-repo scope.

### Consequences

**Positive.** The structural drift root cause becomes visible: every "model will catch this" step is named, classified, scored, and queued for remediation. M022+ planning consumes a deterministically-ranked backlog of A→B/C candidates, each annotated with cost-estimate from PATTERNS.md and eligibility rationale. Future SKILL authors discover the framework via CLAUDE.md §"SKILL Enforcement Audit" + per-SKILL pointer comments; new SKILL adds must add a fragment file before merge (Refresh Trigger). The ADR-260502-A determinism gate is inherited verbatim — non-promotable A steps stay A by architecture, not by oversight. ADR-001 and ADR-004 preserved verbatim; the audit is markdown-only, single-writer, audit-only.

**Negative.** Net new ~1700-2200 LOC of audit content + ~150 LOC tooling + ~30 LOC smoke-check across one milestone. Borderline upper milestone-sized but justifiable by 3-incident cost-recovery argument. Score-axis subjectivity is a real risk — mitigated by the golden-rows fixture (D3) + S08 score-consistency check (L7), but two implementers may legitimately disagree on borderline steps. Audit decays as SKILLs evolve — Refresh Triggers mitigate, but trigger (c) (annex renamed) requires manual cue.

**Neutral.** No new hook scripts ship in M021 (`EXPECTED_HOOKS` array unchanged; SC-11). No installer logic touched (`pkg/scripts/{install,update}.sh` already propagate `_shared/`). 13 SKILL.md files gain one pointer line each (5 of them with trailing-blank strip for net-zero LOC delta — D5 / I-08).

### Threat Model

**Class 1: rubric drift across implementers.** Mitigated by golden-rows fixture (D3 / L3) — every S02-S07 implementer briefing references it before drafting any row. S08 cross-fragment score-consistency check (L7) flags ≥1-axis-level divergences across known-similar regex groups (advisory, not blocking). S08 reconciliation rework loop ≤2 spawns; refusal-grammar halt on 3rd. Recoverable.

**Class 2: score subjectivity.** Mitigated by locked leverage definition (FR-06): two implementers scoring against the prose must agree. Borderline disagreements on similar-shape steps surface via Class-1 mitigation.

**Class 3: audit becomes stale.** Mitigated by ADR-260503-A Refresh Triggers clause and Smoke Check 62 monotone ratchet. Trigger (a) and (b) are auto-detected; (c) requires manual cue. **Acknowledged residual risk** — audit may go stale on annex rename without smoke detection.

**Class 4: model-judgment over-flagging.** Naive backlog generation would surface intentional A steps (e.g., `aih-init` Step 3 codebase scan) as A→C promotion candidates. Mitigated by L8 model-judgment sanity gate (S09 grep step body for "model" / "judgment" / "decide" / "ask" → flag as `eligibility=model-judgment-suspected` requiring Notes rationale OR drop) + eligibility=deterministic in move rule.

**Class 5: self-applying meta-issue.** M021's own production milestone steps are themselves enforcement-layer steps. **Acknowledged not auto-remediated;** S09 backlog explicitly excludes M021-meta rows via Notes-column disambiguation. Future audits may consume M021's own production rows; this is by design.

### Migration

Single-shot within M021. Strictly additive — no retroactive change to existing SKILLs. New: 14 fragment files + canonical concat + backlog + tooling + 7 fixture dirs. Modified-additively: smoke-test (Check 62 add), decisions.md (this ADR append), CLAUDE.md (§ add), 13 SKILL.md (1 pointer line each + 5 trailing-blank strips). No data migration. No schema change. No installer logic touched.

User repos that ran `bash pkg/scripts/install.sh --target .` before M021 see new files appear after the next `bash pkg/scripts/update.sh --target .`. No breaking change.

### Rollback

Comment out the §"SKILL Enforcement Audit" subsection in CLAUDE.md (S10 ownership). Revert S10's 13 SKILL.md pointer-comment additions. Revert this ADR via `git revert <S01-commit-hash>` (NOT amend, NOT reset). The canonical `enforcement-audit.md` and per-skill fragments stay in tree (informational only) — they're harmless without the CLAUDE.md cross-link. ADR-260503-A stays accepted in commit history with Implementation Status marked "rolled back — see M021 retrospective." `tools/audit-skill-enforcement.sh` continues to work for diagnosis.

### Refresh Triggers

The audit is a living document. Re-run conditions:

(a) **New SKILL added** (e.g., a future `pkg/.aihaus/skills/aih-foo/`) → audit MUST add fragment file `pkg/.aihaus/skills/_shared/enforcement-audit/aih-foo.md` before merge. Smoke Check 62 detects this automatically (rubric sweeps all SKILL dirs; expected-row count grows; canonical row count must keep up).

(b) **Step count of any SKILL changes by ≥2** → re-classify affected fragment. Detected automatically: `compute_expected_rows` output shifts; canonical row count must shift in step.

(c) **Annex referenced by a SKILL is renamed/moved** → re-anchor the fragment row paths. NOT detected automatically; requires manual cue from the SKILL editor (one-time annotation in the manifest progress log).

### Implementation Status

**Audit landed in M021. Remediations queued in `enforcement-audit-backlog.md` are reviewed in M022+. THIS ADR DOES NOT AUTO-PROMOTE ANY STEP.**

The framework codifies the classification, scoring, move rule, step-counting rubric, eligibility gate (inherited from ADR-260502-A), and refresh triggers. It does NOT itself force any A→B/C migration. M022+ planners consume `enforcement-audit-backlog.md`'s prioritized candidates one by one, each shipped as its own remediation milestone with cost-estimate from PATTERNS.md and explicit ADR for any new hook.

### References

- Scope: `.aihaus/milestones/M021-260503-skill-enforcement-audit/PRD.md` (40 FRs, 8 NFRs, 12 SCs)
- Architecture: `.aihaus/milestones/M021-260503-skill-enforcement-audit/architecture.md` (§3 component diagram, §4 invariants I-01..I-15, §6 cross-story dependency map, §7 data model, §8 threat model + worked examples, §9 Check 62 spec, §10 backout plan, §11 migration, §12 testing)
- Plan: `.aihaus/plans/260503-skill-enforcement-audit/PLAN.md` (10 stories, 6 phases; post inline-fix)
- Plan supporting docs: `.aihaus/plans/260503-skill-enforcement-audit/{ASSUMPTIONS,PATTERNS,CHECK}.md`
- Stories: S01 (framework + scaffold + this ADR + skeleton script + golden-rows + Check 62 structural + 7 fixtures + test runner), S02-S07 (per-skill fragments), S08 (canonical concat + reconciliation rework + score-consistency check), S09 (backlog with eligibility filter + L8 sanity gate), S10 (CLAUDE.md + per-SKILL pointers + 199-line ceiling fix)
- Inherited ADR: ADR-260502-A "Manifest auto-close enforcement protocol (R1)" — `pkg/.aihaus/decisions.md:1804-1899` (Worked example #2 quoted verbatim above)
- Sibling ADR: ADR-260502-B "Integration-branch awareness (R4) + closest-ancestor reconcile" — `pkg/.aihaus/decisions.md:1901-1981` (style template)
- Outcome gates satisfied: SC-1 through SC-12
- Post-mortem evidence: `.aihaus/brainstorm/260503-skill-enforcement-audit/CONVERSATION.md` + 260502-stale-manifest + 260503-step7 + 260503-getShift-completion

### Amendment (M029, 2026-05-12)

**Amended by:** ADR-260511-B

Move-rule extended with trigger pattern (c) anticipatory-protection-on-new-flow. See ADR-260511-B for full criteria.

---

## ADR-260504-A — V5 global-skill-bootstrap protocol

**Status:** Accepted
**Date:** 2026-05-05
**Milestone:** M022
**Extends:** ADR-001 (filesystem state primitive — preserved; user-global skill symlinks are filesystem-level state); ADR-260502-A (deterministic enforcement gate — eligibility for the discovery chain inherits the determinism rule; non-deterministic arbitration is explicitly rejected per Worked example #2 below); ADR-260503-A (SKILL Enforcement Audit framework — `/aih-install` adds a 14th SKILL row + per-skill fragment, satisfying the framework's Refresh Trigger (a))
**Pattern:** One-time machine-level bootstrap symlinks every package skill into the user-global `~/.claude/skills/aih-*` resolution layer; deterministic 8-tier discovery priority chain pinned in `~/.aihaus/.install-source`; `.aihaus-managed` marker per skill dir prevents collision with third-party skills; dogfood-mode branch refuses `git pull` when cwd is the central clone; new model-invokable `/aih-install` skill (`disable-model-invocation: false`) is the literal fix for Claude composing inconsistent compound install commands.

### Decision

**Ship V5 — global-skill-bootstrap protocol — as the load-bearing architectural pivot of M022.** A one-time `bash pkg/scripts/install.sh` invocation symlinks every `pkg/.aihaus/skills/aih-*` directory under `~/.claude/skills/aih-*`, making every `/aih-*` slash-command resolve from any cwd in any future Claude Code session. Per-repo `.aihaus/` overlay collapses from prerequisite to opt-in enhancement. The CLI verb is `aihaus install`; the new model-invokable skill is `/aih-install` (sibling to the existing project.md-bootstrap skill `/aih-init` which keeps `disable-model-invocation: true`).

The protocol is composed of six binding pieces:

**1. User-global skill install (FR-01).** `install.sh` loops over every `pkg/.aihaus/skills/aih-*` directory (excluding `_shared`) and creates a symlink (Unix) or junction (Windows, via `mklink /J`) at `~/.claude/skills/aih-<name>` pointing back at the package source. Each created dir carries a `.aihaus-managed` marker file (FR-06; threat mitigation R1).

**2. Discovery priority chain (FR-03; binding 8-tier).** Order:

1. `--package <path>` flag on `install.sh` (CI / shim explicit override);
2. `$AIHAUS_HOME` env var;
3. `~/.aihaus/.install-source` registry (one-line plaintext file written on first successful install);
4. `$XDG_DATA_HOME/aihaus` on Unix, `$LOCALAPPDATA\aihaus` on Windows (XDG default);
5. `~/tools/aihaus` (legacy README path);
6. `~/Documents/GitHub/aihaus-flow` (legacy auto-clone path; the friend's case);
7. `~/Documents/GitHub/aihaus` (legacy variant);
8. `~/code/aihaus` (legacy variant).

First-hit wins. Multiple-hits arbitrated by `git log -1 --format=%ct` on HEAD (newest commit date wins silently); pick recorded to `~/.aihaus/.install-source` for deterministic re-resolution.

**3. `.aihaus-managed` marker invariant (FR-06).** Every aihaus-created `~/.claude/skills/aih-X/` directory carries a `.aihaus-managed` two-line marker (`managed_by=aihaus` + `source=<absolute path under AIHAUS_HOME>`). Install refuses to overwrite unmarked dirs (collision defense); uninstall (`--purge-user-global`) refuses to remove unmarked dirs and refuses to follow symlinks whose `readlink` target falls outside registered `AIHAUS_HOME` (R4 defense, FR-21).

**4. Dogfood-mode branch (FR-05; orchestrator lock L9).** When `[ -f "$PWD/pkg/scripts/install.sh" ] && [ -d "$PWD/pkg/.aihaus/skills" ]`, `install.sh` emits one-liner ("you are inside the aihaus package; run `aihaus self-update` to refresh") and exits 0; zero symlinks created. `update.sh` likewise refuses `git pull` on dogfood cwd (R3); `aihaus self-update` aborts on dirty dogfood (R8). The maintainer's local clone at `~/OneDrive/Documents/GitHub/aihaus-flow` and the friend's auto-cloned `~/Documents/GitHub/aihaus-flow` are both structurally the dogfood case — they hit this branch.

**5. Duplicate-clone deterministic resolution.** When the discovery chain finds multiple candidate clones, the arbitration rule is `git log -1 --format=%ct` on HEAD: newest wins silently. The pick is recorded; subsequent invocations read the registry and never re-elect. The other clones remain on disk untouched (no auto-prune, no auto-rename). Logs the pick to the install audit (line in stderr; not interactive).

**6. `/aih-install` skill — model-invokable (FR-13; orchestrator lock L2).** The new skill `pkg/.aihaus/skills/aih-install/SKILL.md` declares `disable-model-invocation: false` and ships under V5's user-global resolution layer. When the user types "install aihaus" or "instale aihaus" in any Claude Code session post-bootstrap, Claude invokes `/aih-install` directly — no compound prompts, no improvised `bash` commands. The skill body has 4 steps: resolve `AIHAUS_HOME`, detect dogfood mode, dispatch to `bash $AIHAUS_HOME/pkg/scripts/install.sh --target .`, confirm with one-liner. **This is the literal fix for contrarian F1** — the screenshot's failure was Claude unable to invoke `/aih-init` (which declares `disable-model-invocation: true`) and improvising an inconsistent install command. The new sibling skill is the structural answer.

**Z0 verification gating (orchestrator lock L1, binding).** Before Z1+ ships, Z0 runs an EXPERIMENT verifying (a) `~/.claude/skills/` resolution works on Windows native PowerShell, Git Bash on Windows, WSL2 (OQ #1) and (b) `~/.claude/hooks/` resolution works for user-global hook fragments (OQ #6). All-PASS unblocks; any FAIL routes Z3 to host-detection branches.

**Graceful degradation rule (orchestrator lock L4, binding).** If OQ #6 returns FAIL, **V5 still ships** — Z7 is conditional. The user-global hook fragment (`~/.claude/hooks/session-start-aihaus.sh`) is NOT dropped; skill-only priming via the model-invokable `/aih-install` is the documented fallback. SC-1 (user-global skill install), SC-2 (per-repo opt-in), SC-3 (≤1 user input) all remain satisfiable in either branch — `/aih-install` is reachable user-globally regardless of hook resolution.

**Copy-mode V5 implications (R9, FR-26).** When install runs in `--copy` mode (no symlinks; e.g., locked-down filesystems), the user-global skill install creates COPIES under `~/.claude/skills/aih-*`, not symlinks. `update.sh` (Z9) refreshes those copies on subsequent updates — otherwise edits to `pkg/.aihaus/skills/aih-help/SKILL.md` would not propagate user-globally on `--copy` installs.

**Cross-platform shape.** Unix uses POSIX symlinks. Windows native PowerShell uses `mklink /J` junctions; falls back to `mklink /D` (directory symlink) on cross-volume failure (R7); falls back to `--copy` if both fail. Git Bash on Windows uses `ln -s` with MSYS native-symlink semantics. Each fallback emits a clear stderr line naming the chosen strategy.
- Detect WSL2 via `WSL_DISTRO_NAME` env var; route to Linux-side `/home/<user>/.claude/skills/` when set. (D-Z0-A: Z0 verification confirmed WSL2 Linux home is a separate, uninitialized directory — Windows-side skills are not auto-discovered from WSL2; install.sh must target the WSL2 Linux home when running inside a WSL2 session.)

### Context

The friend's screenshot (`attachments/01-friend-install-friction.png`) shows ~36s of churn plus two yes/no confirmations on an install command Claude itself composed inconsistently — `bash /c/Users/perse/tools/aihaus/pkg/scripts/install.sh` against a clone Claude had just placed at `~/Documents/GitHub/aihaus-flow` (not `~/tools/aihaus`). The literal failure shape: Claude composed multiple half-decisions (clone to one path, then re-read README's recommendation pointing elsewhere, emitted contradiction, asked TWO compound prompts answered by one `s` keystroke, proposed `bash` against a path that DOES NOT EXIST). This is **Claude composing inconsistent compound decisions**, not "user lacked a verb" (CHALLENGES F1).

The brainstorm produced a synthesis-blocking discovery in Turn 6: V4 (`/aih-init` self-bootstrap) is **infeasible** because `~/.claude/skills/` exists as a real user-global skill resolution layer but contains zero `aih-*` skills today (analyst's direct probe; CHALLENGES F2). V4 cannot resolve in a fresh repo because `/aih-init` itself does not yet exist as a slash-command. V5 collapses the chicken-and-egg by moving the prerequisite from "per-repo skill availability" to "machine-once skill availability": after one `bash install.sh`, every `/aih-*` skill resolves from any cwd. This matches the friend's tool-shaped mental model exactly — "install once, use everywhere".

V5 is not invented from whole cloth: it inherits the architectural shape of rustup, mise, asdf, volta, pyenv, rbenv (advisor's survey of 10+ "central tool + per-project marker" precedents) — one global resolution layer + per-project marker file + two distinct verbs (install central, bind per-project). aihaus today only ships the second (`install.sh --target`); V5 ships the first.

Three brainstorm panel disagreements adjudicated in this ADR:
1. Verb = `install` (not `init`) — friend literally typed "instale"; npm/pip/gh precedent.
2. Hide the two-layer model — XDG default, `AIHAUS_HOME` override, README never names "Layer 1 / Layer 2".
3. `git clone` first-class; `curl|bash` deferred (security policy in companion ADR-260504-B).

### Options Considered

| # | Option | Pros | Cons | Why Not |
|---|--------|------|------|---------|
| A | V1 only — shell shim `aihaus`, no user-global skills | Minimal scope; portable; no Windows skill-resolution risk | Doesn't fix the friend's friction class — Claude inside the session still has no model-invokable install skill; "instale aihaus" still produces compound improvisation | Misses the literal F1 fix; CHALLENGES F1 unresolved |
| B | V3a only — user-global skills, no CLI shim | Solves F1; minimal new files | Power users without Claude Code in cwd have no shell verb; `aihaus update --all` impossible without shim | Loses the rustup/mise CLI shape; advisor §1 precedent ignored |
| C | V4 only — `/aih-init` self-bootstrap | Single slash-command UX | INFEASIBLE — verified Turn 6: `~/.claude/skills/` empty of `aih-*` today; `/aih-init` cannot resolve in fresh repo | CHALLENGES F2 hard constraint |
| D | curl\|bash to custom domain | One-line bootstrap | Inverts security surface for project shipping 5 bypassPermissions agents; domain ownership/transfer unaddressed | CHALLENGES F3; gated by ADR-260504-B; deferred M023+ |
| E | Two-layer mental-model preamble in README | Honest documentation | Band-aid for leaky abstraction; rustup/mise users never see central tool location; user mental model is tool-shaped | CHALLENGES F4; orchestrator lock L7 |
| F | MCP tri-scope vocabulary verbatim (`user`/`project`/`local`) | Users already know the words | MCP's own merge-vs-replace bug (#17299) makes vocabulary import a non-trivial cognitive cost | CHALLENGES F10; rejected |
| G | (Chosen) V5 — user-global skill install via bootstrap + CLI shim + model-invokable `/aih-install` + discovery priority chain + dogfood-mode branch + `.aihaus-managed` marker | Solves F1, F2, F4, F6, F8, F9 in one architectural pivot; matches rustup/mise precedent; preserves dogfood; deterministic chain; cross-platform with R7 fallback | Net-new ~14 fragment files + ~400 LOC scripts + 4 smoke checks + 2 ADRs; wide blast radius across install/update/uninstall + README + smoke | Highest leverage; dissolves the chicken-and-egg verified in Turn 6; matches friend's typed-input verb (`instale` → `install`) |

### Applicability Examples

**Worked example #1 — FITS the pattern.** A future maintainer adds a new skill `aih-foo` in `pkg/.aihaus/skills/aih-foo/`. On next `aihaus update` (or fresh `install.sh`), the user-global symlink loop picks up `aih-foo` automatically — no install.sh edit required. The `.aihaus-managed` marker is dropped on first creation; uninstall safety holds. Per-skill enforcement-audit fragment is added in the same milestone (Refresh Trigger (a) of ADR-260503-A); smoke Check 1 + Check 27 counts increment from 14 to 15. README install section line count and forbidden-language checks are unaffected (no README change required for a new skill). **Fits.** The V5 protocol's architectural invariants (deterministic chain, marker invariant, dogfood-mode branch, model-invocation policy) are all unchanged; the new skill is a pure extension via the symlink loop's universal-quantification over `pkg/.aihaus/skills/aih-*`.

**Worked example #2 — DOES NOT FIT (NLP arbitration).** A future maintainer wants aihaus to "auto-detect the user's intent across multiple aihaus clones via NLP" — e.g., parse the user's recent prompt history to decide which clone is the "preferred" one when `--package` is unset and multiple candidates exist. **Does NOT fit.** ADR-260504-A's pattern requires a *deterministic priority chain* — flag > env > registry > XDG > legacy paths, arbitrated by `git log -1 --format=%ct` when ambiguous. The moment arbitration becomes "model decides," the architectural guarantee dissolves: two consecutive `aihaus install` invocations could pick different clones based on prompt-history drift, breaking I-01 (single canonical clone) and I-03 (deterministic chain). This is the same eligibility gate inherited verbatim from ADR-260502-A "Worked example #2 — DOES NOT FIT" (decisions.md:1863): non-deterministic conditions belong in model-driven prose paths (e.g., a `/aih-install` Step 1.5 prose branch asking the user to pick), never in deterministic infrastructure. Correct answer: the multi-clone disambiguation prose lives in the `/aih-install` SKILL body, not in `install.sh`'s resolver.

### Consequences

**Positive.** The friend's friction class is structurally eliminated: V5 collapses the per-repo prerequisite into a machine-once primitive; Claude composing inconsistent compound install commands becomes architecturally impossible because `/aih-install` is model-invokable user-globally and dispatches deterministically. The 8-tier discovery chain handles every backward-compatibility case (legacy `~/tools/aihaus`, XDG, friend's two-clone state). The dogfood branch eliminates R3/R8 silent stomps. `.aihaus-managed` marker + readlink validation prevent collision-class incidents (R1, R4). Cross-platform R7 mitigation ships in Z4. The new model-invokable `/aih-install` skill is a semantically clean extension — `/aih-init` keeps its existing project.md-bootstrap meaning unchanged (NFR-03; I-11). README install section ≤30 lines + zero "Layer 1/Layer 2" language (FR-27/I-14) matches user mental model (rustup/mise precedent).

**Negative.** Net-new ~400 LOC across `install.sh` + `install.ps1` + 3 CLI shim files + new skill body + 1 enforcement-audit fragment + smoke Check 63 + 64 + regression harness. Wide blast radius: install / update / uninstall / session-start / README / CLAUDE.md / smoke / decisions.md all touched by M022. Z3 is the largest single-story commit (K-002 strict; cannot split). Windows native PowerShell parity (Z4) carries R7 cross-volume risk; verified mitigation but new failure mode if Developer Mode + admin both unavailable. The 14th SKILL bumps the M021 audit canonical baseline (smoke Check 1 + Check 27 13→14); future SKILL adds carry the same minor coordination cost.

**Neutral.** No changes to the `lib/junction-safe.sh`, `lib/merge-settings.sh`, `lib/restore-effort.sh` helpers (M015 / M008 / M009 inheritance). No changes to existing per-repo `.aihaus/` topology or symlink conventions. No changes to existing ADRs (260502-A, 260502-B, 260503-A all extend cleanly). Skill count goes 13 → 14; cohort taxonomy unchanged (`aih-install` joins existing skill-not-cohort taxonomy; cohort effort presets unaffected per ADR-M012-A).

### Threat Model

**R1 — user-global skill collision.** Mitigated by `.aihaus-managed` marker. Install refuses to overwrite unmarked dirs; `--force` only overrides on explicit user intent. Uninstall refuses to remove unmarked dirs.

**R3 — `update.sh` blind `git pull` over dogfood.** Mitigated by `is_dogfood_cwd()` predicate in `update.sh` (Z9) and `install.sh` (Z3) — same logic, both refuse `git pull` on dogfood cwd. R8 (self-update on dirty dogfood) extends with abort-not-stash.

**R4 — uninstall follows symlinks outside `AIHAUS_HOME`.** Mitigated by `readlink` validation: only remove if target resolves under registered `AIHAUS_HOME`. Refusal grammar binding (I-15).

**R5 — legacy `~/tools/aihaus/` users migration.** Mitigated by tier 5 of the discovery chain. No auto-relocation; legacy clone continues to work; `aihaus update` reads `.install-source`. README "Migrating" subsection (≤10 lines) documents.

**R7 — Windows `mklink /J` cross-volume failure.** Mitigated by volume-identity check + `mklink /D` fallback + `--copy` final fallback. Each fallback emits stderr line naming the strategy.

**R8 — `aihaus self-update` dogfood with uncommitted changes.** Mitigated by abort-not-stash semantics. Exit 3; clear "uncommitted changes — aborting" message. User stashes/commits manually; never aihaus's responsibility.

### Migration

Single-shot within M022. Strictly additive — no retroactive change to existing per-repo overlays. New: 1 SKILL dir + 1 audit fragment + 1 CLI shim + 1 user-global symlink loop in install.sh + 1 dogfood branch + 1 priority-chain resolver + 1 marker invariant + 1 conditional hook fragment (Z7) + 4 smoke checks + 1 regression harness + 4 fixture dirs + 2 ADRs. Modified-additively: install.sh, install.ps1, update.sh, update.ps1, uninstall.sh, uninstall.ps1, session-start.sh (cond.), enforcement-audit.md, smoke-test.sh (Check 1 + 26 numerics, then Checks 63 + 64), README.md, CLAUDE.md.

User repos that ran `bash pkg/scripts/install.sh --target .` before M022 see new files appear after the next `aihaus update`. No breaking change. Existing `/aih-init` byte-unchanged. Effort sidecar (`.aihaus/.effort`) preserved (NFR-07). DSP version-gate preserved (NFR-08). M020/S05 auto-close at session-start.sh:95-99 byte-unchanged (NFR-09 / I-08).

Legacy `~/tools/aihaus/` users: discovery chain finds them; `AIHAUS_HOME` pinned automatically via `.install-source`; no force-relocation. README documents in ≤10 lines.

### Rollback

Comment out the `install_user_global_skills()` invocation in `install.sh` (Z3 owns; one-line revert). Revert the `pkg/.aihaus/skills/aih-install/` directory and its enforcement-audit fragment. Revert the smoke Check 1 + 26 count update (14 → 13). The CLI shim files (`pkg/scripts/aihaus`, `.cmd`, `.ps1`) stay in tree (informational; no install.sh wire-up). ADR-260504-A stays accepted in commit history with Implementation Status marked "rolled back — see M022 retrospective."

User-global symlinks already created on user machines remain on disk; users who want to clean up run `bash pkg/scripts/uninstall.sh --purge-user-global` (Z8) — no functional regression. ADR-260504-B (companion) remains independently valid; rolling back V5 does not invalidate the security policy.

### Implementation Status

V5 protocol landed in M022. Custom-domain `curl|bash` shortcut deferred to M023+ pending ADR-260504-B's three ratification fields (named owner, named renewal cadence, named transfer protocol). Pre-install hook injection (Z7) is conditional on OQ #6 PASS — Z0 verification governs whether it ships in M022 or defers to a follow-up milestone.

The 8-tier discovery chain is locked in this ADR; future tier additions require an amending ADR. The `.aihaus-managed` marker shape (two-line `managed_by` + `source`) is locked. The dogfood-mode predicate (`is_dogfood_cwd`) is shared between `install.sh` and `update.sh` via the same shape (implementer may extract to `lib/dogfood-detect.sh` if reasonable; not required).

### References

- Scope: `.aihaus/milestones/M022-260504-install-flow-friction/PRD.md` (36 FRs / 10 NFRs / 14 SCs / L1-L10).
- Architecture: `.aihaus/milestones/M022-260504-install-flow-friction/architecture.md` (§2 component diagram, §3 invariants I-01..I-15, §5 cross-story dep map, §6 data model, §7 threat model + worked examples, §8 smoke Check 63+64 specs, §9 backout, §10 migration, §11 testing).
- Stories: Z0 (verification), Z1 (this ADR), Z3 (install.sh sole writer), Z4 (install.ps1), Z5 (CLI shim), Z6 (`/aih-install` + audit + smoke counts), Z7 (session-start cond.), Z8 (uninstall `--purge-user-global`), Z9 (update + dogfood guard + `--self`), Z10 (README), Z11 (CLAUDE.md), Z12 (smoke Check 63 + 64), Z13 (regression harness).
- Brainstorm: `.aihaus/brainstorm/260504-install-flow-friction/{BRIEF.md, CHALLENGES.md, CONVERSATION.md, PERSPECTIVE-architect.md, PERSPECTIVE-advisor-researcher.md, PERSPECTIVE-ux-designer.md, attachments/01-friend-install-friction.png}`.
- Companion ADR: ADR-260504-B (`curl|bash` security policy + custom-domain ownership requirements) — appended sequentially in Z2.
- Inherited ADRs: ADR-001 (filesystem state primitive — `pkg/.aihaus/decisions.md` early), ADR-260502-A (deterministic enforcement gate — `pkg/.aihaus/decisions.md:1804-1899`; Worked example #2 quoted in §Decision arbitration), ADR-260503-A (SKILL Enforcement Audit framework — `pkg/.aihaus/decisions.md:1986-2138`; Refresh Trigger (a) consumed by Z6).
- Outcome gates satisfied: SC-1 through SC-14.
- Friend's screenshot (canonical artifact): `.aihaus/brainstorm/260504-install-flow-friction/attachments/01-friend-install-friction.png`.

---

## ADR-260504-B — `curl|bash` security policy + custom-domain ownership requirements

**Status:** Accepted (requirements ratified); Implementation deferred to M023+
**Date:** 2026-05-05
**Milestone:** M022
**Extends:** ADR-260504-A (companion ADR; V5 protocol established `git clone` as the canonical install path; this ADR locks the security boundary around any future `curl|bash` convenience shortcut)
**Pattern:** Security-boundary ADR locking the minimum requirements (named owner, named renewal cadence, named transfer protocol) before any custom-domain `curl|bash` shortcut may ship; documents the security delta vs rustup attributable to aihaus shipping 5 `bypassPermissions` agents; `git clone` remains first-class and auditable indefinitely.

### Decision

**`git clone` is the first-class install path for aihaus in M022 and beyond, until and unless the three ratification fields below are populated and a domain is named in a successor ADR.** A `curl|bash` convenience shortcut to a custom domain (e.g., `aihaus.run`, `get.aihaus.dev`) is **not shipped in M022**; it is deferred to M023+ pending the three ratification prerequisites.

**Domain ownership requirements (binding before any custom domain ships):**

1. **Named owner.** Explicit individual or organization with registry-account ownership documented in `pkg/.aihaus/decisions.md` annex. The named owner is responsible for renewal payments and for executing the transfer protocol (#3) on org change or owner-departure. "GitHub user X owns the domain via Cloudflare Registrar account Y" is an example of a fully-named owner clause.

2. **Named renewal cadence.** Explicit frequency (annual, multi-year, auto-renew enabled), payment source documented (e.g., "billed to corporate card; auto-renew enabled; payment failure notifications routed to alerts@<owner>.com"), and renewal-window slack documented (e.g., "renewal triggers 60d before expiry; 30d hard floor before manual escalation").

3. **Named transfer protocol.** What happens on org change, owner-departure, acqui-hire, or sunset. Two-of-N options (escrow, backup-DNS-pointer, signed-Manifest-of-trust embedded in the package, or revocation procedure with 30d notice) MUST be documented. The rollback path to `git clone` MUST always work — the ADR explicitly preserves `git clone` as the regulated-environment fallback irrespective of any domain decision.

**Additional security requirements (binding for any future `curl|bash`):**

- TLS pinning + signature verification rustup-style. The bootstrap script MUST verify a signed manifest before executing any aihaus-supplied content.
- Commit SHA visible in install logs (matching `git clone` auditability — the user can always grep the install log for the exact commit checked out).
- Regulated-environment fallback: `git clone` ALWAYS works. No financial / healthcare / gov user is forced to trust a domain redirect.

**aihaus security delta vs rustup (binding context).** aihaus ships 5 `bypassPermissions` agents (per CLAUDE.md / ADR-M017): `implementer`, `frontend-dev`, `code-fixer`, `executor`, `nyquist-auditor`. These agents have `Bash`, `Edit`, `Write` tools wired to `permissionMode: bypassPermissions`. Compromising the install channel grants persistent code-execution capability inside any future Claude Code session via the user-global skill resolution layer (V5; ADR-260504-A). The security delta vs rustup is real: rustup ships a Rust toolchain (compiler + cargo + std) which is auditable post-install via `cargo audit` and well-known supply chain tools. aihaus ships `bypassPermissions` agents which are NOT enumerated in standard supply-chain tooling. **`git clone` preserves auditability via git commit SHA + signed-tag chain; opaque domain redirect does not.**

### Context

The advisor-researcher panelist recommended a dedicated short domain (`aihaus.run` / `get.aihaus.dev`) for `curl|bash` bootstrap as "future-proof against repo rename" and tagged it ASSUMED-but-high-confidence. The contrarian challenged on three grounds (CHALLENGES F3): (a) panel did not name the domain owner; (b) ownership-transfer / abandonment / re-registration risk is a real supply-chain attack vector (cf. NPM `event-stream`, real-world); (c) ≥30% of professional dev shops block `curl|bash` via egress firewall (financial, healthcare, gov regulated environments). For a project shipping `bypassPermissions` agents, the security delta vs rustup matters more than rustup's because aihaus has Bash/Edit/Write tools wired to bypassPermissions in 5 agents.

The brainstorm adjudicated (BRIEF Adjudicated position #3): `git clone` first-class; `curl|bash` opt-in convenience downstream, never primary. Domain ownership/transfer protocol must be documented in an ADR before any custom domain ships.

This ADR locks that adjudication and codifies the three minimum ratification fields. M022 ships `git clone` only — no domain procurement, no `curl|bash` script, no `aihaus.run` reference in the codebase or README. M023+ may register a domain after the three prerequisites are populated in a successor ADR; until then, the rollback to `git clone` is the only documented install path.

The recommendation also intersects orchestrator lock L3 (custom domain DEFERRED to M023+) and PRD's Out of Scope item 7 (custom domain procurement, registration, DNS setup all post-M022).

### Options Considered

| # | Option | Pros | Cons | Why Not |
|---|--------|------|------|---------|
| A | Ship `curl|bash` to `aihaus.run` first-class as primary install path | One-line user UX; matches rustup/mise precedent surface | Inverts security surface vs `git clone`; domain ownership unaddressed; ≥30% regulated environments blocked by egress firewalls; supply-chain attack vector via abandonment/re-registration; no signature verification ships in M022 | CHALLENGES F3 binding; rejected |
| B | Ship `curl|bash` to `raw.githubusercontent.com/<org>/aihaus-flow/main/install.sh` (no custom domain) | Auditable (GitHub-hosted; commit-pinned); no domain ownership concern; works in many regulated environments that allow GitHub egress | TLS terminated at GitHub; trust shifts to GitHub Inc.; URL doesn't survive repo rename; mid-fetch repo-takeover by malicious actor with merge access still a risk | Acknowledged as conditionally-OK alternative; not shipped in M022 because it adds a second documented install path before the security policy is ratified; M023+ may consider |
| C | Custom-domain-but-no-ratified-owner | Convenience available immediately | Unbounded supply-chain risk; no transfer protocol on owner-departure; rejected on first principles | Rejected; CHALLENGES F3 explicit |
| D | Inherit MCP tri-scope vocabulary (`user`/`project`/`local`) for install scope | Users already know the words from MCP | MCP's own merge-vs-replace bug (issue #17299) makes vocabulary import a non-trivial cognitive cost; aihaus uses verb-shaped commands (`install`, `update`, `self-update`) without inheriting MCP's scope vocabulary | CHALLENGES F10; rejected at the verb level (companion to ADR-260504-A's verb adjudication) |
| E | (Chosen) `git clone` first-class indefinitely; ratify three ownership requirements; defer domain procurement to M023+ | Auditable via git SHA; works in regulated environments; locks the security boundary explicitly; preserves option to ship custom domain later under named ratification | Misses the one-line bootstrap convenience until M023+; users must clone first | Highest leverage given aihaus ships 5 bypassPermissions agents; CHALLENGES F3 binding rationale; brainstorm Adjudicated position #3 |

### Applicability Examples

**Worked example #1 — FITS the pattern.** A future maintainer wants to add a `pkg/scripts/install-from-github.sh` bootstrap script that does `git clone` + `bash install.sh` in one command. **Fits.** The script ships in the repo (auditable); commits to it are signed via standard git workflow; install logs include the commit SHA. No custom domain. No `curl|bash` to opaque endpoint. The convenience is bounded by the same auditability as the canonical path.

**Worked example #2 — DOES NOT FIT (named owner missing).** A future maintainer registers `aihaus.run` personally + writes a 5-line `curl|bash` bootstrap that fetches `install.sh` from the domain. **Does NOT fit until ADR-260504-B's three fields are populated.** Even if the maintainer is the named owner, the renewal cadence and transfer protocol MUST be documented in a successor ADR or annex. Shipping the script before the protocol exists violates ADR-260504-B's binding rule. Correct path: write the successor ADR (named owner = `<maintainer>`; renewal = `annual; auto-renew; payment source `<billing>`; transfer = `escrow with 30d revocation notice`; signature = `Ed25519 with public key in pkg/.aihaus/SIGNING-KEY.pub`); then ship the bootstrap script.

### Consequences

**Positive.** Security boundary is explicit and binding. M022 ships zero `curl|bash` references; the friend (and every future user) has exactly one documented install path — `git clone` + `bash install.sh` — which is auditable via commit SHA and works in every regulated environment that permits git over HTTPS. The 5 `bypassPermissions` agents named explicitly in this ADR provide a concrete rationale for any future ratification debate; "we agreed to require named ownership because of `bypassPermissions`" is a firm anchor. Rollback to `git clone` is permanent — no future ADR can delete the `git clone` path; ADR-260504-B locks it as a regulated-environment fallback.

**Negative.** No one-line install convenience in M022. Users running `instale aihaus` in Claude Code today still benefit (model-invokable `/aih-install` resolves user-globally per ADR-260504-A) BUT users who want to install aihaus from a fresh shell on a new machine MUST type two commands (`git clone`, `bash install.sh`) instead of one. Marketing surface narrower than rustup's. Discoverability cost: README leads with two commands, not one — mitigated by the ≤30-line install section + IDEAL transcript shape (FR-27/FR-28).

**Neutral.** No code changes ship in M022 from this ADR — it locks a *requirement*, not an implementation. Companion ADR-260504-A drives the actual install changes. Future M023+ may ship a domain after ratification; until then, no codebase reference to any candidate domain exists.

### Threat Model

**Class 1: supply-chain attack via opaque domain abandonment / re-registration.** Mitigated by deferral — no domain ships in M022; ADR-260504-B's three ratification fields ensure any future domain has named owner + transfer protocol BEFORE shipping. ADR-260504-A's `git clone` first-class invariant is the permanent fallback.

**Class 2: ownership transfer on org change.** Mitigated by the named transfer protocol requirement (#3). Any future ADR shipping a domain MUST document the transfer protocol before merge.

**Class 3: corporate egress block on `curl|bash`.** Mitigated by `git clone` first-class indefinitely. Regulated environments (financial, healthcare, gov) that block `curl|bash` egress can install aihaus via standard `git clone` over HTTPS. ADR-260504-B preserves this path permanently.

**Class 4: TLS pinning / signature verification absent.** Acknowledged as binding requirement on any future `curl|bash` ship — rustup-style. M022 deferral means no script ships without these guarantees in M023+.

### Migration

N/A — no domain ships in M022. M023+ migration (if a domain is named in a successor ADR) is governed by that ADR; ADR-260504-B does not constrain the migration mechanics beyond the three ratification fields and the security requirements.

### Rollback

N/A — no domain ships, so no rollback target exists. ADR-260504-B remains accepted as a requirements gate; rolling back companion ADR-260504-A does not affect this ADR's status. If a future ADR ships a domain and is later rolled back, ADR-260504-B's `git clone` first-class fallback ensures continuity of installation.

### Implementation Status

Requirements ratified in M022. **No domain ships in v0.26.0.** No `curl|bash` script ships. README documents `git clone` + `bash install.sh` as the canonical install path. Future M023+ may register a domain after the three prerequisites are documented in a successor ADR (ADR-260504-B's ratification is binding before any successor proposes a `curl|bash` script).

The named-owner / renewal-cadence / transfer-protocol fields are NOT populated in M022 — populating them requires a successor ADR with explicit decision-maker sign-off. ADR-260504-B is intentionally a *requirements* gate, not a decision lock — the decision to ship a domain remains future-deferrable.

### References

- Scope: `.aihaus/milestones/M022-260504-install-flow-friction/PRD.md` (FR-32; NFR-06; SC-8; Out of Scope items 3 and 7).
- Architecture: `.aihaus/milestones/M022-260504-install-flow-friction/architecture.md` §4.9 (Brainstorm Key Disagreement #3 adjudication).
- Stories: Z2 (this ADR), Z10 (README documents `git clone` only).
- Brainstorm: `.aihaus/brainstorm/260504-install-flow-friction/{BRIEF.md (Adjudicated position #3), CHALLENGES.md (F3, F10), PERSPECTIVE-advisor-researcher.md (§2, §6, §9)}`.
- Companion ADR: ADR-260504-A (V5 global-skill-bootstrap protocol) — appended sequentially in Z1; defines the `git clone`-as-canonical install path that this ADR locks as permanent fallback.
- Inherited ADRs: ADR-001 (filesystem state primitive — preserved); ADR-M017-A (merge-back-as-script — context for `bypassPermissions` agent enumeration).
- Outcome gates satisfied: SC-8 (ADRs ratified); NFR-06 (security delta vs rustup documented).

---

## ADR-260506-A — Pause-Class Schema + GSP-DS Anti-Pattern Detection

**Status:** Accepted
**Date:** 2026-05-06
**Milestone:** M023
**Extends:** ADR-001 (single-writer manifest), ADR-M005-A (autonomy-protocol bound to all skills — **THIS ADR amends**), ADR-M011-A (paused as TRUE-blocker escape, F-02 worktree bypass), ADR-M014-B (resume substrate v4 gateway)
**Pattern:** Schema enum + fast-path regex extension + stranded-pause recovery UX as a tightly-coupled bundle closing the GSP-DS user-perceived assertiveness gap.

### Context

`/aih-milestone` runs feel less assertive than `/aih-feature` runs. The model self-pauses mid-execution at decomposition seams (Backend/Frontend, Wave 1/Wave 2, Batch A/Batch B), framed as virtue ("honesto sobre escopo," "preservar qualidade," "conversa muito longa"), then offers a recovery menu pointing at `/aih-resume`. None of these match the four TRUE-blocker classes in `_shared/autonomy-protocol.md`. We name this anti-pattern **GSP-DS (Graceful Self-Pause at Decomposition Seam)**.

**Critical empirical finding (A4 / contrarian F1, verified):** M022's RUN-MANIFEST is `phase: running / status: completed` end-to-end. `.claude/audit/hook.jsonl` contains zero `phase-advance --to paused` rows for M022. **The failing model never invokes `phase-advance.sh` at all** — it just emits prose and stops emitting tokens. The 94-min Z3→Z4 gap was bridged via `/aih-resume → Z4 dispatch` against a `running`-status manifest. This means the load-bearing fix for user-perceived behavior is the autonomy-guard regex pack (S02), not the schema enum (S01) — though both ship together to close the auditability gap and provide the M024+ enum slot.

### Decision

1. **`phase-advance.sh --class <enum>` is REQUIRED when `--to paused`.** 4-value enum: `{credential-missing, destructive-git-state, external-dep-down, user-invoked}`. `internal-contradiction` is RESERVED for M024+ adversarial gate (plan-checker writer). Validation is deterministic (case-membership) per ADR-260502-A.

2. **Operational definitions per class (closes the `external-dep-down` laundering surface, per CHECK F4):**
   - **`credential-missing`** — fits when a specific credential / env var / token is absent AND attempting to use it returns an unambiguous error. Negative example: model thinks credentials *might* be missing without testing.
   - **`destructive-git-state`** — fits when `git status` shows uncommitted work that would be destroyed by branch switch / reset / pull. Negative example: a clean tree with pending stories.
   - **`external-dep-down`** — fits when a NAMED EXTERNAL SERVICE (api.github.com, npm registry, etc.) returns an error AT INVOCATION TIME. **Negative examples (BLOCKED):** "Backend done; frontend dep on backend's contract" — backend/frontend decomposition is NEVER an external dep. "Migration depends on schema not yet built" — internal sequencing is NEVER an external dep.
   - **`user-invoked`** — fits when the user typed an explicit pause request in the current turn. Negative example: model inferred "user would want a pause here."

3. **`autonomy-guard.sh` MUST cover GSP-DS regex set** (13 PT-BR patterns + 1 modified threshold per S02; 24 total patterns post-M023). Haiku whitelist MUST include the GSP-DS counter-pattern (conversation-length, decomposition-seam disclaimers).

4. **`/aih-resume` MUST detect stranded-pause heuristic** (4 conditions: no paused audit row in 7 days + ≥2 unfinished stories + last progress within 24h + regex-match in `autonomy-gate.jsonl` within 60s of `last_updated`) and emit the recovery question (S03) — explicit classification, NOT A/B/C menu.

5. **Conversation length is NEVER a TRUE blocker.** Long context, "conversa muito longa," "preservar qualidade" framings are GSP-DS anti-patterns.

6. **Decomposition seams are NEVER TRUE blockers.** Backend/Frontend, Wave N/M, Batch A/B, Phase X/Y boundaries are stylistic decompositions, not blockers.

7. **`status: paused-user-input` (legacy M011 status enum value) is DEPRECATED post-M023** — prefer `status: paused + pause_class: user-invoked`. Pre-M023 manifests retain legacy shape; smoke is permissive (per CHECK F13). RUN-MANIFEST schema stays at v4 (additive).

### Consequences

**Enables:**
- Auditable pause classes — `pause_class` field allows post-hoc validation of every paused milestone.
- Mechanical GSP-DS detection — 13 PT-BR regex patterns at autonomy-guard fast-path.
- Cross-skill autonomy regex coverage — S02 lands in skill-agnostic `autonomy-guard.sh`, incidentally protecting `/aih-feature`, `/aih-quick`, `/aih-bugfix` (per CHECK F8).
- M024+ slot for `internal-contradiction` once an adversarial plan-checker writer-gate exists.

**Costs:**
- Extra hook flag complexity — `phase-advance.sh` gains `--class` argparse + enum validator.
- ~73% hot-path regex iteration growth (12→25 patterns) per CHECK F9. Latency adds ~5-10ms per Stop on Windows. Acceptable at current Stop frequency (~1/min).
- Regex maintenance burden — as decomposition vocabulary expands (e.g., "Etapa 1/Etapa 2", "Bloco A/B" not in M023 set), maintenance grows. Mitigation deferred to M024+ regex governance.
- Skill body growth — `aih-resume/SKILL.md` near 199-line ceiling.
- Haiku prompt grows ~80 tokens per CHECK F11 (~$0.0001/invocation; negligible).

### Migration

**Field-presence gate (NOT date-gate) per CHECK F5.** Existing v4 manifests with `status: paused` and no `pause_class` are PERMISSIVE: smoke Check 70 (audit-pair invariant) fires only on manifests where `pause_class:` field is **present** in `## Metadata` (post-M023 by construction). Pre-M023 manifests with `status: paused` and no `pause_class:` are skipped (legacy permissive).

This is **fork-portable across all install dates and time-stable.** M013/M014/M017 historical paused-events stay valid permanently. No `manifest-migrate.sh` changes; schema stays at v4.

### Rollback

Three opt-out env vars (emergency only):

- `AIHAUS_PAUSE_CLASS=0` — S01 hook bypass (accepts `--to paused` without `--class`; `pause_class` field omitted).
- `AIHAUS_AUTONOMY_HAIKU=0` — existing M011 toggle (skip haiku backstop).
- `AIHAUS_GSP_DS_REGEX=0` — S02 fast-path bypass (skips the 13 new PT-BR patterns; existing 12 — 11 original + 1 modified — still fire).

### Implementation Status

Lands in M023 (S01–S06). M024+ hosts:

- `internal-contradiction` enum addition once plan-checker adversarial-write gate exists.
- Active scope expansion of GSP-DS regex pack to `/aih-feature` and `/aih-quick` (F2 deferred).
- Regex governance / annex (F3 noise-budget governance deferred).

**Forward-link:** the M024 plan-checker writer-gate spec is a stub at `.aihaus/plans/260506-milestone-assertiveness/M024-FORWARD.md` — to be authored as M024 brainstorm.

### References

- ADR-001 (single-writer manifest)
- ADR-004 (Status projection from Metadata.phase)
- ADR-M005-A (autonomy protocol bound to all skills — **THIS ADR amends**)
- ADR-M011-A (paused as TRUE-blocker escape, F-02 worktree bypass)
- ADR-M011-B (statusLine — relevance per CHECK F10)
- ADR-M014-B (resume substrate, schema v3→v4 gateway)
- ADR-M017-A (merge-back hook)
- ADR-M019-A (autonomy-guard 14-field schema)
- ADR-260502-A (determinism gate)
- ADR-260504-A (V5 protocol)
- `_shared/autonomy-protocol.md` (the document THIS ADR amends in §"M023 invariants")

### Worked Example #1 — FITS

Model emits "credentials missing for `gh release create`, blocked. `GH_TOKEN` env var not set." → `phase-advance --to paused --reason "missing GH_TOKEN" --class credential-missing` → fits enum + operational definition (specific credential, unambiguous error attempt). Manifest gains `pause_class: credential-missing`; audit row at `.claude/audit/hook.jsonl` includes `"pause_class": "credential-missing"`; smoke Check 70 finds the audit pair within 60s of `last_updated` and PASSES. The `## Story Records` rows preserve their existing state for `/aih-resume` to pick up later when the user provides the credential.

### Worked Example #2 — DOES NOT FIT (caught at S02 regex layer)

Model emits "Honesto sobre escopo, paro aqui. /aih-resume continua de Z4." → autonomy-guard regex `GSP-DS-honest-scope` (`[Hh]onest[oa] sobre (escopo|qualidade)`) fires at fast-path → Stop blocked at exit 2. **NO `phase-advance` write occurs.** The block is detected at the autonomy-guard layer (S02), NOT the writer hook layer (S01). This is the canonical example of why S02 carries load-bearing user-perceived weight (per L1 binding): the failing model never reaches `phase-advance.sh`, so the schema enum at S01 alone would not have prevented user-felt pause. The audit trail lives in `.claude/audit/autonomy-gate.jsonl` as a `regex-match` decision row, NOT in `hook.jsonl`.

### Worked Example #3 — DOES NOT FIT (laundering attempt — caught at S05 Check 70b)

Model emits `phase-advance --to paused --reason "Backend dep on Frontend, frontend not built yet" --class external-dep-down`. The `external-dep-down` class does not fit per §Decision item 2 negative examples (backend/frontend is NEVER an external dep; internal sequencing is NEVER an external dep). Detection paths (defense in depth):

1. **S02 regex layer** — `GSP-DS-domain-split-frame` (`tratar o (frontend|backend) como`) fires on the reason text if it appears in adjacent prose (block at exit 2 BEFORE the write happens).
2. **S04 ADR documentation** — §Decision item 2 negative examples make the laundering shape explicit; ADR text is binding for human + plan-checker review.
3. **S05 Check 70b** — post-write smoke check greps `pause_reason` text for `(backend|frontend|wave|batch|phase [0-9])` and FAILS if matched. Provides a backstop when S02 regex misses adjacent prose and the model successfully writes the laundered class.

This three-layer defense (S02 regex + S04 docs + S05 smoke) closes the F4 laundering surface without requiring an adversarial writer-gate (the M024+ deferral).
- bypassPermissions agent inventory (5 agents): `implementer`, `frontend-dev`, `code-fixer`, `executor`, `nyquist-auditor` — per CLAUDE.md "Editing Skills and Agents" section + ADR-M017 context.

---

## ADR-260507-A — Milestone Workflow-Shape Parity + Auto-Improve Structural Enforcement

**Status:** Accepted
**Date:** 2026-05-06
**Milestone:** M024
**Extends:** ADR-001 (single-writer manifest), ADR-M005-A (autonomy protocol bound to all skills — **THIS ADR amends**), ADR-260506-A (M023 GSP-DS — composition rule explicit)
**Pattern:** Skill-prose excision composes with byte-identical runtime regex preservation; consumer-self-validating gate replaces producer wiring; post-hoc smoke detection of completion-protocol audit-pair invariant; install-layer hotfix bundle.

### Context

`/aih-milestone` runs feel less assertive than `/aih-feature` runs for the same task class. Brainstorm panel quantified: milestone-skill surface 5-6× feature-skill surface (1256 vs 199 lines); 14-story milestones carry 28-42 turn-boundary ritual beats vs features' 1. Named pattern: **PSRS — Per-Story Ritual Stack**. M023 fought GSP-DS prose at the autonomy-guard layer; M024 reduces the structural cadence pressure that produces it. User framing locked: a milestone is just a feature with more tasks — same workflow shape, just N implementation steps.

Bundled with two production hotfixes from 2026-05-06 dogfood:
- **Concern B:** `install.sh` + `install.ps1` user-global path-doubling. `install_user_global_skills "${PKG_ROOT}"` where `PKG_ROOT=repo/pkg` → scans `repo/pkg/pkg/.aihaus/skills` (never exists). Fresh `git clone` install on `moviemaker` repo failed; user manually junctioned to recover.
- **Concern C:** skill duplication in autocomplete — `/aih-plan (user) + /aih-plan (project)` both register. Per-repo `install.sh --target` always junctions `.claude/skills/aih-*` even when user-global already provides them.

Plus auto-improve structural-enforcement gap (Concern A): `.claude/audit/curator-apply.jsonl` last entry M019 despite M020-M023 completed; protocol exists in skill prose but isn't structurally enforced — auto-improve silently disabled since M020.

CHECK round (plan-checker REVISE) absorbed 3 BLOCKERs inline: F1 producer-wiring → consumer-self-validating gate; F2 sequence-trap → grace-window; F3 monolithic data-ops → S05a/b split. F5 reword: Check 72 is post-hoc detection (offline observability), NOT runtime gating.

### Decision

1. **Workflow-shape parity prose surgery.** `pkg/.aihaus/skills/aih-milestone/annexes/execution.md` excises Wave/Group structural nouns at 5 substitution sites; runtime regex (`autonomy-guard.sh:73`) preserved byte-identical. M023 + M024 compose at runtime.

2. **3-way `--plan <slug>` short-circuit gate at Step E3.** Three conjuncts, H-level permissive: (a) OQ-resolved (`^##+\s*Open Questions(\s|\(|$)`); (b) architecture-coverage (`## Architecture` H2 OR `architecture.md` OR ADR slug-ref); (d) story-table H-level + ≥1 row. **Consumer-self-validating** (CHECK F1 fix): consumer reads on-disk CHECK.md SHA at gate-time via `git log -1 --format=%H -- .aihaus/plans/<slug>/CHECK.md`; no producer wiring. Fail-closed default.

3. **Skipped-planning scaffolding: 3 stub files** (`analysis-brief.md`, `PRD.md`, `architecture.md`) with skip-marker citing upstream plan path. Six production-path consumers depend on them (`context-inject.sh:478-485`, `role-defaults.json:8/14`, `context-curator.md:46`, `statusline-milestone.sh:128`, `aih-update/SKILL.md:145`, `aih-resume/annexes/legacy-mode.md:66-68`). NO `CHECK.md` stub.

4. **Per-repo skill-junction conditional.** `install.sh` + `install.ps1` skip `.claude/skills/aih-*` junction when user-global already provides them (sentinel: `~/.claude/skills/aih-init`). Opt-out: `--force-project-skills` (Bash) / `-ForceProjectSkills` (PowerShell) / `FORCE_PROJECT_SKILLS=1` env.

5. **install.sh + install.ps1 path-doubling fixed.** `install.sh:474+480` and `install.ps1:1010+1020` use `${AIHAUS_RESOLVED}` (not `${PKG_ROOT}`). Dogfood callsite `install.sh:279` preserved byte-identical.

6. **Smoke Check 72 — completion-protocol audit-pair invariant.** Detects post-hoc that `phase-advance.sh --to complete` was called for a milestone without a corresponding `.claude/audit/curator-apply.jsonl` row. Field-presence gate: skips manifests lacking `status: completed + phase: complete`; M0XX format gate skips pre-canonical slug-prefixed manifests; numeric-threshold gate skips pre-M020. Grace-window for currently-running milestone (`git branch --show-current`) prevents M024 self-completion sequence trap. **Honest framing:** offline observability, NOT runtime gating; `phase-advance.sh` has zero hook into `smoke-test.sh`. Classification: primary=A model-driven.

7. **`## Reserved Forbidden Prose Tokens` H2** in execution.md citing `autonomy-guard.sh:73`. Names M024-excised tokens (Wave 1, Wave 2, Group N/2, Story Group N) AND M023 seam-decomposition catalog. Sustaining context for maintainers.

### Consequences

**Enables:** PSRS beat reduction 28-42 → ~8-12 per 14-story milestone; auto-improve substrate gap closed structurally; production fresh-install path repaired; autocomplete duplication eliminated when user-global skills present.

**Costs:** regex/skill-prose drift maintenance via §M024 invariants; +1 smoke check (offline observability surface; no runtime cost); one-time data-ops backfill for M020-M023 amortized in S05a/b; 3-stub staleness risk (write-once); F3 task-fraction laundering ships **prose-only** mitigation (M025+ may add regex if dogfood detects).

**Neutral:** Schema stays v4 (no migration). Existing `aih-milestone --execute` calls unaffected.

### Migration

Schema stays v4. Existing manifests grandfathered via field-presence + M0XX-format + numeric-threshold gates. M020-M023 backfilled by S05a/b. M024+ milestones receive curator-apply rows at end-of-milestone via Step 3.5.

### Rollback

Three opt-out env vars (all preserved from prior milestones; **NO new opt-outs introduced**):
- `FORCE_PROJECT_SKILLS=1` — S02 skill-junction conditional override.
- `AIHAUS_GSP_DS_REGEX=0` — M023 carryover.
- `AIHAUS_AUTONOMY_HAIKU=0` — M011 carryover.

### Implementation Status

Lands in M024 (S01-S07; 8 active stories — S05 split into S05a/b per CHECK F3; S03 fixture rebuild deferred to M025).

**M025+ deferrals:**
- Noun-substitution falsification experiment (M023 F7 carryover).
- Annex consolidation: fold execution.md (372 lines) back into SKILL.md.
- `internal-contradiction` enum re-introduction once adversarial plan-checker writer-gate exists.
- Autonomy-guard regex bundle for F3 task-fraction laundering if dogfood detects.
- `tools/test-install-flow.sh` Case 1 fixture rebuild to production-mirror layout.

### References

- ADR-001 (single-writer manifest)
- ADR-004 (Status projection from Metadata.phase)
- ADR-M005-A (autonomy protocol — **THIS ADR amends**)
- ADR-M011-A (state gate / paused-as-TRUE-blocker escape)
- ADR-M013-A (knowledge-curator + orchestrator-applies)
- ADR-M014-B (resume substrate, schema v3→v4 gateway)
- ADR-M016-B (per-agent memory)
- ADR-M017-A (merge-back hook)
- ADR-M019-A (RUN-STATUS projection)
- ADR-260502-A (determinism gate — Check 72 enforcement-audit classification)
- ADR-260504-A (V5 protocol — `AIHAUS_RESOLVED` is V5-canonical)
- ADR-260506-A (M023 GSP-DS — direct predecessor)

### Worked Example #1 — FITS

`/aih-plan` produces complete PLAN.md with OQs all `[DEFERRED]`/`[RESOLVED]` + `## Architecture` H2 + Story breakdown table + CHECK.md committed. `/aih-milestone --plan <slug>`: E3 short-circuit detects flag, gate PASSES, orchestrator creates 3 stubs, audit row written, dispatches Step E4 directly (skips analyst/PM/architect/plan-checker spawns).

### Worked Example #2 — DOES NOT FIT (gate fails)

PLAN.md contains 3 OQs without `[STATUS]` tags. Conjunct (a) FAILS. Orchestrator falls back to full Step E3 pipeline. NO stubs created. Behavioral parity with today's full-pipeline path.

### Worked Example #3 — Partial fail mode (CHECK absence-#5)

CHECK.md staged but NOT committed. `git log -1 --format=%H -- CHECK.md` returns empty → gate refused (gate-untrustworthy). Fall back to full E3. **Fail-closed (safe default).** Recovery: `git commit`, re-invoke; gate evaluates fresh on Worked Example #1 path. Honors ADR-260502-A determinism gate principle.

---

## ADR-260508-A — LSDD Extension + Phase 0 Verification + Linear-Default Invariants

**Date:** 2026-05-07
**Status:** Accepted
**Milestone:** M025-260506-linear-exec-noun-extension

### Context

Two concerns surfaced post-M024 v0.28.0 from a different project's M002 dogfood (screenshot evidence): (1) user expressed linear-execution preference ("default do milestone é linear"); (2) the model emitted "Phase B complete", "Round 1 paralelo", "23/30 done", "Sigo Round 1 (4 paralelo)?" — exactly what M024 contrarian F7 predicted. M024 excised Wave from skill prose; the model substituted Phase nouns from the agent template surface (`roadmapper.md` L64-83) which M023+M024 left untouched. The named pattern is **LSDD — Lexical Substitution at Decomposition Drift** (analyst R1 nomenclature). This ADR closes the substitution-operator's source surface + extends the autonomy-guard runtime denylist + introduces a Phase 0 verification gate pattern.

### Decision

**4 §Decision invariants (I1-I4):**

#### I1 — Linear-default at story-loop layer

The L353 invariant in `pkg/.aihaus/skills/aih-milestone/annexes/execution.md` ("complete each story's full cycle ... BEFORE spawning the next story's teammate") is the canonical M025 invariant since M017 — verified at S00 via documentary evidence (M023 + M024 commit logs show monotonic per-story commits, zero batched-parallel sha lineage). **No `--parallel` flag introduced** (S00 Branch A). The token `AIHAUS_PARALLEL_EXEC` is reserved for M026+ if dogfood ever reproduces story-level fan-out under future conditions; introducing it requires accompanying ADR amendment. S00 Branch B (flag plumbing) remains an option for M026; S00 Branch C (ambiguous outcome) defaults to Branch A + records OQ for M026 follow-up dogfood with broader fixture matrix.

#### I2 — LSDD 16-pattern reservation (all anchored to CADENCE_VERBS)

`pkg/.aihaus/hooks/autonomy-guard.sh` LSDD heredoc (gated by `AIHAUS_LSDD_REGEX=0` env opt-out). 16 patterns total:

- **5 EN cadence-noun:** Phase letter, Phase numeric, Round, Stage, Tranche
- **5 PT-BR cadence-noun:** Etapa, Bloco, Fase, Rodada, Seção (`Se[çc][ãa]o` for ç/c + ã/a normalization)
- **1 Sigo-question:** `[Ss]igo (Round|Rodada|Phase|Fase|Etapa|Bloco|Stage|Tranche)( [0-9A-Z]+)?\?`
- **5 task-fraction laundering:** `[0-9]+/[0-9]+ (stories|tasks)`, `Progress: x/y done`, `x stor(y|ies)`, `x of y`, `x task[s]`

**Substrate-conflict resolution (per plan-checker F-CRIT-1+F-CRIT-3):** every cadence-noun pattern anchors to completion-prose verb-set on the same line via `.*(complete|completa|completo|done|paralelo|seguir|working|remaining|shipped|finalizada|finalizado|pronta|in progress)`. Without anchoring, bare patterns would fire on autonomy-protocol §M023 catalog at L147+L487 ("Etapa/Bloco/Fase/Phase X/Y" enumeration as legitimate decomposition seams) AND on ~30+ legitimate `## Phase N` H2 headers in skill prose at runtime emission (`aih-brainstorm` Phase 1, 1.5, 2, 3, 4, 5, 6, 7, 7.5, 8; `aih-bugfix`, `aih-feature`, `aih-init`, `aih-plan`, `aih-effort`).

**Onda DROPPED** per F1 BLOCKER absorption (analyst R2's restoration was decorated with a fabricated mandate citation; no technical merit).

**Known-uncovered substitution slots (per F7 — mechanical M026 trigger):** Tier, Cycle, Iteration, Sprint, Slice, Pass, Bucket, Cohort, Greek-letters (α/β/γ). If `.claude/audit/autonomy-gate.jsonl` records a haiku-backstop block within 30 days post-M025 release on prose containing any of these tokens, M026 brainstorm SHALL extend the LSDD pack with anchored regex for the offending token. Mechanical, not aspirational.

#### I3 — Agent-template excision (roadmapper.md only)

Cadence nouns excised from `pkg/.aihaus/agents/roadmapper.md` L64-83 (4 occurrences in 1 file): "Phase 1: {Name}" / "Phase 2: {Name}" / Coverage Matrix `| REQ-001 | Phase 1 | SC-1.1 |` → **"Delivery 1: {Name}" / "Delivery 2: {Name}" / `| REQ-001 | Delivery 1 | SC-1.1 |`** (per plan-checker F-HIGH-7 — "Delivery {N}" avoids the `/aih-milestone` skill-name semantic collision that "Milestone {N}" would create, and is uncovered by F7 LSDD slots). The substitution operator's source surface treated.

**Explicitly out-of-scope (per plan-checker F-CRIT-2):** `pkg/.aihaus/agents/brainstorm-synthesizer.md` Round 1/Round 2 references at L32/L61/L86 are load-bearing 2-round panel mechanics + system-wide `*-r2.md` filename convention; preserved intentionally. Excising would break the synthesizer's input-spec contract.

**Explicitly out-of-scope (per ASSUMPTIONS A1.1):** `pkg/.aihaus/agents/eval-auditor.md:37` + `pkg/.aihaus/agents/eval-planner.md:40` step-headers (skill-step framing, not orchestrator-read templates). M026 follow-up if S00 dogfood reveals propagation.

#### I4 — M027 architectural decision deadline (mechanical semantic-gate, NOT declarative theater)

Smoke Check 76 fails iff a `^## ADR-NNNNNN-X` block in `pkg/.aihaus/decisions.md` satisfying **all three** is absent: (a) `**Date:** YYYY-MM-DD` line present; (b) body contains at least one keyword from `{denylist-extension, haiku-classifier, whitelist-on-cadence}`; (c) body contains `**Status:** Accepted` (NOT `Rejected` / `Deferred` / `Proposed`) within the same ADR block. The `Status: Accepted` requirement (per plan-checker F-HIGH-6) prevents "we considered X and rejected it" prose from passing the gate. Fixture-fail acceptance: 2 fixtures (missing-ADR + token-rejected) prove the check is not green-but-vacuous. **Replaces R2's declarative deadline theater** per CHECK F4.

### Migration

- **Existing manifests:** unaffected. RUN-MANIFEST stays at v4 (no schema bump).
- **Existing autonomy-guard:** the new LSDD pack is appended after the M023 GSP-DS heredoc with a distinct `LSDD_EOF` terminator. M005 fast-path (11 patterns) + M023 GSP-DS pack (13 PT-BR patterns) + M025 LSDD pack (16 anchored patterns) = 40 active patterns total, composing byte-identical at runtime (per ADR-260506-A composition rule + ADR-260507-A workflow-shape parity rule).
- **Existing skill prose:** Wave/Group excisions from M024 (`aih-milestone/annexes/execution.md`) preserved byte-identical. New L353 invariant strengthening adds 1 sentence (Branch A — S01a). New `roadmapper.md` "Delivery {N}" template + cadence-noun substitution rationale block (S01b).
- **Existing F6 message (M023 §4c stranded-pause UX):** preserved byte-identical. M025 widening note added inline (`bash autonomy-guard.sh` round-trip exit 0 invariant binding) — extends §4c blockquote without exceeding 199-line cap.

### Rollback

- **`AIHAUS_LSDD_REGEX=0`** env opt-out skips the 16 new patterns; existing 24 (M005 11 + M023 13) still fire. Single-flip rollback.
- **revert `roadmapper.md`** edit restores "Phase {N}" template; LSDD substrate keeps anchored patterns (zero false-positive risk because L64-83 prose has no completion verbs on same line).
- **Smoke Check 76 fixture-fail tests** validate the gate before any rollback; if M027 ADR is rolled back, Check 76 starts failing immediately, surfacing the regression mechanically.

### References

- ADR-001 (single-writer files-as-state)
- ADR-M005-A (autonomy protocol — RESOLVED via canonical-vocabulary protection in §M025 amendment; anchoring strategy preserves L147+L487 catalog)
- ADR-M011-A/B (autonomy state gate + statusLine)
- ADR-M017-A (merge-back per-story commits)
- ADR-M017-C (same-file rule — split S01 → S01a + S01b per F-CRIT-4)
- ADR-260506-A (M023 GSP-DS — direct predecessor, composes byte-identical)
- ADR-260507-A (M024 workflow-shape parity — direct predecessor, composes byte-identical)

### Worked Example #1 — FITS

Model emits "Round 1 paralelo: S22, S23, S24, S28" mid-execution. autonomy-guard.sh `LSDD-EN-Round` pattern matches (`[Rr]ound [0-9]+.*paralelo`). Stop hook returns `decision: block`. Orchestrator falls back to safer default per autonomy-protocol §TRUE-blocker test, logs choice in RUN-MANIFEST progress log, proceeds silently. No A/B/C menu surfaced.

### Worked Example #2 — DOES NOT FIT (legitimate seam catalog)

User pastes "Backend/Frontend, Wave N/M, Batch A/B, Phase X/Y, Etapa/Bloco" in a brainstorm conversation explaining the canonical decomposition-seam catalog. NO LSDD pattern fires (no completion verb on same line as cadence noun). NO false-positive block. Worked example invariant preserves the autonomy-protocol §M023 enumeration semantics.

### Worked Example #3 — Partial fail mode (uncovered slot)

Model substitutes "Tier 1 done" mid-execution (uncovered per F7). NO LSDD pattern matches (Tier not in 5 EN cadence list). autonomy-guard.sh hot-path passes; haiku backstop catches via the conservative JSON-out prompt OR M026 brainstorm extends the pack post-detection per the mechanical trigger in I2 §F7 inventory. Honest about the denylist arms-race; mechanical trigger converts admission into binding M026 work.

---

## ADR-260508-B — Brainstorm Artifact Actionability + Phase 6.5 Substrate Scan + Alt D OQ Schema

**Date:** 2026-05-08
**Status:** Accepted
**Milestone:** M026-260507-brainstorm-actionability

### Context

The brainstorm pipeline's BRIEF.md ends on `## Open Questions` (unresolved questions) followed by `## Suggested Next Command`. There is no section that commits the panel to a binding path-forward for each question raised. Empirical evidence across M023+M024+M025: plan-checker catches **3-4 CRITICAL BLOCKERs every PLAN**, BRIEF→PLAN line expansion runs **3.8×-4.3×**, and only **9-45%** of plan-checker BLOCKERs trace back to BRIEF Open Questions (per F1-VERIFICATION.md STRICT/LENIENT classification). Two layered defects: schema-level (Recommendations buried in Synthesis prose; consumers can't distinguish panel-bound decisions from deferred-to-plan) and substrate-level (synthesizer is fan-in, not substrate auditor; 55-64% of BLOCKERs are substrate-discoverable per F1-VERIFICATION).

The M026 brainstorm went 3 rounds (R1 + R2 + walk-backs); contrarian surfaced 12 findings (1 BLOCKER + 6 HIGH + 4 MEDIUM + 1 LOW); F1-VERIFICATION ratified 55-64% catch-rate; ASSUMPTIONS verified F5 BLOCKER (UX β option violates synthesizer constraints — must use PM Path B Option α); plan-checker REVISE absorbed 3 CRITICAL + 4 HIGH + 3 MED/LOW inline.

### Decision

**4 §Decision invariants (I1-I4):**

#### I1 — Alt D OQ sub-field schema (committed-contract amendment)

`brainstorm-synthesizer.md` BRIEF.md schema extended with per-OQ inline sub-fields:
```markdown
1. **<Question text>**
   - **Recommendation:** <single-classification path-forward; NOT A/B/C menu>
   - **Panel-Confidence:** H | M | L
   - **Defer if:** <criterion under which OQ defers to PLAN-time>
   - **Source:** <PERSPECTIVE-<role>.md:Lstart-Lend | CONVERSATION.md ## Turn N | pkg/.aihaus/<path>:Lstart-Lend>
```
**Forward-only schema bump** (no migration; legacy 9 BRIEFs remain schema-v1 per M023 field-presence-gate precedent). H/M `**Panel-Confidence:**` requires `**Source:**` citation grammar matching one of three regexes (Smoke Check 77 enforces). L Panel-Confidence may use prose attribution. **`**Confidence:**` renamed to `**Panel-Confidence:**`** — synthesizer cannot read substrate; "Panel-" qualifier makes scope explicit. Synthesis section ships `**Stance:**` markers per bullet (eliminates two-surface scanning per UX FM-8).

#### I2 — Phase 6.5 `--substrate` opt-in via assumptions-analyzer reuse

`/aih-brainstorm` Phase 6.5 (NEW between Phase 6 research + Phase 7 synthesis) spawned by opt-in `--substrate` flag (matches `--research` precedent). Catches **55-64% of CRITICAL BLOCKERs** per F1-VERIFICATION substrate-discoverable classification (regex case-shape, transcript coverage gaps, gate producer absence, autonomy-protocol catalog conflicts, Phase numeric ubiquity, brainstorm-synthesizer load-bearing refs). NOT first-order — **complements** plan-checker's adversarial-review domain (36-45% remaining BLOCKERs: enum loophole, sequence trap, scope explosion, K-002 ownership). assumptions-analyzer **reused** (NOT new agent build) per F7 — 80% of proposed sub-agent's spec already exists in agent's `## Output Format` (Confident/Likely/Unclear confidence + evidence-with-file-paths). Skill writes SUBSTRATE-FINDINGS.md from agent return (PM Path B Option α per F5 — preserves synthesizer single-file write scope + ADR-001 single-writer). SUBSTRATE-FINDINGS.md schema = assumptions-analyzer's existing output format (NOT extended).

#### I3 — Phase 7.5 sub-field validator (Smoke Check 77 + 2 fixture-fail tests)

Phase 7.5 schema validator extended with awk-based per-OQ block scoping (Check 76 `_check_m027_gate` analog). Validates Alt D fields presence + `**Source:**` grammar regex for H/M Panel-Confidence. Field-presence permissive: legacy schema-v1 BRIEFs (no `**Panel-Confidence:**`) skip sub-field check. Composes with existing 8-H2-headers check (compose, don't replace). 2 fixture-fail tests prove gate not green-but-vacuous: missing-recommendation.md (OQ#1 missing field) + source-prose-violation.md (H Panel-Confidence + prose-only Source attribution).

#### I4 — Panelist-template composed prompt rules (R1+R2 binding)

Phase 3 R1 + Phase 4 R2 panelist scaffolds gain mandatory sub-rules from `annexes/panelist-template.md`: (1) PM ground-check rule (citation grammar: `<file>:<line>` or `CONVERSATION.md ## Turn N`) + (2) UX argue-against rule (R2 must dissent OR emit `NO-R1-DISSENT-JUSTIFIED` fail-closed token) + (3) Alt D Recommendation discipline (R2 perspectives MAY end with `## Recommendations` for synthesizer aggregation). **Drops:** analyst's scope-dissent rule (redundant per analyst R2's own concession) + UX auto-R3 escape hatch (walked back per UX R2 — composed prompt eliminates need; hard cap stays 2 rounds).

### Migration

- **Existing BRIEFs (9 pre-M026):** unchanged. Field-presence-permissive gate skips sub-field validation when `**Panel-Confidence:**` absent. Legacy schema-v1 remains valid forever.
- **Existing autonomy-guard / SKILL surface:** unchanged. M026 adds opt-in flag + new annex files + thin SKILL.md references; pre-M026 invocations work unchanged.
- **Existing assumptions-analyzer contract:** unchanged. `## Output Format` byte-identical; only `## Input` section gained 1-sentence brainstorm-shape note.

### Rollback

- **`--substrate` flag absent** → Phase 6.5 skipped; brainstorm reverts to pre-M026 behavior.
- **Phase 7.5 sub-field validator failure on M026+ BRIEF** → field-presence gate skips legacy; canonical M026+ BRIEFs auto-validated with explicit error on missing fields.
- **Synthesizer schema rollback** → revert brainstorm-synthesizer.md amendments; legacy schema-v1 BRIEFs continue working; M026+ BRIEFs need re-synthesis.
- **Smoke Check 77 fixture-fail validation** ensures rollback paths surface immediately if mechanical gate degrades.

### References

- ADR-001 (single-writer files-as-state)
- ADR-003 (skill invocation marker)
- ADR-260507-A (M024 consumer-self-validating gate — BRIEF.md is consumer contract)
- ADR-260508-A (M025 LSDD pack — forward-only schema + mechanical-gate pattern precedent)
- ADR-M003-E (Disposition column / iteration policy default 1)
- ADR-M017-C (same-file rule — S1b+S2+S3 line-range disjointness within shared SKILL.md)

### Worked Example #1 — FITS

M027 brainstorm runs `--substrate`; assumptions-analyzer surfaces 4 substrate findings (3 Confident + 1 Unclear); skill writes SUBSTRATE-FINDINGS.md verbatim from agent return; synthesizer reads SUBSTRATE-FINDINGS.md as new input; binds 3 of 4 findings into Alt D Open Questions with H Panel-Confidence + file:line `**Source:**` citations; Phase 7.5 sub-field validator passes; `/aih-plan --from-brainstorm` consumes BRIEF.md mechanically; plan-checker REVISE finds 1-2 BLOCKERs (vs M025's 4-BLOCKER baseline).

### Worked Example #2 — DOES NOT FIT (default flow)

Brainstorm runs without `--substrate` (default off); no Phase 6.5; SUBSTRATE-FINDINGS.md absent; synthesizer's Phase 7 prompt's "if present" guard handles cleanly. BRIEF still ships Alt D schema (Phase 7.5 sub-field validator passes on Alt D OQ structure regardless of substrate-scan presence). Plan-checker behavior matches M025 baseline.

### Worked Example #3 — Partial fail mode

Brainstorm runs `--substrate`; assumptions-analyzer fails or returns malformed payload (no `## Assumptions` header). Skill catches failure (read-fail / schema-fail), writes minimal SUBSTRATE-FINDINGS.md with `(scan failed; see CONVERSATION.md)` body, logs error to CONVERSATION.md as substrate turn block. Synthesizer's "if present" guard handles cleanly — BRIEF still ships Alt D from R1/R2 inputs.

### Worked Example #4 — Legacy schema-v1 BRIEF compat

Consumer (`/aih-plan --from-brainstorm 260413-port-to-cursor-feasibility`) reads pre-M026 BRIEF.md without Alt D fields. Phase 7.5 sub-field validator detects `**Panel-Confidence:**` absent → field-presence permissive gate fires → validator skips OQ sub-field check, runs only existing 8-H2-headers check. BRIEF accepted; no false-positive failure on legacy artifacts. M027+ legacy BRIEFs continue working without re-synthesis.

### Worked Example #5 — Fabricated-citation rejection (M025 anti-pattern caught at synthesis layer)

Synthesizer emits OQ#1 with `**Panel-Confidence:** H` + `**Source:** "discussed by panel during R2 convergence"` (prose-only, no file:line). Check 77 grammar regex fails (no PERSPECTIVE-*.md / CONVERSATION.md Turn / pkg/.aihaus path match). BRIEF.md schema validation aborts with explicit `BRIEF.md at <slug> failed Source grammar — OQ#1 Panel-Confidence:H requires file:line citation`. M025 PM-cohort fabrication anti-pattern caught at synthesis layer (not just panelist layer).

## ADR-260509-V — `--substrate` tier-conditional default-on (M027/S6)

**Date:** 2026-05-08
**Status:** Accepted
**Milestone:** M027-260508-skills-agents-perf-review
**Supersedes:** ADR-260508-B I2 (opt-in `--substrate` flag — partial supersession; only the default-eligibility logic; rest of I2 preserved)

### Context

ADR-260508-B I2 introduced `--substrate` as an opt-in flag for `/aih-brainstorm` Phase 6.5, catching 55-64% of substrate-discoverable BLOCKERs per F1-VERIFICATION. Empirically, brainstorms invoked with `--research` or `--deep` (research-flagged tiers) carry higher BLOCKER density than default brainstorms — they typically explore new territory where substrate-divergence risk is highest. M027 dogfood evidence (analyst-brief §3 S6) supports flipping the default for the cohort that benefits most while preserving opt-in semantics for the lighter-weight default tier.

### Decision

`--substrate` defaults to **ON** when invoked under `/aih-brainstorm --research` or `/aih-brainstorm --deep`. Default brainstorms (no research-tier flag) remain opt-in (must pass `--substrate` explicitly to enable Phase 6.5).

New flag `--no-substrate` opts out, valid ONLY in combination with `--research`/`--deep`. Invoking `--no-substrate` without a research-tier flag produces an explicit error (`--no-substrate is meaningful only with --research/--deep; default brainstorms are already opt-in`).

Cost-cap recalculation: `--research --substrate` combo cost unchanged (was 14 max, remains 14 max — `--substrate` was already part of the worst-case combo). Default brainstorm cost cap drops by 1 (substrate-scan is no longer in the default-tier worst case).

### Options Considered

1. **Tier-conditional default-on (CHOSEN)** — flips for research tiers; preserves opt-in for default. Pros: ships catch-rate gain to cohort that benefits most; preserves backward-compat for users invoking `/aih-brainstorm` without flags; cost-cap gain for default tier. Cons: introduces second flag (`--no-substrate`) which expands the surface.
2. **Default-on for all tiers** — flips universally. Pros: simplest mental model. Cons: substantially raises default-tier cost cap; risks Goodhart's law (substrate-scan everywhere → noise overwhelms signal in low-stakes brainstorms).
3. **Status quo (opt-in everywhere)** — keep ADR-260508-B I2 unchanged. Pros: zero churn. Cons: catch-rate evidence under-utilized; users invoking `--research`/`--deep` are signaling high-stakes brainstorms but get default-off substrate.

### Rationale

Research-tier brainstorms are the cohort where substrate-discoverable BLOCKERs are most painful (they consume more rounds, attract more contrarian energy, and typically gate larger downstream commitments). Default-on within those tiers turns the catch-rate evidence into a behavior win without affecting low-stakes brainstorms.

### Consequences

- `aih-brainstorm/SKILL.md` Phase 6.5 logic flips at 2 sites (eligibility check + flag enumeration). Line-count budget preserved (≤199).
- Substrate-scan annex unchanged.
- New `--no-substrate` flag documented in SKILL.md + annexes.
- Cost-cap row in SKILL.md updated.
- ADR-260508-B I2 §Decision-block prose retains validity for the opt-in semantics; only the default-eligibility line is superseded.

### Rollback

- Revert `aih-brainstorm/SKILL.md` Phase 6.5 eligibility check to opt-in.
- Remove `--no-substrate` flag handler.
- Substrate-scan annex untouched (no rollback needed there).

### References

- ADR-260508-B (M026 substrate-scan introduction)
- analyst-brief §3 S6 (supersedence preferred over amendment)

## ADR-260509-W — `plan-calibrator` agent + adaptive-interrogator calibration-gate (M027/S5)

**Date:** 2026-05-08
**Status:** Accepted
**Milestone:** M027-260508-skills-agents-perf-review
**Anchored to:** ADR-260508-B Path B α (orchestrator-applies pattern), ADR-001 (single-writer), ADR-M014-B (resume classification framework)

### Context

Empirical evidence across M023+M024+M025+M026: plan-checker catches 3-4 CRITICAL BLOCKERs every PLAN, with only 9-45% tracing back to BRIEF Open Questions. M026 closed the BRIEF→PLAN absorption gap at the brainstorm layer (ADR-260508-B). The next layer down — PRD ↔ user business-rules divergence — remains a recurring blind spot. plan-checker verifies plan-achieves-goal but does NOT verify plan-encodes-user's-actual-business-rules. The pattern repeats: defaults applied without ask in PRD, gaps in analyst-brief, plan-checker CHECK.md flagging inconsistencies that a 60-second user confirmation would have prevented.

The brainstorm panel (M027 brainstorm 260508-skills-agents-perf-review) locked DECISION A: a new agent `plan-calibrator` runs adaptive interrogation AFTER plan-checker emits CHECK.md, conducts turn-by-turn confirmation with the user, and writes BUSINESS-RULES.md with source-line citations. Trigger: ambiguity-surface-detection. Stop condition: business-rules coverage exhaustion + user "no more questions" sinal. NEVER auto-stop heuristic.

### Decision

**New agent `plan-calibrator`** ships in `pkg/.aihaus/agents/plan-calibrator.md` with the 8-field frontmatter:

```yaml
---
name: plan-calibrator
description: Adaptive interrogator. Reads PRD + analyst-brief + architecture + CHECK.md, surfaces ambiguities (defaults applied without ask, gaps in brief, plan-checker inconsistencies), and conducts turn-by-turn confirmation with the user until business-rules coverage is exhausted or user signals "no more questions". Read-only — returns BUSINESS-RULES.md payload to parent skill.
tools: Read, Grep, Glob, Bash
model: opus
effort: max
color: red
memory: project
resumable: false
checkpoint_granularity: step
---
```

**Cohort:** `:adversarial-scout` (preset-immune; baseline opus/max). Post-S10 cohort fork: `:adversarial` with per-agent `effort: max` override.

**Trigger:** ambiguity-surface-detection — defaults applied without ask in PRD, gaps in analyst-brief, plan-checker CHECK.md inconsistencies. NOT story-count threshold. A trivial plan with no ambiguity skips natural — calibrator detects zero ambiguities and emits `BUSINESS-RULES-EXHAUSTED` after turn 1.

**Stop condition:**
- Explicit user signal ("no more questions" / "satisfeito" / "encerrar" / "stop") in turn, OR
- `--no-calibrate` re-invoked mid-flow (escape hatch), OR
- Calibrator emits `BUSINESS-RULES-EXHAUSTED` terminating token, OR
- Hard cap 30 turns (safety guard).

NEVER auto-stop heuristic.

**Pipeline anchor:** AFTER plan-checker emits CHECK.md. Calibrator verifies `git log -1 --format=%H -- .aihaus/plans/<slug>/CHECK.md` SHA against HEAD CHECK.md write-commit (idempotência per Risk R4 — same pattern as M024 short-circuit).

**Tools whitelist:** Read, Grep, Glob, Bash (Bash restricted to `git log -1 --format=%H` for SHA verification — NEVER `git apply`, `git checkout`, or shell-out to runners). NO `Write`, NO `Edit`. Output is a string payload returned to parent skill, which writes BUSINESS-RULES.md verbatim and applies PRD patches via `Edit` (orchestrator-applies pattern preserves ADR-001 single-writer).

**Resume classification:** `resumable: false` + `checkpoint_granularity: step` per ADR-M014-B. Adaptive interrogation has per-step state (turn N depends on user reply to turn N-1) that cannot be re-derived idempotently. Multi-cycle, similar to `debug-session-manager`.

**Scope-fence vs assumptions-analyzer (Risk R1 mitigation):** assumptions-analyzer is brainstorm Phase 6.5 only (per ADR-260508-B I2) — codebase-grounded; reads panelist-named files in `.aihaus/brainstorm/<slug>/PERSPECTIVE-*.md`. plan-calibrator is plan/feature/milestone post-CHECK.md only — conversation-grounded; reads CHECK.md inconsistencies + analyst-brief gaps + PRD defaults. Distinct trigger, distinct surface, distinct lifecycle. NO double-run because the brainstorm phase ends before the plan-checker phase begins.

**Single-session composition (HIGH #7 closure — `--from-brainstorm` path):** for the `/aih-brainstorm <slug>` → `/aih-plan --from-brainstorm <slug>` (or `/aih-feature --from-brainstorm <slug>`) single-session path, plan-calibrator MUST read `.aihaus/brainstorm/<slug>/SUBSTRATE-FINDINGS.md` (if present) BEFORE turn 1 and dedupe its question set against ambiguities already surfaced by assumptions-analyzer. This prevents the user from being asked the same question twice across the brainstorm Phase 6.5 → plan post-CHECK.md boundary. Implementation: calibrator's pre-turn-1 setup includes `Read .aihaus/brainstorm/<slug>/SUBSTRATE-FINDINGS.md` (file-not-found is non-fatal — calibrator proceeds with full ambiguity set if no substrate scan ran). The list of "already-surfaced ambiguities" is parsed from SUBSTRATE-FINDINGS.md `## Findings` section + cross-checked against the calibrator's own ambiguity-detection scan. The skill (parent) passes the brainstorm slug as part of the calibrator's invocation context.

**`--no-calibrate` flag** wired into `/aih-plan`, `/aih-feature`, `/aih-milestone --plan`. Audit-logged via `bash .aihaus/hooks/manifest-append.sh --audit calibration-skip --reason "<text>"` as conscious override.

**Skill integration sites (3):**
- `aih-plan/SKILL.md` — Step 7.5 (after plan-checker)
- `aih-feature/SKILL.md` — same anchor
- `aih-milestone/SKILL.md` — under `--plan` short-circuit; default skip when M024 3-way short-circuit fires (consistent with analyst/PM/architect skip), `--calibrate` opts in.

### BUSINESS-RULES.md schema (orchestrator-applies pattern)

```markdown
# Business Rules: <slug>

**Calibrator:** plan-calibrator
**Calibrated at:** <ISO-8601 UTC>
**CHECK.md SHA verified:** <7-char SHA>
**Turns:** <N>
**Stop reason:** user-no-more-questions | exhaustion | --no-calibrate-override

## Confirmed Rules

| # | Rule | Source-line in CHECK.md / PRD | Confidence |
|---|------|-------------------------------|------------|
| 1 | <single-classification rule> | PRD.md:L<n> or CHECK.md:L<m> | H/M/L |

## PRD Patches Applied

| # | File | Lines | Diff summary |

## Open Questions Promoted to PLAN-time

(Items where Defer-if criterion fired.)
```

### Options Considered

1. **New `plan-calibrator` agent (CHOSEN)** — clean separation, distinct cohort role.
2. **Reuse `contrarian` with new prompt mode** — rejected per CONTEXT.md DECISION A; semantic mixing breaks contrarian's adversarial-idea-challenger role.
3. **Reuse `assumptions-analyzer` with new input shape** — rejected; would conflate brainstorm-time codebase analysis with plan-time conversation-grounded interrogation.

### Rationale

Build-new is favored over reuse when scope-fence and trigger-fence diverge enough that conflation creates double-run risk (Risk R1). Calibrator's lifecycle (plan-time) and surface (CHECK.md inconsistencies) are disjoint from contrarian (brainstorm-time, panel artifacts) and assumptions-analyzer (brainstorm Phase 6.5, codebase). Three distinct agents with three distinct triggers prevents semantic drift and preserves audit-trail clarity.

### Consequences

- 1 new agent file in `pkg/.aihaus/agents/`.
- 3 SKILL.md edits (aih-plan + aih-feature + aih-milestone).
- 1 new artifact contract (BUSINESS-RULES.md).
- ADR-001 single-writer preserved (parent skill is sole writer).
- Risk R5 (testability) addressed via fixture-fail tests for ambiguity-DETECTION trigger only.
- Hard cap 30 turns prevents runaway interrogation.

### Rollback

- Delete `pkg/.aihaus/agents/plan-calibrator.md`.
- Revert 3 SKILL.md edits.
- BUSINESS-RULES.md is per-invocation runtime artifact — no schema migration concerns.

### References

- ADR-001 (single-writer)
- ADR-M014-B (resume classification: false + step)
- ADR-260507-A (M024 short-circuit gate; SHA idempotência pattern)
- ADR-260508-B (Path B α orchestrator-applies pattern)
- analyst-brief §3 S5 (scope-fence rationale)

## ADR-260509-X — Smoke Check 76 two-tier autonomy-guard (M027/S7)

**Date:** 2026-05-08
**Status:** Accepted
**Milestone:** M027-260508-skills-agents-perf-review
**Token:** `haiku-classifier`
**Resolves:** M025/ADR-260508-A I4 mechanical deadline (Smoke Check 76 forcing function)

### Context

M025/ADR-260508-A I4 introduced Smoke Check 76 as a forcing function: M027 must emit an ADR with `Status: Accepted` + `Date:` + a token from `{denylist-extension, haiku-classifier, whitelist-on-cadence}` in the same ADR block, or the gate stays inactive (offline observability per smoke-test.sh:3850-3859 awk parser).

The known-uncovered slots tracked by M025 (Tier/Cycle/Iteration/Sprint/Slice/Pass/Bucket/Cohort/Greek-letters) plus 30-day haiku-backstop monitoring of `.claude/audit/autonomy-gate.jsonl` produced empirical evidence: top-6 M005 patterns dominate 99.7% of regex hits (1427/1431); M023 GSP-DS + M025 LSDD packs (29 patterns) total 4 cumulative hits across the 30-day window. The pattern-arms-race-by-extension hypothesis (`denylist-extension`) is empirically uneconomical. The cadence-noun whitelist hypothesis (`whitelist-on-cadence`) cannot scale to LSDD-uncovered slots without re-introducing the false-positive class M025 anchored away.

The remaining viable path is `haiku-classifier`: a context-aware two-tier dispatch where the haiku backstop becomes primary in milestone-execution turns (where +600-900ms p95 latency amortizes against agent turns) and the regex fast-path remains primary in `/aih-quick` + PreToolUse paths (where pattern-match latency <50ms is the right tradeoff and milestone-state coupling is loose).

### Decision

`autonomy-guard.sh` is extended with a context-aware two-tier dispatch. The 40-pattern total (M005=11 + M023 GSP-DS=13 + M025 LSDD=16) is **frozen** at runtime — total locked, NOT per-pack. Per-pack env-gates (`AIHAUS_GSP_DS_REGEX`, `AIHAUS_LSDD_REGEX`) preserved.

**Two-tier dispatch:**

- **regex-primary** in `/aih-quick` paths + PreToolUse paths + idle/planning contexts. The 40-pattern walk runs first; on miss + opt-in haiku enabled, falls back to haiku backstop (M011 logic preserved).
- **haiku-primary** in milestone-execution turns (Stop hook fires AFTER an execution turn). Haiku classifier runs first via `claude --print --model haiku-4.5` with the existing CONTEXT.md §Q-3 prompt; on classify=block → block; on classify=allow → exit 0; on timeout/error → fall back to regex-primary 40-pattern walk.

**Dispatch fields (HIGH #9 + BLOCKER #5 amendment):**

`manifest_status` is an **8-value enum** per ADR-260502-A schema v4. Dispatch tier per status value:

| `manifest_status` | Tier route |
|-------------------|------------|
| `running` | haiku-primary (when `exec_phase="1"`) |
| `in-progress` | haiku-primary (when `exec_phase="1"`) |
| `null` | regex-primary (no active milestone state) |
| `paused` | regex-primary (terminal-pending state) |
| `complete` | regex-primary (terminal state) |
| `aborted` | regex-primary (terminal state) |
| `stopped` | regex-primary (terminal state) |
| `superseded` | regex-primary (terminal state) |
| `auto-closed-stale` | regex-primary (terminal state) |
| any unknown future value | regex-primary (default fail-safe) |

`exec_phase` is the **binary string** `"0"` (idle) or `"1"` (in execution) per existing `autonomy-guard.sh:294-300` printf. This ADR amends the dispatch logic to map `exec_phase="1"` (existing binary semantics) → milestone-execution tier route. **NO printf-format change** in autonomy-guard.sh — the 4185+ existing JSONL rows continue to parse identically. **NO parent-skill `AIHAUS_EXEC_PHASE=milestone-execution` env-string mandate.** The string `"milestone-execution"` is documentation prose describing the SEMANTICS of `exec_phase="1"`, NOT a wire value. This path is chosen over re-versioning the JSONL schema because the blast radius is smaller (zero changes to historical row parseability, zero parent-skill wire-contract changes).

Both fields are already present in JSONL rows; the empirical value distribution (1441/1441 rows of `exec_phase="1"`, zero rows of `exec_phase="milestone-execution"`) confirmed during plan-checker review prompted this clarification. Existing schema is preserved verbatim; dispatch semantics are documented to match.

**Opt-out env vars:**
- New `AIHAUS_AUTONOMY_TIER=regex|haiku|two-tier` ships with default unset → context-route. `AIHAUS_AUTONOMY_TIER=regex` forces regex-primary on every invocation.
- Existing `AIHAUS_AUTONOMY_HAIKU=0` preserved (disables haiku entirely on every path).
- Existing `AIHAUS_GSP_DS_REGEX=0` preserved.
- Existing `AIHAUS_LSDD_REGEX=0` preserved.

**M005 byte-identical preservation:** the 11 M005 patterns + their pattern strings + their match order are byte-identical at runtime. The only behavior change is the DISPATCH (which tier runs first); within regex-primary, the 40-pattern walk is unchanged.

**Pattern-arms-race halt:** total=40 frozen. Adding a new pattern requires a new ADR that explicitly amends ADR-260509-X. Per-pack env-gates remain (per-pack disable still permitted via env, additive only).

**Latency p95 retention:** ADR includes `haiku_p95_ms` retention review at 30-day burn-in. Target P95 600-900ms (per RESEARCH §1.5). If post-M027 30-day window shows p95 >1s consistently in milestone-execution turns, M028 hotfix flips `AIHAUS_AUTONOMY_TIER=regex` as install-default.

**JSONL schema extension (additive):** new field `tier_used` per row (regex|haiku|two-tier-fallback) + `haiku_p95_ms` when haiku invoked. Existing fields unchanged.

**Error-grammar (S3 verdict integration):** if S3's error-grammar audit returns **opaque** verdict, this ADR adds a `rephrase_suggestion` field obligation on haiku-classifier output (haiku must emit a 1-line rephrase suggestion when it classifies block). If S3 returns **clear/partial**, the field obligation is deferred to M028.

### Options Considered

1. **`haiku-classifier` two-tier dispatch (CHOSEN)** — context-aware. Pros: economical (only milestone-execution turns pay the +600-900ms p95); empirical evidence supports two-tier hypothesis (top-6 patterns 99.7%); preserves M005 fast-path byte-identical. Cons: dispatch logic adds ~80 lines to autonomy-guard.sh.
2. **`denylist-extension` (more patterns)** — REJECTED. M025 30-day data shows pack 2+3 (GSP-DS + LSDD) total 4 cumulative hits across 29 patterns. Adding more patterns is empirically uneconomical and entrenches the pattern-arms-race anti-pattern.
3. **`whitelist-on-cadence`** — REJECTED. Cannot scale to LSDD-uncovered slots without re-introducing the false-positive class M025 anchored away. Whitelisting cadence-noun headers risks regression on legitimate `## Phase N` H2 emissions.

### Rationale

Two-tier composes with the existing pattern packs without forking them. Latency cost is paid only where it amortizes (milestone-execution turns where agent turns are 30s-3min, not in `/aih-quick` paths where the user is typing fast). The 40-pattern freeze is the quid-pro-quo — pattern growth halted, classifier accuracy is the new lever.

### Consequences

- ~80 lines added to `pkg/.aihaus/hooks/autonomy-guard.sh` (existing 591 + dispatch prelude).
- 1 new env var (`AIHAUS_AUTONOMY_TIER`).
- CLAUDE.md autonomy-protocol section gains M027 paragraph documenting two-tier composition rule.
- `pkg/.aihaus/skills/_shared/autonomy-protocol.md` §M027 invariants section appended.
- Smoke Check 76 fires GREEN post-merge — the awk parser at smoke-test.sh:3850-3859 finds the `haiku-classifier` token + `**Date:** 2026-05-08` + `**Status:** Accepted` in this ADR block, satisfying the M025 forcing-function gate.
- 30-day burn-in monitors `haiku_p95_ms`; M028 hotfix path defined if p95 >1s.

**Honest framing (BLOCKER #1 path b — mechanical-vs-architectural distinction):** the awk parser at `tools/smoke-test.sh:3850-3859` is **token-presence permissive across the whole decisions.md file** — it walks `^## ADR-` blocks looking for any block carrying `Status: Accepted` + `Date:` + a token from the 3-set. Because ADR-260508-A (M025) §I4 enumeration prose contains the literal `haiku-classifier` token alongside its own `Status: Accepted` + `Date:`, the gate already fires GREEN against the existing decisions.md — Smoke Check 76 was **mechanically discharged at M025 merge**, before this ADR was even drafted. M027/S7 ADR-260509-X is therefore **architecturally additive** (it introduces the two-tier dispatch substrate that the M025 forcing function pointed at — context-aware regex vs haiku tier-routing, 40-pattern freeze, P95 retention review) but **mechanically redundant** for the gate itself. Tightening the awk parser to anchor the token to a `### Decision` heading or a `**Token:**` frontmatter line would close this parse-side-effect, but that requires editing `tools/smoke-test.sh` and is out of scope for M027. This ADR's load-bearing-ness is therefore the architectural substance (two-tier dispatch + 40-pattern freeze + audit-grammar extension), NOT the M025 gate-discharge claim. The PRD §Goals #2 prose is updated to reflect this honestly.

**Telemetry-contradicts fail-safe (HIGH #10):** if S1 telemetry shows GSP-DS or LSDD pack hit-rate >5% of total `regex-match` rows over the 30-day window, the empirical foundation of the two-tier hypothesis (top-6 patterns 99.7%, 4 cumulative GSP-DS/LSDD hits) is contradicted. In that case, S7-FINAL MUST be re-designed BEFORE commit. Possible re-designs: (a) `denylist-extension` per-pack tightening, (b) `haiku-classifier-with-pack-pruning` (haiku tier handles packs 2+3 only, regex handles M005 always), (c) deferred two-tier with M028+ scope. This ADR's commit explicitly waits for S1 closure; the parallelization of S7-spike with S1 (per architecture.md §Migration Strategy Phase 1) is a drafting/design overlap only, NOT an early commit.

### Rollback

- Revert ~80 lines in autonomy-guard.sh (the dispatch prelude).
- Revert this ADR.
- JSONL schema is additive (new field absence is field-presence-permissive).
- Smoke Check 76 reverts to its forcing-function pre-M027 state (silent — gate not yet active).

### References

- ADR-260508-A (M025 LSDD pack + Smoke Check 76 forcing function)
- ADR-260506-A (M023 GSP-DS pattern pack + opt-out env policy)
- M005 fast-path (autonomy-guard.sh L60-77; byte-identical preserved)
- analyst-brief §3 S7 (dispatch fields already present in JSONL)

---

## ADR-260509-Y — Cohort fork 6→5 + schema v4 migration (M027/S10)

**Date:** 2026-05-08
**Status:** Accepted
**Milestone:** M027-260508-skills-agents-perf-review
**Supersedes (partial):** ADR-M012-A (6-cohort taxonomy → 5-cohort)
**Rejects:** advisor `--router` opt-in (per locked DECISION C)

### Context

ADR-M012-A (M012/v0.17.0) introduced the 6-cohort taxonomy by splitting `:adversarial` into `:adversarial-scout` + `:adversarial-review` (preset-immunity carried by both). M027 brainstorm + RESEARCH.md §4.4 evidence shows: (a) the 2-member sub-distinction is more cleanly expressed as per-agent `effort:` overrides than as cohort baselines; (b) per-agent `effort:` frontmatter already exists across all 46 agents and is byte-identical to the 6-cohort baseline plus 2 overrides (plan-checker + contrarian carry `(opus, max)`); (c) the cohort layer is UX additive over per-agent role-based tuning per Anthropic published guidance.

Locked DECISION C in CONTEXT.md: cohort fork to 4 included in M027 wave 3, advisor `--router` opt-in REJECTED (conflicts with ADR-001 single-writer + auditable-spend story).

Locked OQ-OPEN-5 in PRD: schema v3 → v4 migration policy = `v4 + .effort.v3.backup + 1-milestone deprecation + abort-on-parse-fail`.

### Decision

**Cohort taxonomy forks 6 → 5** (5 cohort names — earlier prose said "6 → 4" which was a counting error per plan-checker Finding #12):

- `:planner-binding` (4 agents, opus/xhigh) — preserved (M015 carve-out load-bearing).
- `:planner` (13 agents, opus/high) — preserved.
- `:doer` (15 agents, sonnet/high) — preserved.
- `:verifier` (9 agents, haiku/high) — preserved.
- `:adversarial-scout` (2 agents) + `:adversarial-review` (2 agents) → **merged → `:adversarial`** (4 agents, opus baseline). Cohort-baseline effort = `high`. The `(opus, max)` profile for `plan-checker` + `contrarian` is preserved at the **per-agent override** level via `effort: max` in their respective frontmatter (NOT via cohort baseline).

**Per-agent `effort:` frontmatter authoritative.** cohorts.md becomes derivative — the table exists for human readability, but Smoke Check 6 validates against per-agent frontmatter as authoritative source of truth. If frontmatter and cohorts.md disagree, frontmatter wins.

**Schema v3 → v4 migration:**

- `update.sh --target .` writes `.effort.v3.backup` BEFORE migration begins. Atomic write — if backup write fails, abort with stable error grammar; do not touch v3 file.
- `:adversarial-scout.*` keys folded into `:adversarial.*` with cohort-baseline effort = `high`.
- `:adversarial-review.*` keys folded into `:adversarial.*` with no effort change.
- If both `:adversarial-scout.effort` AND `:adversarial-review.effort` exist in user `.effort` with conflicting values, the migrator emits a **conflict** error to stderr and **aborts** — does NOT silently pick one. User runs `update.sh --target . --resolve-cohort-merge <effort-value>` to confirm intent.
- Per-agent overrides preserved verbatim (parser does not re-cohort them).
- 1-milestone deprecation window: schema-v3 read-compat in `update.sh` preserved through M028; M029 `update.sh` removes v3 reader.
- **Abort on parse fail.** Any malformed key/value in v3 file → emit error, preserve original v3 file untouched, abort migration. NO silent drop.

**Preset-immunity preservation invariant (BLOCKER #2):** the v3 baseline `:adversarial-scout.effort = max` is silently demoted to v4 cohort-baseline `:adversarial.effort = high` during the cohort fold. Without compensating per-agent overrides, this regresses the preset-immune `(opus, max)` profile that motivated the original `:adversarial-scout` split (per cohorts.md "false-negatives catastrophic"). The migration MUST therefore preserve the per-agent `(opus, max)` profile via explicit per-agent override entries:

```
plan-checker.effort = max
contrarian.effort = max
plan-calibrator.effort = max   # new in M027/S5; joins :adversarial post-S10
```

Migration rules for these entries:
- If user `.effort` v3 already has these per-agent overrides → preserved verbatim into v4 (no warning).
- If user `.effort` v3 lacks one or more (relying on cohort baseline) → migrator INJECTS the missing entries on-the-fly with an INFO-level row in the migration log: `injected per-agent override <agent>.effort=max (preset-immunity preservation; v4 cohort baseline would have demoted to high)`.
- Smoke Check 6 sub-assert (added in S10): when an agent has `cohort: :adversarial`, validate that `{plan-checker, contrarian, plan-calibrator}.effort == max`. Failure → smoke test fails → migration is reverted.

This honors the architecture's "per-agent override preserved verbatim" prose at an enforceable level instead of an honor-system check.

**`tools/restore-effort.sh` map update (BLOCKER #2 — explicit):**

```bash
# v3 → v4 cohort name mapping
case "$cohort" in
  ":adversarial-scout"|":adversarial-review") echo ":adversarial" ;;
  *) echo "$cohort" ;;
esac

# Per-agent override preservation (binding):
# plan-checker.effort = max
# contrarian.effort = max
# plan-calibrator.effort = max
# These three lines MUST appear in v4 verbatim, regardless of whether v3
# carried them explicitly. The restore-script also inspects the input v3
# file and emits these lines if absent (defensive injection).
```

**Smoke Check 6 extension:**

- Cohort 5-set validated: `{:planner-binding, :planner, :doer, :verifier, :adversarial}` (5 cohort names — Finding #12 corrects "6 → 4" which was wrong by count).
- Per-agent `effort:` validated against cohort baseline OR per-agent override.
- **Preset-immunity preservation sub-assert (BLOCKER #2):** when an agent has `cohort: :adversarial`, validate that `{plan-checker, contrarian, plan-calibrator}.effort == max`. Failure indicates the v3 → v4 migration silently demoted the (opus, max) profile.
- `tools/smoke-test.sh` `_cohort_model_map` bash declare -A array at lines 244-250 patched: remove `:adversarial-scout`/`:adversarial-review` keys, add single `:adversarial` key with model=opus.
- 3 fixture-fail tests:
  (a) agent with cohort `:adversarial-scout` (legacy) → MUST FAIL.
  (b) agent with effort `ultraplus` (invalid enum) → MUST FAIL.
  (c) agent in `{plan-checker, contrarian, plan-calibrator}` with `cohort: :adversarial` AND `effort: high` → MUST FAIL (preset-immunity violation).

**`--router` opt-in REJECTED.** Advisor §4.4 proposed dynamic per-request classifier. Conflicts with ADR-001 single-writer + auditable-spend story (a runtime-routed model choice cannot be deterministically replayed from manifest). Not introduced. NOT to be re-proposed without an ADR amendment explicitly addressing the auditable-spend conflict.

**`install.sh` / `install.ps1` impact:** unchanged. The Windows regex `(?<cohort>:\w[\w-]*)` is opaque-parse — accepts any cohort token shape. Only `tools/restore-effort.sh` cohort-name map updates.

**CLAUDE.md cohort table:** rewritten to 5-cohort shape. M027 paragraph appended documenting the fork + per-agent `effort:` authoritative.

### Options Considered

1. **6 → 5 merge `:adversarial-scout` + `:adversarial-review` → `:adversarial` (CHOSEN)** — preset-immunity becomes one rule; per-agent override expresses the 2-member sub-distinction. Pros: simpler taxonomy; per-agent already exists; status-quo-codifying; Anthropic-aligned. Cons: 1 cohort name change in user-facing surface (CLAUDE.md + cohorts.md); migration required.
2. **Status quo (6 cohorts)** — REJECTED per locked DECISION C.
3. **6 → 5 (drop `:adversarial-scout`, leave `:adversarial-review`)** — REJECTED. Asymmetric. Loses the preset-immunity unification motivation.
4. **Advisor `--router` opt-in** — REJECTED per locked DECISION C; conflicts with auditable-spend.

### Rationale

Per-agent `effort:` frontmatter already encodes the granularity that the 6-cohort taxonomy was approximating. Merging to 4 simplifies the cohort layer to its natural role (rough cut by compute profile) while preserving the fine cut (per-agent override) where it matters. The `(opus, max)` profile for `plan-checker` + `contrarian` is preserved exactly via per-agent override.

The `--router` rejection is binding because dynamic per-request routing breaks the auditable-spend chain: `.claude/audit/autonomy-gate.jsonl` records the model used, but a router that re-decides per-request makes spend non-deterministic-from-manifest. ADR-001 requires deterministic replay from files-as-state.

### Consequences

- ~30-40 frontmatter edits across `pkg/.aihaus/agents/*.md` (only the 4 `:adversarial-scout` + `:adversarial-review` agents change cohort value; other 42 agents already declare correct cohort + effort).
- 1 `update.sh` extension (schema v3 → v4 migration logic).
- 1 `restore-effort.sh` map update.
- 1 cohorts.md regeneration (derivative).
- 1 CLAUDE.md update (cohort table + M027 paragraph).
- Smoke Check 6 extension (cohort 4-set + 2 fixture-fail tests).
- 1-milestone deprecation window for v3 reader (M028 retains compat; M029 removes).

### Rollback

- Schema v4 → v3 path via `update.sh --rollback-v4` (reads `.effort.v3.backup` + restores).
- Cohort frontmatter reverted per-agent.
- cohorts.md regenerated.
- CLAUDE.md cohort table reverted.
- This ADR reverted.
- 1-milestone deprecation window in update.sh keeps v3 reader active through M028 — rollback within the window is mechanical.

### References

- ADR-M012-A (6-cohort taxonomy — partial supersession)
- ADR-001 (single-writer; auditable-spend foundation)
- ADR-M014-B (per-agent frontmatter resume classification)
- locked DECISION C (CONTEXT.md `--router` rejection)
- analyst-brief §3 S10 (status-quo-codification + Smoke Check 6 extension)

## ADR-260509-Z — `enforcement-audit.md` consumer scope (M027/S5+S7 — resolves OQ-7)

**Date:** 2026-05-08
**Status:** Accepted
**Milestone:** M027-260508-skills-agents-perf-review
**Resolves:** brainstorm OQ-7 (enforcement-audit external consumers)

### Context

`pkg/.aihaus/skills/_shared/enforcement-audit.md` (293 rows post-M026) is referenced by ADR-260503-A move-rule and Smoke Check 62 scaffold check. Brainstorm OQ-7 surfaced the open question: does this audit have external consumers (third-party tools, dashboards, downstream packages) that warrant a Statement-of-Coverage promise + stable-format guarantee, or is it maintainer-internal?

Contrarian Finding #10 (M027 brainstorm) recommended deferring any external-consumer mandate; analyst-brief recommended maintainer-internal default with mini-ADR resolution.

### Decision

`pkg/.aihaus/skills/_shared/enforcement-audit.md` is a **maintainer-internal artifact**. Its consumers are:

- The maintainer running the move-rule check (per ADR-260503-A) when promoting A-rows to B/C.
- The smoke-test scaffold check (Check 62) when validating audit existence + structural shape.
- Future maintainer-driven refactors that re-classify rows during structural changes.

It does NOT carry an external-consumer mandate. It does NOT require a Statement-of-Coverage. It does NOT need to be documented for end users in CLAUDE.md beyond the existing reference.

### Rationale

The audit is a structural inventory used to decide whether A-rows promote to B/C. End-user-facing surface is the actual hook/skill behavior, not the classification table. Treating the audit as maintainer-internal preserves move-rule velocity (rows can be re-classified during refactors without external-consumer breakage anxiety) while keeping the eligibility-gate authority (per ADR-260502-A) intact.

### Consequences

- No external-consumer mandate; no Statement-of-Coverage obligation.
- Future audit edits remain mechanical (regenerate via `tools/audit-skill-reconcile.sh --concat`).
- If a genuine external consumer ever emerges (e.g., a third-party tool that reads the audit to build a skill-coverage dashboard), this ADR is amended explicitly in a new ADR — not silently extended.

### References

- ADR-260503-A (audit framework + move rule)
- ADR-260502-A (eligibility-gate authority)
- M027 brainstorm OQ-7 + Contrarian Finding #10 + analyst-brief §5

---

## ADR-260509-CURATE-A — Researcher consolidation overlap threshold (PARK rule)

**Status:** Accepted
**Date:** 2026-05-08
**Milestone:** M027 (curator pass)

### Context

S8 spike (PARK verdict) measured 7 researcher agents (phase, advisor, domain, ai, project, ui + research-synthesizer) at ~32% mean body overlap — far below the >70% threshold the spike PRD set as PROCEED-WITH-MERGE precondition. Shared content was structural scaffolding (stack-read, conflict-prevention, self-evolution, memory template) common to ALL 46 agents, NOT researcher-specific logic. Domain logic (210-380 unique words per agent) was genuinely divergent: different output schemas, input enums, downstream consumer contracts. advisor-researcher has no Write/Bash (in-context structured output), research-synthesizer is a downstream aggregator+committer (different pipeline stage), ui-researcher anchors a hard ui-checker contract (UI-SPEC.md).

### Decision

Adopt a binary >70% / PARK rule for any future agent-consolidation spike: cross-agent body-overlap below 70% means PARK regardless of telemetry confirmation. Telemetry alone (zero per-agent invocations) is insufficient justification for a merge — overlap measures the structural cost of preserving distinct contracts, telemetry only measures runtime tuning friction. Both axes must clear independently. Partial-merge candidates (e.g., phase-researcher + project-researcher at ~45% overlap, identical YAML, shared planner/roadmapper consumer family) require an explicit M028+ scoping decision and contract-impact analysis before any merge proceeds.

### Consequences

- Future spike PRDs can cite this rule rather than re-deriving the threshold.
- Researcher cohort frozen at 7 agents; codebase-mapper remains separate (different cohort/model/tools).
- M028+ partial-merge work is a deliberate, scoped story — not a side-effect of researcher tuning.
- The 70% threshold is REVISABLE — if a future milestone produces evidence that lower-overlap merges are viable (e.g., kind-dispatch refactor), the threshold can be amended via a successor ADR.

---

## ADR-260510-A — `testing_discipline` schema for `project.md` (M028/S1)

**Status:** Accepted
**Date:** 2026-05-09
**Milestone:** M028

### Context

M028 introduces TDD discipline as an opt-in user preference for aihaus clients.
The brainstorm `260509-tdd-aihaus-clients` + plan-checker surfaced that aihaus
currently has no mechanism for users to declare a testing methodology preference —
the `project.md` template captures stack details (language, framework, test
framework) but not process discipline (TDD, test-after, or none). Without a
machine-readable field, downstream enforcement (the `tdd-guard.sh` PreToolUse
hook — ADR-260510-C) and skill-level dispatch (Step 7.6 in aih-feature —
S3) have no authoritative source to gate on.

The PLAN (Decision D) established the enum shape after ruling out alternatives:
a Stack-table row was rejected because the Stack table is AUTO-GENERATED and
testing discipline is a process choice, not a file-system fingerprint that
aih-init can reliably detect. A new `## Practices` MANUAL section preserves
"user owns the choice" semantics (ASSUMPTIONS S2 + Alternatives §5).

### Decision

Introduce a `testing_discipline` field in `pkg/.aihaus/templates/project.md`
as the 10th H2 section (`## Practices`), within its own MANUAL block.

**Enum:** `tdd | test-after | none`

- `tdd` — implementer/frontend-dev prepend "draft a failing test before writing
  implementation" to their internal briefing; `tdd-guard.sh` PreToolUse hook
  active.
- `test-after` — implementer treats tests as required acceptance criteria but not
  pre-implementation; `tdd-guard.sh` inactive.
- `none` (default) — no test discipline change; `tdd-guard.sh` inactive; current
  behavior preserved for all existing installs.

**Template default:** `testing_discipline: none`

This preserves current behavior for all existing installs. No breaking change.

**Auto-detection at install time:** `aih-init` Step 9.5 runs heuristic detection
and seeds the value before writing `project.md`. Detection logic (full spec in
`aih-init/annexes/testing-discipline-detection.md`):

1. If `.tdd-discipline` marker file exists OR `tdd:` commit-message prefix
   found in last 30 commits → seed `tdd`.
2. If test directory (`tests/`, `__tests__/`, `test/`, `spec/`) AND framework
   declared in manifest (`package.json`, `pyproject.toml`, `Cargo.toml`,
   `go.mod`) → seed `test-after`.
3. Otherwise → seed `none`.

Auto-detection applies on FIRST RUN only. Re-run mode (Step 10b) skips
Step 9.5 entirely — the user's current value in `## Practices` is preserved.

### Rationale

- **Stack-agnostic:** `testing_discipline` is a process choice, not a
  file-system fingerprint. Keeping it in the MANUAL section and seeding via
  heuristics (not enforcing via AUTO-GENERATED) respects the user's authority
  over methodology decisions.
- **Opt-in preserves current behavior:** default `none` means zero behavior
  change for the ~100% of current aihaus users who have not declared a
  testing discipline.
- **Pairs field with consumer:** shipping the schema in S1 alongside the
  enforcement hook (S2) and skill dispatch (S3) avoids the "vestigial-by-design"
  anti-pattern the contrarian flagged in the brainstorm (CHALLENGES HIGH #4).
- **Self-eating-cake scope-fence (Decision G):** `testing_discipline` is offered
  to aihaus USERS working on application code. It does NOT apply to aihaus's own
  bash hooks/scripts, which are integration-tested via smoke-test, not unit-tested
  via bats. This honest scoping is explicit here to avoid user confusion (see
  ADR-260510-D for full scope-fence).

### Consequences

- `pkg/.aihaus/templates/project.md` gains a 10th H2 (`## Practices`) after the
  existing 9 sections.
- `aih-init` Step 9.5 (new) runs heuristic detection at install time; annex
  `aih-init/annexes/testing-discipline-detection.md` holds the full spec.
- Downstream consumers read `testing_discipline` at runtime from `project.md`
  (existing Stack-read pattern at `implementer.md:39-46`).
- Performance: `tdd-guard.sh` caches the value in env at session start
  (R4 mitigation from PLAN Risk Assessment — full spec in ADR-260510-C).
- `tdd | test-after | none` is the COMPLETE enum. Adding a new value requires
  a new ADR amendment to this ADR.
- Governance: each new structured key added to a MANUAL-block section of
  `project.md` requires a milestone-tagged ADR — see ADR-260510-B for the
  full governance rule.

### References

- M028 BRIEF/PLAN (`260509-tdd-aihaus-clients`) — Decision D (enum shape),
  Alternatives §5 (Practices vs Stack-table)
- ADR-260510-B — project.md structured-keys governance + sunset clause (S6)
- ADR-260510-C — `tdd-guard.sh` PreToolUse hook contract (S2)
- ADR-260510-D — TDD scope-fence / Surface 4 permanent rejection (S6)

## ADR-260510-C — `tdd-guard.sh` PreToolUse hook contract (M028/S2)

**Status:** Accepted
**Date:** 2026-05-09
**Milestone:** M028-260509-tdd-aihaus-clients

### Context

M028 ships TDD enforcement as a first-class aihaus primitive. The PLAN Decision A table
identified aihaus's hook architecture as the correct enforcement surface (CHALLENGES HIGH #6):
30 hooks already ship; the hook-level enforcement pattern is empirically stronger than
prose-level prescription per RESEARCH F5 (alexop.dev measured 20%→84% compliance jump with
hook-based enforcement vs documentation alone).

Two blockers required pre-commit resolution:

**BLOCKER #1 (aih-quick bypass):** The original design used a `MANIFEST_PATH` active-skill
marker to detect when `aih-quick` was the active skill. However, `aih-quick` by design
creates no manifest — it skips planning per ASSUMPTIONS A7, sets no `MANIFEST_PATH`, and has
no `## Invoke stack`. The hook cannot detect "active skill = aih-quick" via this mechanism.

**BLOCKER #2 (ADR overscoping):** The original single ADR-260510-A was flagged by plan-checker
for covering 4 distinct decisions. Per Decision C2, split into 4 ADRs (A/B/C/D) for
traceability and rollback granularity, mirroring M027's V/W/X/Y/Z 5-ADR split precedent.

### Decision

**`tdd-guard.sh`** is a PreToolUse hook that fires on `Write` and `Edit` tool events.

**Lifecycle contract:**

1. **Env bypass first:** `[ "${AIHAUS_TDD_GUARD:-1}" = "0" ] && exit 0` — silent bypass when
   `AIHAUS_TDD_GUARD=0`. Audit row written to `.claude/audit/hook.jsonl` even on bypass.

2. **Discipline check:** reads `AIHAUS_TESTING_DISCIPLINE` env if set (session-cached via
   parent skill Step 0 / R4 performance mitigation). Falls back to reading
   `.aihaus/project.md` `testing_discipline:` field on first invocation per session.
   If `testing_discipline != tdd` → exit 0 silently (no-op for `none` / `test-after`).

3. **Test-file allowlist (R5 mitigation):** if `file_path` matches the allowlist regex,
   always allow (exit 0) AND record a session marker (so future non-test edits are unblocked):
   - `tests/`, `__tests__/`, `test/`, `spec/`, `e2e/`, `cypress/integration/`, `__specs__/`
   - `*_test.*` (Go/Python), `*.test.*` (JS/TS), `*.spec.*` (JS/TS)
   Allowlist is extensible — future language patterns added per user issue reports.

4. **Session marker check:** marker file at `.claude/audit/tdd-guard.session.{session_id}.json`
   (keyed to `CLAUDE_SESSION_ID` or `$$`). If marker exists AND is within TTL (default 120
   minutes) AND has a non-empty `test_files` array → allow (exit 0).

5. **Block:** if none of the above applies → exit 2 with stderr message:
   `tdd-guard: Write|Edit on <file> blocked. testing_discipline=tdd requires a test file
   edit/create in the same session before implementation. Allowlist regex matched paths
   bypass this check. Set AIHAUS_TDD_GUARD=0 to opt out.`

**aih-quick lifecycle (Decision B — resolves BLOCKER #1):**

- `aih-quick/SKILL.md` Protocol Step 0 (NEW): `export AIHAUS_TDD_GUARD=0` — explicitly
  disables tdd-guard for the duration of the aih-quick session.
- `aih-quick/SKILL.md` Protocol Step 6 (amended): ends with `unset AIHAUS_TDD_GUARD` —
  bounds the env to the aih-quick invocation, prevents leakage to subsequent commands.

Trade-off vs original MANIFEST_PATH approach: env-var can theoretically leak across nested
invocations within the same shell session (e.g., user runs aih-quick then immediately
aih-feature without exiting). Mitigation: Step 6 explicit `unset`; Smoke Check 79
fixture-fail #3 verifies the bypass fires correctly when `AIHAUS_TDD_GUARD=0`.

**Audit log:** all decisions (allow/block/bypass) written to `.claude/audit/hook.jsonl` with
fields: `ts`, `hook`, `event`, `decision`, `reason`, `file_path`, `testing_discipline`.
Enables future numeric trigger queries per PLAN §OQ-3.

**Performance (R4):** session-marker file is the primary cache. Project.md is read only on
first invocation per session (when `AIHAUS_TESTING_DISCIPLINE` env is not set). Parent
skills that call `export AIHAUS_TESTING_DISCIPLINE=$(...)` at Step 0 avoid the file read
entirely.

### Options Considered

| # | Option | Pros | Cons | Why Not |
|---|--------|------|------|---------|
| 1 | **(Chosen)** env-var bypass `AIHAUS_TDD_GUARD=0` with explicit aih-quick lifecycle | Clean; testable; matches `AIHAUS_GIT_ADD_GUARD` precedent | Env can leak if Step 6 `unset` skipped by crash | Step 6 unset + smoke fixture-fail #3 mitigates; simpler than all alternatives |
| 2 | MANIFEST_PATH active-skill marker | Original plan | Broken — aih-quick creates no manifest (BLOCKER #1) | Mechanically unsound per ASSUMPTIONS A7 |
| 3 | `--no-tdd` per-tool flag | Per-invocation precision | High blast radius (every Edit|Write call needs the flag) | Impractical; surface is too granular |
| 4 | Process-tree heuristic (`pgrep -f aih-quick`) | No env pollution | Fragile; OS-dependent; breaks in nested invocations | Non-deterministic — rejected |
| 5 | Wrap upstream `nizos/tdd-guard` | Code reuse | No runtime config handoff (RESEARCH F1 — verified) | In-house hook with project.md gating is the only viable path |

### Rationale

Hook-level enforcement is empirically stronger than prose-level prescription (RESEARCH F5).
The env-var bypass pattern matches the established `AIHAUS_GIT_ADD_GUARD=0` precedent
(git-add-guard.sh L29-38) — both use `${VAR:-default}` defaulting to active. The aih-quick
lifecycle (Step 0 export / Step 6 unset) is the minimal-blast-radius solution to BLOCKER #1.
Session-marker for test-file pairing tracks the TDD "write test first" intent across
tool invocations without requiring cross-tool shared state.

### Consequences

- `pkg/.aihaus/hooks/tdd-guard.sh` (NEW) — ~165 LOC.
- `pkg/.aihaus/skills/aih-quick/SKILL.md` — +2 lines (Step 0 + Step 6 amendment).
- `tools/smoke-test.sh` — Check 79 added (3 fixture-fail tests; total 78 → 79).
- `tools/fixtures/check-79/` — 3 JSON fixture files.
- `.claude/audit/hook.jsonl` — shared audit log (existing path per git-add-guard.sh pattern).
- `.claude/audit/tdd-guard.session.{id}.json` — session-scoped marker (gitignored path).

### Rollback

- Delete `pkg/.aihaus/hooks/tdd-guard.sh`.
- Revert `aih-quick/SKILL.md` Step 0 + Step 6 amendment.
- Remove Check 79 from `tools/smoke-test.sh` and `tools/fixtures/check-79/`.
- Session markers are ephemeral runtime artifacts — no migration concerns.

### References

- ADR-260510-A — `testing_discipline` schema (the field this hook reads)
- ADR-260510-B — project.md structured-keys governance (S6)
- ADR-260510-D — TDD scope-fence / Surface 4 permanent rejection (S6)
- ADR-M017-A — `git-add-guard.sh` env opt-out pattern (structural analog)
- ADR-260509-X — M027/S7 two-tier autonomy-guard (hook precedent)
- M028 PLAN Decision B (aih-quick bypass mechanism — resolves BLOCKER #1)
- M028 PLAN Decision C2 (ADR split — resolves BLOCKER #2)
- RESEARCH F5 (20%→84% hook-enforcement claim; Spence measurement + Seleznov replication)

## ADR-260510-B — Project.md structured-keys governance + sunset clause (M028/S6)

**Status:** Accepted
**Date:** 2026-05-09
**Milestone:** M028-260509-tdd-aihaus-clients

### Context
ADR-260510-A introduced `testing_discipline` as a structured machine-readable key in project.md `## Practices` section. Without governance, future milestones may add ad-hoc keys (`commit_convention`, `style_discipline`, `ci_gates`, etc.) until project.md becomes a 200-line policy file. CHALLENGES MED #8 + ASSUMPTIONS S2 flagged the schema-creep risk.

### Decision
This ADR governs **structured machine-readable keys within MANUAL-block sections of project.md** — NOT new H2 sections themselves (5 already exist: Glossary, Active Milestones, Decisions, Knowledge, Milestone History — `## Practices` is the 10th total H2, 6th MANUAL section, per ASSUMPTIONS S2 verification). Discipline rule:

1. **Each new structured key requires a milestone-tagged ADR** (e.g., ADR-260510-A landed `testing_discipline`).
2. **Sunset clause**: 2 milestones post-introduction with zero downstream consumers → key removed via amendment ADR.
3. **Flat namespace**: keys are top-level (`testing_discipline`), no nesting (`practices.testing.discipline`).
4. **aih-init auto-detection takes precedence** over explicit user-set value at install time. User can override post-install by editing project.md directly.
5. **Reserved key namespace** (claimed by aihaus, do NOT use for app-specific config): `testing_discipline`, `commit_convention`, `style_discipline`, `ci_gates`, `code_review_discipline`. Future milestones may extend.

### Rationale
The 5-already-exist clarification (per ASSUMPTIONS S2) means the `## Practices` section ISN'T precedent-setting structurally — what's precedent-setting is the structured-key-in-markdown pattern. Governance scoping must match: governs keys, not sections.

### Consequences
- Future structured-key proposals require ADR + sunset commitment.
- Smoke check (deferred to M029+) MAY enforce the reserved-namespace claim if needed.
- aih-init auto-detection logic is canonical; user override via direct edit is allowed.

### References
- ADR-260510-A (testing_discipline schema — first user of this governance)
- ASSUMPTIONS S2 (project.md has 9 H2 sections, not 5; `## Practices` is 10th)
- CHALLENGES MED #8 (schema-creep risk)

## ADR-260510-D — TDD discipline scope-fence — user code only, NOT aihaus internals (M028/S6)

**Status:** Accepted
**Date:** 2026-05-09
**Milestone:** M028-260509-tdd-aihaus-clients

### Context
M028 ships TDD discipline as opt-in user preference. The brainstorm contrarian (CHALLENGES MED #7) flagged a self-eating-cake observation: aihaus's own M027/S7 added 864 LOC of bash to autonomy-guard.sh with **zero unit tests**. The aihaus team's own primary stack (bash) is integration-tested via `tools/smoke-test.sh` + fixture-fail patterns, NOT unit-tested via bats or shunit2.

### Decision
TDD discipline is **offered to aihaus users for application code**; it does **NOT apply to aihaus's own bash hooks/scripts**. Specifically:
1. Surface 4 (test-first baseline in implementer/frontend-dev/code-fixer) is **permanently rejected** — not "deferred pending evidence."
2. aihaus internals (pkg/.aihaus/hooks/*.sh, tools/*.sh, pkg/scripts/*.sh) continue to use smoke-test integration + fixture-fail patterns (M026 Check 77, M027 Check 78, M028 Check 79).
3. The `testing_discipline` field in project.md applies ONLY to the user's project context — the field is read by implementer/frontend-dev when they work on USER code, not aihaus's own substrate.

### Rationale
This is honest scoping, not a deferred decision. The maintainer's behavior IS the data: M027/S7 added non-trivial bash logic without unit tests because integration-via-smoke-test is the appropriate test discipline for shell hooks. Prescribing TDD to users while ignoring it internally would be paternalistic. Documenting the asymmetry explicitly preempts the "self-contradiction" critique that an external auditor would otherwise make.

### Consequences
- Surface 4 carries forward as PERMANENTLY REJECTED in any future TDD-related milestone.
- aihaus's smoke-test layer (`tools/smoke-test.sh`) remains the canonical test substrate for the package itself.
- User-facing skills (aih-feature, aih-plan, aih-milestone) honor `testing_discipline=tdd` for user code paths; aihaus's own validation runs unchanged.

### References
- ADR-260510-A (schema — testing_discipline applies to user project context)
- ADR-260510-C (hook contract — tdd-guard.sh fires on user code Edits, not aihaus's own substrate)
- CHALLENGES MED #7 (self-eating-cake observation)
- M027/S7 ADR-260509-X autonomy-guard.sh expansion precedent (LOC = 864 at draft time)

---

## ADR-M028-CURATE-A — Hook bypass for skill-specific lifecycles uses explicit env-var, not implicit marker file

**Status:** Accepted
**Date:** 2026-05-10
**Milestone:** M028 (curator pass)

### Context

When `aih-quick` needed to bypass `tdd-guard.sh` (M028/S2 PreToolUse hook), two designs surfaced during PLAN remediation: implicit detection (hook scans for active-skill marker) vs explicit env-var lifecycle (skill Step 0 sets `AIHAUS_TDD_GUARD=0`, Step 6 unsets). Plan-checker BLOCKER #1 surfaced that implicit detection was broken — `/aih-quick` writes no manifest, has no marker. Decision B replaced it with the env-var lifecycle (ADR-260510-C).

### Decision

For any future PreToolUse hook needing context-aware bypass for one specific skill, **prefer explicit env-var lifecycle owned by the skill** (set in entry, unset in exit) over implicit marker-file or manifest-existence detection. Skill declares; hook honors. No reverse-direction discovery.

### Consequences

- Bypass is auditable via `grep AIHAUS_<HOOK>_GUARD pkg/.aihaus/skills/`.
- Lifecycle symmetric and self-cleaning.
- Cost: one env-var name per bypass surface.
- Pattern established for M029+.

---

## ADR-M028-CURATE-B — Honest-scope-fence for self-modifying tooling — disciplines apply to user code only

**Status:** Accepted
**Date:** 2026-05-10
**Milestone:** M028 (curator pass)

### Context

M028 brainstorm raised Surface 4 (apply TDD baseline stance to implementer/frontend-dev/code-fixer so aihaus's own bash hooks would also be test-first). Decision G rejected on two grounds: (a) stack-agnosticism — agents can't assume specific test framework exists in user repo; (b) maintainer behavior across M001-M027 is empirical evidence — 864 LOC autonomy-guard.sh shipped without co-evolving test suite. ADR-260510-D captured the specific scope-fence; this curator-rule generalizes.

### Decision

When designing any discipline (TDD, contract-tests, fuzz harnesses, etc.) shipped to user repos, **explicitly fence scope to user code at ADR-write time**. Document that aihaus's own bash hooks, skill markdown, shell scripts are out of scope — and cite maintainer's commit history as evidence rather than aspirational adoption.

### Consequences

- Future discipline ADRs must include Scope section naming what is in/out. Vague "applies to all aihaus-touched code" claims rejected.
- Stack-agnosticism + honest-scoping compose: a discipline cannot baseline-apply to agents that read user-stack at runtime.
- Honest-scoping ADRs ship verification commands (e.g., `wc -l autonomy-guard.sh = 864` for ADR-260510-D).

---

## ADR-260511-A — calibrate-guard.sh UserPromptExpansion hook contract (M029/S1)

**Status:** Accepted
**Date:** 2026-05-12
**Milestone:** M029/S1

### Context

M027/S5 shipped a calibration-gate in `aih-plan/SKILL.md` Phase 3.5 (Layer A prose). Empirical observation post-M027: globbing `.aihaus/plans/*/CHECK.md` returns 23 files, zero companion `BUSINESS-RULES.md` files — 100% skip rate. Root cause: the gate called `manifest-append.sh --audit calibration-skip` which is structurally dead-code (manifest-append.sh has no `--audit` mode). Additionally, Layer A enforcement is vulnerable to (a) model-judgment-skip and (b) skill-cache staleness (PRE-M027 skill body can load in a live session even after `git pull`). The `UserPromptExpansion` hook event fires from Claude Code runtime regardless of orchestrator skill cache — immune to both failure modes.

### Decision

Ship `calibrate-guard.sh` as a `UserPromptExpansion` hook (Layer C enforcement):

- **Single-channel:** `UserPromptExpansion` only — dropping the defensive PreToolUse:Bash 2nd channel per BLOCKER F4 (merge-settings.sh uses replacement semantics for arrays; adding a 5th PreToolUse entry via update.sh would replace user's custom entries on next refresh).
- **Matcher:** `"aih-feature|aih-milestone"` in settings.local.json. Hook internally narrows `aih-milestone` to `--plan` invocations via `command_args` grep.
- **Active-slug sentinel:** `aih-plan` Phase 1 writes `.claude/calibrate-guard.active-slug` after slug finalization; clears at Phase 4 completion. Hook reads sentinel to resolve active plan dir; absent sentinel → exit 0 (gate not in scope).
- **Ambiguity detection:** Check 78 regex (`TBD|assumed|TODO|pending confirmation`) applied to `.aihaus/plans/<slug>/ASSUMPTIONS.md`. Count = 0 → exit 0 (legitimate zero-ambiguity skip).
- **Ctime exemption (Decision E):** CHECK.md mtime predates M029 first-commit timestamp (epoch `1747008000` / 2026-05-12T00:00:00Z) → exit 0 (legacy artifact grandfathered).
- **Direct JSONL emit:** hook writes `{"event":"calibrate-guard",...}` rows directly to `.claude/audit/hook.jsonl` (mirrors tdd-guard.sh + git-add-guard.sh). Replaces the dead-code `manifest-append.sh --audit calibration-skip` path.
- **Bypass mechanisms:** `AIHAUS_CALIBRATE_GUARD=0` env (aih-quick/bugfix Step 0/6 lifecycle) + `--no-calibrate` flag (per-invocation; prior `calibration-skip` row in audit log within 24h → exit 0).
- **Block output:** stderr message + exit 2 (consistent with tdd-guard.sh pattern; no JSON stdout needed).

### Rationale

Layer A → C promotion per ADR-260503-A move-rule: `leverage=high` (gate prevents unresolved ambiguity from reaching implementation) AND `reversibility=irrev` (implementation built on ambiguous spec is costly to unwind) AND `eligibility=deterministic` (BUSINESS-RULES.md file-existence check is deterministic). Anticipatory-promotion trigger (c) also applies: 100% on-disk skip rate (23/23 CHECK.md without companion BUSINESS-RULES.md) constitutes empirical-failure signal.

`UserPromptExpansion` is confirmed immune to Issue #21614 (skill-hook surface instability) per RESEARCH F4. Single-channel design is sufficient: all `/aih-*` invocations route through UserPromptExpansion when user types them; orchestrator-dispatched slash commands also fire it.

### Consequences

- Hook count: 31 → 32 (smoke-test Check 3 allowlist updated in S1).
- Existing 5 in-flight CHECK.md artifacts grandfathered via ctime exemption — no retroactive blocking.
- `aih-quick` and `aih-bugfix` Step 0/6 env-var lifecycle (`AIHAUS_CALIBRATE_GUARD=0` set at entry, unset at exit) — adds 2 lines each (S2).
- M027/S5 dead-code `manifest-append.sh --audit calibration-skip` references cleaned in S5.
- settings.local.json gains new top-level `UserPromptExpansion` key (NOT appended to existing `PreToolUse` array — avoids replacement-semantics break per BLOCKER F4).

### References

- ADR-260503-A (Layer A → C move-rule)
- ADR-260509-W (plan-calibrator agent)
- PLAN.md Decision B+C+D+E (single-channel, sentinel, JSONL emit, ctime exemption)
- STDIN-SCHEMA.md (UserPromptExpansion field shape verification 2026-05-12)
- PATTERNS.md Pattern 1+4+8 (tdd-guard shape, analyst-brief read, stdin parse)
- Pattern reusable for M029+ governance ADRs (per ADR-260510-B sunset clause).

---

## ADR-260511-C — Smoke Check 81 drift detection + legacy ctime-exemption (M029/S3)

**Status:** Accepted
**Date:** 2026-05-12
**Milestone:** M029/S3

### Context

Smoke Check 81 catches post-merge drift: a `PLAN.md` plan that went through plan-checker (CHECK.md present) but whose ASSUMPTIONS.md ambiguity surface was never resolved via BUSINESS-RULES.md calibration. This complements `calibrate-guard.sh` (M029/S1 / ADR-260511-A): the hook prevents forward-creation; the smoke check catches existing drift at the CI gate. Defense-in-depth per RESEARCH F3 (Gitleaks/Helmet/rate-limiters field pattern).

**Legacy context:** At M029 first-commit timestamp (epoch `1747008000` / 2026-05-12T00:00:00Z), 5 in-flight CHECK.md artifacts exist with no companion BUSINESS-RULES.md (empirical baseline: 23 CHECK.md / 0 BUSINESS-RULES.md). These predating artifacts must be grandfathered to avoid immediate CI failure on the milestone branch.

### Decision

Ship Smoke Check 81 (`check_calibrate_drift`) in `tools/smoke-test.sh`:

- **4-axis allow logic:** for each `.aihaus/plans/*/CHECK.md`, allow if ANY condition holds:
  (a) companion `BUSINESS-RULES.md` exists,
  (b) `ASSUMPTIONS.md` ambiguity count = 0 (Check 78 regex: `TBD|assumed|TODO|pending confirmation`),
  (c) `.claude/audit/hook.jsonl` has `"event":"calibration-skip"` row matching the plan slug,
  (d) CHECK.md mtime predates `M029_EPOCH=1747008000` (legacy artifact exemption).
  Else: emit per-slug drift error string and fail.

- **ctime exemption constant:** `M029_EPOCH=1747008000` — same value as `calibrate-guard.sh` L41. Codified in 2 places (hook + smoke); changes to the epoch require coordinated update of both files.

- **Fixture-based validation (non-vacuous gate):** 3 fixture dirs under `tools/fixtures/check-81/`:
  - `drift-detected/` — ASSUMPTIONS with ≥1 ambiguity, no BUSINESS-RULES.md, no audit row → MUST fail (block).
  - `drift-bypassed-by-no-calibrate/` — same ambiguities but companion `hook.jsonl` has valid `calibration-skip` row → MUST pass (allow).
  - `no-ambiguity-skip/` — ASSUMPTIONS with zero ambiguity markers → MUST pass (allow).

- **Real-plan scan** runs at CI only if `.aihaus/plans/` exists on disk (gitignored; empty in fresh CI clone).

- **Check numbering:** smoke total 80 → 81.

### Rationale

Hook prevents forward-creation of new ambiguous plans; smoke catches accumulated drift in repo state. Both layers needed: `calibrate-guard.sh` fires at skill-invocation time (real-time), while smoke-test runs at commit/CI gate (batch audit). Mirrors the Check 79 fixture-fail pattern verbatim (PATTERNS verbatim-copy principle per PLAN Decision D).

The `mtime`-as-ctime proxy is portable (`stat -c%Y` on Linux, `stat -f%m` on macOS) and fail-safe (if stat is unavailable, treats file as non-exempt — proceeds to drift check, never silently allows).

### Consequences

- Smoke total: 80 → 81.
- 3 new fixture dirs under `tools/fixtures/check-81/`.
- `M029_EPOCH=1747008000` constant now lives in 2 files: `pkg/.aihaus/hooks/calibrate-guard.sh` L41 and `tools/smoke-test.sh` (Check 81 function).
- Real `.aihaus/plans/` drift check runs in dogfood sessions (non-empty plans dir); CI runs fixture-only assertions.
- Future plan drift: any new CHECK.md without BUSINESS-RULES.md and with ambiguity markers will fail smoke (forcing explicit `--no-calibrate` opt-out or plan calibration before merge).

### References

- ADR-260511-A (calibrate-guard.sh hook contract — hook is the forward-creation gate)
- ADR-260503-A (Layer A → C move-rule; anticipatory-promotion trigger)
- PLAN.md Decision D (Smoke Check 81 design) + Decision E (ctime exemption policy)
- tools/fixtures/check-79/ (fixture-fail reference pattern — Check 81 mirrors shape)
- tools/fixtures/check-78/ (ambiguity-detection regex reference — Check 81 reuses same regex)

---

## ADR-260511-B — ADR-260503-A move-rule amendment: anticipatory-promotion trigger (M029/S4)

**Status:** Accepted
**Date:** 2026-05-12
**Milestone:** M029/S4
**Amends:** ADR-260503-A (SKILL enforcement-layer audit framework + move rule)

### Context

ADR-260503-A's move rule reads: "Promote A → B/C iff `leverage=high AND (reversibility=irrev OR drift-detectability=hard) AND eligibility=deterministic`." The rule captures when to act, but not WHAT TRIGGERS the decision to evaluate promotion for a specific row. Historically, triggers were either:

- **Visible-escape recurrence** — model-driven gate fires incorrectly ≥1 time in production, post-mortem surfaces the row.
- **Single-incident-with-irreversible-blast-radius** — one incident is enough when the cost of a second is catastrophic (M017 merge-back race precedent).

M029 introduced a third pattern: `calibrate-guard.sh` was promoted to Layer C before any incident, based on (a) 100% on-disk skip rate (23 CHECK.md / 0 BUSINESS-RULES.md) and (b) RESEARCH F3 field-precedent verification (Gitleaks/ggshield/Helmet/rate-limiters all deploy anticipatory). The original ADR-260503-A did not codify this as a legitimate trigger, creating a gap: the calibrate-guard.sh promotion was sound but lacked explicit ADR authority.

### Decision

Amend ADR-260503-A move-rule to accept **3 legitimate trigger patterns** for initiating a Layer A → C promotion evaluation:

**(a) Visible-escape recurrence (original — M005, M023, M025 precedent):** model-driven gate fires incorrectly ≥1 time in production; post-mortem nominates the row for promotion.

**(b) Single-incident-with-irreversible-blast-radius (original — M017 precedent):** one confirmed incident where the blast radius is irreversible (e.g., cross-story file ownership violation, merge-back race) constitutes sufficient trigger regardless of recurrence.

**(c) NEW — Anticipatory-protection-on-new-flow:** promotion is legitimate BEFORE any incident when ANY of the following holds:
  - (i) **On-disk artifact-presence ratio shows ≥50% skip rate** — empirical evidence that the Layer A gate is being bypassed in practice (M029 example: 23 CHECK.md / 0 BUSINESS-RULES.md = 100% skip rate).
  - (ii) **≥1 published field precedent** — documented deployment of an analogous gate in a shipped open-source tool or security library without incident-driven motivation (M029 example: Gitleaks/ggshield pre-commit, Helmet default-on, express-rate-limit default-install per RESEARCH F3).
  - (iii) **Explicit threat-model documentation citing model-judgment-vulnerability** — the promoting ADR names the specific model-judgment failure mode (e.g., skill-cache staleness, executor-context ambiguity) AND the field precedent demonstrates the same vulnerability class was pre-empted anticipatorily.

Trigger (c) is SUFFICIENT for beginning a promotion evaluation. The move rule's existing `leverage=high AND (reversibility=irrev OR drift-detectability=hard) AND eligibility=deterministic` conditions must STILL ALL PASS — trigger (c) only unlocks the evaluation; it does not override the eligibility gate.

**DOES NOT FIT clarification (additive to ADR-260503-A §Decision "Worked example #2" and §Applicability Examples):** Rows with `eligibility=model-judgment` REMAIN ineligible for Layer C promotion regardless of which trigger pattern fires. Trigger (c) does NOT create a path for promoting model-judgment rows — the ADR-260502-A determinism gate is inherited verbatim and overrides anticipatory motivation. When a threat-model documents a model-judgment-vulnerability, the correct response is SKILL prose hardening (Layer A improvement), not hook promotion.

### Rationale

RESEARCH F3 (Phase 6 of M029 brainstorm) verified that anticipatory hook deployment is the field-default in security tooling: Gitleaks and ggshield deploy pre-commit hooks that block before any leak incident; Helmet sets secure-header defaults before any XSS incident; express-rate-limit is installed before any DoS incident. aihaus's prior stance — requiring incident evidence before promotion — was unusual relative to the field. The amendment closes the gap.

The ≥50% skip-rate threshold (condition (i)) is intentionally high: it requires empirical evidence that more than half of all artifact instances are missing their companion gate output. A 5% or 20% skip rate could reflect intentional `--no-calibrate` usage; 50%+ signals structural bypass rather than intentional opt-out. M029's 100% rate (23/23) is the canonical example.

The field-precedent condition (ii) creates a documented peer-review path: the promoting ADR must cite a specific tool, not "general practice." This keeps the bar verifiable.

Conditions (i)+(ii)+(iii) are OR-conditions — any single one is sufficient to trigger evaluation. All three together constitute strong evidence for promotion.

### Consequences

- Future Layer A high-leverage rows can be promoted pre-incident when trigger (c) criteria are documented in the promoting ADR.
- The ≥50% skip-rate threshold is a high bar — prevents floodgate of speculative promotions.
- `eligibility=model-judgment` rows remain permanently ineligible for Layer C promotion (ADR-260503-A DOES NOT FIT examples + ADR-260502-A authority preserved).
- ADR authors must cite ONE of (a)/(b)/(c) explicitly in the "Rationale" section of any future Layer A → C promoting ADR — absence of trigger citation is a plan-checker BLOCKER.
- Promotion backlog (`pkg/.aihaus/skills/_shared/enforcement-audit-backlog.md`) rows may now be re-evaluated against trigger (c) retroactively; rows passing (c)(i) or (c)(ii) move from "await-incident" to "promotable-now" status.

### References

- ADR-260503-A (parent — amended by this ADR; move rule lives at `pkg/.aihaus/decisions.md:2026`)
- ADR-260511-A (calibrate-guard.sh contract — first consumer of trigger (c); documents the 23/0 ratio + RESEARCH F3 citations)
- ADR-260511-C (Smoke Check 81 — defense-in-depth complement; cites RESEARCH F3 Gitleaks/Helmet field pattern)
- CHALLENGES Finding #2 (anticipatory-deployment is field-default — from M029 brainstorm `260510-hook-promote-gates/CHALLENGES.md`)
- RESEARCH §3 (field-precedent verification — Gitleaks, ggshield, Helmet, express-rate-limit)

---

## ADR-M029-CURATE-A — Hook-level enforcement primary when Layer A prose failure-prone; env-var lifecycle canonical bypass (3rd-instance generalization)

**Status:** Accepted
**Date:** 2026-05-12
**Milestone:** M029 (curator pass)

### Context

Third milestone promoting model-driven Layer A prose to Layer C hook (M027/S5 calibration, M028/S2 tdd-guard, M029/S1 calibrate-guard). Empirical motivation identical: Layer A fails for 2 compounding reasons — (1) model judgment-skip; (2) skill-cache staleness (orchestrator's loaded skill body lags on-disk after `/aih-update`). M027/S5's 100% calibration-skip rate (23 CHECK.md / 0 BUSINESS-RULES.md) observed **during M029-planning session itself** — `/aih-plan` loaded pre-M027 SKILL.md body. UserPromptExpansion fires BEFORE skill body loads (K-260512-003) — only primitive immune to both.

### Decision

For aih-* enforcement where (a) leverage=high AND (b) consequence-of-skip=hard-to-reverse-drift AND (c) eligibility=deterministic: **prefer Layer C hook from first design pass**. Do not wait for empirical skip-rate evidence. ADR-260511-B trigger is formal authority; this rule generalizes the meta-pattern. Bypass: env-var lifecycle (Step 0 set / Step 6 unset). Reject marker-files, manifest-presence inference, command-args parsing, audit-row precedence detection — all chicken-and-egg (M029/F-O5). Audit-emit: direct `.claude/audit/<hook>.jsonl` write (K-260512-004), NEVER `manifest-append.sh --audit` (dead-code since v0.31.0).

### Consequences

- 3 instances compose: M028-CURATE-A + M029/S1 + this rule.
- Cache-staleness is NEW Layer A failure class beyond model-judgment-skip.
- Cost auditable via grep at design time.
- Anti-pattern reject: tightening writer-schema when failure is model NOT INVOKING writer.
- Caveat M029/F-O1: hook only effective same-session as sentinel writer; cold-start = fail-open.

### References

- ADR-M028-CURATE-A (first instance — single-skill env-var bypass)
- ADR-260511-A (second instance + cache-staleness root cause documented)
- ADR-260511-B (anticipatory-promotion trigger)
- ADR-260503-A (move-rule)
- K-260512-003 (UserPromptExpansion cache-staleness immunity)
- K-260512-004 (hook audit-emit direct-JSONL convention)

---

## ADR-260514-B — Array-aware settings merge: dual by-shape union semantics (M030/S05)

**Status:** Accepted
**Date:** 2026-05-14
**Milestone:** M030/S05

### Context

During a forensic audit of the maintainer's dogfood specimen (`the maintainer's dogfood install/.claude/settings.local.json`), 7 canonical hook entries were found missing from the user's settings file — entries that had been added to the template in M017+ but were silently overwritten on every `update.sh` run. The `merge-settings.sh` jq merge used `.[0] * .[1]` semantics; the Python fallback used simple `deep_merge` with `return overlay` on array collision. Both implementations replace arrays wholesale — a bidirectional-lossy merge that drops template additions silently.

**7-hook delta table (field evidence from maintainer's maintainer's dogfood specimen, 2026-05-14):**

| Hook | Event | Template since | Missing in specimen |
|------|-------|---------------|---------------------|
| `calibrate-guard.sh` | UserPromptExpansion | M029/S1 | yes |
| `context-inject.sh` | SubagentStart | M022 | yes |
| `git-add-guard.sh` | PreToolUse (2nd Bash entry) | M017 | yes |
| `read-guard.sh` | PreToolUse (empty matcher) | M014 | yes |
| `warning-recurrence.sh` | SubagentStop | M022 | yes |
| `worktree-release.sh` | SubagentStop | M017 | yes |
| `worktree-release-all.sh` | SessionEnd | M017 | yes |

Root cause at code level: `merge-settings.sh:53` (jq) and the Python fallback `deep_merge` both replace `.hooks.<Event>[]` arrays wholesale. User's pre-M017 `settings.local.json` snapshot was never updated because the fix was a simple array-overlay.

ASSUMPTIONS A4/A15 reframe: the brainstorm hypothesis was that 9 user-custom hooks were at risk from the merge. Verification refuted this — all 9 are CANON. The real defect is the inverse: the user's file is frozen at pre-M017 shape, missing 7 newer canon hook entries. The fix is therefore prophylactic per ADR-260511-B trigger (c)(i).

### Options Considered

| # | Option | Why Not |
|---|--------|---------|
| 1 | **(Chosen)** Path-scoped union per per-array-path matrix; dual by-shape scoping (no path-state); jq + Python + PowerShell symmetric. jq snippet: `def merge_hooks_arrays(base_arr; overlay_arr): if has_matcher_hooks then position-paired-merge elif has_command then union-by-command else overlay end`. | None — closes gap, zero regression, reversible. |
| 2 | `.hooks._preserve_commands` user-override list in settings | Forces users to track package additions manually; high cognitive cost; fragile on aihaus upgrades. |
| 3 | `--preserve-user-arrays` flag on `update.sh` | Silent-default-lossy still exists until users discover and set the flag; the trap remains. |
| 4 | Document-only (no code change) | This is the C8 framing the brainstorm contrarian called out — insufficient when field evidence shows active drift. |

### Decision

Ship **dual by-shape union semantics** in `merge-settings.sh` (jq path + Python fallback symmetric) and `install.ps1` `Merge-Object` (PowerShell), governed by the per-array-path matrix:

**Per-array-path semantics matrix:**

| JSON path | Semantics | Rationale |
|-----------|-----------|-----------|
| `.hooks.<Event>[]` (outer; objects with `matcher` + `hooks` siblings) | **POSITION-PAIRED MERGE WITH RECURSION** — paired by ordinal index; for each pair, recurse into inner `hooks[]` and apply inner-union; surplus template entries appended; surplus user entries appended last | Outer is shape-tested by `{matcher, hooks}` presence; preserves multi-`Bash`-matcher template entries without duplicating bash-guard between paired user[0] and template[0] |
| `.hooks.<Event>[N].hooks[]` (inner; objects with `command` field) | **UNION BY `.command`** (template wins on collision) | Closes the canonical drift gap; future user-custom hooks at this layer survive `update.sh` |
| `permissions.allow` | **REPLACEMENT** (template wins) | Existing M014 contract per `merge-settings.sh` migration-hint logic. Not changed. |
| `permissions.deny` | **REPLACEMENT** | Same as above. |
| `additionalDirectories` | **REPLACEMENT** | Same as above. |
| All other arrays | **REPLACEMENT** (current semantics) | Default; opt-in to union/merge only for `.hooks.<Event>[]`. |

**Worked example (canonical 2-`Bash`-matcher case):**

Template `PreToolUse`:
```json
[
  {"matcher":"Bash","hooks":[{"command":"bash-guard.sh"}]},
  {"matcher":"Bash","hooks":[{"command":"git-add-guard.sh"}]}
]
```
User (pre-update):
```json
[
  {"matcher":"Bash","hooks":[{"command":"bash-guard.sh"},{"command":"my-custom-bash-audit.sh"}]}
]
```
Expected merged output:
```json
[
  {"matcher":"Bash","hooks":[{"command":"bash-guard.sh"},{"command":"my-custom-bash-audit.sh"}]},
  {"matcher":"Bash","hooks":[{"command":"git-add-guard.sh"}]}
]
```
Trace:
- Outer position-paired: user[0] pairs with template[0]; user has no [1] -> template[1] appended as surplus.
- Inner union (user[0] vs template[0]): template's `bash-guard` collides with user's `bash-guard` (template wins; same string); user's `my-custom-bash-audit` is novel -> unioned in.
- Template[1] (`git-add-guard`) appended as-is (no pair to merge with).

**Dual by-shape test (applied symmetrically across jq + Python + PowerShell — CHECK F4):**

Test outer first, then inner:
- If both arrays are non-empty list-of-dicts AND every element on both sides has BOTH `matcher` AND `hooks` keys -> outer shape: position-paired merge with recursion into inner; surplus appended.
- If both arrays are non-empty list-of-dicts AND every element on both sides has `.command` key -> inner shape: union by `.command` (template wins on collision).
- Otherwise: replacement (current behavior).

No path-state threading; pure by-shape (BR-005 verified zero current-state regression).

### Rationale

ADR-260511-B move-rule trigger (c)(i) applies: the 7-hook delta table constitutes empirical field evidence from the maintainer's own dogfood specimen that the prior array-replacement merge was producing a 100% silent-drift scenario on every `update.sh` run. Trigger (c)(i) requires an on-disk artifact-presence ratio showing structural bypass — here the equivalent is a single-user canonical specimen with 7 of 7 newer hook entries silently absent.

ADR-260511-B trigger (c)(i) was unlocked to enable exactly this class of anticipatory protection: prophylactic code change before a second user is affected, based on empirical single-specimen evidence from the maintainer's own install.

The dual by-shape scoping rule (no path-state threading) is the symmetry lever across jq + Python + PowerShell. BR-005 verifies zero current-state regression: current canonical schema has zero `{matcher, hooks}` list-of-dicts outside `.hooks.<Event>[]` and zero `{command}` list-of-dicts outside `.hooks.<Event>[N].hooks[]`.

### Consequences

- **(a) M014 migration-hint contract preserved.** `permissions.allow` replacement semantics unchanged. Regression assertion: smoke-test Check 23 still PASSES for `permissions.allow` replacement.
- **(b) Already-installed user rollout via Half B drift-detect** (per BR-002). Users who installed pre-M030 benefit from the fix automatically on next `bash update.sh` when the heuristic threshold fires. `update.sh` and `install.ps1` ship a drift-detect block: `template_hook_count - user_hook_count >= AIHAUS_DRIFT_THRESHOLD (default 2)` for any Event triggers interactive prompt `"Detected N missing canonical hook entries from <Event>. Recompute merged settings now? [Y/n]"`. Y -> re-invoke merge with `AIHAUS_RECOMPUTE_MERGE=1`. N -> sentinel `.aihaus/.recompute-skipped-260514`.
- **(c) Dual by-shape forward-compat constraint.** Any future settings array whose elements all carry a `.command` key will also union-merge. Currently zero such schema per BR-005; documented for future schema authors.
- **(d) Sibling defense-in-depth reference.** S07's `pkg/.aihaus/hooks/worktree-reconcile.sh` `[DETACHED-HEAD-MAIN]` warn is a parallel field-evidence-driven fix from the same dogfood install audit; documented here as defense-in-depth coordination, not a separate ADR.

### Rollback

`git revert` the commit containing this ADR + `merge-settings.sh` + `install.ps1` `Merge-Object` changes. Restore prior `merge-settings.sh` jq `.[0] * .[1]` path + Python `deep_merge` return-overlay path. Revert smoke-test Check 23 label + delete Check 82 + delete Check 83 + delete 19 fixture files under `tools/fixtures/settings-merge-hooks/` and `tools/fixtures/update-drift/`. Re-run install/update restores prior replacement behavior.

### References

- ADR-260511-B (move-rule trigger c(i) authority — anticipatory-protection-on-new-flow)
- ADR-260511-A (heading shape template — this ADR follows same shape)
- ADR-260510-C (Options Considered table shape)
- ADR-260509-X (autonomy-guard 40-pattern freeze — out-of-scope; M030 adds zero new patterns)
- ADR-260503-A (enforcement-audit move-rule parent)
- BR-002 (rollout rule — drives Half B drift-detect in `update.sh` + `install.ps1`)
- BR-005 (Python by-shape scoping zero current-state regression verified)
- INVESTIGATE-settings-drift.md (S03 forensic report on maintainer dogfood pre-M017-shape specimen — gitignored in user installs; 7-hook delta table inlined above per CHECK F5)
- M014 migration-hint contract (`merge-settings.sh` `_autonomy_post_merge_hint` function, L200+)

---

## ADR-260515-A — aih-graph privacy contract (M031/S01)

**Status:** Accepted
**Date:** 2026-05-15
**Milestone:** M031/S01

### Context

aih-graph (specified in M031, built in M032-M040) is a Go binary that ingests source code + markdown + structured data from arbitrary repositories into a queryable knowledge graph. The maintainer (per BRIEF.md Turn 12 Q6) works regularly with NDA-protected client code. Without a binding privacy contract, the moment aih-graph touches a client repo, the graph ingests potentially-NDA-protected content into per-user-global storage — an NDA violation vector any aihaus user who consults professionally faces.

Per BRIEF.md Turn 13 user correction, machine-config concerns (OneDrive sync, OS-level encryption, backup policy) are OUT OF SCOPE for this ADR — they're the user's machine ownership. This ADR commits ONLY to pkg-level invariants aihaus controls.

### Decision

aih-graph v0.1 ships **5 binding privacy contracts**:

1. **XDG-compliant default storage path.** `${XDG_DATA_HOME:-$HOME/.local/share}/aih-graph/<repo-hash>/` on Linux/macOS; `%LOCALAPPDATA%\aih-graph\<repo-hash>\` on Windows. NEVER `~/Documents/...` or user-Documents-rooted paths that conventionally land in cloud-sync trees. `<repo-hash>` is a stable SHA256 prefix of canonical absolute repo path.

2. **Per-repo isolation invariant.** Graph nodes from repo A cannot leak into repo B's query results — even with future v0.2 global query features. Enforced via per-repo subdirectory + repo-hash namespacing on every record. Test: `aih-graph query --repo <repo-b-path> "..."` MUST NOT surface any node sourced from repo A.

3. **Ingestion consent gate.** aih-graph aborts on first encounter with previously-unseen repo unless: `.aih-graph-consent` marker file exists at repo root, OR `--accept-all-repos` CLI flag set, OR `AIHGRAPH_AUTO_CONSENT=1` env. On abort: exit code 2, human-readable error, no storage writes. CI/integration uses env or flag.

4. **`--purge` uninstall = full delete.** `aih-graph uninstall --purge` removes all per-repo graphs + global state + sentinels under XDG path. Hard contract: no orphan data. Verification at uninstall: `ls "${XDG_DATA_HOME:-$HOME/.local/share}/aih-graph/"` returns empty or directory absent.

5. **`.aih-graph-isolated` NDA opt-out.** Marker file at repo root forces local-only mode: aih-graph indexes the repo but it never participates in cross-repo aggregation regardless of future global features. Stronger than `.aih-graph-consent`; both coexist.

### Options Considered

| # | Option | Pros | Cons | Why Not |
|---|--------|------|------|---------|
| 1 | **(Chosen)** 5-contract pkg-level privacy (XDG + isolation + consent + purge + NDA opt-out) | Concrete + testable + binding; aligns with ADR-260504-A V5 XDG precedent; covers CHALLENGES C8 | More install-time complexity vs no-contract default | None — chosen |
| 2 | Single global "do not run on client repos" warning | Trivial | No enforcement; NDA = legal cost, not inconvenience | Insufficient |
| 3 | Mandatory encryption-at-rest | Defense-in-depth | Key management; OS-level full-disk-encryption is right layer | Out-of-scope per Turn 13 |
| 4 | Privacy deferred to v0.2+ | Faster v0.1 | NDA risk HIGH per Q6 — deferral = exposure window | Rejected — binding pre-condition |

### Rationale

ADR-260511-B trigger c(i) — anticipatory-protection-on-new-flow — applies directly. Per BRIEF Q6 "Sim, regularmente — NDA risk é real", per-repo isolation + ingestion consent are blocking-pre-condition for the maintainer's working context. Privacy ADR landing FIRST in M031 signals aih-graph's design begins from contractual reality, not technical capability. Substrate §4.5 (OneDrive in Victor's path as ingestion vector when combined with naive default storage) reinforces explicit pkg-level safe defaults.

### Consequences

1. aih-graph install (M039) verifies XDG path resolves correctly per-platform; install fails if `${XDG_DATA_HOME}` points at known-synced path (OneDrive substring detection, attested only).
2. `aih-graph build` rejects new repos without `.aih-graph-consent` marker (or env/flag override). aihaus's `aih-graph-refresh.sh` (M039) writes marker programmatically for aihaus-managed repos.
3. `aih-graph uninstall --purge` is binding contract; verifier regression-tests path absent on completion.
4. M037 CI workflow includes `--purge` round-trip test (build → uninstall --purge → verify empty).
5. Future v0.2+ global features inherit `.aih-graph-isolated` opt-out; cannot bypass.
6. Sync-root detection list LOCKED to OneDrive only (substrate-attested per §4.5); extended detection deferred to `AIHGRAPH_SYNC_DENYLIST=<csv>` env (per F8 NIT).

### Rollback

`git revert` removes this ADR. aih-graph v0.1+ commits depending on `internal/privacy/` would need separate rollback; not blocking since no code exists yet.

### References

- ADR-260511-B (trigger c(i) authority)
- ADR-260511-A (heading shape template)
- ADR-260510-C (Options Considered shape)
- ADR-260504-A (V5 XDG precedent)
- BRIEF.md Turn 12 Q6 + Turn 13 (NDA scope confirmation + pkg-level correction)
- SUBSTRATE-FINDINGS.md §4.5 (OneDrive empirical signal)
- CHALLENGES.md C8 (privacy/NDA flagged by contrarian)

---

## ADR-260515-B — aih-graph Node/Edge data model: hybrid generic+type-tag storage with typed accessor API (M031/S03)

**Status:** Accepted
**Date:** 2026-05-15
**Milestone:** M031/S03

### Context

aih-graph v0.1's distinguishing capability over graphify-as-shipped is **first-class ontology for aihaus concepts**: graphify treats all markdown as generic headers; aih-graph natively understands `Decision`, `Milestone`, `Story`, `Agent`, `Hook`, `Skill` as distinct node types with type-specific fields. Two storage-API patterns were debated (F5): (a) first-class typed structs end-to-end vs (b) generic Node + type-tag. R2 converged on hybrid (c).

### Decision

aih-graph v0.1 ships **hybrid F5(c) generic+type-tag storage with typed accessor API**:

1. **Storage layer (JSONL).** Each record is generic JSON: `{"type": "Decision", "id": "ADR-260514-B", "data": {...}, "edges": [...], "_v": 1}`. `type` is the type-tag; `data` is free-form; `_v` is schema version (currently 1). Append-friendly, jq-inspectable, evolves without struct migrations, tolerates unknown types (skip-with-warning).

2. **API layer (Go).** Each first-class type ships typed accessor struct + constructor:
   ```go
   type Decision struct { ID, Status string; Date time.Time; /* ... */ }
   func DecisionFrom(n Node) (Decision, error) { /* parses Props into Decision; error on missing required */ }
   ```
   Callers get compile-time type safety at API boundary; storage stays flexible.

3. **6 first-class types in v0.1 (forever-scope per Q4):** Decision (ADRs), Milestone (RUN-MANIFEST entries), Story (S0X-*.md files), Agent (pkg/.aihaus/agents/*.md), Hook (pkg/.aihaus/hooks/*.sh), Skill (pkg/.aihaus/skills/aih-*/SKILL.md).

4. **Worked example (binding):** ADR-260514-B (M030's array-aware merge) maps to:
   ```json
   {
     "type": "Decision", "id": "ADR-260514-B",
     "data": { "title": "Array-aware settings merge", "status": "Accepted", "date": "2026-05-14",
               "milestone": "M030/S05", "supersedes": [], "amends": [], "references": ["ADR-260511-B"] },
     "edges": [ {"to": "ADR-260511-B", "type": "references"},
                {"to": "M030-260514-merge-settings-array-aware", "type": "decided-in-milestone"} ],
     "_v": 1
   }
   ```
   `DecisionFrom(node)` returns Go `Decision` struct with typed fields.

5. **Generic Node remains accessible** for cross-type queries (BFS), debugging, future-type ingestion before typed-accessor structs land.

### Options Considered

| # | Option | Pros | Cons | Why Not |
|---|--------|------|------|---------|
| 1 | **(Chosen)** F5(c) hybrid storage+API | Schema evolution cheap + compile-time API safety + JSONL inspectable + 7th type is Props key | Accessor functions per-type | None — R2 convergence |
| 2 | F5(a) first-class typed structs end-to-end | Strong compile-time guarantees | 7th type = struct + migration + tests; brittle | R2 falsified |
| 3 | F5(b) pure generic Node | Maximum flexibility | Runtime-only type safety; bug-prone | R2 conceded API layer safety worth maintenance |
| 4 | SQLite typed schema | Indexed queries; mature tooling | Heavy dep; not "aihaus aesthetic"; defer to v0.2 if perf demands | Out-of-scope v0.1 |

### Rationale

Hybrid F5(c) is the unique sweet-spot: storage stays append-friendly (matching aihaus's audit-jsonl + manifest-append per ADR-001), while API layer recovers compile-time safety where it matters. Adding 7th type is `<10 LOC` (new accessor struct + constructor); F5(a) would be `>100 LOC` (struct + migration + 6 switch sites).

### Consequences

1. Storage format MUST include `_v` on every record. v0.1 = `_v=1`. v0.2+ readers detect-and-skip unknown versions.
2. API surface adds 6 accessor types: `DecisionFrom`, `MilestoneFrom`, `StoryFrom`, `AgentFrom`, `HookFrom`, `SkillFrom` in `pkg/aihgraph/` public Go package.
3. Future type additions follow pattern: add type-tag, add JSONL records, add accessor + constructor. No migration.
4. Aihaus skills invoking `aih-graph query` get human-readable JSON with `type` tag; consuming pipelines branch on type without parsing.
5. schemagen (advisor-R2 amendment proposal) deferred to v0.2 per phase-researcher-R2 YAGNI argument — fixed 6 types in v0.1 don't need generator overhead.

### Rollback

`git revert` removes this ADR. Storage format change in M033 needs separate revert.

### References

- ADR-260515-A (privacy — storage path is per-repo XDG-namespaced)
- ADR-260511-A (heading shape template)
- ADR-260510-C (Options Considered shape)
- BRIEF.md Turn 12 Q4 (custom aihaus node types as build justification)
- BRIEF.md Turn 14 (monorepo F6 — node types accessible via Go API)
- PERSPECTIVE-architect-r2.md (hybrid F5(c) R2 pivot)
- PERSPECTIVE-phase-researcher-r2.md (schemagen YAGNI for v0.1)

---

## ADR-260515-C — aih-graph tree-sitter Go binding: provisional official binding lock with M032 pre-flight verification gate (M031/S04)

**Status:** Accepted (provisional pending M032 pre-flight verification)
**Date:** 2026-05-15
**Milestone:** M031/S04

### Context

aih-graph v0.1's AST extraction depends on a Go binding for tree-sitter. Two candidates: `smacker/go-tree-sitter` (community, MIT, SHA-pin culture per RESEARCH.md:138) vs `tree-sitter/go-tree-sitter` (official, newer, explicit release tagging). R2 converged on official based on "zero release tags" claim. However, per VERIFICATIONS.md (S02), this claim was NOT verified via live gh-api in either brainstorm (network blocked 3x) or M031/S02 (network blocked 4th time).

### Decision

aih-graph v0.1 **provisionally locks `tree-sitter/go-tree-sitter` (official)** with a binding M032 pre-flight verification gate:

1. **Provisional default:** official `tree-sitter/go-tree-sitter`, MIT.
2. **M032 pre-flight gate (BINDING):** M032's first agent dispatch MUST re-run the 8 verification commands from VERIFICATIONS.md §G on live-network BEFORE writing any Go code that imports tree-sitter. If verifications:
   - **PASS** → proceed with official binding lock.
   - **CONTRADICT** (e.g., smacker has 2+ tags AND covers more langs AND maintained) → M032 commits ADR-260515-C-amend-01 BEFORE Go code commit. Amendment may flip choice to smacker, document hybrid, or maintain official with new rationale.
   - **STILL BLOCKED** → M032 issues `phase-advance --to paused --class external-dep-down --reason "tree-sitter binding verification still blocked"`. Resume via `/aih-resume`.
3. **5 required grammars for v0.1 (per Q4):** tree-sitter-bash, -python, -javascript (covers JS+JSX), -typescript (covers TS+TSX), -go, -markdown (5 conceptual langs; 6 grammar modules per RESEARCH OQ-5).
4. **Path-C cascade rule (per F9 NIT):** if M032 verification reveals a grammar that's GPL/archived/unavailable, v0.1 scope shrinks. Cascade-update applies to: S06 PRD `## Language Coverage`, S09 CI workflow language matrix, this ADR section 3. M032 architect issues same-PR amendments to all three.

### Options Considered

| # | Option | Pros | Cons | Why Not |
|---|--------|------|------|---------|
| 1 | **(Chosen)** Provisional official + M032 pre-flight gate | Verifiable downstream; no flow-state lock on unverified data; explicit cascade rule | Provisional, not yet truly locked | None — provisional is honest |
| 2 | Lock official NOW from R2 web-search citations | Faster; matches panel consensus | RESEARCH.md:138 not verified live; substrate §1.2 flagged | M026 "we'll verify later" anti-pattern; CHALLENGES.md C3 |
| 3 | Lock smacker as default | Larger ecosystem per snippets; 30+ langs | "Zero tags" suggests less version discipline; less aihaus tag-discipline alignment | Provisional favors official; C amendment can flip |
| 4 | Shell out to `ast-grep` CLI | Avoids binding choice | Wrong abstraction — typed AST nodes vs pattern matches; subprocess cost | Phase-researcher-R2 rejected |

### Rationale

The verification gate at M032 pre-flight is the load-bearing discipline. M031's spec-only nature means binding choice doesn't yet block code commit. Provisional lock + downstream gate gives aihaus freedom to ship M031 design package without flow-state pretending to verify what cannot be verified in this session. CHALLENGES.md C3 explicitly named "we'll verify later" as the M026 anti-pattern; this ADR institutionalizes verification at the actual decision-load-bearing point.

### Consequences

1. M032's first agent dispatch MUST execute verification commands as story-block-1 deliverable. NO Go code lands before verification PASS or BLOCKED-honest-pause.
2. If verifications contradict default, M032 also commits ADR-260515-C-amend-01 before any Go code commit. Original remains in `decisions.md` for audit trail.
3. v0.1's grammar list may shrink if Path-C fires. Cascade applies to PRD + CI spec.
4. Aih-graph build uses `go.mod` with specific commit SHAs (not loose `latest`) — enforced in M032 regardless of binding choice.

### Rollback

`git revert` removes this ADR. If smacker preferred post-verification, ADR-amendment is the canonical fix, not revert.

### References

- ADR-260515-A (privacy)
- ADR-260515-B (data model)
- ADR-260511-A (heading shape template)
- ADR-260510-C (Options Considered shape)
- VERIFICATIONS.md §G (M032 pre-flight contract — this ADR's load-bearing gate)
- RESEARCH.md:138 (provisional "zero tags" claim; superseded by M032 verification)
- CHALLENGES.md C3 (gh-api unverified — directly addressed)
- BRIEF.md Turn 14 (monorepo — binding lives in `aihaus-flow/aih-graph/go.mod`)

---

## ADR-260515-D — aih-graph integration model: monorepo with direct binary invocation, no loose adapter, MCP deferred to v0.2 (M031/S05)

**Status:** Accepted
**Date:** 2026-05-15
**Milestone:** M031/S05

### Context

aih-graph is being built (M032-M040) as a Go binary inside aihaus-flow monorepo (per BRIEF.md Turn 14 user lock — no sibling repo). aihaus agents need to invoke aih-graph at runtime. Two F6 patterns debated: (a) tight direct binary invocation vs (b) loose adapter skills. R2 converged on (b) — but phase-researcher-R2 argued against in final round: "direct Bash in v0.1; MCP search-and-replace at v0.2."

### Decision

aih-graph v0.1 ships **tight integration via direct binary invocation**:

1. **Binary location (canonical):** `${CLAUDE_PROJECT_DIR}/aih-graph/bin/aih-graph` after M032's `go build`. Pre-build dev invocation: `go run ./aih-graph` from repo root.

2. **Aihaus skill invocation pattern.** Skills + agent prompts invoke via Bash:
   ```bash
   bash $CLAUDE_PROJECT_DIR/aih-graph/bin/aih-graph query "<question>" --budget 2000
   ```
   Or via thin wrapper `pkg/scripts/aih-graph-wrapper.sh` (M039) for stable invocation surface.

3. **NO loose-adapter skill in v0.1.** No `aih-graph-query`/`aih-graph-refresh` skills ship. Adapter pattern rejected:
   - Skills are markdown wrappers; add indirection without computational value.
   - Bash is already first-class in aihaus.
   - Agent prompts include Bash command directly without skill registration overhead.

4. **MCP server deferred to v0.2.** Native MCP integration (typed tool surface) explicitly out of v0.1. v0.2 ships `aih-graph mcp` subcommand exposing query/save-result via stdio MCP transport.

5. **Aihaus integration touchpoints (M039):**
   - `pkg/scripts/install.sh` builds aih-graph during install: `(cd "${REPO}/aih-graph" && go build -o bin/aih-graph ./cmd/aih-graph)`.
   - `pkg/.aihaus/hooks/aih-graph-refresh.sh` (NEW M039) invokes `aih-graph build` on milestone-close / per-commit / on-demand. Lifecycle TBD M039.
   - Agent prompts (M039 architecture handoff; PM estimate ~15 advisory per F5 NIT) gain 1-2 line addendum suggesting `aih-graph query` for structural lookup.

### Options Considered

| # | Option | Pros | Cons | Why Not |
|---|--------|------|------|---------|
| 1 | **(Chosen)** F6 tight — direct binary invocation, no adapter, MCP v0.2 | Minimum indirection; aihaus skills + agents call binary directly | Skill prompts hardcode binary path | None — phase-researcher-R2 argue-against |
| 2 | F6(b) loose adapter — new query+refresh skills | Insulates skill prompts from binary location | Indirection without compute; 2 skill defs to maintain | Rejected per phase-researcher-R2 |
| 3 | MCP server in v0.1 | Typed tool surface; first-class Claude tool | aih-graph v0.1 has no MCP code; stdio MCP transport needed | Out-of-scope; v0.2 |
| 4 | HTTP daemon (localhost) + CLI client | Persistent index; lower invocation latency | Daemon lifecycle complexity; port allocation; security surface | Out-of-scope |

### Rationale

Simplest path is right for v0.1. Aihaus's agents already use Bash for tool invocations; one more `bash aih-graph query ...` is zero new conceptual surface. Loose-adapter would add 2 markdown files + 2 agent dispatch round-trips per invocation without changing what aih-graph actually does. MCP in v0.1 would force premature stdio-transport implementation before core graph engine stabilizes. Phase-researcher-R2's argue-against landed: "direct Bash + MCP search-and-replace at v0.2" is honest minimal-scope path.

### Consequences

1. Binary path change between v0.1 and v0.2+ is breaking integration change (search-and-replace across aihaus skill prompts). Mitigated by `pkg/scripts/aih-graph-wrapper.sh` in M039 as stable invocation surface.
2. Agent prompts (advisory ~15 per M039 PRD estimate) gain `aih-graph query` mention. Implementer agents at M039 handle bulk edit.
3. v0.2 MCP migration is structured refactor: implement `aih-graph mcp` subcommand + register MCP server in aihaus `settings.local.json` template + edit agent prompts to use new tool name. Anticipated M041+ work.
4. Build dependency: `aih-graph/bin/aih-graph` MUST exist post-install. Smoke check 84 (S08 spec) asserts.

### Rollback

`git revert` removes this ADR. M039 integration commits need separate revert.

### References

- ADR-260515-A (privacy)
- ADR-260515-B (data model)
- ADR-260515-C (binding)
- ADR-260511-A (heading shape template)
- ADR-260510-C (Options Considered shape)
- BRIEF.md Turn 14 (monorepo F6 lock)
- PERSPECTIVE-phase-researcher-r2.md (direct Bash + MCP search-and-replace at v0.2 argue-against)
- PERSPECTIVE-advisor-researcher-r2.md (loose-adapter proposal — REJECTED)

---

## ADR-260515-E — aih-graph v0.1 forever-scope: 5 langs + AST + JSONL + BFS + 6 custom types (M031/S10)

**Status:** Accepted
**Date:** 2026-05-15
**Milestone:** M031/S10

### Context

Per BRIEF.md Turn 12 Q4, user's build justification is **custom aihaus node types** (Decision/Milestone/Story/Agent/Hook/Skill as first-class). NOT graphify-parity. Contrarian C9 named this pattern "intentionally narrower forever" — v1.0 is the forever-scope, not stepping-stone to broader feature parity. This ADR commits aihaus to that narrowed scope and signals to future contributors that scope-expansion requires explicit ADR amendment.

### Decision

aih-graph v0.1 ships **5 langs + AST + JSONL + BFS + 6 custom aihaus node types** as **forever-scope**:

**IN v0.1:**
- 5 langs: bash, python, JavaScript/TypeScript (via tree-sitter-javascript + -typescript = 6 grammar modules per ADR-260515-C §3), Go, Markdown.
- AST extraction via tree-sitter (per ADR-260515-C provisional).
- JSONL storage (per ADR-260515-B).
- BFS query with `--budget N` token cap.
- 6 first-class aihaus node types (per ADR-260515-B).
- Privacy contracts (per ADR-260515-A).
- Tight monorepo integration (per ADR-260515-D).
- `--include-gitignored <glob>` flag OR `.aihignore` config (so `.aihaus/memory/*.md` can be ingested despite gitignore). Default `.aihignore` ships at aih-graph root with sensible aihaus defaults.

**OUT v0.1 (deferred or never):**
- Embeddings / vector retrieval (semantic similarity) — v0.2 ONNX-local candidate; not committed.
- Clustering (Leiden community detection) — v0.2+ candidate; not committed.
- HTML visualization (graph.html) — possibly never; CLI + JSONL output is enough.
- Cross-repo global graph — v0.2+ candidate gated on per-repo isolation invariant evolution.
- LLM-semantic extract (paid API backend) — never in v0.1; user installs graphify in parallel if they want it.
- Watch mode auto-rebuild — v0.2+ candidate.
- Git merge driver for graph.json files — never.
- 24+ other tree-sitter grammars (Rust, Java, Ruby, etc.) — never expected in v0.1; might land in v0.3+ if aihaus user-base broadens beyond polyglot-shell+Go.

### Path α vs Path β (per CHECK F6 NIT clarification)

This ADR ships in M031/S10 closeout as the 5th committed ADR (**Path α default**). Alternative Path β would defer this ADR to a follow-up milestone, leaving M031 with 4 ADRs committed. **Path α chosen** — v0.1 scope is load-bearing for M032-M040 story chain; deferring leaves the future milestones unanchored.

### Options Considered

| # | Option | Pros | Cons | Why Not |
|---|--------|------|------|---------|
| 1 | **(Chosen)** 5 langs + AST + JSONL + BFS + 6 types as forever-scope | Honest narrow scope; aligns with Q4 justification; ~3-4 month build estimate; no graphify-chase | Some users will request more langs / semantic features; deferral required | None — Q4 + C9 framing |
| 2 | v0.1 scope + explicit v0.2/v0.3 feature roadmap | Sets user expectations | Implies trajectory aih-graph might not honor; scope creep | Rejected — v1.0 IS forever-scope; v0.2+ are optional, not promised |
| 3 | Graphify-parity v1.0 trajectory | Feature-rich; competitive with graphify | 9-12 month commitment; competes on substrate aihaus doesn't own | Rejected per Q4 and C9 |
| 4 | Tiny MVP (1 lang only — Go) | Faster v0.1 | Doesn't cover aihaus's actual codebase (heavy bash + markdown) | Insufficient |

### Rationale

Q4 narrowed the build justification to "custom aihaus node types". Those 6 types fit cleanly in 5-lang AST + JSONL + BFS architecture. Anything beyond (embeddings, clustering, semantic) belongs to graphify's existing surface — installing graphify in parallel is the right answer for users who want those features. aih-graph stays focused on what graphify can't do (typed ontological retrieval over aihaus concepts). Forever-scope discipline keeps M032-M040 timeline bounded at ~3-4 months instead of 9-12.

### Consequences

1. M032-M040 story budget is fixed against v0.1 forever-scope. Any feature beyond requires explicit ADR amendment.
2. Aihaus's M041+ feature delivery resumes after M040; aih-graph remains in maintenance mode (bug fixes, grammar updates) rather than feature expansion.
3. Users who need semantic LLM extract, embeddings, clustering, or 24+ other langs install graphify in parallel. aih-graph + graphify coexist without conflict (different output paths).
4. `.aihignore` config ships at aih-graph repo root with sensible aihaus defaults (e.g., `node_modules/`, `.git/`, `.claude/audit/` excluded; `.aihaus/memory/*.md` INCLUDED despite gitignore via explicit allow). M035 architect locks final config schema.
5. v0.2+ features are OPTIONAL — proposed via ADR amendment with user-confirmation gate. No automatic trajectory.

### Rollback

`git revert` removes this ADR. M032-M040 milestones inherit unanchored scope and would re-derive expectations — costly.

### References

- ADR-260515-A (privacy)
- ADR-260515-B (data model — 6 types named here)
- ADR-260515-C (binding — provisional + 5-lang scope)
- ADR-260515-D (integration model)
- ADR-260511-A (heading shape template)
- ADR-260510-C (Options Considered shape)
- BRIEF.md Turn 12 Q4 (custom node types build justification)
- CHALLENGES.md C9 ("intentionally narrower forever" naming)
- CHALLENGES.md C2 (graphify-as-shipped vs aih-graph v1 honest comparison — surfaced in S06 aih-graph PRD)

---

## ADR-260515-C-amend-01 — M032 pre-flight gate scope correction (M032)

**Status:** Accepted (amends ADR-260515-C)
**Date:** 2026-05-15
**Milestone:** M032 (correction surfaced before any Go code commit)
**Amends:** ADR-260515-C

### Context

The original ADR-260515-C (M031/S04) instituted a pre-flight verification gate before "any Go code commit" — requiring gh-api verification of `smacker/go-tree-sitter` vs `tree-sitter/go-tree-sitter` binding choice BEFORE foundation work begins. That was conservative-correct in spirit (prevent flow-state decisions on unverified data) but **mechanically over-scoped**: the verification is only load-bearing at the point where tree-sitter is actually IMPORTED into the Go code, which is M033 (AST extraction), not M032 (foundation scaffold).

M032 foundation work — `go mod init`, CLI scaffold via stdlib `flag`, LICENSE, README placeholder, package directory structure — is **binding-agnostic**. Whether the eventual binding is smacker or official `tree-sitter/go-tree-sitter` doesn't change a single byte of M032's scaffold output. The pre-flight gate was therefore blocking work that has no dependency on the gate's outcome.

This amendment was surfaced after 8 consecutive blocked attempts of the gh-api verification through a sandbox egress block (consistent `dial tcp 4.228.31.149:443: timeout`). User question "pra que precisa de rede? pro go?" forced the design audit. Answer: Go itself needs zero network for M032 foundation. The gate's network requirement was an artifact of conflating "decision verification" with "code commit blocking."

### Decision

**Move the pre-flight gate from M032 → M033.**

1. **M032 pre-flight gate: NONE.** M032 ships scaffold (go.mod, cmd/aih-graph/main.go with stdlib flag, LICENSE, README.md, package directory structure, .gitignore) with zero network dependency.

2. **M033 pre-flight gate: ADR-260515-C verification (binding choice) + `go mod tidy`** (the first command that actually adds tree-sitter to `go.sum`). M033's first agent dispatch MUST:
   - Re-run the 8 gh-api verification commands from M031/S02 VERIFICATIONS.md §G.
   - If verifications PASS → official binding locked → proceed with `go mod tidy` to add tree-sitter dep + AST extraction implementation.
   - If verifications CONTRADICT → commit `ADR-260515-C-amend-02` (or further amendments) BEFORE adding tree-sitter dep.
   - If STILL BLOCKED → `phase-advance --to paused --class external-dep-down`.

3. **M032 acceptance criterion 1 (`go build ./aih-graph` succeeds)** is gated on Go toolchain being installed on the build machine — NOT on network. If Go isn't installed when M032 scaffold lands, that acceptance defers until next `/aih-resume` after Go installation (no network dependency).

4. **M032 acceptance criterion 4 (tree-sitter Go binding compiles + at least 1 grammar imports successfully)** is MOVED to M033 acceptance — that's the milestone where tree-sitter actually imports.

### Options Considered

| # | Option | Pros | Cons | Why Not |
|---|--------|------|------|---------|
| 1 | **(Chosen)** Move pre-flight gate from M032 → M033 | Mechanical correctness: verification gates where decision is load-bearing (at tree-sitter import); unblocks M032 scaffold without network | Slight delay in catching binding-choice errors (one milestone later) — but no Go code with binding dependency exists in M032 to be wrong | None — chosen as the design correction |
| 2 | Keep M032 pre-flight strict; wait for network indefinitely | Honors original ADR-260515-C literal | Over-conservative; blocks work that has zero dependency on the gate's outcome; wastes session cycles re-attempting verification when no decision was actually being made | Rejected as overcorrection |
| 3 | Skip the gate entirely; assume official binding without ever verifying | Faster | Re-introduces the M026 "we'll verify later = we won't" anti-pattern that CHALLENGES.md C3 named | Rejected |
| 4 | Add a Go-toolchain-presence gate to M032 | Catches Go-not-installed early | Cross-cuts with network gate; both are environmental; better to fail at first `go build` invocation than gate the scaffold writing | Not preferred — scaffold writing doesn't need Go installed |

### Rationale

ADR-260511-B trigger c(i) anticipatory-protection-on-new-flow remains the authority for the verification existing AT ALL — that's unchanged. What's amended is **WHERE the verification gate fires**. The gate should fire at the load-bearing decision point (`go mod tidy` adding tree-sitter dep + `import "github.com/.../tree-sitter"` in `internal/parser/`), not before the milestone whose work has zero dependency on the verification outcome.

This correction also surfaces a broader principle worth knowledge-logging: **environmental pre-flight gates should be at the point where the environmental resource is actually used, not as a blanket pre-milestone gate.** If a milestone's work doesn't touch the resource, no gate fires.

### Consequences

1. M032 ships scaffold immediately (no network required). Branch advances from `paused` → `running` → completion as scaffold files commit.
2. M033 first agent dispatch executes the 8-command gh-api verification BEFORE `go mod tidy` AND BEFORE writing any `internal/parser/*.go` that imports tree-sitter.
3. M032 acceptance criterion list updated:
   - Criteria 1 (`go build` succeeds): satisfied when Go toolchain available; until then deferred.
   - Criteria 4 (tree-sitter compiles): MOVED to M033 acceptance entirely.
4. ADR-260515-C original text remains in `pkg/.aihaus/decisions.md` for audit trail. This amendment supersedes its M032-specific gating language with M033-specific gating.
5. PRE-FLIGHT-GATE.md for M032 is renamed conceptually to "M032 scaffold-status" — captures what shipped + what defers.

### Rollback

`git revert` removes this amendment; original ADR-260515-C strict gate re-applies. If user prefers the strict pattern in retrospect, no aih-graph code is lost (only scaffold files exist) — they would need to be unmade in a separate revert.

### References

- ADR-260515-C (original; this amendment narrows its scope)
- ADR-260511-B trigger c(i) (anticipatory-protection authority — unchanged)
- M031/S02 VERIFICATIONS.md (the 8 gh-api commands; moved from M032 pre-flight to M033 pre-flight)
- CHALLENGES.md C3 (M026 "verify later" anti-pattern — addressed by gating at correct point, not by removing gate)
- User exchange surfacing the design flaw: "pra que precisa de rede? pro go?" (forced the audit that produced this amendment)

### Knowledge log entry (promote at S10 closeout-style update)

**K-M032-A:** Environmental pre-flight gates (network, toolchain, external services) should fire **at the point where the resource is actually used**, NOT as a blanket pre-milestone gate. Over-eager gating blocks work that has zero dependency on the gate's outcome and wastes session cycles. Test: if the milestone's scaffold/foundation work has NO dependency on the gated resource, the gate is misplaced.

---

## ADR-260515-E-amend-01 — v0.1 lang list: add PowerShell (M032)

**Status:** Accepted (amends ADR-260515-E)
**Date:** 2026-05-15
**Milestone:** M032 (surfaced after foundation commit; before M033 begins)
**Amends:** ADR-260515-E

### Context

The original ADR-260515-E locked v0.1 forever-scope at "5 langs: bash, python, JS/TS, Go, Markdown". User question — "why across 5 langs?" — surfaced that the choice was under-audited: of the 5 langs picked, only **bash** and **Markdown** are load-bearing for aihaus's own substrate. Python is used minimally (~30 LOC fallback in `merge-settings.sh`); JS/TS and Go are ZERO usage in aihaus-flow itself; **PowerShell** is used (in `install.ps1` for Windows installer) yet **was left OUT of the list**.

The 5-lang list reflects "popular langs that fit on one hand" + assumptions about typical aihaus user codebases (React/Next.js frontend + Python/Go backend + bash devops + markdown docs) — not a survey of aihaus's actual install base, which remains unknown per CHALLENGES.md L1.

This amendment surfaces the most honest minimal correction: **add PowerShell** so the lang list at least honestly covers aihaus's own usage. The deeper question (whether to make grammars pluggable, or to do an actual install-base survey) is deferred to a future amendment if the design needs grow.

### Decision

aih-graph v0.1 forever-scope lang list is **6 langs**, not 5:

1. **bash** — load-bearing for aihaus (32 hooks + 5+ scripts).
2. **Markdown** — load-bearing for aihaus (skills, agents, ADRs, docs, memory files).
3. **PowerShell** — load-bearing for aihaus (`install.ps1` Windows installer; tree-sitter-powershell grammar available per smacker README + dep list).
4. **Python** — typical user assumption (FastAPI backends, ML pipelines, scripts).
5. **JavaScript / TypeScript** — typical user assumption (React/Next.js frontends; covered by 2 grammar modules: tree-sitter-javascript + tree-sitter-typescript).
6. **Go** — typical user assumption (CLI tools, microservices, devops).

**Total grammar modules: 7** (the 6 langs above; TS/JS split into 2 grammar modules per RESEARCH OQ-5 convention).

### Options Considered

| # | Option | Pros | Cons | Why Not |
|---|--------|------|------|---------|
| 1 | **(Chosen)** Add PowerShell → 6 langs / 7 grammar modules | Honest about aihaus's own usage; small incremental scope; tree-sitter-powershell grammar already available | Still "feels right" not "audited"; doesn't address JS/TS/Go assumption gap | Acknowledged as the minimal honest correction the user explicitly authorized |
| 2 | Plug-in architecture (2 mandatory: bash+Markdown; rest pluggable) | Honors actual aihaus coverage; reduces maintenance; user-extensible | Bigger architectural change; M033 architect rewrites grammar-loader interface | User chose (d) — minimal honest correction over architectural shift |
| 3 | Survey-driven (ship what install base uses) | Most defensible | Install base unknown per CHALLENGES.md L1; not actionable | Deferred |
| 4 | Keep at 5 langs, document under-auditedness | Smallest blast radius | Perpetuates the gap; doesn't even include PowerShell which aihaus uses today | Rejected — leaves known issue unaddressed |

### Rationale

Two principles in tension:
- **Forever-scope discipline** (ADR-260515-E original): don't expand without ADR; v0.1 is the forever scope.
- **Audit honesty** (K-M032-A surfaced via this same exchange): design choices should be grounded in actual usage, not assumption.

The 5-lang list violated audit-honesty by excluding aihaus's own PowerShell usage. Adding PowerShell brings the list to minimal honest coverage of aihaus-self. The remaining 3 langs (Python, JS/TS, Go) stay in v0.1 as typical-user-codebase assumptions — flagged here as "assumption-based, not surveyed" so future amendments can re-audit if install-base data ever surfaces.

This amendment does NOT switch to plug-in architecture (option 2) — that's a larger design shift the user chose not to pursue at this point. v0.1 stays fixed-list; the list is just 1 lang longer + 1 grammar module longer.

### Consequences

1. **M033 acceptance** updated: 6 langs / 7 grammar modules to integrate (was 5 / 6).
2. **`aih-graph/PRD.md`** updated: Language Coverage section reflects 6 langs.
3. **ADR-260515-C "5 required grammars"** language re-aligned: 6 required grammars now (bash + python + javascript + typescript + go + markdown + **powershell**).
4. **Path-C cascade rule** (per ADR-260515-C §4) extends to PowerShell — if `tree-sitter-powershell` is unavailable/GPL/archived at M033 verification, scope shrinks correspondingly (back to 5, dropping PS).
5. **CI workflow spec (S09)** Language Matrix: smoke tests must cover PS in addition to other 5.
6. **Knowledge surfaced (K-M032-B):** "feels right" lang lists deserve an audit pass against actual aihaus usage before locking forever-scope. The PowerShell omission was visible in 60 seconds of `find pkg/scripts/ -name '*.ps1'` — that audit should have been routine in M031 architect's work.

### Rollback

`git revert` removes this amendment; lang list reverts to 5. PowerShell stays out. No code-impact yet since M033 hasn't begun — M033 architect would have caught the omission during AST extraction implementation otherwise.

### References

- ADR-260515-E (original; this amendment extends its lang list)
- ADR-260515-C (re-aligned: 6 required grammars now, not 5)
- CHALLENGES.md L1 (install base unknown — survey-driven option (3) is not actionable)
- User exchange: "why across 5 langs?" — forced the audit surfacing PowerShell omission
- K-M032-A (env pre-flight gate scoping correction — paired knowledge entry)
- K-M032-B (lang list audit honesty — knowledge surfaced by this amendment)

---

## ADR-260515-D-amend-01 — install.sh Go pre-flight check with interactive 3-way prompt (M032)

**Status:** Accepted
**Date:** 2026-05-14
**Milestone:** M032 (design-audit amendment; implementation M039)
**Amends:** ADR-260515-D §5 (install.sh `go build` step — was implicit, now explicit pre-flight)

### Context

ADR-260515-D §5 specified that `pkg/scripts/install.sh` builds aih-graph during install: `(cd "${REPO}/aih-graph" && go build -o bin/aih-graph ./cmd/aih-graph)`. This implicitly required Go 1.22+ on the user's machine but did NOT specify pre-flight detection or graceful fallback. Post-M032 design audit surfaced the question: what happens when a user runs `install.sh` without Go installed?

User position (verbatim, 2026-05-14 turn): "aihaus é um projeto para desenvolvedores, eles instalam em suas maquinas e trabalham em repositorios diferentes, por isso acho que precisa do go como critério" — Go is a legitimate install criterion for a developer-tools project, NOT user-hostile friction.

Three options surfaced during design audit:
1. **Hard fail** — `command -v go || exit 1` with install link. Cleanest mental model ("aihaus needs Go, period"). Drops M037 binary distribution scope.
2. **Soft warn + binary fallback** — try `go build`, fall back to GitHub Releases binary download. Preserves M037 scope; more code; more resilient offline.
3. **Interactive prompt** — when Go absent, ask user: install Go now / download pre-built binary / abort.

User chose option 3 (interactive prompt).

### Decision

`pkg/scripts/install.sh` and `pkg/scripts/install.ps1` ship a **Go pre-flight check with interactive 3-way prompt** at install time:

1. **Pre-flight detection.** Before invoking `go build` for aih-graph (per ADR-260515-D §5), check `command -v go >/dev/null 2>&1` (bash) / `Get-Command go -ErrorAction SilentlyContinue` (PowerShell). If found AND `go version` reports `go1.22+` → proceed silently. If Go missing OR version < 1.22 → enter interactive prompt.

2. **Interactive prompt shape (binding).** Print:
   ```
   aihaus requires Go 1.22+ to build aih-graph (mandatory memory engine).
   Detected: <none | go1.X.Y (too old)>.

   Options:
     [1] Pause install — I'll install Go now (https://go.dev/dl/) and re-run install.sh
     [2] Download pre-built binary from GitHub Releases (skip go build this install)
     [3] Abort install

   Choice [1/2/3]:
   ```

3. **Branch behavior:**
   - **[1] Pause** → print `Re-run install.sh after installing Go. Exiting cleanly (no partial state written).`; exit 0; no `.aihaus/` writes occur after this point.
   - **[2] Binary fallback** → invoke `pkg/scripts/install-aih-graph-binary.sh` (NEW, M039 spec) which downloads the matching platform binary from GitHub Releases per M037 spec. On failure → fall back to choice [3].
   - **[3] Abort** → print `aihaus install aborted by user.`; exit 2.

4. **Non-interactive mode.** When `AIHAUS_NONINTERACTIVE=1` (CI, scripted installs) AND Go missing → default to binary fallback (option [2]). When `AIHAUS_NO_GO_CHECK=1` → skip pre-flight entirely (user takes responsibility; advanced opt-out).

5. **M037 scope preserved.** Because option [2] (binary fallback) remains a first-class path, M037 (CI cross-compile + GitHub Releases binary distribution) stays in scope as originally specified in ADR-260515-E §4. NOT dropped.

6. **PowerShell parity.** `install.ps1` ships byte-equivalent prompt UX with `Read-Host` for choice input. Verified via smoke-test (M039 scope).

7. **M033 pre-flight gate composition.** ADR-260515-C-amend-01 moved a different pre-flight gate (tree-sitter binding verification) from M032→M033. That gate fires at M033/S1 dispatch and is orthogonal to this install-time Go check. The two compose: install-time check guarantees Go exists; M033/S1 gate verifies the tree-sitter binding contract works with that Go install.

### Options Considered

| # | Option | Pros | Cons | Why Not |
|---|--------|------|------|---------|
| 1 | Hard fail + Go install link | Cleanest mental model; less code; drops M037 binary scope | Pure-Python devs forced to install Go SDK (~500MB) before aihaus useful | User chose option 3 |
| 2 | Soft warn + auto-fallback | Silent install; resilient offline | Hides Go install opportunity from devs who would install it; opaque about what happened | User chose option 3 |
| 3 | **(Chosen)** Interactive prompt 3-way | User controls path; surfaces Go install opportunity; binary fallback preserved | More install.sh code; prompt-UX in install (precedent) | None — selected by user 2026-05-14 |
| 4 | No check, build-or-fail loud | Zero new install code | Cryptic `go: command not found` error mid-install; leaves partial state | Rejected — bad UX for documented dev audience |

### Rationale

User's framing — "aihaus é projeto para desenvolvedores" — is correct empirically: aihaus's audience builds software for a living. A Go install link is not friction; it's surfacing a legitimate dependency. But forcing Go SDK on a Python-only dev is overreach. The interactive prompt threads the needle: developers who CAN install Go are nudged toward it (path [1]); developers who can't or won't get a binary fallback (path [2]); CI/scripted installs default to binary via env var (`AIHAUS_NONINTERACTIVE=1`).

This amendment also resolves a latent ambiguity in ADR-260515-D §5: the original "install.sh builds aih-graph" prose implied Go was required but never said so. New developers reading ADR-260515-D would not know the install behavior under missing-Go. Explicit pre-flight + 3-way prompt eliminates that ambiguity.

K-M032-C (new knowledge entry, paired with this amendment): **Interactive prompts at install time are acceptable for ENV pre-flight checks when fallback paths exist.** Pattern is: detect missing dep → surface choice → preserve all reasonable paths → fail loud only when user explicitly chooses abort. Contrast with K-M032-A: blanket pre-milestone gates over-correct; resource-use-point gates fire only when needed. install-time Go check is a resource-use-point gate (Go is used immediately at install) — not blanket pre-milestone.

### Consequences

1. **install.sh + install.ps1 gain ~30-40 LOC** for pre-flight + prompt + branch handling. Implementation lands in M039 (Aihaus integration milestone — already planned to modify install.sh per ADR-260515-D §5).
2. **`pkg/scripts/install-aih-graph-binary.sh` (NEW M039)** ships as the [2] branch handler. Downloads platform-matched binary from GitHub Releases; verifies SHA256 per M037 spec.
3. **M037 scope preserved** — CI cross-compile matrix + release artifacts remain in scope. Without [2] branch, M037 would have been candidate for descope.
4. **New env vars (M039 scope):** `AIHAUS_NONINTERACTIVE` (defaults binary fallback when Go missing); `AIHAUS_NO_GO_CHECK` (skip pre-flight entirely — opt-out). Documented in install.sh `--help` and `CLAUDE.md`.
5. **Update.sh implication:** `pkg/scripts/update.sh` should NOT re-run the prompt — it inherits the Go-or-binary path chosen at install time. If user originally chose [2], update.sh re-downloads binary; if originally chose [1], update.sh runs `go build`. State recorded in `.aihaus/.install-mode` (`go` | `binary`) — NEW sidecar, written by install.sh, read by update.sh.
6. **M039 story breakdown** in `aih-graph/PRD.md` needs new story slot for "install.sh Go pre-flight + prompt + binary-fallback wiring" — ~1 story addition. Amendment-time PRD.md edit handled in this same commit.

### Rollback

`git revert` removes this amendment + PRD.md edit. Pre-flight check + prompt code can be removed from install.sh/.ps1 separately if user later prefers hard-fail or auto-fallback. Sidecar `.aihaus/.install-mode` becomes orphan but harmless.

### References

- ADR-260515-D (parent: install.sh `go build` step — §5 amended)
- ADR-260515-C-amend-01 (M033 pre-flight gate move — compositional precedent for env-check timing)
- ADR-260515-E (v0.1 forever-scope — confirms aih-graph mandatory addon, justifying install-time gate)
- ADR-M028-CURATE-A (env-var lifecycle pattern — `AIHAUS_NONINTERACTIVE` follows precedent)
- K-M032-A (resource-use-point env gates — composition rule)
- K-M032-C (interactive prompt for ENV pre-flight with fallback — NEW, paired)
- User exchange 2026-05-14 ("aihaus é projeto para desenvolvedores...precisa do go como critério")
- M037 spec (binary release matrix — preserved by option [2] choice)
- M039 spec (install.sh integration milestone — implementation lands here)

---

## ADR-260515-B-amend-01 — Data model pivot: JSONL → SQLite + sqlite-vec (M032)

**Status:** Accepted
**Date:** 2026-05-15
**Milestone:** M032 (design-audit amendment; implementation M034)
**Amends:** ADR-260515-B (Node/Edge data model — hybrid generic+typed JSONL → hybrid generic+typed SQLite+sqlite-vec)

### Context

ADR-260515-B locked **hybrid generic+typed JSONL storage** with a custom Go writer/reader, BFS query implementation, and 6 typed accessor structs. The justification was simplicity: append-only file, human-greppable, minimal dependencies.

Post-M032 design audit surfaced **sqlite-vec** (`github.com/asg017/sqlite-vec`) as a production-ready SQLite extension providing native vector storage + KNN search. Combined with SQLite's relational substrate, this collapses 3-4 milestones of custom Go infrastructure (storage layer, query engine, embedding store) into thin wrappers over SQL + `vec_distance()`.

User exchange 2026-05-15 ("vamos com sqlite vec") ratified the pivot after empirical analysis:
- 95% of aihaus's target repos (solo dev → enterprise app, NOT Google-scale monorepos) fit comfortably in sqlite-vec brute-force envelope (100k vectors @ int8 = ~25ms query latency)
- Privacy contract (ADR-260515-A) composes naturally: per-repo `.db` file = isolation grátis; `--purge` = `rm file.db`; NDA opt-out preserved
- Vector embeddings (originally scoped to v0.2+ per ADR-260515-E) become tier-1 v0.1 feature at near-zero marginal cost
- Single-binary distribution preserved: `mattn/go-sqlite3` + sqlite-vec extension load at runtime, no daemon lifecycle

### Decision

aih-graph v0.1 ships **SQLite + sqlite-vec storage** with hybrid generic+typed access:

1. **Storage substrate.** Single SQLite database file per repo (location per ADR-260515-A privacy contract: `$XDG_STATE_HOME/aih-graph/<repo-hash>/graph.db`). Stock SQLite + loaded sqlite-vec extension (single .dll/.so/.dylib bundled per platform per ADR-260515-C-amend revisions).

2. **Schema (binding contract):**
   ```sql
   CREATE TABLE nodes (
     id INTEGER PRIMARY KEY,
     type TEXT NOT NULL,           -- 'Decision' | 'Milestone' | 'Story' | 'Agent' | 'Hook' | 'Skill' | 'Symbol' | 'File' | ...
     identifier TEXT NOT NULL,     -- 'ADR-260514-B' | 'M030' | 'pkg/scripts/install.sh:117' | ...
     properties JSON NOT NULL,     -- type-specific fields (title, body, status, etc.)
     created_at INTEGER NOT NULL,
     updated_at INTEGER NOT NULL,
     UNIQUE(type, identifier)
   );

   CREATE TABLE edges (
     id INTEGER PRIMARY KEY,
     from_id INTEGER NOT NULL REFERENCES nodes(id),
     to_id INTEGER NOT NULL REFERENCES nodes(id),
     type TEXT NOT NULL,           -- 'contains' | 'references' | 'calls' | 'amends' | 'supersedes' | ...
     properties JSON,
     created_at INTEGER NOT NULL
   );

   CREATE INDEX idx_nodes_type ON nodes(type);
   CREATE INDEX idx_nodes_identifier ON nodes(identifier);
   CREATE INDEX idx_edges_from ON edges(from_id);
   CREATE INDEX idx_edges_to ON edges(to_id);

   -- sqlite-vec virtual table; int8 quantized per dim guidance
   CREATE VIRTUAL TABLE vec_nodes USING vec0(
     node_id INTEGER PRIMARY KEY,
     embedding float[1024] distance_metric=cosine
   );
   ```

3. **Hybrid typed access.** Public API in `pkg/aihgraph/` exposes typed accessor methods that wrap parametrized SQL. Example:
   ```go
   type Decision struct { ID int64; Identifier string; Status string; Body string; ... }
   func (g *Graph) GetDecision(id string) (*Decision, error)
   func (g *Graph) FindSimilar(text string, k int) ([]Node, error)  // vec_distance KNN
   func (g *Graph) Query(question string, budget int) ([]Node, error)  // hybrid SQL+vec
   ```
   No code generation; typed accessors hand-written for 6 aihaus types (Decision, Milestone, Story, Agent, Hook, Skill) + 1 generic (Symbol/File).

4. **Embedding column is optional.** Nodes can be inserted without embeddings — pure structural graph still works (BFS query unchanged). Embedding generation pipeline (M035) is opt-in by node type: high-value types (Decision/Milestone/Story/Agent/Hook/Skill) embedded by default; Symbol/File embedded only with `--embed-all` flag.

5. **Query model.** Three query modes:
   - **Structural BFS** (`aih-graph query --bfs "ADR-260514-B"`) — recursive CTE over edges, no embeddings needed
   - **Vector similarity** (`aih-graph query --semantic "how does merge-settings work"`) — KNN over vec_nodes
   - **Hybrid** (`aih-graph query "..."` default) — SQL pre-filter (e.g., type='Decision') + KNN ranking + edge traversal, single SQL statement

6. **Backward-compat with prior ADR-260515-B prose.** The "hybrid generic+typed" intent is preserved — same accessor shape, same 6 custom types as first-class. What changes is the substrate: SQL table + JSON properties column instead of JSONL line + type-tag prefix.

### Options Considered

| # | Option | Pros | Cons | Why Not |
|---|--------|------|------|---------|
| 1 | JSONL (original ADR-260515-B) | Append-only, human-greppable, zero ext dep | Custom Go reader/writer/query/index; vector requires v0.2+ ground-up build | Pivot per user 2026-05-15 — sqlite-vec saves 2-3 milestones |
| 2 | **(Chosen)** SQLite + sqlite-vec | Battle-tested substrate; vector tier-1 in v0.1; hybrid SQL+vec in single query; embed-friendly | One C extension dep; brute-force KNN ceiling ~1M vectors | Selected — covers 95% of target repos |
| 3 | PostgreSQL + pgvector | Industrial-strength vector + relational; HNSW | Server lifecycle; not embeddable in single binary; breaks XDG isolation pattern | Out-of-scope; aihaus is solo-dev/small-team positioning |
| 4 | LanceDB / DuckDB-VSS | Modern, columnar, fast | More complex deps; younger projects than SQLite | Less aligned with single-file-per-repo isolation model |
| 5 | Pinecone/Qdrant cloud | Best-in-class vector | External service; breaks NDA opt-out (ADR-260515-A); subscription cost | Categorically excluded by privacy contract |

### Rationale

User-stated goal (2026-05-15 turn): vector memory functioning in agents. Original v0.1 scope deferred vector to v0.2+ — 2-3 month gap before user's goal becomes reachable. sqlite-vec collapses that gap to ~2 weeks of additional M035 scope (embedding pipeline) while preserving every constraint of ADR-260515-A (privacy) and ADR-260515-D (integration model).

The custom JSONL + BFS implementation in the original ADR was a tactical simplification to avoid dependency complexity. sqlite-vec is a SINGLE extension file with a 5-function API surface (vec0 virtual table, vec_distance, vec_quantize, vec_normalize, vec_length). Dependency complexity is lower than expected — comparable to adding tree-sitter (which the project already committed to). The compose with mattn/go-sqlite3 (ubiquitous, stable since 2014) is straightforward.

Brute-force KNN ceiling concern: empirical analysis shows aihaus's target repos (solo dev project up to enterprise SaaS app — NOT Google-scale monorepos) operate in <500k-vector territory where sqlite-vec serves sub-100ms queries with int8 quantization. The 5% of use cases above this ceiling (massive monorepos) are categorically out-of-scope per existing aihaus positioning in CLAUDE.md.

Privacy preservation (ADR-260515-A): per-repo `.db` file IS the isolation primitive. No daemon, no shared state, no cross-repo contamination. `--purge` = `rm file.db`. NDA opt-out = don't run `aih-graph build`. Composes byte-cleaner than the prior JSONL design (which still needed per-repo dir + multiple files).

### Consequences

1. **`internal/storage/` rewrite (M034).** JSONL writer/reader scaffold (placeholder dirs from M032) gets replaced with SQLite schema migrations + `database/sql` wrappers + sqlite-vec extension loader. Estimated 3-5 days of focused work.

2. **`internal/query/` becomes thinner (M035).** Recursive CTE for BFS (10-20 lines of SQL); typed accessors are parametrized SQL queries (~30-50 lines per type); KNN via `vec_distance()`. Estimated 3-5 days. Original ADR-260515-B's "6 typed accessor structs" target is unchanged in shape.

3. **Embedding pipeline (M035).** Pluggable provider interface (`internal/embed/`). v0.1 ships with Voyage AI provider (Anthropic's recommended embedding partner; takes API key via env var) as default; local provider (e.g., `all-MiniLM-L6-v2` via Go ONNX runtime) as optional fallback for offline/NDA contexts. Embedding generation triggers on graph build for high-value node types; SHA-based change detection avoids re-embedding unchanged content. Estimated 1 week.

4. **CI cross-compile (M037) gains sqlite-vec extension bundling.** Per-platform bundle: `linux-amd64/sqlite-vec.so`, `darwin-amd64/sqlite-vec.dylib`, `darwin-arm64/sqlite-vec.dylib`, `windows-amd64/sqlite-vec.dll`. Either downloaded at build-time from sqlite-vec's GitHub Releases (recommended) or vendored in repo (avoid — license + size). Estimated +1 day vs original M037.

5. **Smoke check 84 (build smoke) covers DB creation + sqlite-vec extension load.** New sub-assert: schema applied successfully + `SELECT sqlite_version()` returns + `SELECT vec_version()` returns. Trivial.

6. **`pkg/aihgraph/` public API unchanged in shape from ADR-260515-B.** Typed accessors maintain same Go method signatures. Internal implementation changes from JSONL scan → SQL query. Consumers of the library see no breaking API change.

7. **Vector promoted from "v0.2+ candidate" to "v0.1 tier-1 feature"** per ADR-260515-E-amend-02 (paired with this amendment).

8. **CGO toolchain decision (ADR-260515-C-amend-01 M033/S1 gate) unchanged in shape but now BLOCKS more.** Both tree-sitter binding AND sqlite-vec extension load + mattn/go-sqlite3 require CGO. If M033/S1 plan-checker concludes CGO is irrecoverable on Windows-default toolchains, the entire stack pivots. Risk mitigation: validate sqlite-vec build under selected toolchain as part of M033/S1 pre-flight.

9. **No re-amendment of ADR-260515-D (integration model).** Direct binary invocation pattern unchanged — `aih-graph query "..." --budget N` still the canonical invocation. SQLite is invisible to aihaus agents.

### Rollback

`git revert` removes this amendment. Original ADR-260515-B JSONL design re-becomes binding. M034-M035 implementation work would re-target JSONL. No rollback risk in M032-M033 timeframe since no implementation code exists yet — pure design pivot.

If sqlite-vec proves untenable mid-implementation (M034+): revert to ADR-260515-B JSONL OR pivot to alternative substrate (DuckDB-VSS, LanceDB). Both are documented in "Options Considered" above.

### References

- ADR-260515-B (parent: data model — substrate replaced; type taxonomy preserved)
- ADR-260515-A (privacy contract — preserved unchanged; per-repo .db file aligns naturally)
- ADR-260515-D (integration model — preserved unchanged; CLI invocation contract intact)
- ADR-260515-E-amend-02 (paired: vector promoted to v0.1 tier-1 forever-scope)
- ADR-260515-C-amend-01 (M033/S1 pre-flight gate — now validates both tree-sitter AND sqlite-vec under chosen toolchain)
- `github.com/asg017/sqlite-vec` — Alex Garcia (asg017), v0.1.x stable since 2024-08
- `github.com/mattn/go-sqlite3` — Go SQLite binding (stable since 2014, ubiquitous)
- User exchange 2026-05-15 ("se usar sqlite-vec realisticamente um repositorio de projeto production grade vai se beneficiar ou nao?" → "vamos com sqlite vec")

---

## ADR-260515-E-amend-02 — v0.1 forever-scope: vector promoted from v0.2+ candidate to tier-1 (M032)

**Status:** Accepted
**Date:** 2026-05-15
**Milestone:** M032 (design-audit amendment; implementation M035)
**Amends:** ADR-260515-E §IN v0.1 (vector promoted in) + §Out-of-scope (vector removed); paired with ADR-260515-B-amend-01

### Context

ADR-260515-E locked v0.1 forever-scope **excluding** vector embeddings and similarity retrieval — listed as "v0.2+ candidate" alongside clustering and additional language grammars. Justification was the JSONL substrate (per original ADR-260515-B) made vector retrofit expensive: would require parallel embedding store, similarity index, separate query path.

ADR-260515-B-amend-01 (this same date) pivots the substrate to SQLite + sqlite-vec. Vector storage becomes a native first-class column accessible via `vec_distance()` in standard SQL queries — marginal scope cost is the embedding generation pipeline (1 week of M035 work), not 2-3 months of custom v0.2 infrastructure.

User goal (per 2026-05-15 turn): "vector memory functioning in agents" was the actual objective. Original v0.1 scope deferred that 5-8 months. Promoting vector to v0.1 collapses time-to-user-goal from 5-8 months to ~3 months calendar.

### Decision

aih-graph v0.1 forever-scope updated:

**IN v0.1 (additions):**
- Vector embeddings (1024-dim default; int8 quantized) stored via sqlite-vec `vec0` virtual table
- Pluggable embedding provider interface (`internal/embed/`)
- Two default providers: Voyage AI (paid API, default for online use) + local ONNX (e.g., all-MiniLM-L6-v2, fallback for offline/NDA contexts)
- Hybrid query (SQL pre-filter + KNN ranking + edge traversal in single statement)
- Embedding generation triggered on graph build for high-value node types (Decision/Milestone/Story/Agent/Hook/Skill) by default; `--embed-all` flag for full coverage including Symbol/File

**OUT of v0.1 (unchanged):**
- Semantic LLM extraction (paid LLM-driven node/edge extraction — distinct from embedding generation)
- Clustering (Leiden community detection)
- 24+ additional language grammars (only 6 langs per ADR-260515-E-amend-01)
- HNSW/IVF index (sqlite-vec brute-force only; sufficient for target repos per analysis)
- Re-ranking via LLM (`--rerank` flag deferred to v0.2+)

**Promoted FROM "v0.2+ candidate" (no longer deferred):**
- ~~Vector embeddings / similarity retrieval~~ → now v0.1 tier-1

### Options Considered

| # | Option | Pros | Cons | Why Not |
|---|--------|------|------|---------|
| 1 | Keep v0.2+ deferral (original ADR-260515-E) | Smallest v0.1 scope; clean separation | User goal ("vector memory") deferred 5-8 months; v0.2 milestone unstaffed | User pivot 2026-05-15 |
| 2 | **(Chosen)** Promote vector to v0.1 | Time-to-user-goal collapses to ~3mo; native via sqlite-vec marginal cost | +1 week M035 scope; embedding provider tier complexity | Selected per user direction |
| 3 | Promote vector AND clustering AND re-ranking | "Full v1.0 in one shot" | Scope explosion; ship date pushed to 6+ months | Rejected — preserve forever-scope discipline; ship narrow v0.1, expand by amendments |

### Rationale

Same logic as ADR-260515-B-amend-01: marginal cost of vector in sqlite-vec substrate is negligible. Keeping it deferred to v0.2 was a JSONL-substrate-imposed artifact, not a principled scope decision. With substrate pivoted, the principled decision flips to "include in v0.1".

Embedding provider tier (Voyage default + local fallback) preserves the NDA opt-out contract from ADR-260515-A: NDA-restricted contexts use local ONNX provider; everyone else gets Voyage's quality at modest cost.

Forever-scope discipline (Contrarian C9 from original brainstorm: "intentionally narrower forever") still intact — we DROP clustering, re-ranking, semantic LLM extraction, additional grammars. Only vector promoted; rest of out-of-scope list unchanged.

### Consequences

1. **M035 scope grows by ~1 week** (embedding pipeline). Total v0.1 timeline grows from ~6 weeks (per ADR-260515-B-amend-01 estimates) to ~7-8 weeks.

2. **PRD.md M033-M040 story breakdown rewritten** in this same commit (M032 amendment trio: ADR-B-amend-01 + ADR-E-amend-02 + PRD rewrite).

3. **Acceptance Criteria for v0.1** gains:
   - [ ] `aih-graph query --semantic "how does merge-settings work"` returns top-K relevant Decision/Milestone/Skill nodes by cosine similarity
   - [ ] Embedding generation runs in <60s for aihaus-flow repo (high-value nodes only)
   - [ ] Embedding skipped on subsequent builds for unchanged content (SHA-based change detection)
   - [ ] Local-only embedding provider available for NDA contexts (`--embed-provider local`)

4. **Voyage AI API key (or local provider) becomes runtime requirement for `--semantic` queries.** Documented in README. Graph build still works without embeddings (pure structural BFS). Vector queries gracefully fail with clear message if no embeddings exist.

5. **Cost transparency:** Voyage AI's pricing (per-token embedding) is documented in aih-graph README + agent prompt addenda; estimated cost for typical repo embedding: $0.01-0.10 per full rebuild.

### Rollback

`git revert` removes this amendment. Vector reverts to v0.2+ candidate status. M035 scope shrinks back to query+typed-accessors only. No implementation rollback risk (M035 not started).

### References

- ADR-260515-E (parent: forever-scope — vector promoted in; rest unchanged)
- ADR-260515-B-amend-01 (paired: data model pivot enables this scope change)
- ADR-260515-A (privacy contract — local-only provider preserves NDA opt-out)
- User exchange 2026-05-15 (sqlite-vec pivot ratification)
- Original brainstorm BRIEF.md C9 (contrarian "intentionally narrower forever" — preserved by promoting only vector, not also clustering/re-rank)

---

## ADR-260515-B-amend-02 — Pure-Go substrate: modernc/sqlite + Go-native KNN (M032)

**Status:** Accepted
**Date:** 2026-05-15
**Milestone:** M032 (design-audit amendment; implementation M034)
**Amends:** ADR-260515-B-amend-01 (sqlite-vec pivot from earlier today — C-extension SQLite + sqlite-vec → pure-Go SQLite + roll-own vector KNN)

### Context

ADR-260515-B-amend-01 (4 hours earlier this same date) pivoted from JSONL → SQLite + sqlite-vec. Implementation requires CGO to load `github.com/mattn/go-sqlite3` + sqlite-vec C extension. Empirical session experience proved CGO toolchain on Windows-without-admin is hostile:

- w64devkit gcc 16.1.0 portable: produces `pe-bigobj-x86-64` COFF objects; Go cgo's `debug/pe` parser fails (`optional header has unexpected Magic of 0x20af`). Cannot be disabled (binutils config-time choice).
- TDM-GCC 10.3.0 NSIS installer: silent install attempts crash with ACCESS_VIOLATION (-1073741819). Likely admin requirement disguised as installer bug.
- Chocolatey/MSYS2: require admin or interactive elevation.
- MSVC Build Tools 2022: 1-5GB install, hard admin requirement, hours to install fully.

User stated goal (2026-05-15): "vector memory functioning in agents". Critical insight on re-examination: **100% of aihaus's high-value memory content is markdown** (ADRs, Milestones, Stories, Agents YAML frontmatter, Hook script headers, Skills YAML frontmatter). AST extraction of Python/JS/Go/bash code files is nice-to-have but does NOT serve the stated goal — it's covered for graphify's broader generic use case, not aihaus's specific need.

User decision 2026-05-15 turn ("faz purego entao"): pivot substrate to pure-Go entirely. Drop CGO from v0.1.

### Decision

aih-graph v0.1 ships **pure-Go substrate**:

1. **SQLite driver:** `modernc.org/sqlite` — automated transpilation of SQLite C source to Go, dual-licensed BSD-3-Clause/MIT. Pure-Go, no CGO required. Trade-off: ~2-3x slower than mattn/go-sqlite3 on raw SQLite operations; for aihaus's scale (<500k nodes) imperceptible.

2. **Vector storage:** BLOB column `embedding` in `nodes` table (or separate `node_embeddings` table — schema TBD M034). Encoded as `[]float32` little-endian byte array, optionally int8-quantized. No virtual table, no extension load.

3. **KNN search:** Pure-Go implementation in `internal/embed/knn.go` (~100 LOC). Brute-force cosine/L2 over all embeddings. Optional: parallelize via goroutines for repos >50k vectors. SIMD acceleration via `gonum.org/v1/gonum/blas` if useful at scale (deferred to optimization pass; not v0.1 blocker).

4. **Schema (binding contract — updated from B-amend-01):**
   ```sql
   CREATE TABLE nodes (
     id INTEGER PRIMARY KEY,
     type TEXT NOT NULL,           -- 'Decision' | 'Milestone' | 'Story' | 'Agent' | 'Hook' | 'Skill'
     identifier TEXT NOT NULL,     -- 'ADR-260514-B' | 'M030' | ...
     properties JSON NOT NULL,     -- type-specific fields
     embedding BLOB,               -- nullable; []float32 LE-encoded; v0.1 dim=1024
     embedding_model TEXT,         -- 'voyage-3' | 'local-minilm' | NULL
     content_sha TEXT,             -- SHA-256 for change detection
     created_at INTEGER NOT NULL,
     updated_at INTEGER NOT NULL,
     UNIQUE(type, identifier)
   );

   CREATE TABLE edges (
     id INTEGER PRIMARY KEY,
     from_id INTEGER NOT NULL REFERENCES nodes(id),
     to_id INTEGER NOT NULL REFERENCES nodes(id),
     type TEXT NOT NULL,
     properties JSON,
     created_at INTEGER NOT NULL
   );

   CREATE INDEX idx_nodes_type ON nodes(type);
   CREATE INDEX idx_nodes_identifier ON nodes(identifier);
   CREATE INDEX idx_nodes_embedding_present ON nodes(id) WHERE embedding IS NOT NULL;
   CREATE INDEX idx_edges_from ON edges(from_id);
   CREATE INDEX idx_edges_to ON edges(to_id);
   ```

   Differences vs B-amend-01 schema: no `vec_nodes` virtual table; `embedding` is a regular BLOB column; partial index speeds "find all nodes with embeddings" KNN scan.

5. **Query model unchanged in shape** (3 modes — BFS / semantic / hybrid), but `semantic` and `hybrid` implementation is Go-side rather than SQL `vec_distance()` function. Hybrid pseudocode:
   ```go
   // SQL pre-filter (e.g., type='Decision')
   rows := db.Query("SELECT id, embedding FROM nodes WHERE type=? AND embedding IS NOT NULL", filter)
   // Go-side cosine ranking
   ranked := knn.Rank(queryEmb, rows, topK)
   // Edge expansion via recursive CTE on ranked IDs
   ```

6. **Public API in `pkg/aihgraph/`** unchanged from B-amend-01. Typed accessor method signatures preserved.

### Options Considered

| # | Option | Pros | Cons | Why Not |
|---|--------|------|------|---------|
| 1 | mattn/go-sqlite3 + sqlite-vec (B-amend-01) | C-speed; native vec_distance() in SQL | Requires CGO toolchain; Windows-without-admin hostile | Empirical CGO toolchain failure on this machine |
| 2 | **(Chosen)** modernc/sqlite + Go-native KNN | Zero CGO; single Go binary; works anywhere Go runs | 2-3x slower; ~100 LOC roll-our-own | Selected per user 2026-05-15 |
| 3 | crawshaw.io/sqlite (still CGO) | Different SQLite binding | Same CGO blocker | Same issue |
| 4 | bbolt + roll-own everything | Pure-Go embedded KV | Loses SQL — write/maintain custom query language | Excess scope; SQL valuable |
| 5 | BadgerDB + roll-own | Pure-Go KV with TTL | Same as #4 | Same |
| 6 | JSON files + grep (revert to ADR-260515-B original) | Simplest | Loses query power; no vector | Reverts user-approved progress |

### Rationale

modernc.org/sqlite is the canonical pure-Go SQLite for Go ecosystem. Used by Caddy, Tailscale's `tsweb`, several Anthropic SDK examples. Maturity: stable since 2020, tracks SQLite upstream. Performance: 2-3x slower than CGO mattn/go-sqlite3 on raw ops, irrelevant at aihaus scale (<500k nodes).

Go-native KNN at ~100 LOC is trivial maintenance burden. Cosine similarity = normalized dot product = float32 SIMD-friendly. Brute force on 100k 1024-dim vectors: ~50-200ms in pure Go (faster with gonum/blas SIMD; that's optimization, not v0.1 scope).

Distribution simplification: single Go binary, no platform-specific extension bundle, no `--bundle-sqlite-vec-extension` CI step. M037 CI cross-compile becomes trivial `GOOS=X GOARCH=Y go build`.

NDA opt-out preserved: same `--embed-provider local` flag; local embedding stays pure-Go (ONNX inference via `github.com/yalue/onnxruntime_go` if needed; or skip embeddings entirely with `--no-embed`).

### Consequences

1. **M034 implementation simpler.** modernc/sqlite imports = `_ "modernc.org/sqlite"`. Driver name = `sqlite`. Standard `database/sql` API. No extension load step.

2. **M035 embedding pipeline unchanged in design.** Provider interface same: Voyage AI (online), local ONNX (offline). Storage: write `embedding` BLOB column instead of `vec_nodes` virtual table row.

3. **M035 KNN implementation:** `internal/embed/knn.go` ~100 LOC. Brute-force cosine over `[]float32`. Goroutine fan-out for >50k vectors optional. No optimization in v0.1.

4. **M037 CI cross-compile drastically simplified.** 4-platform matrix is `GOOS=linux/darwin/windows GOARCH=amd64/arm64 go build`. Single binary output per platform. No sqlite-vec.so/dll/dylib bundling. **Saves 1-2 days of M037 work.**

5. **install.sh path simplification:** binary distribution becomes the default and primary path. Source-build (Go required) becomes contributor-only. ADR-260515-D-amend-01 3-way prompt remains valid (option [1] for contributors, [2] for users); but option [2] becomes the recommended default in install.sh prose.

6. **CGO toolchain dependency dropped entirely from v0.1.** ADR-260515-C M033/S1 pre-flight gate (per C-amend-01) is RETIRED — no toolchain to validate. See paired ADR-260515-C-amend-02.

7. **Performance ceiling:** brute-force KNN at 1M+ vectors becomes >1s. For aihaus's <500k target, fine. If future scale demands HNSW, that's v0.2+ (could swap to chewxy/hnsw or roll-own).

### Rollback

`git revert` removes this amendment. Reverts to ADR-260515-B-amend-01 (sqlite-vec C-extension stack). No implementation rollback risk (no code yet).

### References

- ADR-260515-B-amend-01 (parent: sqlite-vec pivot, partial revert)
- ADR-260515-C-amend-02 (paired: tree-sitter retirement, fully drops CGO requirement)
- ADR-260515-E-amend-03 (paired: forever-scope drops AST-for-code-files)
- `modernc.org/sqlite` (pure-Go SQLite; BSD-3/MIT dual)
- Session empirical: w64devkit pe-bigobj failure + TDM-GCC NSIS access-violation
- User exchange 2026-05-15 ("faz purego entao")

---

## ADR-260515-C-amend-02 — Retire tree-sitter from v0.1; markdown-only extraction (M032)

**Status:** Accepted
**Date:** 2026-05-15
**Milestone:** M032 (design-audit amendment; implementation M033)
**Amends:** ADR-260515-C (tree-sitter Go binding provisional lock) + ADR-260515-C-amend-01 (M033/S1 pre-flight gate)

### Context

ADR-260515-C provisionally locked `github.com/tree-sitter/go-tree-sitter` v0.25.0 for AST extraction across 6 langs. ADR-260515-C-amend-01 moved the pre-flight verification gate from M032 to M033/S1 (CGO toolchain validation).

Both tree-sitter binding AND sqlite-vec extension (ADR-260515-B-amend-01) required CGO. Pure-Go pivot (ADR-260515-B-amend-02) removes CGO requirement for SQLite + vector. tree-sitter remains CGO-only — no pure-Go tree-sitter port serves the 6 langs target.

Critical scope re-evaluation (2026-05-15 turn): **aihaus's actual high-value memory content is 100% markdown** (ADRs, Milestone manifests, Story records, Agent YAML frontmatter, Hook script headers, Skill YAML frontmatter). AST extraction for Python/JS/Go/bash code files was originally scoped to provide graphify-parity for code symbol queries — but aihaus agents primarily need structural lookup over aihaus's OWN content (Decisions, Milestones, etc.), not arbitrary code symbols.

User decision 2026-05-15 ("faz purego entao"): drop tree-sitter from v0.1. Markdown-only extraction.

### Decision

aih-graph v0.1 ships **markdown-only structured extraction** for the 6 aihaus typed nodes:

1. **tree-sitter binding retired from v0.1.** No CGO. No tree-sitter dependency. Deferred to v0.2+ (when pure-Go tree-sitter port matures OR when CGO toolchain ecosystem improves on Windows).

2. **Markdown-only extractor (`internal/extract/`):**
   - `extract/adr.go` — parses `pkg/.aihaus/decisions.md` by splitting on `^## ADR-` headers; extracts ADR ID, status, date, milestone, body. Tested on existing 80+ ADRs in repo.
   - `extract/milestone.go` — walks `.aihaus/milestones/M*/RUN-MANIFEST.md`; parses Metadata block (status, phase, last_updated, slug), Story Records table, Progress Log entries.
   - `extract/story.go` — extracts from RUN-MANIFEST.md Story Records table rows; cross-references Milestone parent.
   - `extract/agent.go` — walks `pkg/.aihaus/agents/*.md`; parses YAML frontmatter (name, tools, model, effort, color, memory, resumable, checkpoint_granularity); extracts body description.
   - `extract/hook.go` — walks `pkg/.aihaus/hooks/*.sh`; extracts header comment block (purpose), declared bash function names, file metadata (size, mtime).
   - `extract/skill.go` — walks `pkg/.aihaus/skills/aih-*/SKILL.md`; parses YAML frontmatter (name, description, disable-model-invocation, allowed-tools, argument-hint); extracts annex references.

3. **No code symbol extraction in v0.1.** No `Symbol` or `File` generic node types. The schema (per ADR-260515-B-amend-02) still has `type TEXT` column accepting any value — but v0.1 emits only the 6 aihaus types.

4. **M033 scope (post-amendment):** markdown extraction across 6 aihaus types. No tree-sitter wiring. No CGO. M033/S1 pre-flight gate (per C-amend-01) is RETIRED — no toolchain to validate; pure-Go stack works on any machine with Go 1.22+.

### Options Considered

| # | Option | Pros | Cons | Why Not |
|---|--------|------|------|---------|
| 1 | Keep tree-sitter (CGO) | AST for 6 langs; graphify-parity | CGO toolchain blocker; +1 week M033 toolchain work | User pivot 2026-05-15 |
| 2 | **(Chosen)** Markdown-only for v0.1 | Zero CGO; aihaus's actual goal covered; -1 week M033 | Drops code symbol extraction (low-value for aihaus) | Selected per user decision |
| 3 | Pure-Go tree-sitter port (unproven) | Would preserve original scope | No mature pure-Go port exists; high risk | Rejected — no viable port |
| 4 | Regex-based code AST (rough) | Some code symbol extraction without tree-sitter | Brittle, low-quality, maintenance burden | Excess scope; aihaus goal doesn't need it |

### Rationale

aihaus's actual memory-lookup queries target aihaus content, not arbitrary code. Examples from session experience:
- "How does merge-settings handle hooks arrays" → Decision (ADR) + Skill (aih-update) + Agent (relevant code-fixer)
- "What does M030 cover" → Milestone + Stories
- "Recent CGO findings" → Decision (amendments) + memory entries (NOT direct memory access here, but conceptually aihaus's accumulated wisdom)
- "Show pause_class options" → Decision (ADR-260506-A)

Zero of those queries fundamentally need Python/JS/Go function AST. The structural-markdown-only approach **covers 100% of aihaus's memory-lookup value** while dropping the CGO dependency that was costing ~1 week of M033 toolchain work + ongoing maintenance burden.

The 6 aihaus types are well-defined markdown structures: ADR sections, RUN-MANIFEST tables, agent/skill YAML frontmatter, hook bash files. Each has a single canonical parser. No grammar ambiguity. No edge cases that need tree-sitter's robustness.

When/if aihaus future scope expands to "let aihaus agents understand user's project code structure" (NOT v0.1 goal), tree-sitter can return via v0.2+ amendment.

### Consequences

1. **M033 scope dramatically simplified.** Was: tree-sitter wiring across 6 langs + per-lang query files + CGO toolchain swap. Now: 6 markdown parsers (~50 LOC each = ~300 LOC total) + no CGO.

2. **M033/S1 pre-flight gate retired.** No environmental pre-check needed. M033 starts immediately on any machine with Go 1.22+.

3. **Memory entry `project_m033_cgo_prereq.md` SUPERSEDED.** CGO blocker no longer applies. Memory entry should be updated to reflect retirement (deferred — file-guard hook blocks update; ADR commits are canonical record).

4. **PRD.md M033-M040 story breakdown rewritten** in this amendment cluster commit. M033 becomes "markdown extraction"; M034-M040 follow as defined in B-amend-02 + this amendment.

5. **Smoke check 86 (integration round-trip)** simplifies: no tree-sitter assertion needed. Verifies `aih-graph build .` parses N ADRs (compare against `grep -c '^## ADR' pkg/.aihaus/decisions.md`) and N agents (compare against `ls pkg/.aihaus/agents/*.md | wc -l`).

6. **CLAUDE.md M033 description (not yet written) will reflect markdown scope.** When M033 closes, the CLAUDE.md update is structural-not-AST.

7. **6-lang list from ADR-260515-E-amend-01 becomes vestigial for v0.1.** ADR-260515-E-amend-03 (paired) formally drops it. Markdown is the only "lang" parsed in v0.1.

### Rollback

`git revert` removes this amendment. tree-sitter binding re-enters v0.1 scope; M033/S1 pre-flight gate re-activates. No implementation rollback risk (no tree-sitter code written yet).

### References

- ADR-260515-C (parent: provisional tree-sitter binding lock — superseded for v0.1)
- ADR-260515-C-amend-01 (parent: M033/S1 pre-flight gate — retired)
- ADR-260515-B-amend-02 (paired: pure-Go SQLite — both retirements compose to drop ALL CGO)
- ADR-260515-E-amend-03 (paired: forever-scope drops 6-lang list for v0.1)
- Session empirical: 2 CGO toolchain attempts failed (w64devkit, TDM-GCC)
- User exchange 2026-05-15 ("faz purego entao")

---

## ADR-260515-E-amend-03 — v0.1 forever-scope: drop AST/code symbols; markdown-only for v0.1 (M032)

**Status:** Accepted
**Date:** 2026-05-15
**Milestone:** M032 (design-audit amendment)
**Amends:** ADR-260515-E (forever-scope) + E-amend-01 (lang list 5→6 → moot) + E-amend-02 (vector promoted, unchanged here)

### Context

Companion to ADR-260515-B-amend-02 (pure-Go substrate) + ADR-260515-C-amend-02 (tree-sitter retirement). Updates forever-scope to reflect markdown-only extraction for v0.1; preserves vector embeddings promotion from E-amend-02.

### Decision

aih-graph v0.1 forever-scope updated (consolidated):

**IN v0.1:**
- Markdown-only structured extraction (per ADR-260515-C-amend-02)
- 6 aihaus typed nodes: Decision, Milestone, Story, Agent, Hook, Skill
- modernc.org/sqlite storage (per ADR-260515-B-amend-02)
- Vector embeddings tier-1 (per E-amend-02 — UNCHANGED by this amendment)
- 3 query modes: structural BFS, vector similarity, hybrid SQL+vec
- Pure-Go: zero CGO, single Go binary distribution

**OUT of v0.1 (CHANGES from prior amendments):**
- ~~AST extraction across 6 langs~~ (was E-amend-01; now deferred to v0.2+)
- ~~tree-sitter binding~~ (was C; now deferred to v0.2+)
- ~~Symbol/File generic node types for code~~ (was implied scope; now deferred to v0.2+)

**OUT of v0.1 (UNCHANGED from prior amendments):**
- Clustering (Leiden community detection)
- Semantic LLM extraction (paid LLM-driven node/edge extraction)
- HNSW/IVF vector indexes (sqlite-vec brute-force was sufficient; pure-Go brute-force also sufficient at target scale)
- LLM re-ranking (`--rerank` deferred to v0.2+)

**E-amend-01 6-lang list becomes vestigial.** Bash/Python/JS/TS/Go/Markdown/PowerShell — only Markdown is parsed in v0.1. The 6-lang list survives in ADR history as record of forever-scope discussion but is **not load-bearing for v0.1 implementation**.

### Options Considered

| # | Option | Pros | Cons | Why Not |
|---|--------|------|------|---------|
| 1 | Keep 6-lang AST + add markdown | Maximum extraction coverage | CGO toolchain blocker; +1 week M033 | User pure-Go pivot 2026-05-15 |
| 2 | **(Chosen)** Markdown-only v0.1; AST → v0.2+ | Zero CGO; aihaus goal covered; ship faster | Drops code symbol queries (low-value for aihaus) | Selected |
| 3 | Drop everything but bash + markdown | Maximum simplicity | Drops Python/JS/Go too aggressive; aihaus uses all in scripts | Excess cut |

### Rationale

Three pivots in two sessions (graphify → standalone Go; JSONL → sqlite-vec; sqlite-vec → pure-Go) reflect **honest convergence** toward what aihaus's stated goal actually requires:

- **Stated goal:** vector memory functioning in agents
- **Critical content:** aihaus's own ADRs/Milestones/Stories/Agents/Hooks/Skills — all markdown
- **Critical operation:** semantic lookup over aihaus's accumulated wisdom
- **NOT critical (for stated goal):** AST symbol queries over user's Python/JS/Go code

The 6-lang AST scope was added in the brainstorm cascade because graphify supported it — graphify-parity was treated as scope-forming, but the user's actual use case is narrower. Each pivot has removed unneeded scope:

1. Graphify dep → standalone fork → standalone Go: removed dependency on external project
2. JSONL → sqlite-vec: collapsed v0.1 + v0.2 vector work into one milestone
3. sqlite-vec → pure-Go: removed CGO toolchain dependency that was blocking implementation

Net effect: v0.1 ship time collapsed from 5-8 months (original v0.2+ vector deferral) → 3 months (sqlite-vec pivot) → **~6 weeks** (pure-Go pivot). And v0.1 still covers 100% of aihaus's actual stated goal.

Forever-scope discipline (Contrarian C9 original principle: "intentionally narrower forever") preserved: drops further into the actual core, doesn't expand. v0.2+ amendments can re-add AST when CGO ecosystem matures or pure-Go alternatives emerge.

### Consequences

1. **v0.1 timeline collapses further.** Per ADR-260515-B-amend-02 estimate: ~3-4 weeks focused effort, ~6-8 weeks calendar.

2. **PRD.md M033-M040 story breakdown rewritten** in amendment-cluster commit. M033 = markdown extraction; rest unchanged in shape.

3. **6-lang list in CLAUDE.md, README.md, main.go usage text — needs update.** Companion commits in this cluster.

4. **Memory entry `project_m033_cgo_prereq.md` becomes historical.** Cannot be deleted from this session (file-guard hook), but content is superseded. Future sessions reading it should note this amendment.

5. **v0.2+ re-addition path (deferred):** AST extraction returns via:
   - New ADR-260515-X (AST scope re-expansion)
   - tree-sitter binding choice (C-amend-NN)
   - CGO toolchain pre-flight (re-activation of C-amend-01 logic)
   - Symbol/File node type definitions in PRD update

   When ready (not now), this is a clean re-amendment path.

### Rollback

`git revert` removes this amendment. 6-lang AST scope re-becomes binding for v0.1. ADR-260515-C-amend-02 + B-amend-02 (paired amendments) also need revert for consistent state.

### References

- ADR-260515-E (parent: forever-scope — narrowed further)
- ADR-260515-E-amend-01 (parent: lang list 5→6 — now vestigial for v0.1)
- ADR-260515-E-amend-02 (sibling: vector promoted — UNCHANGED by this amendment)
- ADR-260515-B-amend-02 (paired: pure-Go substrate)
- ADR-260515-C-amend-02 (paired: tree-sitter retirement)
- User exchange 2026-05-15 ("faz purego entao")

---

## ADR-260516-A — Demote Voyage AI to undocumented escape hatch; BM25/FTS5 is the sole advertised embedding surface

**Status:** Accepted (amends ADR-260515-E-amend-02)
**Date:** 2026-05-15
**Milestone:** M042

### Context

M041 (v0.36.0) flipped the aih-graph default `--embed-provider` from `voyage` to `bm25` — pure-Go FTS5 lexical search, no API key, no model download, no external network call. That change closed the install ergonomics gap that ADR-260515-E-amend-02 had documented as a follow-on concern.

However, **the user-facing prompts and docs were not updated in lockstep with M041**. Specifically:

1. `pkg/.aihaus/skills/aih-init/annexes/aih-graph-bootstrap.md` Step 16 still printed a `VOYAGE_API_KEY` upgrade tip after every clean install — surfacing an external-dependency prompt on what is otherwise a zero-credential bootstrap.
2. `aih-graph/README.md` bullet still advertised "Vector embeddings tier-1 with Voyage AI default + local ONNX fallback" — language from before the M041 pivot.
3. `pkg/.aihaus/hooks/aih-graph-refresh.sh` docstring enumerated `voyage` as a first-class `AIH_GRAPH_PROVIDER` value.
4. `pkg/.aihaus/skills/_shared/enforcement-audit.md` carried a `voyage-upgrade-suggest` row classifying the hint as an A-tier model-enforced affordance.

User direction (dogfood report after running `/aih-init`, 2026-05-15): "tá pedindo voyage_api_key sendo que conversamos anteriormente sobre nao pedir isso e usarmos opcoes locais sem dependencias externas o que precisamos fazer pra ajustar?"

Local-ONNX provider (the historical "offline alternative to Voyage" per ADR-260515-E-amend-02) remains deferred. Pure-Go transformer inference is not production-grade today, and `onnxruntime_go` requires CGO — directly contradicting the pure-Go substrate locked in ADR-260515-B-amend-02 and re-validating the M033 CGO toolchain finding (`memory/project_m033_cgo_prereq.md`).

### Decision

Voyage AI is **demoted from advertised default to undocumented escape hatch**:

1. No aihaus skill, hook, or annex prompts for `VOYAGE_API_KEY` or suggests `--embed-provider voyage`.
2. `aih-graph/README.md` documents **BM25/FTS5 as the sole embedding surface**. The phrase "Voyage AI" appears only in historical milestone notes and ADR cross-references.
3. The `VoyageProvider` class in `aih-graph/internal/embed/embed.go` is **preserved as-is**. Users who explicitly set `VOYAGE_API_KEY` and pass `--embed-provider voyage` keep their existing behavior (backward-compat for early adopters).
4. The `--embed-provider voyage` flag value remains accepted by the CLI; only the **advertising surfaces** change.
5. Local-ONNX provider is **formally deferred indefinitely**. Re-evaluation requires (a) production-grade pure-Go transformer inference or (b) a binding decision to re-introduce CGO (which would supersede ADR-260515-B-amend-02). Neither is in flight.

### Affected surfaces (M042 implementation scope)

- DELETE `## Step 16. Voyage upgrade hint` from `pkg/.aihaus/skills/aih-init/annexes/aih-graph-bootstrap.md`; renumber old Step 17 → Step 16.
- DELETE `voyage-upgrade-suggest` row from `pkg/.aihaus/skills/_shared/enforcement-audit.md`; update next row's H2 reference (Step 17 → Step 16).
- REWRITE `AIH_GRAPH_PROVIDER` docstring in `pkg/.aihaus/hooks/aih-graph-refresh.sh` to drop `voyage` from the enumerated default-value list.
- REWRITE the "Vector embeddings tier-1" bullet in `aih-graph/README.md` to describe BM25/FTS5 as the documented surface and external providers as opt-in unadvertised.
- KEEP `VoyageProvider` Go class intact (escape hatch).

### Consequences

**Positive:**
- Clean install flow (`bash install.sh --target . && /aih-init`) emits zero references to external credentials, API keys, signup URLs, or paid services. Matches user mental model "no external dependencies."
- ONNX deferral made explicit — future maintainers won't be surprised by its absence from the v0.1 surface.
- Voyage power-users (anyone with `VOYAGE_API_KEY` already configured) experience zero behavioral change.

**Negative:**
- Semantic (paraphrase-tolerant) query quality is bounded by what BM25 lexical can deliver. Synonym queries that Voyage would catch may miss. Acceptable tradeoff per M041 dogfood: BM25 ranked ADR-260514-B #1 by 2× margin on the test query "merge-settings lida com hooks arrays".
- The undocumented escape hatch means `--embed-provider voyage` users have no path to discover that flag from the README. This is **intentional** — they already know about it (set `VOYAGE_API_KEY`); newcomers should not.

**Neutral:**
- `VoyageProvider` class adds ~100 LOC of unreferenced-from-docs code. Acceptable maintenance cost; deletion would break existing users with no warning.

### Forcing function

Smoke Check 62 (`bash tools/audit-skill-enforcement.sh --compute-expected`) enforces row-count parity between `enforcement-audit.md` and the annex H2 step count. M042 row count: 342 (was 343 pre-M042). Reverting this ADR without reverting the annex change fails the check.

### Alternatives Considered

| Alternative | Verdict | Reason |
|-------------|---------|--------|
| Delete `VoyageProvider` Go class entirely | Rejected | Silently breaks existing users with `VOYAGE_API_KEY` set — high blast radius for low cleanup gain |
| Implement local-ONNX provider now | Rejected | Re-introduces CGO (contradicts B-amend-02); no production-grade pure-Go inference today; high scope, low payoff vs BM25 |
| Keep Voyage tip, gate behind `AIHAUS_VOYAGE_HINT=1` env var | Rejected | Adds env-var surface area; users still see the variable referenced somewhere; doesn't fix the user's "no external deps" intent |
| Implement a third pure-Go BGE-small variant | Out of scope | Multi-week scope; revisit if BM25 quality complaints surface in dogfood |

### Rollback

`git revert` of the M042 commit restores Voyage advertising. Acceptable rollback; no schema/data migration required.

### References

- ADR-260515-E-amend-02 (parent: vector tier promoted; this ADR demotes the Voyage half)
- ADR-260515-B-amend-02 (paired: pure-Go substrate — gates ONNX re-introduction)
- ADR-260515-C-amend-02 (paired: tree-sitter retirement — sibling pure-Go discipline)
- M041 ADR-260515-B-amend-04 (BM25/FTS5 default flip)
- `memory/project_m033_cgo_prereq.md` (CGO toolchain finding)
- User exchange 2026-05-15 ("tá pedindo voyage_api_key... usarmos opcoes locais sem dependencias externas")
