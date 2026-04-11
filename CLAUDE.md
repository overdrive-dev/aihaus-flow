# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

AIhaus is a workflow automation package for Claude Code. It provides 8 intent-based commands (`init`, `plan`, `bugfix`, `feature`, `milestone`, `help`, `quick`, `sync-notion`) that users install into their own repositories. There is no runtime, no build step, no package manager — the entire package is markdown files (skills, agents, memory) and shell scripts (install/uninstall).

## Repo Structure

This repo has two layers:

- **`pkg/`** — The publishable package. Everything inside `pkg/` ships to users. This is what `install.sh` copies into target repos. Edits to skills, agents, and hooks go here.
- **`.aihaus/`** — Local installation (gitignored). Created by running `bash pkg/scripts/install.sh --target .` to dogfood AIhaus on its own repo. Contains runtime artifacts (project.md, plans, milestones, memory) that never leave this machine.

Self-evolution: when agents improve their own definitions during milestone execution, those edits land in `pkg/.aihaus/agents/` and get committed — feeding improvements back into the published package.

## Validation

```bash
# Smoke test — validates package structure, file counts, frontmatter, templates
bash pkg/scripts/smoke-test.sh

# Purity check — ensures no references to foreign framework names
bash pkg/scripts/purity-check.sh
```

There is no build command, no type checker, and no unit test framework. The smoke test is the primary validation gate.

## Package Contents (inside `pkg/`)

- `pkg/.aihaus/skills/*/SKILL.md` — 8 skill definitions with YAML frontmatter. Each skill is a Claude Code command invoked as `/aih-<name>`.
- `pkg/.aihaus/agents/*.md` — 17 agent definitions with YAML frontmatter. Agents are spawned by skills to do specialized work (analyst, architect, implementer, reviewer, plan-checker, verifier, code-reviewer, code-fixer, security-auditor, integration-checker, debugger, etc.).
- `pkg/.aihaus/hooks/*.sh` — 12 shell hooks for Claude Code lifecycle events.
- `pkg/.aihaus/memory/` — Empty memory index and directory structure (populated at runtime in target repos).
- `pkg/.aihaus/templates/` — Starter `project.md` and `settings.local.json` templates.
- `pkg/scripts/` — Cross-platform installers and validation scripts.

## Key Conventions

- **Skills must declare `name: aih-<slug>`** in YAML frontmatter and stay under 200 lines. The smoke test enforces both.
- **Agents declare** `name`, `tools`, `model`, and `memory` in YAML frontmatter. `implementer`, `frontend-dev`, and `code-fixer` use `isolation: worktree` and `permissionMode: bypassPermissions`.
- **Agents are stack-agnostic.** They read `.aihaus/project.md` at runtime for stack details. Never hardcode languages, frameworks, or directory structures in agent definitions.
- **The purity check** scans all shipped files for references to foreign framework names. Any match fails the check. See the `FORBIDDEN_TERMS` array in `pkg/scripts/purity-check.sh` for the full denylist.
- **`project.md`** uses marker comments (`<!-- AIHAUS:AUTO-GENERATED-START -->` / `<!-- AIHAUS:MANUAL-START -->`) to separate machine-owned and human-owned sections.
- **Conflict prevention:** All code-writing agents must read `.aihaus/decisions.md` (ADRs) and `.aihaus/knowledge.md` before implementation.
- **Self-evolution:** After milestones, the reviewer proposes agent definition improvements based on accumulated decisions and knowledge. The completion protocol applies approved evolutions.

## Editing Skills and Agents

When modifying a skill, preserve the two-phase pattern: (1) ask scoping questions upfront, (2) get one approval, (3) run autonomously. The `quick` skill is the exception — it skips planning entirely.

When modifying an agent, keep it read-only unless it's `implementer`, `frontend-dev`, or `code-fixer` (those have write tools). The `reviewer` and `code-reviewer` agents must never modify code.

After any change to skills, agents, or hooks, run `bash pkg/scripts/smoke-test.sh` to validate counts and frontmatter.

## Installer Behavior

The install scripts create symlinks (Unix) or directory junctions (Windows) from `.claude/{skills,agents,hooks}` to `.aihaus/{skills,agents,hooks}` in the target repo. The `--copy` flag forces file copies instead. Settings are merged (not overwritten) using `jq` or Python as a fallback.

## Dogfooding

To use AIhaus on this repo itself:
```bash
bash pkg/scripts/install.sh --target .
```
This creates `.aihaus/` (gitignored) with symlinks back to `pkg/.aihaus/`. Local artifacts accumulate in `.aihaus/` while package improvements go to `pkg/.aihaus/`.
