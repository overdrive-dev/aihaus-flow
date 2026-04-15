# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

aihaus is a workflow automation package for Claude Code **and** Cursor (multi-platform since v0.10.0 / M006 — see ADR-005). It provides 11 intent-based commands (`init`, `plan`, `bugfix`, `feature`, `milestone`, `resume`, `brainstorm`, `help`, `quick`, `update`, `sync-notion`) that users install into their own repositories via `install.sh --platform <claude|cursor|both>`. `/aih-run` and `/aih-plan-to-milestone` were retired in v0.11.0 — their behavior lives in `/aih-milestone` (execution + `--plan` promotion) and `/aih-feature --plan` (inline small-plan execution). There is no runtime, no build step, no package manager — the entire package is markdown files (skills, agents, rules, memory) and shell scripts (install/uninstall + hook helpers like manifest-append, phase-advance, invoke-guard, manifest-migrate introduced in M003).

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

- `pkg/.aihaus/skills/*/SKILL.md` — 13 skill definitions with YAML frontmatter. Each skill is a command invoked as `/aih-<name>` on Claude Code (or as a `Task` mention on Cursor).
- `pkg/.aihaus/skills/_shared/autonomy-protocol.md` — binding execution-autonomy rules (M005 / ADR-bound-to-all-skills): 3-phase rule, TRUE blocker definition, no option menus, no delegated typing. Every SKILL.md references it.
- `pkg/.aihaus/agents/*.md` — 43 agent definitions with YAML frontmatter. Agents are spawned by skills to do specialized work (analyst, architect, implementer, reviewer, plan-checker, verifier, code-reviewer, code-fixer, security-auditor, integration-checker, debugger, etc.).
- `pkg/.aihaus/hooks/*.sh` — 16 shell hooks for Claude Code lifecycle events + M003 protocol enforcement (invoke-guard, manifest-append, manifest-migrate, phase-advance).
- `pkg/.aihaus/rules/` — Cursor plugin rules and compatibility matrix (M006; `aihaus.mdc`, `COMPAT-MATRIX.md`, `README.md`). Consumed by Cursor's plugin subsystem when installed with `--platform cursor` or `--platform both`.
- `pkg/.aihaus/.cursor-plugin/plugin.json` — Cursor plugin manifest (M006; Strategy B per ADR-005). `pkg/.aihaus/` is the plugin root when installed on Cursor.
- `pkg/.aihaus/skills/aih-plan/annexes/*.md` — 4 annex files (attachments, intake-discipline, from-brainstorm, guardrails) — M004 enxugamento of the aih-plan core SKILL.md.
- `pkg/.aihaus/templates/SESSION-LOG.md` — template for `/aih-update --session-log <slug>` post-hoc retrospective (M004 story L).
- `pkg/.aihaus/memory/` — Empty memory index and directory structure (populated at runtime in target repos).
- `pkg/.aihaus/templates/` — Starter `project.md` and `settings.local.json` templates.
- `pkg/scripts/` — Cross-platform install/uninstall/update scripts (ship to users).
- `tools/` — Maintainer-only scripts (validation, purity, regression, release-notes generator; never ship to users).

## Key Conventions

- **Skills must declare `name: aih-<slug>`** in YAML frontmatter and stay under 200 lines. The smoke test enforces both.
- **Agents declare** `name`, `tools`, `model`, and `memory` in YAML frontmatter. `implementer`, `frontend-dev`, and `code-fixer` use `isolation: worktree` and `permissionMode: bypassPermissions`.
- **Agents are stack-agnostic.** They read `.aihaus/project.md` at runtime for stack details. Never hardcode languages, frameworks, or directory structures in agent definitions.
- **The purity check** scans all shipped files for references to foreign framework names. Any match fails the check. See the `FORBIDDEN_TERMS` array in `tools/purity-check.sh` for the full denylist.
- **`project.md`** uses marker comments (`<!-- AIHAUS:AUTO-GENERATED-START -->` / `<!-- AIHAUS:MANUAL-START -->`) to separate machine-owned and human-owned sections.
- **Conflict prevention:** All code-writing agents must read `.aihaus/decisions.md` (ADRs) and `.aihaus/knowledge.md` before implementation.
- **Self-evolution:** After milestones, the reviewer proposes agent definition improvements based on accumulated decisions and knowledge. The completion protocol applies approved evolutions.

## Editing Skills and Agents

When modifying a skill, preserve the two-phase pattern: (1) ask scoping questions upfront, (2) get one approval, (3) run autonomously. The `quick` skill is the exception — it skips planning entirely.

When modifying an agent, keep it read-only unless it's `implementer`, `frontend-dev`, or `code-fixer` (those have write tools). The `reviewer` and `code-reviewer` agents must never modify code.

After any change to skills, agents, or hooks, run `bash tools/smoke-test.sh` to validate counts and frontmatter.

**Multi-platform authoring (since M006 / ADR-005).** aihaus ships to both Claude Code and Cursor. When adding a new skill or agent, consider cross-platform behavior:

- If the skill/agent relies on `isolation: worktree` or `permissionMode: bypassPermissions`, it cannot run on Cursor (Cursor lacks both primitives). Update `pkg/.aihaus/rules/COMPAT-MATRIX.md` with a NOT-SUPPORTED row in the same commit.
- If it uses the `Agent` tool for subagent spawning, Cursor users invoke the same surface via `Task` + `/<name>` mentions — the rules file handles tool-name translation, no skill-side change needed.
- Prefer per-agent `tools:` whitelists even though Cursor inherits parent tools (the read-only discipline is documented in COMPAT-MATRIX.md and still enforced on Claude Code).

## Installer Behavior

The install scripts create symlinks (Unix) or directory junctions (Windows) from `.claude/{skills,agents,hooks}` to `.aihaus/{skills,agents,hooks}` in the target repo. The `--copy` flag forces file copies instead. Settings are merged (not overwritten) using `jq` or Python as a fallback.

Since M006, both install.sh and uninstall.sh accept `--platform <claude|cursor|both>`. Default is `claude` (preserves pre-v0.10.0 behavior byte-identical). `cursor` additionally symlinks `~/.cursor/plugins/local/aihaus` → `<target>/.aihaus`. `both` does both. A `.aihaus/.install-platform` marker records the choice for update.sh.

## Dogfooding

To use aihaus on this repo itself:
```bash
bash pkg/scripts/install.sh --target .
```
This creates `.aihaus/` (gitignored) with symlinks back to `pkg/.aihaus/`. Local artifacts accumulate in `.aihaus/` while package improvements go to `pkg/.aihaus/`.

After modifying `pkg/.aihaus/templates/settings.local.json`, re-run `bash pkg/scripts/update.sh --target .` to keep the local install aligned with the template.

## Releasing

After a milestone merges, generate a user-facing release-note draft:

```bash
bash tools/generate-release-notes.sh M0XX > tools/.out/release-notes-M0XX.md
```

The generator filters maintainer-only `tools/` paths and omits any Validation section, so `smoke-test`, `purity-check`, and `dogfood-brainstorm` changes don't bleed into user-visible notes. Review the draft, then publish:

```bash
gh release create vX.Y.Z --title "vX.Y.Z — <milestone title>" --notes-file tools/.out/release-notes-M0XX.md
```
