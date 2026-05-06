---
name: aih-install
description: Install or refresh the aihaus per-repo overlay in the current directory. Resolves AIHAUS_HOME via the 8-tier priority chain. Zero prompts on the happy path.
disable-model-invocation: false
allowed-tools: Bash
argument-hint: "[no arguments needed — or --copy, --force, --package <path>]"
---

## Task

Install or refresh the aihaus overlay into the current working directory by
dispatching to `pkg/scripts/install.sh` with `--target .`. Fully autonomous
on the happy path — no prompts, no option menus, no compound decisions.

$ARGUMENTS

---

## Step 1 — Resolve AIHAUS_HOME

Locate the central aihaus clone. Check in order:

1. `$AIHAUS_HOME` env var — if set and `$AIHAUS_HOME/pkg/.aihaus/skills` exists,
   use it.
2. `~/.aihaus/.install-source` registry — if the file exists and the recorded
   path contains `pkg/.aihaus/skills`, use it.
3. Standard candidate paths (newest HEAD commit timestamp wins when multiple
   match):
   - `$XDG_DATA_HOME/aihaus` (default: `~/.local/share/aihaus`)
   - `~/tools/aihaus`
   - `~/Documents/GitHub/aihaus-flow`
   - `~/Documents/GitHub/aihaus`
   - `~/code/aihaus`

If no candidate is found, stop with:
> "AIHAUS_HOME not found. Clone aihaus (e.g. `git clone https://github.com/user/aihaus ~/tools/aihaus`) then re-run `/aih-install`."

The full discovery chain (including tier arbitration) is implemented in
`install.sh` itself — the dispatch in Step 3 benefits from it automatically.
The check above is the pre-flight guard for the dogfood detection in Step 2.

---

## Step 2 — Detect dogfood mode

If both of the following are true in `$PWD`:
- `pkg/scripts/install.sh` exists
- `pkg/.aihaus/skills/` exists

Then `$PWD` IS the central aihaus clone (dogfood mode). Do NOT install into
itself. Print:

> "Dogfood mode detected — cwd is the aihaus central clone."
> "To install aihaus into another repo, cd there and re-run /aih-install."
> "To dogfood aihaus on this repo: `bash pkg/scripts/install.sh --target .`"

Then stop without running Step 3.

---

## Step 3 — Dispatch

Run the install script, forwarding any `$ARGUMENTS` flags the user provided
(e.g. `--copy`, `--force`, `--package <path>`):

```bash
# Prefer the aihaus CLI shim if it is on PATH (installed by Z5 / ADR-260504-A)
if command -v aihaus >/dev/null 2>&1; then
  aihaus install --target . $ARGUMENTS
else
  bash "$AIHAUS_HOME/pkg/scripts/install.sh" --target . $ARGUMENTS
fi
```

The install script is idempotent — re-running on an already-installed repo
performs a refresh (equivalent to `--update`).

On non-zero exit, surface the install script's stderr verbatim and stop.

---

## Step 4 — Confirm

After a successful exit (exit code 0) from the install script, print a single
confirmation line:

> "aihaus overlay active in $PWD."

No further output — the install script already prints its own progress lines.

---

## Guardrails

- No commits, no `git add`, no branch creation.
- Writes are limited to the target repo's `.aihaus/` and `.claude/` directories
  (performed by `install.sh` — this skill does not write files directly).
- If `$ARGUMENTS` contains any flag not accepted by `install.sh`, the script
  will reject it and print usage; surface that to the user.
- This skill does NOT modify `pkg/.aihaus/skills/aih-init/SKILL.md` or any
  other skill definition (NFR-03 — `aih-init` retains `disable-model-invocation: true`).

## Autonomy

See `_shared/autonomy-protocol.md` — binding rules for planning/threshold/execution phases, no option menus, no honest checkpoints, no delegated typing. Overrides contradictory prose above.
<!-- See pkg/.aihaus/skills/_shared/enforcement-audit.md for this SKILL's enforcement audit. -->
