# First-Installer Journey Walkthrough — M027/S2

**Author:** analyst (read-only research; planner cohort, opus)
**Date:** 2026-05-08
**Branch:** milestone/M027-260508-skills-agents-perf-review
**Method:** analytical walkthrough — installer is NOT actually executed. Stdout
blocks are reproduced verbatim from `pkg/scripts/install.sh` and SKILL prose;
each step is tagged with the 4-bucket surface schema (`install` / `init` /
`first-feature` / `maintainer-only`) per OQ-5 resolution (PRD §S2).

**Scenario:** A first-time aihaus user has cloned the central package to
`~/Documents/GitHub/aihaus-flow` and now wants to install aihaus into a fresh
empty repo `~/code/myproj` that they just created with `git init`. They have
Claude Code v2.1.126+ on PATH. No prior aihaus install on this machine
(no `~/.claude/skills/aih-init`, no `~/.aihaus/.install-source`).

---

## Step 1: `bash ~/Documents/GitHub/aihaus-flow/pkg/scripts/install.sh --target ~/code/myproj`

**Surface bucket:** `install`

**Stdout (verbatim, from `install.sh:323-326,411,417-418,440-441,453,458,463,504,512-513,522,551,561-563`):**

```
aihaus installer
  package:  /home/v/Documents/GitHub/aihaus-flow/pkg
  target:   /home/v/code/myproj
  mode:     link
  link: .claude/agents -> .aihaus/agents
  link: .claude/hooks -> .aihaus/hooks
  skip: .claude/skills -- user-global skills present (pass --force-project-skills to override)
  link: .aihaus/auto.sh -> /home/v/Documents/GitHub/aihaus-flow/pkg/scripts/launch-aihaus.sh
  installing user-global skills...
  user-global: /home/v/.claude/skills/aih-bugfix
  user-global: /home/v/.claude/skills/aih-brainstorm
  user-global: /home/v/.claude/skills/aih-effort
  user-global: /home/v/.claude/skills/aih-feature
  user-global: /home/v/.claude/skills/aih-help
  user-global: /home/v/.claude/skills/aih-init
  user-global: /home/v/.claude/skills/aih-install
  user-global: /home/v/.claude/skills/aih-milestone
  user-global: /home/v/.claude/skills/aih-plan
  user-global: /home/v/.claude/skills/aih-quick
  user-global: /home/v/.claude/skills/aih-resume
  user-global: /home/v/.claude/skills/aih-sync-notion
  user-global: /home/v/.claude/skills/aih-update
  user-global: /home/v/.claude/skills/aih-roadmap
  user-global skills: 14 installed, 0 skipped (collision)
  registry: ~/.aihaus/.install-source -> /home/v/Documents/GitHub/aihaus-flow
  .gitignore: aihaus block injected

aihaus installed (link mode).
Launch with: bash .aihaus/auto.sh
Run /aih-init inside the launched session to bootstrap project.md
```

**Note (V5 ordering subtlety):** On a TRULY first-ever install, `_has_user_global_skills`
returns FALSE because `~/.claude/skills/aih-init` does not yet exist (it is created in Step 10
of `install.sh`, which runs AFTER the per-repo `link_or_copy` loop at L435-445). So on the
very first install, the per-repo `.claude/skills` junction IS created, AND the user-global
skills get installed afterward. On the SECOND install (into a different repo), the sentinel
is present and the per-repo `.claude/skills` junction is skipped — see the M022 V5 divergence
flag below.

**UX:** A single ~25-line block of structured stdout, four logical phases (banner →
per-repo links → user-global skills → registry/gitignore → launch instructions). No prompts,
no questions. User reads the final two lines as next-step instructions.

**File-system effects in `~/code/myproj/`:**
- `.aihaus/` populated with full package (skills, agents, hooks, templates, memory scaffolding)
- `.claude/agents` → symlink to `.aihaus/agents`
- `.claude/hooks` → symlink to `.aihaus/hooks`
- `.claude/skills` → symlink to `.aihaus/skills` (first-ever install only; skipped on subsequent installs)
- `.claude/settings.local.json` merged from template (permissions + hooks + env)
- `.aihaus/auto.sh` → symlink to launcher
- `.aihaus/.install-mode` = `link`
- `.gitignore` block injected (12 paths)

**File-system effects in `~`:**
- `~/.claude/skills/aih-{bugfix,brainstorm,effort,feature,help,init,install,milestone,plan,quick,resume,sync-notion,update,roadmap}/` — 14 symlinks
- Each carries `.aihaus-managed` ownership marker
- `~/.aihaus/.install-source` registry written

---

## Step 2: User launches Claude Code session

**Surface bucket:** `install` (terminal-side; not a skill yet)

**Command:** `cd ~/code/myproj && bash .aihaus/auto.sh`

**Stdout (from `pkg/scripts/launch-aihaus.sh` wrapper):** wrapper `exec`s
`claude --dangerously-skip-permissions`. User sees the standard Claude Code TUI.

**UX:** Standard Claude Code prompt; no aihaus banner. The `.claude/settings.local.json`
merged in Step 1 has already configured PreToolUse / Stop / SessionEnd hooks, so the
session starts in autonomous-mode silently.

---

## Step 3: `/aih-init`

**Surface bucket:** `init`

**Trigger:** User types `/aih-init` at Claude Code prompt. Skill resolves from
`~/.claude/skills/aih-init/SKILL.md` (user-global), not the per-repo path.

### Phase 0 — Configure Claude Code settings

**Stdout (from `aih-init/SKILL.md:46`, after deep-merge of `.aihaus/templates/settings.local.json`):**

> "Claude Code settings configured for autonomous operation."

**UX:** One line. Idempotent — if `.claude/settings.local.json` already had keys from
Step 1's installer, the deep-merge preserves them.

### Phase 1 — Pre-flight (steps 1-5)

**Step 1 (verify git repo, `aih-init/SKILL.md:53-56`):** Runs `git rev-parse --is-inside-work-tree`.
Passes silently because user ran `git init` before installing.

**Step 2 (detect existing project.md, `aih-init/SKILL.md:58-69`):** `.aihaus/project.md`
does not exist → enters **first-run mode**. No prompt.

**Step 2.5 (migrate older project.md, `aih-init/SKILL.md:72`):** No-op (no file to migrate).

**Step 2.7 (Windows .gitattributes, `aih-init/SKILL.md:75-90`):** ONLY fires on
`MINGW`/`MSYS`/`CYGWIN`. On Linux/macOS this step is silent. Hypothetical Windows prompt:

> "Windows detected, no .gitattributes. Git prints 'LF will be replaced by CRLF' warnings during milestone execution. Create a minimal .gitattributes to suppress? [y/N]"

**This is the ONE interactive prompt in the entire init flow** — and it only appears on Windows.

**Step 3 (validate marker order, `aih-init/SKILL.md:93-96`):** Skipped (re-run only).

**Step 4 (detect project name, `aih-init/SKILL.md:98-104`):** Tries package.json → pyproject.toml → Cargo.toml → directory basename. In a fresh empty repo, falls through to basename: `myproj`.

**Step 5 (zero questions, `aih-init/SKILL.md:108-110`):** No prompts.

### Phase 2 — Discovery + Generation (steps 6-12)

**Step 6 (spawn project-analyst agent, `aih-init/SKILL.md:115-119`):** `Agent` tool with
`subagent_type: "project-analyst"`. Agent runs read-only discovery and writes
`.aihaus/.init-scratch.md`. In a fresh empty repo, this scratch file will report
`language: unknown`, `framework: unknown`, zero models/endpoints/components.

**Step 7-9 (read scratch, load template, substitute placeholders, `aih-init/SKILL.md:122-157`):**
Substitutes `[PROJECT_NAME]=myproj`, `[LANG]=unknown`, etc. Inventory table receives zero rows.

**Step 10a (first-run write, `aih-init/SKILL.md:159-161`):** Writes substituted template to
`.aihaus/project.md`.

**Step 11 (cleanup, `aih-init/SKILL.md:173-174`):** Deletes `.aihaus/.init-scratch.md`.

**Step 12 (report completion, `aih-init/SKILL.md:177-184`):**

> "project.md ready at `.aihaus/project.md` (N sections populated, M placeholders left for manual edit)."

For an empty repo, expect something like `(2 sections populated, 5 placeholders left for manual edit)`.

**UX (whole skill):** ~3-5 minutes wall-clock (project-analyst dominates). User sees agent
spawn message, agent return, then the single completion line. Zero clarifying questions on
non-Windows. One y/N on Windows.

**Files written:**
- `.aihaus/project.md` (new)
- `.claude/settings.local.json` (merged, already partly populated by installer)

---

## Step 4: First `/aih-feature "add a hello-world endpoint"`

**Surface bucket:** `first-feature`

**Trigger:** User types `/aih-feature add a hello-world endpoint` (or with `--plan slug` for the planned-execution path; for "first feature" we assume the inline path).

### Phase 1: Understand & Plan (interactive)

**Step 1 — Load Context (`aih-feature/SKILL.md:29-33`):**
1. Read `.aihaus/memory/MEMORY.md` — empty index on a fresh install
2. Read `.aihaus/project.md` — populated by `/aih-init`
3. Read `.aihaus/decisions.md` — does not exist on fresh install (skill is permissive)
4. Read `.aihaus/knowledge.md` — does not exist (permissive)

**Stdout:** silent (no banner). The four reads happen invisibly.

**Step 1.5 — Persist Attachments (`aih-feature/SKILL.md:35-40`):** No-op (no attachments).

**Step 2 — Check Working Tree (`aih-feature/SKILL.md:42-45`):** Runs `git status` and
`git branch --show-current`. On a fresh empty repo with one commit (the user's `git init` +
optional initial commit, plus our installer-modified `.gitignore` if not yet committed),
this MAY emit a dirty-state warning if `.gitignore` is uncommitted:

> "Your working tree has uncommitted changes. I can stash them before branching, or work on the current branch — your call."

**Step 3 — Codebase Scan (`aih-feature/SKILL.md:47-52`):** Empty repo → finds no relevant
models/endpoints/components. Will report "No existing files match; this is a from-scratch
endpoint."

**Step 4 — Escalation Check (`aih-feature/SKILL.md:54-58`):** 0 files → no escalation
recommended (well below the 10-file threshold).

**Step 5 — Present Plan & Ask Questions (`aih-feature/SKILL.md:60-74`):** This is the
**single in-flow checkpoint**. Skill emits a message containing:

```
Clarifying questions:
1. What language/framework should the hello-world endpoint use? (project.md detected: unknown)
2. ...

Plan summary:
- Feature description: [echo of user request]
- Files to change: (none)
- Files to create: e.g., src/server.py + test_server.py
- Approach: [brief technical approach]
- Branch: feature/add-hello-world-endpoint
- Verification: [tests + checks]

Approve this plan to proceed, or adjust.
```

**STOP HERE. Wait for the user to respond.** (`aih-feature/SKILL.md:74`)

**UX of Phase 1:** This is the user's first encounter with the **two-phase pattern** —
plan, approve, execute. Critically, this is also the FIRST surface where the per-installer
journey shape diverges by stack: an empty repo with `language: unknown` forces the model
to ask a real clarifying question, whereas an established Python repo would auto-infer.

### Phase 2: Autonomous Execution

User approves. Skill enters Phase 2 (which is fully autonomous per `aih-feature/SKILL.md:76-79`).

**Pre-dispatch (`aih-feature/SKILL.md:77`):** Runs `bash .aihaus/hooks/worktree-reap.sh`
(silent no-op on first install — no stale worktrees) and creates a session sentinel.

**Phase 2 Task Tracking (`aih-feature/SKILL.md:83-93`):** Creates 6 TaskCreate entries
(branch / implement / verify / review / commit / artifacts). User sees these in the
TodoWrite UI.

**Step 6 — Create Branch + RUN-MANIFEST (`aih-feature/SKILL.md:95-99`):**
- `git checkout -b feature/add-hello-world-endpoint`
- Writes `.aihaus/features/260508-add-hello-world-endpoint/RUN-MANIFEST.md` (v3 schema, status: running, phase: implement)

**Step 7 — Implement (`aih-feature/SKILL.md:101-103`):** Spawns specialty agents per
`annexes/agent-routing.md`. For a hello-world endpoint in Python: spawns
`backend-dev` (in `:doer` cohort) inside an isolation worktree.

**Step 8 — Verify (`aih-feature/SKILL.md:105-106`):** Runs project-defined tests; on a
fresh repo with no test framework, emits a soft warning ("no test runner detected; ran
syntax check only").

**Step 9 — Adversarial Review (`aih-feature/SKILL.md:108-114`):** Spawns `code-reviewer`
(in `:adversarial-review` cohort). Writes `REVIEW.md`. Cap at 2 review+fix iterations.

**Step 10 — Commit (`aih-feature/SKILL.md:116-123`):**
```
feat: add hello-world endpoint

Feature: add-hello-world-endpoint
Files: 0 changed, 2 created
```

**Step 11 — Write Artifacts (`aih-feature/SKILL.md:125-160`):** Creates `PLAN.md` +
`SUMMARY.md` under `.aihaus/features/260508-add-hello-world-endpoint/`.

**Step 11.5 — Goal-Backward Verification (`aih-feature/SKILL.md:162-163`):** Spawns
`verifier` (`:verifier` cohort, haiku). Writes `VERIFICATION.md`.

**Step 11.7 — Integration Check (`aih-feature/SKILL.md:165-166`):** Conditional —
likely SKIPPED for a single-subsystem hello-world.

**Step 12 — Update project.md if structural (`aih-feature/SKILL.md:168-187`):** Detects
that `src/server.py` is new structural code. Spawns `project-analyst` with
`--refresh-inventory-only` and merges the AUTO-GENERATED block. Appends to
`## Milestone History` in the manual section.

**Step 13 — Report Completion (`aih-feature/SKILL.md:189-196`):** Sets terminal status
via `manifest-append.sh --field status --payload completed`. Reports:
- What was implemented
- Branch + commit hash
- Verification results
- Path to `.aihaus/features/260508-add-hello-world-endpoint/`

**UX of Phase 2:** Largely silent except agent-spawn announcements + final status.
~5-15 minutes wall-clock depending on complexity. User reads only the final completion
report.

---

## Architect R1-R6 surface mapping

The R1-R6 list below is re-verified from `.aihaus/brainstorm/260508-skills-agents-perf-review/PERSPECTIVE-architect.md:49-66`. The prompt's R-numbering differs from the file's actual ordering — the **file is authoritative** per the analyst skill instruction.

| Rec | Title (file authoritative) | Bucket(s) | First-installer-visible? | Note |
|-----|----------------------------|-----------|--------------------------|------|
| R1 | Merge 7 researcher agents into 2 (researcher + research-synthesizer) | maintainer-only (cohort table) → indirect `init`/`first-feature` (only if user reads `project.md` cohort references) | NO — directly | Cohort knob consolidation. First-installer never spawns researchers in `/aih-init` or first `/aih-feature` (researchers belong to milestone/plan flows, not feature flow). User would only feel this through `/aih-effort --cohort :planner` invocations later. |
| R2 | Promote ≥5 deterministic A-rows to C-hooks before M027 | install (hook installation), maintainer-only (audit changes) | NO — visible only as faster guard rejection messages | Hooks are already symlinked in Step 1; user never sees the A→C promotion as a journey shape change. Concrete candidates per architect: cost-cap-precheck, slug-format validation, citation-grammar enforcement (M026 Smoke Check 77). |
| R3 | Resolve M027 haiku-classifier-vs-denylist-vs-whitelist (commit to haiku-classifier) | maintainer-only | NO | Lives in `pkg/.aihaus/hooks/autonomy-guard.sh:411-591`. Architect cites ADR-260508-A I4 deadline (decisions.md:2658). User sees no journey shape change — only different stop-gate behavior at message Stop boundary, which is invisible to the install/init/first-feature happy path. |
| R4 | Extract `## Load Context` to `_shared/load-context.md` (referenced by aih-feature, aih-bugfix, aih-quick, aih-plan) | first-feature (Step 1 of aih-feature) | YES — indirectly | This is the ONE rec where the first-feature journey IS visibly affected. The 4-line Step 1 block at `aih-feature/SKILL.md:29-33` (and parallel block at `aih-bugfix/SKILL.md:14-18`) would resolve from `_shared/load-context.md` rather than inline prose. Behavior identical; SKILL.md becomes thinner. NOT installer-visible at install or init time; surfaces on first feature. |
| R5 | Update CLAUDE.md drift numbers + nightly Smoke Check assertion | maintainer-only | NO | CLAUDE.md is documentation-only for non-maintainers. First-installer never reads CLAUDE.md as part of any aih-* skill flow — it is project-root prose for Claude Code conversations. Drift: "12 commands" (actually 14), "20 hooks" (actually 30), cohort table count "44" (actually 46). |
| R6 | Spike migrations-specialist agent OR ADR documenting why aihaus does not ship one | maintainer-only (agent ships or ADR ships) | NO — first-feature flow does not exercise migrations | A spawned migrations-specialist would be a `:doer` cohort agent invoked from `/aih-milestone` or `/aih-feature` only when `project.md` Inventory contains a `migrations/` path. First-installer's first feature is hello-world — never triggers. |

### Tally

- First-installer-visible recs (any of `install` / `init` / `first-feature`): **1 of 6** (R4 only)
- Maintainer-only recs: **5 of 6** (R1, R2, R3, R5, R6)

This is consistent with the analyst-brief §3 S2 prior that the architect's review is heavily
biased toward maintainer-side cohort/skill cleanup rather than first-installer UX
improvements — which is its own finding.

---

## M022 V5 divergence flags

The architect's recommendations were drafted with priors from before M022/V5
(global-skill bootstrap) was fully observed at runtime. M022 changed several journey-shape
invariants. Flagged divergences:

### D1 — User-global skill resolution shifts the "where does my skill live" mental model

**Pre-M022 prior (panel-side):** all aih-* skills live at `.claude/skills/aih-*` per repo.
First-installer must run `install.sh` per repo to get any skill.

**Post-M022 reality (observed in `install.sh:435-445` + `:498-505`):** the FIRST install
populates BOTH `~/.claude/skills/aih-*` (user-global, 14 skills) AND `<target>/.claude/skills`
(per-repo). The SECOND install into a different repo **skips** the per-repo `.claude/skills`
junction (sentinel `_has_user_global_skills` returns TRUE). So R4's claim that "aih-feature,
aih-bugfix, aih-quick, aih-plan" share a load-context block must account for the resolution
order: a user-global SKILL.md that references `_shared/load-context.md` must resolve that
relative path correctly when invoked from a per-repo cwd. Currently, `aih-init/SKILL.md`
references `_shared/autonomy-protocol.md` via relative path (`pkg/.aihaus/skills/_shared/...`)
— this resolves through the symlink on per-repo path AND through the user-global symlink
because the user-global symlink targets the package's `pkg/.aihaus/skills/aih-init/`
directory, which sits adjacent to `_shared/`. **R4 implementation must preserve this
resolution**; the proposed `_shared/load-context.md` would inherit the same resolution
guarantee as `_shared/autonomy-protocol.md`. Low risk, but the architect's recommendation
prose did not mention V5.

### D2 — Stdout shape on subsequent installs differs from prose

The architect's R5 (CLAUDE.md drift numbers) reports "20→30 hooks" and "12→14 commands"
as cardinality drift. M022 V5 added a NEW user-visible stdout block:
`"  skip: .claude/skills -- user-global skills present (pass --force-project-skills to override)"`
(install.sh:440). This line did not exist in the pre-M022 install flow. The CLAUDE.md
§Installer Behavior section (last paragraph, "Since v0.26.0 / M022") covers it, but the
installer stdout was not part of any architect-cited drift. **Net effect:** first install
matches CLAUDE.md prose; second install adds one line not captured anywhere. Minor doc
drift candidate.

### D3 — `_has_user_global_skills` sentinel race on first-ever install

The architect's R2 (promote A-rows to hooks) treats the install-time hook population as a
solved primitive. But the sentinel check (`install.sh:432`,
`[[ -d "$HOME/.claude/skills/aih-init" ]]`) is checked BEFORE Step 10 user-global skill
install (install.sh:498-505). On the first-ever install on a machine, the per-repo
`.claude/skills` IS created (sentinel returns FALSE), then the user-global skills are
installed. On any subsequent install, the per-repo is SKIPPED. This is by design (M024/S02
ADR-260507-A #5) but it means R2's hook-promotion deployment story has a one-time
discrepancy: per-repo hooks always populate (`name: hooks` is unconditional in the loop at
install.sh:435-445), so R2's ≥5 promotions land identically on first vs subsequent installs.
**No actual divergence**; flagged for completeness because the architect did not
distinguish first-vs-subsequent install variants.

### D4 — Installer wraps DSP via `auto.sh`, not direct `claude --dangerously-skip-permissions`

The architect's recommendations do not address the launcher path. In V5, `bash .aihaus/auto.sh`
is the canonical entry per CLAUDE.md §Calibration and Permission Modes. The hello-world
first-feature journey above assumes the user reads the install.sh footer and follows the
`bash .aihaus/auto.sh` instruction. If the user instead types bare `claude`, hooks still
fire (autonomy-guard, etc.) but DSP is not active, so each tool call may prompt for
permission. **R-list silent on this; first-installer surface fully exposed.** Suggests a
gap for M027 to consider: an init-time check that warns if DSP wrapper was not used.

### Summary

**Divergence count:** 4 flagged (D1, D2, D3, D4).
**Material to R-list re-prioritization:** D4 is the most material — it surfaces a
first-installer UX gap that NONE of R1-R6 address. Recommend M027 PM consider whether to
fold D4 into a follow-up rec (e.g., "init-time DSP wrapper detection") alongside R4
(Load-Context extraction).

---

## Author note

This walkthrough was produced read-only per OQ-5 resolution. No installer was actually
executed; all stdout blocks were transcribed from `pkg/scripts/install.sh` (current HEAD)
and `pkg/.aihaus/skills/aih-{init,feature}/SKILL.md`. Any drift between this walkthrough
and live installer behavior should be treated as a finding for S7 (audit consolidation) or
S10 (final verification).
