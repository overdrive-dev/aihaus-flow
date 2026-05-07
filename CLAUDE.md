# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

aihaus is a workflow automation package for Claude Code (Cursor support removed in v0.19.0 / M015 — see ADR-M015-A). It provides 12 intent-based commands (`init`, `plan`, `bugfix`, `feature`, `milestone`, `resume`, `brainstorm`, `help`, `quick`, `update`, `sync-notion`, `effort`) that users install into their own repositories via `install.sh --target <path>`. `/aih-run` and `/aih-plan-to-milestone` were retired in v0.11.0 — their behavior lives in `/aih-milestone` (execution + `--plan` promotion) and `/aih-feature --plan` (inline small-plan execution). `/aih-effort` (the effort-tuning skill, added M008 and renamed in v0.17.0 / M012) handles effort + model tuning. The permission-mode skill was deleted in v0.18.0 / M014 (replaced by DSP wrapper launch — see ADR-M014-A). There is no runtime, no build step, no package manager — the entire package is markdown files (skills, agents, memory) and shell scripts (install/uninstall + hook helpers like manifest-append, phase-advance, invoke-guard, manifest-migrate introduced in M003).

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
- `pkg/.aihaus/agents/*.md` — 46 agent definitions with YAML frontmatter. Agents are spawned by skills to do specialized work (analyst, architect, implementer, reviewer, plan-checker, verifier, code-reviewer, code-fixer, security-auditor, integration-checker, debugger, etc.).
- `pkg/.aihaus/hooks/*.sh` — 20 shell hooks for Claude Code lifecycle events: M003 protocol enforcement (invoke-guard, manifest-append, manifest-migrate, phase-advance) plus v0.12.0 runtime autonomy enforcement (autonomy-guard blocks forbidden execution-phase patterns).
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

**Cohort aliases** (v0.17.0 / M012 / ADR-M012-A). All 46 agents are
grouped into **6** uniform cohorts — one fixed default model per cohort:

| Cohort | Count | Default model | Notes |
|--------|-------|---------------|-------|
| `:planner-binding` | 4 | opus | Split from `:planner` (v0.15.0 intra-cohort xhigh carve-out → first-class cohort). Members: architect, planner, product-manager, roadmapper |
| `:planner` | 13 | opus | Research + structured planning agents upstream of code. Was 17 before `:planner-binding` split |
| `:doer` | 15 | sonnet | Forward-edit implementation agents. Absorbed former `:investigator` (deleted M012) — default tier byte-identical. Only cohort with model swap: `high` preset → `(opus, high)` |
| `:verifier` | 7 | haiku | Read-only assessment agents. Former `verifier-rich` subset (sonnet overrides) deleted |
| `:adversarial-scout` | 2 | opus | `plan-checker`, `contrarian` — preset-immune, `(opus, max)` baseline. Split from `:adversarial` |
| `:adversarial-review` | 2 | opus | `reviewer`, `code-reviewer` — preset-immune, `(opus, high)` baseline. Split from `:adversarial` |

**Deleted cohorts (M012):** `:investigator` (absorbed into `:doer`) and
`:verifier-rich` subset (agents reassigned individually). The single
`:adversarial` cohort (v0.15.0) is replaced by two cohorts above.

Invoke via `/aih-effort --cohort :<name> --model X --effort Y` (both axes
required). Per-agent escape hatch via `/aih-effort --agent <name> --model X
--effort Y` (ADR-M008-A amendment). The `:adversarial-scout` and
`:adversarial-review` cohorts are preset-immune — only an explicit
`--cohort :adversarial-scout` or `--cohort :adversarial-review` (with
literal-word `adversarial` confirmation) or `--agent <member>` can mutate
them. Full 46-agent mapping + prose rationale:
`pkg/.aihaus/skills/aih-effort/annexes/cohorts.md`.

**Sidecars.** Effort calibration survives `/aih-update` via a
`.aihaus/.effort` sidecar (schema v3; renamed from `.aihaus/.calibration`
v2 in M012 / ADR-M012-A; ownership preserved per ADR-M009-A).
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
declares two new YAML fields (46 agents classified; smoke-test Check 6 enforces both):

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
