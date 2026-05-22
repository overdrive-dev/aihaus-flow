---
name: aih-update
description: Update aihaus to the latest version from the remote repository. Fetches, compares, applies, and re-links.
disable-model-invocation: true
allowed-tools: Read Grep Glob Bash
argument-hint: "[--check | --force]"
---

## Task

Update the local aihaus installation by pulling the latest package from the remote git repository. Fully autonomous — fetches, compares versions, applies changes, re-links, and reports what changed.

$ARGUMENTS

## Flags

- `--check` — Only check if an update is available. Do not apply.
- `--force` — Skip version comparison, always pull and apply.
- `--session-log <milestone-slug>` — M004 story L post-hoc retrospective. Skip update logic; generate `.aihaus/milestones/<slug>/execution/SESSION-LOG.md` from `pkg/.aihaus/templates/SESSION-LOG.md`. Fill Timeline/Friction/Wins/Ideas/Artifacts/Hand-off from on-disk artifacts (RUN-MANIFEST.md, CHECK.md, VERIFICATION.md, INTEGRATION.md, reviewer reports, `.claude/audit/*.jsonl`, self-evolution additions). Opt-in only (F-M5); template H2 headers load-bearing — smoke-test enforces.
- No flag — Default: check version, pull if newer, apply, re-link.

---

## Phase 1 — Detect Package Source

### 1. Find the aihaus package repository

Resolve `PKG_REMOTE`/`PKG_LOCAL` in order: `.aihaus/.install-source`; symlinked `.aihaus/` target's git remote; dogfooding `pkg/` repo remote; otherwise ask for a git URL or local path.

### 2. Check if package repo is cloned locally

Use existing `PKG_LOCAL` when it is a git repo; otherwise use `~/.aihaus-pkg/` or `/tmp/aihaus-pkg/`; otherwise clone:

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

Route by platform — Windows must use PowerShell. `.aihaus/` is a managed copy; `.claude/{skills,agents,hooks}` may be junctions or copies. Git Bash's `rm -rf` can follow junctions and `ln -s` cannot recreate them, so the bash path **must not** run on Windows:

```bash
case "$OSTYPE" in
  msys*|cygwin*|win32)
    powershell.exe -NoProfile -ExecutionPolicy Bypass \
      -File "$PKG_LOCAL/pkg/scripts/update.ps1" -Target "$(pwd)" ;;
  *) bash "$PKG_LOCAL/pkg/scripts/install.sh" --target "$(pwd)" --update ;;
esac || { echo "ERROR: update script failed"; exit 1; }
```

Re-links skills/agents/hooks/templates. Preserves local data + calibration via `.aihaus/.calibration`.

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
[[ -f "$PKG_LOCAL/tools/smoke-test.sh" ]] || { echo "tools/smoke-test.sh missing in $PKG_LOCAL — migration notice: older clone layout. Re-run /aih-update after a clean clone."; return 0; }
SMOKE_OUT="$(mktemp 2>/dev/null || printf '.aihaus-smoke-%s.log' "$$")"
if bash "$PKG_LOCAL/tools/smoke-test.sh" >"$SMOKE_OUT" 2>&1; then
  tail -5 "$SMOKE_OUT"
else
  echo "WARNING: aihaus smoke test failed. Failing checks:"
  grep -E '^\[FAIL\]' "$SMOKE_OUT" || tail -40 "$SMOKE_OUT"
  grep -Eq 'framework purity|Check 15' "$SMOKE_OUT" && [[ -f "$PKG_LOCAL/tools/purity-check.sh" ]] && { echo "--- delegated purity-check.sh output ---"; bash "$PKG_LOCAL/tools/purity-check.sh" || true; }
fi
rm -f "$SMOKE_OUT"
```

If it fails, warn but don't rollback — the user can investigate.

### 11. Pre-flight Warnings

Before reporting, surface any migration-relevant state:

- **In-flight milestones** — mirror `aih-resume` Phase 1: skip `drafts/`; warn on `RUN-MANIFEST.md` whose `Status:` is not `completed`; legacy fallback warns only when execution visibly started (`stories/*.md` or `execution/{analysis-brief,PRD,architecture}.md`). Message: `In-flight milestone detected: <slug> (phase: <phase>). Post-update, run /aih-resume to continue.`
- **Legacy `aihaus:` prefix installs** — if `.claude/commands/aihaus:*.md` exists, warn: "Pre-rename installation detected — legacy `aihaus:` commands will be replaced by `aih-*`."

### 12. Migration Notice (version-gated)

Read previous version from `.aihaus/.version` (treat as `0.0.0` if missing). Fire each block whose boundary `prev_version` crosses (multi-version skips fire multiple):

- **< 0.2.0** — `/aih-milestone` now enters gathering mode; `/aih-resume` added; `/aih-milestone "desc" --execute` preserves old one-shot.
- **< 0.11.0** — retired: `/aih-run` → `/aih-milestone start|--execute` or `/aih-feature --plan <slug>`; `/aih-plan-to-milestone` → `/aih-milestone --plan <slug>`. Update CI scripts and keyboard snippets accordingly.
- **< 0.18.0** — M014 BREAKING (ADR-M014-A/B): `/aih-automode` DELETED; launch via `bash .aihaus/auto.sh`; `permissions.{allow,deny,defaultMode}` stripped (safety in PreToolUse hooks); `/aih-resume` rewritten (schema v3 sub-story checkpoints; `--legacy-mode` preserves old).
- **< 0.19.0** — M015 BREAKING (ADR-M015-A, supersedes ADR-002+005): Cursor removed; `--platform` flag dropped; `pkg/.aihaus/{.cursor-plugin,rules}/` deleted.

When any block fires, append: "Restart Claude Code to pick up reshuffled skills."

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

When running inside aihaus-flow (`pkg/` exists): use `PKG_LOCAL=.`; pull `origin main`; re-link via the same OS-aware case from Step 7; never call `bash install.sh --update` unconditionally on Windows; report what changed.

---

## Guardrails

- NEVER modifies files inside `pkg/` — only pulls from remote.
- NEVER deletes local data (project.md, plans, milestones, memory).
- If git fetch fails, report the error and stop gracefully.
- If the smoke test fails after update, warn but don't rollback.
- Write `.aihaus/.version` and `.aihaus/.install-source` for future updates.
## Autonomy
See `_shared/autonomy-protocol.md` — binding rules; overrides contradictory prose above.
<!-- See pkg/.aihaus/skills/_shared/enforcement-audit.md for this SKILL's enforcement audit. -->
