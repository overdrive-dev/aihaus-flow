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
Status: Accepted

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
