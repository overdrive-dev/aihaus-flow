---
name: aih-init
description: Bootstrap project.md by analyzing the codebase. Mandatory first run after install. Re-runnable to refresh structural sections.
disable-model-invocation: true
allowed-tools: Read Write Edit Grep Glob Bash Agent
argument-hint: "[no arguments needed]"
---

## Task

Bootstrap or refresh `.aihaus/project.md` by analyzing the current repository.
Two phases: pre-flight checks, then discovery + generation. Default behavior
is fully autonomous with zero clarifying questions. Makes NO commits, NO
branch changes, and NO writes outside `.aihaus/`.

---

## Phase 0 — Configure Claude Code for autonomous operation

### 0. Write `.claude/settings.local.json`
Merge the aihaus settings template into `.claude/settings.local.json` so
all subsequent commands and agent teams run without permission prompts.

1. Read `.aihaus/templates/settings.local.json` (the template with
   permissions, hooks, and env for autonomous operation).
2. If `.claude/settings.local.json` does not exist, copy the template.
3. If it exists, deep-merge: template keys win (permissions, hooks, env),
   user-only keys are preserved. Use the same Python merge from `install.sh`:
   ```bash
   PY_BIN="$(command -v py || command -v python3 || command -v python)"
   "$PY_BIN" - .claude/settings.local.json .aihaus/templates/settings.local.json <<'PY'
   import json, sys
   def deep_merge(b, o):
       if isinstance(b, dict) and isinstance(o, dict):
           out = dict(b)
           for k, v in o.items(): out[k] = deep_merge(b.get(k), v) if k in b else v
           return out
       return o if o is not None else b
   d, s = sys.argv[1], sys.argv[2]
   with open(d) as f: dst = json.load(f)
   with open(s) as f: src = json.load(f)
   with open(d, "w") as f: json.dump(deep_merge(dst, src), f, indent=2); f.write("\n")
   PY
   ```
4. If no Python available, copy the template directly (warn user).
5. Print: "Claude Code settings configured for autonomous operation."

---

## Phase 1 — Pre-flight

### 1. Verify git repository
Run `git rev-parse --is-inside-work-tree`. If the command fails or prints
anything other than `true`, stop with:
> "This directory is not a git repository. /aih-init only runs inside git
> repositories. Run `git init` first or `cd` to your project root."

### 2. Detect existing `.aihaus/project.md`
Check whether `.aihaus/project.md` already exists.

- **Does not exist → first-run mode.** Continue to step 5.
- **Exists, both markers present in correct order → re-run mode.** Continue
  to step 5 and route to the re-run branch of Phase 2.
- **Exists, markers absent or out of order → degraded.** Prompt the user:
  > "`.aihaus/project.md` exists but is missing aihaus section markers (or
  > they are in the wrong order). Overwrite with a fresh file? [y/N]"
  - `y` / `yes` → treat as first-run mode.
  - Anything else → abort with: "Leaving project.md untouched. Fix markers
    manually, then re-run `/aih-init`."

### 2.5. Migrate older project.md files
If top-level AUTO/MANUAL markers exist but newer sub-markers (`ACTIVE-MILESTONES-START/END`, `RECENT-DECISIONS-START/END`, `RECENT-KNOWLEDGE-START/END`) are absent, inject them: within MANUAL, wrap the body of `## Active Milestones`, `## Decisions`, and `## Knowledge` headings with the corresponding start/end markers. Preserve existing user content — markers just demarcate the auto-populated region. Back up to `project.md.bak` first. Skip if already present.

### 2.7. Offer .gitattributes on Windows (suppress CRLF warnings)
If `uname -s` contains `MINGW`/`MSYS`/`CYGWIN` AND no `.gitattributes` at repo root, ask: *"Windows detected, no .gitattributes. Git prints 'LF will be replaced by CRLF' warnings during milestone execution. Create a minimal .gitattributes to suppress? [y/N]"*. If yes, write:
```
* text=auto eol=lf
*.sh text eol=lf
*.png binary
*.jpg binary
*.jpeg binary
*.gif binary
*.svg binary
*.webp binary
*.ico binary
*.pdf binary
*.woff binary
*.woff2 binary
```
Report created; otherwise skip silently.

### 3. Validate marker order (re-run only)
When both markers are present, verify `AUTO-GENERATED-START` appears BEFORE
`AUTO-GENERATED-END`. If not:
> "Marker order incorrect. Please fix manually or backup and re-run."
Abort.

### 4. Detect project name
Try these sources in order, using the first one that succeeds:
1. `package.json` → `.name` field (parse with a small `node -e` or
   `grep -oE '"name"\s*:\s*"[^"]+"'` one-liner).
2. `pyproject.toml` → `[project] name =` or `[tool.poetry] name =`.
3. `Cargo.toml` → `[package] name =`.
4. Directory basename of `pwd`.

Store as `PROJECT_NAME` for placeholder substitution in Phase 2.

### 5. Default behavior: zero questions
Do not prompt the user for anything beyond the degraded-file fallback in
step 2. The entire run is autonomous.

---

## Phase 2 — Discovery + Generation

### 6. Spawn the project-analyst agent
Use the `Agent` tool with `subagent_type: "project-analyst"` and a short
instruction: "Run full discovery and write `.aihaus/.init-scratch.md`
following your Discovery Protocol." Wait for the agent to complete. The
agent is read-only aside from the single scratch file.

### 7. Read the scratch file
Read `.aihaus/.init-scratch.md`. If it is missing after the agent run,
abort with: "project-analyst did not produce `.aihaus/.init-scratch.md`.
See the agent output above." Parse the YAML frontmatter to extract fields
(language, framework, database, test_framework, build_tool, package_manager,
models_count, endpoints_count, frontend_components_count, etc.).

### 8. Load the template
Read the project.md template from the first of these locations that exists:
1. `.aihaus/templates/project.md` — installed location (preferred; the
   installer copies the template here so each project can version it).
2. `.claude/skills/init/project.md.template` — fallback for installs that
   keep the template alongside the skill.

If neither exists, abort with: "project.md template not found. Re-run the
installer or place a template at `.aihaus/templates/project.md`."

### 9. Substitute placeholders
Replace each of the following tokens in the template with the corresponding
scratch-file value (use `unknown` if the field is missing):

| Token            | Source field                       |
|------------------|------------------------------------|
| `[PROJECT_NAME]` | step 4 result                      |
| `[LANG]`         | `language` (+ secondary in parens) |
| `[FRAMEWORK]`    | `framework` (+ secondary)          |
| `[DB]`           | `database`                         |
| `[TEST]`         | `test_framework`                   |
| `[BUILD]`        | `build_tool`                       |

Populate the Inventory table with one row per discovered layer, using
`models_count`, `endpoints_count`, `frontend_components_count`, and
`frontend_screens_count`. Populate the Architecture section from
`architecture_summary` if present, otherwise leave the template paragraph
as-is. Populate the Conventions section from `naming_style`, `linter`,
`formatter`, `commit_style`, `package_manager`.

### 10a. First-run write
If Phase 1 selected first-run mode, write the substituted template verbatim
to `.aihaus/project.md`. Overwrite any existing file.

### 10b. Re-run write — section-aware merge
If re-run mode: replace ONLY the content between `<!-- AIHAUS:AUTO-GENERATED-START -->`
and `<!-- AIHAUS:AUTO-GENERATED-END -->`. Everything outside (header, manual block,
footer) must be byte-identical before and after.

Steps: backup to `.aihaus/project.md.bak`, extract header (up to START marker),
extract footer (from END marker), build fresh auto block from the substituted
template, concatenate header + auto + footer, write back through any symlink.
Use `awk` to split on marker lines and `cat >` to follow symlinks.

### 11. Cleanup
Delete `.aihaus/.init-scratch.md`. Leave `.aihaus/project.md.bak` in place
for re-runs; it is auto-overwritten on the next invocation.

### 12. Report completion
Print a single-line summary:
> "project.md ready at `.aihaus/project.md` (N sections populated,
> M placeholders left for manual edit)."

Where N is the number of AUTO-GENERATED sections populated and M is the
count of `[PLACEHOLDER]` tokens still present in the manual block (those are
expected — they live inside the MANUAL region and are the user's to fill).

---

## Guardrails
- NO commits, NO `git add`, NO `git checkout`, NO branch creation.
- Writes limited to `.aihaus/` (scratch file, `project.md`, `project.md.bak`)
  and `.claude/settings.local.json` (Phase 0 only).
- If anything fails, surface the error and leave `.aihaus/project.md`
  untouched (first-run mode) or restore from `.aihaus/project.md.bak`
  (re-run mode) before exiting.
