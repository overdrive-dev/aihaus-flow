# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

aihaus is a workflow automation package for Claude Code (Cursor support removed in v0.19.0 / M015 — see ADR-M015-A). It provides 14 intent-based commands (`init`, `install`, `plan`, `bugfix`, `feature`, `milestone`, `close`, `resume`, `brainstorm`, `help`, `quick`, `update`, `sync-notion`, `effort`) that users install into their own repositories via `install.sh --target <path>`. `/aih-run` and `/aih-plan-to-milestone` were retired in v0.11.0 — their behavior lives in `/aih-milestone` (execution + `--plan` promotion) and `/aih-feature --plan` (inline small-plan execution). `/aih-effort` (the effort-tuning skill, added M008 and renamed in v0.17.0 / M012) handles effort + model tuning. The permission-mode skill was deleted in v0.18.0 / M014 (replaced by DSP wrapper launch — see ADR-M014-A). There is no runtime, no build step, no package manager — the entire package is markdown files (skills, agents, memory) and shell scripts (install/uninstall + hook helpers like manifest-append, phase-advance, invoke-guard, manifest-migrate introduced in M003).

## Repo Structure

This repo has two layers:

- **`pkg/`** — The publishable package. Everything inside `pkg/` ships to users. This is what `install.sh` copies into target repos. Edits to skills, agents, and hooks go here.
- **`.aihaus/`** — Local installation (gitignored). Created by running `bash pkg/scripts/install.sh --target .` to dogfood aihaus on its own repo. Contains runtime artifacts (project.md, plans, milestones, memory) that never leave this machine.

Self-evolution: when agents improve their own definitions during milestone execution, those edits land in `pkg/.aihaus/agents/` and get committed — feeding improvements back into the published package.

## Validation

```bash
# Smoke test — validates package structure, file counts, frontmatter, templates
bash tools/smoke-test.sh

# Purity check — ensures no references to foreign framework names
bash tools/purity-check.sh
```

There is no build command, no type checker, and no unit test framework. The smoke test is the primary validation gate.

## Package Contents (inside `pkg/`)

- `pkg/.aihaus/skills/*/SKILL.md` — 12 skill definitions with YAML frontmatter. Each skill is a command invoked as `/aih-<name>` on Claude Code.
- `pkg/.aihaus/skills/_shared/autonomy-protocol.md` — binding execution-autonomy rules (M005 / ADR-bound-to-all-skills): 3-phase rule, TRUE blocker definition, no option menus, no delegated typing. Every SKILL.md references it.
- `pkg/.aihaus/agents/*.md` — 48 agent definitions with YAML frontmatter. Agents are spawned by skills to do specialized work (analyst, architect, implementer, reviewer, plan-checker, verifier, code-reviewer, code-fixer, security-auditor, integration-checker, debugger, plan-calibrator, migration-reviewer, etc.).
- `pkg/.aihaus/hooks/*.sh` — 33 shell hooks for Claude Code lifecycle events: M003 protocol enforcement (invoke-guard, manifest-append, manifest-migrate, phase-advance) plus v0.12.0 runtime autonomy enforcement (autonomy-guard blocks forbidden execution-phase patterns) plus M017+ merge-back/git-add/lock-leak guards plus M039 aih-graph-refresh.sh (refreshes structural/semantic memory index).
- `pkg/.aihaus/skills/aih-plan/annexes/*.md` — 4 annex files (attachments, intake-discipline, from-brainstorm, guardrails) — M004 enxugamento of the aih-plan core SKILL.md.
- `pkg/.aihaus/templates/SESSION-LOG.md` — template for `/aih-update --session-log <slug>` post-hoc retrospective (M004 story L).
- `pkg/.aihaus/memory/` — Empty memory index and directory structure (populated at runtime in target repos).
- `pkg/.aihaus/templates/` — Starter `project.md` and `settings.local.json` templates.
- `pkg/scripts/` — Cross-platform install/uninstall/update scripts (ship to users).
- `tools/` — Maintainer-only scripts (validation, purity, regression, release-notes generator; never ship to users).

## Key Conventions

- **Skills must declare `name: aih-<slug>`** in YAML frontmatter and stay under 200 lines. The smoke test enforces both.
- **Agents declare** `name`, `tools`, `model`, `effort`, `color`, `memory`, `resumable`, and `checkpoint_granularity` in YAML frontmatter (M008 + M014; smoke-test Check 6 enforces all eight). `implementer`, `frontend-dev`, and `code-fixer` use `isolation: worktree` and `permissionMode: bypassPermissions`.
  Default effort tier post-v0.13.0 is `xhigh` on Opus 4.7 coding/agentic agents (requires Claude Code v2.1.111+; older Claude Code falls back to `high` automatically).
- **Agents are stack-agnostic.** They read `.aihaus/project.md` at runtime for stack details. Never hardcode languages, frameworks, or directory structures in agent definitions.
- **The purity check** scans all shipped files for references to foreign framework names. Any match fails the check. See the `FORBIDDEN_TERMS` array in `tools/purity-check.sh` for the full denylist.
- **`project.md`** uses marker comments (`<!-- AIHAUS:AUTO-GENERATED-START -->` / `<!-- AIHAUS:MANUAL-START -->`) to separate machine-owned and human-owned sections.
- **Conflict prevention:** All code-writing agents must read `.aihaus/decisions.md` (ADRs) and `.aihaus/knowledge.md` before implementation.
- **Self-evolution:** After milestones, the reviewer proposes agent definition improvements based on accumulated decisions and knowledge. The completion protocol applies approved evolutions.

## Editing Skills and Agents

When modifying a skill, preserve the two-phase pattern: (1) ask scoping questions upfront, (2) get one approval, (3) run autonomously. The `quick` skill is the exception — it skips planning entirely.

When modifying an agent, scope edits to the permission/write-isolation profile the agent declares. 28 agents have `Write` in their tools; 9 also have `Edit`; 5 declare `isolation: worktree` + `permissionMode: bypassPermissions` (the stateful trio `implementer` / `frontend-dev` / `code-fixer` plus `executor` and `nyquist-auditor`). The `reviewer` and `code-reviewer` agents must never modify code regardless of tools declaration.

After any change to skills, agents, or hooks, run `bash tools/smoke-test.sh` to validate counts and frontmatter.

## Calibration and Permission Modes

>> **BREAKING (v0.18.0 / M014):** The permission-mode toggle skill has been deleted entirely.
> DSP launch via `bash .aihaus/auto.sh` is the sole autonomy path. Typing the old skill name
> returns skill-not-found. See ADR-M014-A in `pkg/.aihaus/decisions.md`.

aihaus runs in auto mode when launched via `bash .aihaus/auto.sh` (which `exec`s
`claude --dangerously-skip-permissions`). Safety lives entirely in PreToolUse hooks
(`bash-guard.sh`, `file-guard.sh`, `read-guard.sh`). Bare `claude` invocation is the non-auto
path — permission prompts appear normally. **No skill toggle exists.** See ADR-M014-A.

On Windows PowerShell: `.aihaus/auto.ps1` is the equivalent wrapper.

Users can retune effort tiers via `/aih-effort` (added M008, cohort taxonomy unaffected by M014).
The Stop hook `autonomy-guard.sh` (M005 / ADR-bound-to-all-skills) remains active on all
invocation paths — its execution-phase autonomy rules are **orthogonal** to DSP and still binding.
See `pkg/.aihaus/skills/_shared/autonomy-protocol.md`.

**Effort presets** (v0.17.0 — cohort-tuple shape, 6 cohorts). Three
presets, invoked via `/aih-effort --preset <name>`:
- `cost` — `:planner-binding (opus, high)`, `:planner (opus, high)`,
  `:doer (sonnet, medium)`, `:verifier (haiku, medium)`;
  `:adversarial-scout` + `:adversarial-review` preset-immune. Maximum
  cost reduction via haiku on verifiers and medium effort on doers.
- `balanced` — default on clean v0.17.0 install. Matches cohort defaults
  byte-identically: `:planner-binding (opus, xhigh)`, `:planner (opus, high)`,
  `:doer (sonnet, high)`, `:verifier (haiku, high)`.
- `high` — maximum quality on non-immune cohorts: `:planner-binding (opus, xhigh)`
  (unchanged), `:planner (opus, xhigh)`, `:doer (opus, high)` (sonnet → opus
  swap; sonnet caps at `high` so xhigh silently clips), `:verifier (haiku, high)`
  (unchanged). Prone to overthinking on `:planner`, use sparingly.

**Cohort aliases** (v0.31.0 / M027 / ADR-260509-Y — 6→5 fork). All 48 agents are
grouped into **5** uniform cohorts — one fixed default model per cohort:

| Cohort | Count | Default model | Notes |
|--------|-------|---------------|-------|
| `:planner-binding` | 4 | opus | Split from `:planner` (v0.15.0 intra-cohort xhigh carve-out → first-class cohort). Members: architect, planner, product-manager, roadmapper |
| `:planner` | 14 | opus | Research + structured planning agents upstream of code. Was 17 before `:planner-binding` split |
| `:doer` | 15 | sonnet | Forward-edit implementation agents. Absorbed former `:investigator` (deleted M012) — default tier byte-identical. Only cohort with model swap: `high` preset → `(opus, high)` |
| `:verifier` | 9 | haiku | Read-only assessment agents. Former `verifier-rich` subset (sonnet overrides) deleted |
| `:adversarial` | 6 | opus | Merged from `:adversarial-scout` + `:adversarial-review` (M027/ADR-260509-Y). Preset-immune as one rule. plan-checker, contrarian, plan-calibrator carry per-agent `effort: max` override; reviewer, code-reviewer, migration-reviewer carry cohort baseline `effort: high`. |

**Deleted cohorts (M012 + M027):** `:investigator` (absorbed into `:doer` in M012);
`:verifier-rich` subset (agents reassigned individually in M012); `:adversarial-scout`
and `:adversarial-review` (merged into `:adversarial` in M027/ADR-260509-Y).

Invoke via `/aih-effort --cohort :<name> --model X --effort Y` (both axes
required). Per-agent escape hatch via `/aih-effort --agent <name> --model X
--effort Y` (ADR-M008-A amendment). The `:adversarial` cohort is preset-immune —
only an explicit `--cohort :adversarial` (with literal-word `adversarial`
confirmation) or `--agent <member>` can mutate it. Full 48-agent mapping + prose
rationale: `pkg/.aihaus/skills/aih-effort/annexes/cohorts.md`.

**Sidecars.** Effort calibration survives `/aih-update` via a
`.aihaus/.effort` sidecar (schema v4 post-M027; schema v3 in M012-M026;
renamed from `.aihaus/.calibration` v2 in M012 / ADR-M012-A; ownership preserved
per ADR-M009-A). Schema v4 folds `:adversarial-scout.*` + `:adversarial-review.*`
keys → `:adversarial.*` and injects per-agent `effort=max` overrides for
plan-checker/contrarian/plan-calibrator. v3→v4 migration on next `update.sh`
run; `.effort.v3.backup` written before migration; abort on parse fail.
Both files are user-owned, never committed, and live at `.aihaus/` root so
the refresh loop (which only touches `skills/`, `agents/`, `hooks/`,
`templates/`) leaves them alone. `update.sh` re-applies recorded
`(model, effort)` to refreshed agents from `.effort`. Full schema + migration
guide: `pkg/.aihaus/skills/aih-effort/annexes/state-file.md`.

## SKILL Enforcement Audit

Since v0.25.0 / M021, every step in every aih-* SKILL is classified by enforcement
layer (A model-driven / B agent-delegated / C hook-enforced) with a 13-column row
schema (SKILL / Location / Step / Label / Primary / Actor / Gate / Escape /
Leverage / Reversibility / Drift Risk / Eligibility / Notes). 293 rows cover
the 14 SKILLs (M022 added `aih-install`) + binding annexes + _shared protocols.
Since v0.27.0 / M023 the rubric extends with the GSP-DS pattern catalog.

- Canonical audit: `pkg/.aihaus/skills/_shared/enforcement-audit.md`
- Promotion backlog (M022+): `pkg/.aihaus/skills/_shared/enforcement-audit-backlog.md`
- Framework + move rule: ADR-260503-A in `pkg/.aihaus/decisions.md`
- Move rule: promote A → B/C iff `leverage=high AND (reversibility=irrev OR
  drift-risk=hard) AND eligibility=deterministic` (per ADR-260502-A determinism gate).

Refresh triggers: (a) new SKILL added → audit must add fragment, (b) step count
of any SKILL changes by ≥2 → re-classify, (c) annex referenced by a SKILL is
renamed/moved → re-anchor. Smoke Check 62 detects (a) and (b).

## Resume Substrate

Since v0.18.0 / M014, `/aih-resume` uses an authoritative checkpoint substrate rather
than file-existence heuristics. See ADR-M014-B in `pkg/.aihaus/decisions.md`.

**Schema v3 `## Checkpoints` (LD-1).** RUN-MANIFEST v3 gains an optional `## Checkpoints`
section (additive — v2 manifests migrate in-place without data loss). 7-column table:

```
| ts (ISO-8601 UTC) | story (S\d{2}) | agent (slug) | substep (<kind>:<id>) | event (enter|exit|resumed) | result (OK|ERR|SKIP) | sha (7-char) |
```

`manifest-append.sh` is the sole writer (single-writer discipline from ADR-004 extended).
New modes: `--checkpoint-enter <story> <agent> <substep>` and
`--checkpoint-exit <story> <agent> <substep> <result> [<sha>]`.

**Agent frontmatter classification (LD-6).** Every agent in `pkg/.aihaus/agents/*.md`
declares two new YAML fields (48 agents classified; smoke-test Check 6 enforces both):

```yaml
resumable: true | false
checkpoint_granularity: story | file | step
```

- `(true, story)` — ~42 idempotent agents. Re-spawn is safe; fresh run produces equivalent output.
- `(false, file)` — `implementer`, `frontend-dev`, `code-fixer` (3 stateful). Dispatch with `--resume-from <substep>`.
- `(false, step)` — `debug-session-manager` (1 multi-cycle). Per-step state needs explicit recovery.

**`--resume-from <substep>` dispatch (LD-2).** For stateful agents, `/aih-resume` passes the
free-text substep ID from the last checkpoint row. The agent reads `## Checkpoints`, skips all
prior substeps, and continues from the next un-completed substep.

**Worktree reconciliation.** `pkg/.aihaus/hooks/worktree-reconcile.sh` runs before dispatch.
Classifies each non-main worktree as Category A (prune), B (emit cherry-pick recipe), or C
(dirty — preserve untouched). Safe-default-to-C prevents silent data loss. Hook is
standalone-safe (`bash worktree-reconcile.sh`).

**Legacy-mode retention policy (LD-10).** The old file-existence heuristic is preserved in
`aih-resume/SKILL.md` as a `<!-- LEGACY MODE -->` comment block, reachable via
`/aih-resume --legacy-mode`. **REMOVE in M015 if no usage reported.** If the dogfood
acceptance test (S10) passes without fallback to legacy mode, the comment block is safe to
delete in the next milestone.

## Autonomy Protocol (M011 state gate + statusLine)

Since v0.16.0 / M011, `autonomy-guard.sh` runs a layered stop gate in
deterministic order: (1) `Metadata.status: paused` → allow stop silent
(S04 promotes `paused` to a first-class TRUE-blocker escape via
`phase-advance.sh --to paused --reason "<text>"`); (2) 11-regex
fast-path (M005, byte-identical); (3) haiku backstop via
`claude --print --model haiku-4.5` with the conservative JSON-out
prompt — 3s timeout, fail-safe allow on every ambiguous path. Opt-out
via `AIHAUS_AUTONOMY_HAIKU=0`. Every decision lands in
`.claude/audit/autonomy-gate.jsonl` (13-field schema, 11-value
decision enum, rotated at 10 MB OR 10 000 lines atomically to
`.old`). Per-message 5-min hash cache + global 30-s rate window in
`.claude/audit/autonomy-gate.cache` dedupe retry-storms. Milestone
visibility rides the same substrate: `statusline-milestone.sh`
reads RUN-MANIFEST on every TUI turn (per-turn ~5ms) and renders
`M0XX · SNN/total · phase:X · agents:N · sha:abc1234`. Both
primitives are ADR-M011-A (state gate) + ADR-M011-B (statusLine). M017
adds `git-add-guard.sh` PreToolUse — rejects `git add -A` / `<dir>/` /
`-u` / `-p` + `git commit -am` on `milestone/*` / `feature/*` branches;
opt-out `AIHAUS_GIT_ADD_GUARD=0`. M018 corrects `AIHAUS_SKIP_E55` (no dot)
as the canonical E5.5 skip env; prior prose used a dot-in-name variant that
is bash-invalid (POSIX shell rejects dot in parameter names).

Since v0.27.0 / M023 (ADR-260506-A), `phase-advance.sh --to paused` REQUIRES `--class <4-enum>`
(writing `pause_class` to manifest Metadata): `{credential-missing, destructive-git-state,
external-dep-down, user-invoked}`. `internal-contradiction` is RESERVED for M024+ adversarial-write
gate. `autonomy-guard.sh` extends to 24 patterns (1 modified + 13 added) covering GSP-DS
(Graceful Self-Pause at Decomposition Seam) — the PT-BR dialect the M005 fast-path missed.
`/aih-resume` adds stranded-pause detection (no `phase-advance --to paused` audit row + ≥2
unfinished stories + recent activity + GSP-DS regex match in `autonomy-gate.jsonl` within 60s of
`last_updated` → emit continue-here vs re-promote-as-feature classification). Conversation length
and decomposition seams (Backend/Frontend, Wave N/M, Batch A/B, Phase X/Y) are NEVER TRUE blockers.
Opt-out env vars: `AIHAUS_PAUSE_CLASS=0` (S01 hook bypass), `AIHAUS_GSP_DS_REGEX=0` (S02
fast-path bypass — skips 13 new patterns; existing 11 still fire), `AIHAUS_AUTONOMY_HAIKU=0`
(existing M011 backstop bypass).

Since v0.28.0 / M024 (ADR-260507-A), `aih-milestone/annexes/execution.md` excises Wave/Group
structural nouns from skill prose at 5 substitution sites; `autonomy-guard.sh:73` runtime
regex preserved byte-identical (M023 + M024 compose). `/aih-milestone --plan <slug>`
short-circuits the analyst/PM/architect/plan-checker pipeline at Step E3 when a 3-way gate
passes ((a) OQ-resolved + (b) architecture-coverage + (d) story-table, all H-level permissive)
AND the on-disk CHECK.md SHA proves plan-checker ran (consumer reads `git log -1
--format=%H -- .aihaus/plans/<slug>/CHECK.md`). Skipped planning creates 3 stub files
(`analysis-brief.md`, `PRD.md`, `architecture.md`) with skip-markers preserving 6
production-path consumer contracts. `install.sh` and `install.ps1` ship a path-doubling
hotfix (`AIHAUS_RESOLVED` replaces `PKG_ROOT` at user-global install + registry write at
lines 474/480 + 1010/1020) plus skill-junction conditional (per-repo install skips
`.claude/skills/aih-*` when user-global already provides them; `--force-project-skills` /
`-ForceProjectSkills` / `FORCE_PROJECT_SKILLS=1` overrides). Smoke Check 72 detects
post-hoc that `phase-advance.sh --to complete` was called without a corresponding
`.claude/audit/curator-apply.jsonl` row — **offline observability, NOT runtime gating**;
grace-window for currently-running milestone (`git branch --show-current`) prevents
self-completion sequence trap. M024 introduces NO new opt-out env vars. See
`pkg/.aihaus/skills/_shared/autonomy-protocol.md` §M024 invariants for runtime composition rule.

Since v0.29.0 / M025 (ADR-260508-A), `pkg/.aihaus/hooks/autonomy-guard.sh` ships the **LSDD
pack** — 16 anchored cadence-noun + Sigo-question + task-fraction patterns under
`AIHAUS_LSDD_REGEX=0` env opt-out (composes byte-identical with M005 fast-path + M023 GSP-DS
pack: 11 + 13 + 16 = 40 active patterns total). Every cadence-noun pattern (`Phase`, `Round`,
`Stage`, `Tranche`, `Etapa`, `Bloco`, `Fase`, `Rodada`, `Seção`) anchors to a completion-prose
verb-set on the same line via `.*(complete|completa|completo|done|paralelo|seguir|working|
remaining|shipped|finalizada|finalizado|pronta|in progress)` — anchoring preserves §M023
catalog at L147+L487 ("Etapa/Bloco/Fase/Phase X/Y" enumeration as legitimate decomposition
seams) AND ~30+ legitimate `## Phase N` H2 headers in skill prose at runtime emission.
**Onda DROPPED** per F1 absorption (no fabricated user mandate). Known-uncovered slots
(Tier/Cycle/Iteration/Sprint/Slice/Pass/Bucket/Cohort/Greek-letters) have a mechanical M026
trigger via `.claude/audit/autonomy-gate.jsonl` haiku-backstop monitoring (30-day window
post-release). `pkg/.aihaus/agents/roadmapper.md` L64-83 cadence-noun template excised →
"Delivery 1/Delivery 2/N" substitution (avoids `/aih-milestone` skill-name collision and
LSDD-uncovered slots). `pkg/.aihaus/agents/brainstorm-synthesizer.md` Round 1/Round 2 panel
mechanics + `*-r2.md` filename convention preserved (load-bearing per F-CRIT-2). The L353
serialization invariant (M017+) is canonical and explicit — `--parallel` flag NOT introduced;
`AIHAUS_PARALLEL_EXEC` token reserved for M026+ if dogfood ever reproduces story-level fan-out.
Smoke Check 76 enforces M027 architectural decision deadline via semantic-gate ADR-presence
(requires `Status: Accepted` + token from `{denylist-extension, haiku-classifier,
whitelist-on-cadence}` + `Date:` line). 2 fixture-fail tests prove not green-but-vacuous.
M025 introduces `AIHAUS_LSDD_REGEX=0` opt-out env var.

Since v0.30.0 / M026 (ADR-260508-B), `/aih-brainstorm` ships the **Brainstorm Artifact
Actionability** stack closing the BRIEF→PLAN absorption gap. Empirical baseline across
M023+M024+M025: plan-checker catches 3-4 CRITICAL BLOCKERs every PLAN with only 9-45% of
those tracing back to BRIEF Open Questions. M026 fixes two layered defects: schema-level
(Alt D inline OQ sub-fields + Synthesis stance-marker) + substrate-level (Phase 6.5
`--substrate` opt-in). **Alt D OQ schema (per ADR-260508-B I1)** — every Open Question ships
inline `**Recommendation:**` + `**Panel-Confidence:** H/M/L` + `**Defer if:**` + `**Source:**`
sub-fields. H/M Panel-Confidence requires `**Source:**` citation grammar
(`PERSPECTIVE-<role>.md:Lstart-Lend` OR `CONVERSATION.md ## Turn N` OR
`pkg/.aihaus/<path>:Lstart-Lend`); Smoke Check 77 enforces. Synthesis bullets ship
`**Stance:**` markers eliminating two-surface scanning. **Phase 6.5 substrate-scan (per
ADR-260508-B I2)** — opt-in `--substrate` flag spawns `assumptions-analyzer` (REUSED, not
new agent build); skill writes SUBSTRATE-FINDINGS.md verbatim from agent return (PM Path B
Option α — preserves synthesizer single-file write scope + ADR-001). Catches 55-64% of
substrate-discoverable BLOCKERs per F1-VERIFICATION; complements (not replaces) plan-checker.
**Phase 7.5 sub-field validator (per ADR-260508-B I3)** — awk-based per-OQ block scoping
extends existing 8-H2-headers check; field-presence-permissive gate skips legacy schema-v1
BRIEFs. **Panelist-template composed rules (per ADR-260508-B I4)** — R1+R2 panelist prompts
include mandatory PM ground-check (citation grammar) + UX argue-against (R2 dissent OR
`NO-R1-DISSENT-JUSTIFIED`). Annex-split mandatory (`aih-brainstorm/annexes/sub-field-validator.md`,
`/substrate-scan.md`, `/panelist-template.md`) keeps SKILL.md ≤199 line cap. Cost-cap +1 per
flow when `--substrate`; max combo = 14. M026 adds Smoke Check 77 (count 76 → 77) with 2
fixture-fail tests (missing-recommendation + source-prose-violation) proving gate not
green-but-vacuous on M025 PM-cohort fabrication anti-pattern.

Since v0.31.0 / M027 (ADR-260509-X), `pkg/.aihaus/hooks/autonomy-guard.sh` ships **two-tier dispatch** — the composition rule M005 + M023 + M025 + M027 = **40 patterns frozen** (total locked, NOT per-pack). Two-tier routes by `manifest_status` + `exec_phase` binary field: `exec_phase="1"` AND `manifest_status ∈ {running, in-progress}` → **haiku-primary** (milestone-execution turns where +600-900ms p95 latency amortizes against agent turns); all other statuses + `exec_phase="0"` → **regex-primary** (40-pattern walk, `<50ms`). Adding a new pattern requires a new ADR that explicitly amends ADR-260509-X. New env var `AIHAUS_AUTONOMY_TIER=regex|haiku|two-tier` ships with default unset → context-route. Existing `AIHAUS_AUTONOMY_HAIKU=0` opt-out preserved (disables haiku on all paths). JSONL schema extended additively: `tier_used` (`regex`|`haiku`|`two-tier-fallback`) per row + `rephrase_suggestion` (static human-readable string on `regex-match` rows only — S3 OPAQUE verdict obligation, static lookup, `<1ms`). 30-day burn-in monitors `haiku_p95_ms`; M028 hotfix path defined if p95 >1s. M027 adds `AIHAUS_AUTONOMY_TIER` opt-out env var.

M027 also ships: **(1) cohort fork 6→5** (ADR-260509-Y / S10) — `:adversarial-scout` + `:adversarial-review` merged → single `:adversarial` cohort (6 members: plan-checker, contrarian, plan-calibrator, reviewer, code-reviewer, migration-reviewer). Preset-immunity becomes one rule. Per-agent `effort: max` frontmatter preserves the `(opus, max)` profile for the 3 scout-tier agents (plan-checker, contrarian, plan-calibrator); Smoke Check 6 Part C enforces. Schema v4 sidecar: `:adversarial-scout.*`/`:adversarial-review.*` keys folded → `:adversarial.*`; max-effort per-agent overrides injected if absent; `.effort.v3.backup` written before migration; abort on parse fail. 1-milestone deprecation window (v3 read-compat through M028). **(2) `plan-calibrator` agent** (ADR-260509-W / S5) — adaptive interrogator spawned after `plan-checker` emits CHECK.md; surfaces ambiguities, conducts turn-by-turn confirmation, produces BUSINESS-RULES.md payload; `--no-calibrate` flag on all 3 skills skips it. **(3) `migration-reviewer` agent** (S9) — read-only migration reviewer spawned when diff matches `^(migrations/|*.sql)`; reviews schema migrations for reversibility, lock impact, data-loss risk. Smoke Check 6 sub-assert (preset-immunity) + Smoke Check 78 (calibration-gate ambiguity-detection) added. Total agents: 48. Total cohorts: 5.

Since v0.32.0 / M028 (ADR-260510-A through D), aihaus ships TDD discipline as a user-prescribable preference. The `project.md` template gains a `## Practices` section (10th H2, MANUAL block — ADR-260510-B governance rule: each new structured key requires a milestone-tagged ADR, 2-milestone sunset clause if unused, flat namespace enforced). The section exposes a single structured key: `testing_discipline: tdd | test-after | none` (default `none`). `/aih-init` populates this via auto-detection heuristic at install time: presence of a test-infra directory (`tests/`, `spec/`, `__tests__/`, `*.test.*` files) → `test-after`; `.tdd-discipline` marker file OR at least 10% of recent commits carrying a `tdd:` prefix → `tdd`; else `none`. User can override post-install by editing `project.md` directly; auto-detection value is advisory, not locked (per ADR-260510-B §4).

`tdd-guard.sh` (`pkg/.aihaus/hooks/tdd-guard.sh`, ~195 LOC, PreToolUse) enforces the discipline at session scope. When `testing_discipline=tdd` AND no test-file Write|Edit has occurred in the current session, the hook blocks any Write|Edit targeting a non-test file and emits a human-readable rejection with suggested test-first remediation. `/aih-quick` bypasses the guard via `AIHAUS_TDD_GUARD=0` set in Step 0 and unset in Step 6 (resolves BLOCKER #1 — aih-quick creates no manifest and cannot trigger guard via manifest-status path). The `--no-tdd` flag is honored across `/aih-feature`, `/aih-plan`, and `/aih-milestone --plan`; every invocation is audit-logged to `.claude/audit/tdd-guard.jsonl`. Surface 3 (tdd-coach agent) and Surface 4 (implementer baseline stance injection) are OUT OF SCOPE per ADR-260510-A Decision A — tdd-coach adds agent-count cost without measurable enforcement uplift; implementer stance injection was REJECTED as it conflates process coaching with code generation. Decision G honest scoping (ADR-260510-D): `testing_discipline` applies to USER CODE in repos that install aihaus — it does NOT apply to aihaus's own bash hooks (e.g., `autonomy-guard.sh` = 864 LOC, zero unit tests, integration-tested via smoke-test). Smoke Check 78 → 79 → 80 (Check 79 tdd-guard fixtures + Check 80 tdd-discipline annex wiring). Opt-out: `AIHAUS_TDD_GUARD=0` (single-session bypass); `--no-tdd` (per-skill-invocation, audit-logged).

Since v0.34.0 / M030 (ADR-260514-B), `pkg/scripts/lib/merge-settings.sh` ships **dual by-shape array-aware merge** closing the canonical defect identified post-M029. Empirical field evidence (maintainer's dogfood install): `settings.local.json` frozen at pre-M017 shape (last commit `abc26803`, 2026-04-12) was missing 7 newer canon hook entries (`calibrate-guard`, `context-inject`, `git-add-guard`, `read-guard`, `warning-recurrence`, `worktree-release`, `worktree-release-all`) despite the corresponding hook scripts being on-disk. Root cause: `merge-settings.sh:53` jq `*` semantics replaced arrays wholesale; the Python fallback at `:73-79` was byte-identical bidirectional-lossy. **Path-scoped semantics matrix** (binding contract per ADR-260514-B): `.hooks.<Event>[]` (outer, `{matcher, hooks}` shape) → **position-paired merge with recursion into inner**; surplus template entries appended; surplus user entries appended last. `.hooks.<Event>[N].hooks[]` (inner, `{command}` shape) → **union by `.command`** (template wins on collision). `permissions.allow|deny`, `additionalDirectories`, all other arrays → **REPLACEMENT** (existing M014 migration-hint contract preserved). **Dual by-shape symmetry** across 3 implementations (bash jq `merge_hooks_arrays`, Python `deep_merge`, PowerShell `Merge-Object`) verified via smoke-test Check 82 running each fixture under both jq path AND `AIHAUS_FORCE_PYTHON_MERGE=1` Python path (4 fixture-pairs at `tools/fixtures/settings-merge-hooks/`). **HAS_JQ guard** introduced at `merge_settings()` function-head consolidates 3 previously-inline `command -v jq` checks (L50/L120/L172) into a single deterministic gate. **Rollout closure (S08 absorbed into S05 per CHECK F2):** `update.sh` ships a drift-detect block — for each `.hooks.<Event>[]` key, counts `template_hook_count - user_hook_count`; if delta `>= ${AIHAUS_DRIFT_THRESHOLD:-2}` for any Event, prompts `"Detected N missing canonical hook entries from <Event>. Recompute merged settings now? [Y/n]"`. On `Y` → re-invokes merge with `AIHAUS_RECOMPUTE_MERGE=1` (consumed at function-head; emits tracing line + suppresses stale granular-Bash migration hint). On `N` → writes sentinel `.aihaus/.recompute-skipped-260514` to suppress prompt-spam on subsequent runs. Non-interactive opt-out via `AIHAUS_DRIFT_PROMPT=0` (CI-safe). `install.ps1` ships PowerShell parity of BOTH the Merge-Object fix AND the drift-detect block (BR-003 mandatory per maintainer verification of `Merge-Object` byte-equivalent bug at L924-937). **Defense-in-depth:** `pkg/.aihaus/hooks/worktree-reconcile.sh` ships a `[DETACHED-HEAD-MAIN]` stderr marker after `MAIN_WORKTREE_PATH` resolution; emitted only when main worktree HEAD is detached; never blocks; exit 0; opt-out `AIHAUS_RECONCILE_DETACHED_WARN=0`. Consumer-survey confirmed zero `\[`-prefix grep collisions in callers. Smoke Check 23 amended (preserves `permissions.allow` replacement assertion under new matrix); new Check 82 (hooks union under jq + Python, 4 fixture-pairs); new Check 83 (drift-detect heuristic, 3 fixture-pairs). Check count: 81 → 83. **ADR-260514-B Rationale** cites ADR-260511-B move-rule trigger (c)(i) — anticipatory protection on a new flow, with single-user empirical field evidence inlined verbatim in ADR Context (7-hook delta table). M030 introduces three new env vars: `AIHAUS_FORCE_PYTHON_MERGE`, `AIHAUS_RECOMPUTE_MERGE`, `AIHAUS_DRIFT_THRESHOLD`, `AIHAUS_DRIFT_PROMPT`, `AIHAUS_RECONCILE_DETACHED_WARN`. **S4 (stranded-pause SessionStart hook) DEFERRED** to M031+ per BR-001 — threshold rule observably met (M044/M045 8d-stale in dogfood specimen → SessionStart hook recommendation per deterministic rule), follow-up plan stub seeded at `.aihaus/plans/260514-stranded-pause-session-start/`. Hook count unchanged at 32 (no new hook files; M030 modifies existing hooks + scripts only).

Since v0.36.0 / M041 (3 sub-stories S1/S2/S3, no new ADR — incremental atop ADR-260515-B-amend-02 substrate), aihaus collapses the aih-graph install dance from 3 commands to 2 and replaces paid-Voyage-default with **pure-Go offline BM25/FTS5 lexical search**. S1: aih-graph default `--embed-provider` flips from "" (skip) to `bm25`; new `nodes_fts` virtual table (SQLite FTS5; ships in stock modernc/sqlite); `internal/storage/fts5.go` exposes `SaveFTS()` + `QueryFTS5()` using SQLite's built-in `bm25()` ranking function (no roll-own scoring). Empirical query quality on aihaus-flow's own ADRs (153 indexed nodes): query "merge-settings lida com hooks arrays" → ADR-260514-B ranks #1 by 2× margin; "sqlite vector pivot" → 4 data-model-pivot ADRs land in top 4. Voyage AI demoted to **opt-in upgrade** (still wired; `--embed-provider voyage` + `VOYAGE_API_KEY`) — recommended for queries needing paraphrase tolerance. S2: `/aih-init` ganha Phase 3 — auto-dispatches `aih-graph build --accept-all-repos --embed-provider bm25 .` after `project.md` generation; 5-step flow lives in `aih-init/annexes/aih-graph-bootstrap.md` (binary discovery → consent marker → build → Voyage hint → completion summary); non-fatal envelope keeps `/aih-init` exit-0 regardless of Phase 3 outcome. S3: `pkg/scripts/install.sh` Step 13 auto-invokes `install-aih-graph-binary.sh` on initial install (skipped on `--update`); soft-fail on network / platform-unsupported / source-script-missing; `AIHAUS_SKIP_GRAPH_BINARY=1` opt-out for CI / airgapped. Net result: end-user flow is `bash install.sh --target .` then `/aih-init` — zero credit card, zero model file download, zero CGO toolchain. Smoke check enforcement-audit canonical (Check 62) extended from 337 → 343 rows mirroring the 6 new H2 sections in `aih-graph-bootstrap.md`. Binary size 10.7MB → 16.1MB (FTS5 + tokenizer code shipped with modernc/sqlite; no new deps). Tag pair this release: `aihaus-v0.36.0` + `aih-graph-v0.1.1`.

Since v0.35.0 / M033–M040 (ADR-260515-A through E + 8 amendments), aihaus ships **aih-graph v0.1.0** as the mandatory structural+semantic memory engine. Pure-Go standalone binary (10.7 MB; zero CGO; `modernc.org/sqlite` + roll-own Go KNN — converged after 3 design pivots: graphify dep → standalone Go binary → SQLite+sqlite-vec → pure-Go). Scope: **markdown-only structured extraction** for 6 aihaus typed nodes (`Decision`, `Milestone`, `Story`, `Agent`, `Hook`, `Skill`) from `pkg/.aihaus/{decisions.md, milestones/, agents/, hooks/, skills/}`. **3 query modes** in `cmd/aih-graph`: `--bfs` (recursive CTE over `edges` table, structural-only), `--semantic` (vector KNN via Go-native brute-force cosine over `embedding` BLOB column), `--hybrid` (KNN top-K + 1-hop edge expansion per match in a single output). **Embedding pipeline** with pluggable providers (`internal/embed/`): `voyage` (Voyage AI HTTP — default; `VOYAGE_API_KEY` env var), `fake` (deterministic SHA-256-derived; offline pipeline-validation), `none` (skip; default). SHA-based change detection (`content_sha` column) skips re-embedding unchanged nodes. **Privacy contract per ADR-260515-A** (`internal/privacy/`): per-repo `.db` file under XDG state root (`$XDG_STATE_HOME/aih-graph/<sha256-hex-16-of-abs-repo-path>/graph.db` on Linux; `~/Library/Application Support/aih-graph/<hash>/graph.db` on macOS; `%LOCALAPPDATA%/aih-graph/<hash>/graph.db` on Windows; `AIH_GRAPH_HOME` env var overrides). `aih-graph build` refuses without `.aih-graph-consent` marker at repo root unless `--accept-all-repos` (creates marker). `aih-graph uninstall <repo>` purges one repo's `.db` + WAL/SHM sidecars; `aih-graph uninstall --purge` removes entire state root. NDA opt-out via `--embed-provider fake` or `none`. **Integration touchpoints (M039):** `pkg/scripts/install-aih-graph-binary.sh` downloads platform-matched binary from `https://github.com/overdrive-dev/aihaus-flow/releases/tag/aih-graph-v0.1.0` (4-platform matrix: linux-amd64, darwin-amd64, darwin-arm64, windows-amd64 + 4 `.sha256` checksums); `pkg/.aihaus/hooks/aih-graph-refresh.sh` on-demand index refresh with 4-tier binary discovery (`AIH_GRAPH_BIN` env > `~/.aihaus/bin/aih-graph[.exe]` > `$CLAUDE_PROJECT_DIR/aih-graph/bin/` > `PATH`); M048 supersedes this prompt contract: 48/48 packaged agents now ship `## Native Repository Memory (M048)` sections that require `aih-graph status --repo . --json` plus role-relevant `query|context|impact|callers --json` commands before role-specific work when the binary is available, while still no-oping gracefully when absent. **CI / release workflows** `.github/workflows/aih-graph-{ci,release}.yml` cross-compile 4-platform matrix via `actions/setup-go@v5` + `CGO_ENABLED=0 go build`; release workflow triggers on tag pattern `aih-graph-v*` → uploads stripped binaries (`-trimpath -ldflags="-s -w"`) + per-platform SHA-256 checksums. **Smoke checks 84/85/86 added** (count 83 → 86): Check 84 (forcing function — ADR-260515-{B-amend-02, C-amend-02, E-amend-03} presence prevents silent pivot revert), Check 85 (build smoke — Go-on-PATH gates `go build` + `version`/`help` smoke; soft-skip when Go absent), Check 86 (integration round-trip — builds + runs against this repo + asserts node counts match Smoke Check 1/2/3 ground truth + privacy gate exit-2 on missing consent; soft-skip when Go absent). Hook count: 32 → 33 (`aih-graph-refresh.sh` + `tdd-guard.sh` allowlist correction). New env vars (M039): `AIH_GRAPH_HOME`, `AIH_GRAPH_BIN`, `AIH_GRAPH_VERSION`, `AIH_GRAPH_REPO`, `AIH_GRAPH_PROVIDER`, `AIH_GRAPH_DB`, `AIH_GRAPH_QUIET`, `VOYAGE_API_KEY`. **Deferred to v0.1.1+:** local ONNX embedding provider (NDA-context offline path; `internal/embed/onnx.go` not in v0.1), public `pkg/aihgraph/` Go library API (internal exports already suffice for any consumer; naming/polish only).

Since v0.33.0 / M029 (ADR-260511-A through C), aihaus ships Layer A → Layer C calibration-gate enforcement promotion. `pkg/.aihaus/hooks/calibrate-guard.sh` (~182 LOC, UserPromptExpansion) closes a dead-code gap identified post-M027: `aih-plan` Phase 3.5's calibration gate called `manifest-append.sh --audit calibration-skip` — a structurally dead path (manifest-append.sh has no `--audit` mode), confirmed by 23 CHECK.md / 0 BUSINESS-RULES.md on-disk artifact ratio (100% skip rate). **Single-channel design** (UserPromptExpansion only) per BLOCKER F4: `settings.local.json` arrays use replacement semantics on merge; adding a defensive 2nd PreToolUse channel via `update.sh` would silently overwrite user-custom entries on next refresh. **Active-slug sentinel:** `aih-plan` Phase 1 writes `.claude/_state/active-slug` after slug finalization; hook reads this sentinel to resolve the active plan directory; absent sentinel → exit 0 (gate not in scope for non-plan flows). **aih-quick + aih-bugfix** receive Step 0/Step 6 env-var lifecycle (`AIHAUS_CALIBRATE_GUARD=0` set at entry, unset at exit) — matching the ADR-M028-CURATE-A hook-bypass pattern. **Check 78 regex reuse:** ambiguity detection (`TBD|assumed|TODO|pending confirmation`) reuses the exact regex from Smoke Check 78 — hook applies this to ASSUMPTIONS.md; count = 0 → exit 0 (legitimate zero-ambiguity skip). **JSONL direct-emit:** hook writes `{"event":"calibrate-guard",...}` rows directly to `.claude/audit/hook.jsonl` — root cause of M027/S5 dead-code confirmed as `manifest-append.sh --audit` being non-existent; direct emit mirrors tdd-guard.sh + git-add-guard.sh pattern. **Smoke Check 81** (`check_calibrate_drift`) detects post-merge drift: any CHECK.md without companion BUSINESS-RULES.md AND with ambiguity markers fails unless (a) `calibration-skip` audit row present OR (b) CHECK.md mtime predates M029 epoch `1747008000` (5 legacy CHECK.md grandfathered via ctime-exemption). 3 fixture dirs prove gate non-vacuous. **tdd-dispatch DEFERRED** to M030+ pending dogfood evidence. **Surface 4** (implementer baseline) permanently rejected — carried forward from M028 ADR-260510-D. **M027/S5 dead-code removal** (S5): dead `manifest-append.sh --audit calibration-skip` references cleaned in `aih-plan/SKILL.md` + 2 annexes. **ADR-260511-B** (S4) amends ADR-260503-A move-rule to codify trigger pattern (c) anticipatory-protection-on-new-flow, closing the gap between aihaus's prior incident-required stance and field-default (Gitleaks/Helmet/rate-limiters) anticipatory deployment. Hook count: 31 → 32.

## Merge-Back (M017 / ADR-M017-A)

Merge-back from `isolation: worktree` agents to the milestone branch is driven by
`pkg/.aihaus/hooks/merge-back.sh` (the sole path). Per-file `cp` + explicit
`git add <file>` loop; refuses on file-set mismatch (exit 3, stable stderr grammar
`MERGE_BACK_REFUSED story=S<NN> reason=<unexpected-files|missing-files|cross-story-spill> expected=<...> actual=<...> worktree=<...>`).
Recovery paths (`--drop <file>`, `--abort`, or user MANIFEST edit + retry) documented at
`pkg/.aihaus/skills/aih-milestone/annexes/merge-back-recovery.md`. Checkpoint wrapping via
`manifest-append.sh --checkpoint-enter/exit merge-back:S<NN>` preserves ADR-004 single-writer
discipline. Companion defense: `pkg/.aihaus/hooks/git-add-guard.sh` (PreToolUse) blocks
destructive stage shapes on `milestone/*` / `feature/*` branches. 4-layer lock-leak
prevention stack (L1 SubagentStop + L2 SessionEnd + L3 `/aih-milestone --abort` + L4 reap)
lives in ADR-M017-B. Both guards opt-out via `AIHAUS_MERGE_BACK_GUARD=0` /
`AIHAUS_GIT_ADD_GUARD=0`; L1-L4 opt-out via `AIHAUS_RELEASE_L1=0` / `_L2=0` /
`AIHAUS_L3_DISABLED=1` / `AIHAUS_REAP_DISABLED=1`.

## Native CC features in use (M043)

Since v0.37.0 / M043, the following native Claude Code primitives are leveraged directly by the aihaus harness — documented here so maintainers don't reinvent what the platform already provides.

**Native features actively in use:**
- `memory: project` frontmatter on 46 of 48 agents → native subagent persistent memory at `.claude/agent-memory/<name>/MEMORY.md` (auto-injected first 200 lines / 25KB into system prompt). Two agents (`context-curator`, `learning-advisor`) declare `memory: none` by design. Accumulating today for at least `code-reviewer`, `project-analyst`, `verifier`, `assumptions-analyzer`, `brainstorm-synthesizer`, `pattern-mapper` (verified via `ls .claude/agent-memory/`).
- `isolation: worktree` frontmatter on 5 agents (`implementer`, `frontend-dev`, `code-fixer`, `executor`, `nyquist-auditor`) → native worktree isolation; each subagent gets a temp worktree under `.claude/worktrees/`, auto-cleaned if no changes.
- `effort: <tier>` frontmatter on all 48 agents → native CC field; the M008 cohort taxonomy (`:planner-binding`, `:planner`, `:doer`, `:verifier`, `:adversarial`) composes byte-identically with native semantics. Smoke Check 6 enforces.
- `.worktreeinclude` at repo root (M043/S1) → native gitignore-syntax file that copies untracked sidecars (`.aihaus/.effort`, `.aihaus/.install-source`, `.aihaus/.calibration`, `.aihaus/auto.sh`, `.aihaus/auto.ps1`) into every worktree, so isolated agents resolve relative sidecar paths correctly.

**Enabled but NOT yet in use (reserved for forward-compat):**
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` ships in `pkg/.aihaus/templates/settings.local.json:env` but **zero skills currently invoke Agent Teams primitives** (`SendMessage`, `teammate_name`, `task_subject`). The env flag is reserved for M044+ candidates: `/aih-brainstorm --team` panel rounds (BRIEF B3) is the most likely first consumer. Honest framing: this is **enabled, not active**.

**Safety overlays that extend (not replace) native primitives:**
- `pkg/.aihaus/hooks/merge-back.sh` (M017 / ADR-M017-A) — extends native worktree cleanup with per-file Owned-Files refuse-on-spill semantics that native cleanup lacks.
- `pkg/.aihaus/hooks/autonomy-guard.sh` — extends native subagent permission inheritance with policy enforcement (M005 + M011 + M023 + M025 + M027 composition; 40 active patterns). Native permission inheritance is capability-level; our guard is policy-level.
- `pkg/.aihaus/hooks/context-inject.sh` (M013/S05, v0.16.0) — runs on `SubagentStart` (wired at `settings.local.json:158-169`) and injects `decisions.md` + `knowledge.md` + `project.md` + `MEMORY.md` as HIGH-tier required pre-read into the subagent's `additionalContext`. Per-cohort token budgets at `pkg/.aihaus/hooks/context-budget.conf` (verified values: `planner-binding=4000`, `adversarial-scout=3000`, `adversarial-review=3000` — note the latter two predate the M027 cohort fork and still need migration to the merged `:adversarial` entry; tracked as M044+ defect). 5-minute memoization cache at `.claude/audit/context-inject.cache`.

**Empirically verified non-functional under Task-tool spawn (ADR-260517-A):**
- Native `skills:` frontmatter field for skill-content preload — canary test on `analyst` agent confirmed NO preload fires under aihaus's Task/Agent-tool spawn path. Subagent's system prompt did not contain the skill body content. **B1 (bundled `aih-binding-context` + 48-agent migration) formally deferred indefinitely.** `context-inject.sh` (M013/S05) remains canonical context-injection path for subagents. Re-evaluation triggers documented in ADR-260517-A. Full empirical evidence: `.aihaus/research/260515-cc-native-features.md` §1 + `.aihaus/plans/260515-m043-native-cc-leverage/CHECK.md`.

**Deferred to M046+ (genuine milestone scope):**
- aih-graph indexing of `.claude/agent-memory/*/MEMORY.md` as a new node type for cross-agent semantic query (BRIEF Turn 3 future scope).
- `context-budget.conf` M027 cohort fork propagation — `:adversarial` baseline added in M043 follow-up; pre-M027 keys retained for back-compat until M046+ deprecation window.
- Full bg-milestone substrate (worktree-aware manifest discovery + cross-session bg-milestone registry + merge-back orchestration across detached processes) per M044 honest caveat below.

**Empirically verified architecturally unreachable (ADR-260518-A, M045):**
- AgentTeams programmatic spawn from a skill body — ai-researcher VERDICT HIGH confidence NO with 3 verbatim doc citations (`docs/cc-native-features-260515.md` §2). Team creation is user-NL-gated; no `/team` slash command, no `CreateTeam` tool. `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` stays in template enabling the **user-NL-driven path** (user types "create an agent team to debate X" at top-level CC); no aihaus skill wraps this. Re-evaluation triggers in ADR-260518-A.

### Backgrounding a long-running milestone (M044 honest scope)

Claude Code ships `/bg` (alias `/background`) as a native slash command that detaches the current session into the background. After `/bg`, the session continues running and `claude agents` from any shell shows its status. Aihaus does NOT add a custom `--bg` flag to `/aih-milestone` because `/bg` already covers this use case at the native layer.

**Honest caveat (M048+ scope for full support):** native `/bg` and `claude --bg` both auto-isolate the session into a worktree under `.claude/worktrees/` before the first file edit (per `docs/cc-native-features-260515.md` §4:250). M047 Layer 1 (shipped) addresses **path resolution**: `resolve_manifest_path()` in `pkg/.aihaus/hooks/lib/manifest-helpers.sh` now detects `.claude/worktrees/<id>/` paths and rewrites the anchor to the main repo before walk-up, so statusLine + resume can find the parent milestone's manifest from inside a bg worktree (opt-out via `AIHAUS_M047_WORKTREE_AWARE=0`). Still M048+ scope: (a) `merge-back.sh` cross-process orchestration when the bg session creates new edits in its worktree, (b) cross-session bg-milestone registry so the main session knows what bg work is in flight, (c) automatic merge-back signal when the bg session completes.

`claude agents` itself shows **sibling Claude Code sessions only** — aihaus subagents spawned via Task/Agent tool (in worktrees with `isolation: worktree`) do NOT appear as separate rows (per `docs/cc-native-features-260515.md` §4:256).

## Installer Behavior

The install scripts create symlinks (Unix) or directory junctions (Windows) from `.claude/{skills,agents,hooks}` to `.aihaus/{skills,agents,hooks}` in the target repo. The `--copy` flag forces file copies instead. Settings are merged (not overwritten) using `jq` or Python as a fallback.

Since v0.19.0 / M015 (ADR-M015-A), aihaus is Claude Code-only. The `--platform` flag has been removed from install.sh and uninstall.sh. Launch via `bash .aihaus/auto.sh` (M014 DSP wrapper).

Since v0.26.0 / M022 (ADR-260504-A), `install.sh` ships V5 — global-skill bootstrap. A one-time `bash install.sh` symlinks every `pkg/.aihaus/skills/aih-*` into `~/.claude/skills/aih-*`, making every `/aih-*` skill resolve from any cwd in any future Claude Code session. Per-repo `.aihaus/` becomes opt-in enhancement (hooks + `project.md`), no longer a prerequisite for skill resolution. Default package location is `$XDG_DATA_HOME/aihaus` on Unix (`%LOCALAPPDATA%\aihaus` on Windows). Override via `AIHAUS_HOME` env var. Discovery priority chain: `--package` flag > `AIHAUS_HOME` > `~/.aihaus/.install-source` > XDG default > legacy paths. The central package vs per-repo overlay distinction is internal architecture, not user-facing. See ADR-260504-A.

## Dogfooding

To use aihaus on this repo itself:
```bash
bash pkg/scripts/install.sh --target .
```
This creates `.aihaus/` (gitignored) with symlinks back to `pkg/.aihaus/`. Local artifacts accumulate in `.aihaus/` while package improvements go to `pkg/.aihaus/`.

After any post-merge drift in `pkg/.aihaus/{hooks,skills,agents,templates}/` (including `settings.local.json`), re-run `bash pkg/scripts/update.sh --target .` to keep the local install aligned with the latest package contents.

## Releasing

After a milestone merges, generate a user-facing release-note draft:

```bash
bash tools/generate-release-notes.sh M0XX > tools/.out/release-notes-M0XX.md
```

The generator filters maintainer-only `tools/` paths and omits any Validation section, so `smoke-test`, `purity-check`, and `dogfood-brainstorm` changes don't bleed into user-visible notes. Review the draft, then publish:

```bash
gh release create vX.Y.Z --title "vX.Y.Z — <milestone title>" --notes-file tools/.out/release-notes-M0XX.md
```

### Tag Hygiene

After `gh release create`, run `git fetch --tags origin` on every aihaus install that follows the release branch. Tags occasionally land on remote without a corresponding local ref (M016/v0.20.0 case observed 2026-04-26 dogfood; recovered via `git fetch --tags`).

<!-- AIHAUS:EVOLVING-START -->
<!-- Curator writes ONLY inside this block. Content here is machine-maintained. -->
<!-- Do not edit manually — /aih-* skills append here during milestone completion. -->

<!-- AIHAUS:EVOLVING-END -->
