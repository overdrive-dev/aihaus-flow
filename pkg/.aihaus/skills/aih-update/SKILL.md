---
name: aih-update
description: Update aihaus to the latest version from the remote repository. Fetches, compares, applies, and re-links.
disable-model-invocation: true
allowed-tools: Read Grep Glob Bash
argument-hint: "[--check | --force]"
---

## Task

Update the local aihaus installation by pulling the latest package from the
remote git repository. Fully autonomous — fetches, compares versions, applies
changes, re-links, and reports what changed.

$ARGUMENTS

## Flags

- `--check` — Only check if an update is available. Do not apply.
- `--force` — Skip version comparison, always pull and apply.
- No flag — Default: check version, pull if newer, apply, re-link.

---

## Phase 1 — Detect Package Source

### 1. Find the aihaus package repository

Check these locations in order:

1. If `.aihaus/.install-source` exists, read the remote URL from it.
2. If `.aihaus/` is a symlink, resolve it to find the package root, then
   check `git -C <pkg-root> remote get-url origin`.
3. If a `pkg/` directory exists in the current repo (dogfooding mode),
   use the current repo's remote: `git remote get-url origin`.
4. If none found, ask the user: "Where is the aihaus package repo?
   Provide a git URL or local path."

Store as `PKG_REMOTE` and `PKG_LOCAL` (local clone path).

### 2. Check if package repo is cloned locally

If `PKG_LOCAL` exists and is a git repo, use it.
If not, check for a cached clone at `~/.aihaus-pkg/` or `/tmp/aihaus-pkg/`.
If no local clone exists, clone to `~/.aihaus-pkg/`:

```bash
git clone --depth 1 "$PKG_REMOTE" ~/.aihaus-pkg
```

---

## Phase 2 — Version Comparison

### 3. Fetch latest from remote

```bash
git -C "$PKG_LOCAL" fetch origin --tags
```

### 4. Compare versions

Read local version: `cat .aihaus/.version 2>/dev/null || echo "0.0.0"`
Read remote version: `git -C "$PKG_LOCAL" show origin/main:pkg/VERSION 2>/dev/null`

If `--check` flag: print comparison and stop.

```
aihaus update check:
  Local:  0.1.0
  Remote: 0.2.0
  Status: Update available (run /aih-update to apply)
```

If versions are equal and `--force` is not set: print "Already up to date." and stop.

### 5. Show changelog diff

```bash
git -C "$PKG_LOCAL" log --oneline local-tag..origin/main -- pkg/
```

Print: "Changes since your version: [N commits]"
Show the commit subjects (max 20 lines).

---

## Phase 3 — Apply Update

### 6. Pull latest

```bash
git -C "$PKG_LOCAL" checkout main
git -C "$PKG_LOCAL" pull origin main
```

### 7. Run the package update script

```bash
bash "$PKG_LOCAL/pkg/scripts/install.sh" --target "$(pwd)" --update
```

This re-links skills, agents, hooks, templates from the updated package.
Preserves all local data (project.md, plans, milestones, memory).

### 8. Write version marker

```bash
cat "$PKG_LOCAL/pkg/VERSION" > .aihaus/.version
```

### 9. Write source marker (for future updates)

```bash
echo "$PKG_REMOTE" > .aihaus/.install-source
```

---

## Phase 4 — Verify & Report

### 10. Run smoke test (if available)

```bash
bash "$PKG_LOCAL/pkg/scripts/smoke-test.sh" 2>/dev/null
```

If it fails, warn but don't rollback — the user can investigate.

### 11. Pre-flight Warnings

Before reporting, surface any migration-relevant state:

- **In-flight milestones** — `Glob` `.aihaus/milestones/*/` for dirs without `execution/MILESTONE-SUMMARY.md`. If any exist, warn: "In-flight milestone detected: [slug]. Post-update, run `/aih-resume` to continue."
- **Legacy `aihaus:` prefix installs** — if `.claude/commands/aihaus:*.md` exists, warn: "Pre-rename installation detected — legacy `aihaus:` commands will be replaced by `aih-*`."

### 12. Migration Notice (version-gated)

Read the previous version stored in `.aihaus/.version` (or treat as `0.0.0` if missing). If the new version crosses the boundary where gathering-mode milestones were introduced (v0.2.0 or first version shipping `aih-run`), print:

```
Migration notice — command surface changed:
  /aih-milestone now enters gathering mode (conversational draft refinement).
  New commands:
    /aih-run                 — execute a ready draft or plan (no slug required)
    /aih-resume              — pick up an interrupted run
    /aih-plan-to-milestone   — promote a plan to a milestone draft

  Backward compat:
    /aih-milestone "desc" --execute    — preserves old one-shot behavior
    /aih-milestone --plan [slug]       — auto-routes to /aih-plan-to-milestone

  Restart Claude Code to discover the new skills.
```

### 13. Report

```
aihaus updated: 0.1.0 → 0.2.0
  Agents: [N] (was [M])
  Skills: [N] (was [M])
  Hooks: [N]
  Changes: [N commits]
  Source: [remote URL]

Run /aih-help to see available commands.
```

If new skills appeared in the update diff, append: "⚠️  Restart Claude Code to load new skills."

---

## Dogfooding Mode

When running inside the aihaus-flow repo itself (detected by `pkg/` existing):

1. Skip cloning — use `pkg/` directly as the package source.
2. `git pull origin main` to update the repo itself.
3. Run `bash pkg/scripts/install.sh --target . --update` to re-link.
4. Report what changed.

---

## Guardrails

- NEVER modifies files inside `pkg/` — only pulls from remote.
- NEVER deletes local data (project.md, plans, milestones, memory).
- If git fetch fails, report the error and stop gracefully.
- If the smoke test fails after update, warn but don't rollback.
- Write `.aihaus/.version` and `.aihaus/.install-source` for future updates.
