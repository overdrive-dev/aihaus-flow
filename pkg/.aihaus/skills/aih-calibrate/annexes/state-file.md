# State File — `.aihaus/.calibration`

Companion doc to `/aih-calibrate` SKILL.md Phase 4 and `/aih-update`'s
`restore_calibration()`. Describes the sidecar that lets calibration
survive package refreshes.

Authoritative plan: `.aihaus/plans/260416-calibrate-survive-update/PLAN.md`
(§1 schema, §2 Phase-4 write, §4 bash restore, §5 PowerShell mirror).
Architecture: `.aihaus/milestones/M009-260416-calibrate-survive-update/architecture.md`.
Decision record: ADR-M009-A in `.aihaus/decisions.md`.

## Purpose

Every `/aih-calibrate` invocation commits in-place edits to
`pkg/.aihaus/agents/*.md` (`effort:` frontmatter) and
`pkg/.aihaus/templates/settings.local.json` (`permissions.defaultMode`).
`/aih-update` refreshes both surfaces on every run and would otherwise
silently revert those edits. The `.calibration` sidecar lives outside the
refreshed subdirectories and records absolute restore targets so
`/aih-update` can re-apply them.

## Location

`.aihaus/.calibration` — flat file at `.aihaus/` root. Sits alongside
`.install-mode`, `.install-platform`, `.install-source`, `.version` — four
existing user-owned sidecars that survive `update.sh` by placement alone
(the refresh loop only touches `skills/`, `agents/`, `hooks/`,
`templates/`).

## Ownership

- **User-owned.** Written by `/aih-calibrate` Phase 4 after the commit +
  smoke-test/purity gate passes. Never written on `--dry-run`, never
  written if the self-revert (`git reset --hard HEAD~1`) fired.
- **Never committed.** `git add .aihaus/.calibration` is forbidden under
  any mode (dogfood or end-user). In dogfood, `.gitignore` line 19
  (`/.aihaus/`) already covers it. End-user repos follow whatever policy
  they have for the rest of `.aihaus/`.
- **Derived state.** Safe to delete. Missing sidecar = restore is a silent
  no-op. Regeneration: the next `/aih-calibrate` invocation rewrites it
  with the full final state; `/aih-calibrate --inspect` surfaces current
  distribution without writing anything.
- **Not source of truth.** Git history (`chore(calibrate):` commits on
  `pkg/.aihaus/agents/*.md`) is authoritative. The sidecar is a
  re-application target, not a replacement for the commit.

## Schema v1

```
# aihaus calibration state — managed by /aih-calibrate, consumed by /aih-update
# Schema: v1
# This file is USER-OWNED and derived state. Safe to delete (regenerate via
# /aih-calibrate --inspect). Do not commit.

schema=1
permission_mode=bypassPermissions
last_preset=cost-optimized
last_commit=920cf48

# Per-agent effort overrides. Format: <agent-basename>=<effort-level>
# Values recorded are ABSOLUTE (restore writes them verbatim regardless of
# how package default evolves). NOT deltas from a preset row.
analyst=high
architect=xhigh
implementer=high
```

### Fields

- **`schema=1`** — mandatory first non-comment line. Restore bails with a
  loud warning if this field is missing or any value other than `1`. The
  schema version is forward-compat insurance: a future `schema=2` using
  different parsing will be skipped cleanly on v1-aware installs.
- **`permission_mode`** — absolute restore target for
  `permissions.defaultMode` in `.claude/settings.local.json`. Written
  verbatim; `merge-settings.sh` post-merge step overwrites the template
  value if this field is non-empty.
- **`last_preset`** — informational + used to trigger the auto-mode-safe
  side-effect warning. Accepted values: `cost-optimized`, `balanced`,
  `quality-first`, `auto-mode-safe`, `custom` (for ad-hoc `--agent` runs).
- **`last_commit`** — short SHA of the `chore(calibrate):` commit that
  produced this state. Informational; delete-safe before sharing (e.g.,
  in a support ticket) to avoid leaking private-branch SHAs.
- **`<agent-basename>=<effort-level>`** — one line per calibrated agent.
  The basename matches the filename stem in `pkg/.aihaus/agents/` (e.g.
  `implementer.md` → `implementer`). Effort level is one of
  `low | medium | high | xhigh | max` written verbatim into the agent's
  `effort:` frontmatter.

### Schema invariants (binding)

1. Values MUST NOT contain `=`. Parser uses naive `IFS='='` / `cut -d=`;
   escaping is not supported. Future schema bumps needing `=` in values
   must increment to `schema=2` and switch parsing.
2. Restore **must** strip `\r` before using any parsed value (CRLF safety;
   see below).
3. Blank lines and `#`-prefixed lines are skipped. Unknown keys are
   silently ignored (forward-compat).
4. Whitespace-only values are skipped (defensive continue; never apply an
   empty frontmatter value).

## Absolute-restore semantic

Recorded values are **verbatim restore targets**, not deltas from any
preset row. If a package release changes an agent's default, your
recorded value still wins on the next `/aih-update`. To track the new
package default after an upgrade, re-run `/aih-calibrate --preset <name>`
— that rewrites the sidecar with the current distribution.

This keeps the restore path stateless and ambiguity-free: no need to know
"what was the package default when this was written?" — the file already
records the intended final state.

## CRLF handling (Windows-compat)

On Windows, some editors flip LF → CRLF when saving the sidecar. Both
restore paths normalize:

- **Bash** (`update.sh`): `value="${value%$'\r'}"` strips a trailing `\r`
  from every parsed value.
- **PowerShell** (`install.ps1`): `-replace "\r", ""` (or `.Trim()`)
  applied to every value, and `Set-Content -Encoding UTF8 -NoNewline`
  on the output frontmatter to match `sed -i.bak` byte-identically.

## Migration path — pre-v0.13 hand edits

Users upgrading from v0.12 had no `/aih-calibrate` and no `.calibration`
file. The first `/aih-update` run post-v0.13 finds no sidecar → restore
is an early-return no-op. Calibration starts fresh from the shipped
defaults.

If you hand-edited agent frontmatter pre-v0.13 and want to preserve those
edits:

1. **Before** the first post-v0.13 update, run `/aih-calibrate --inspect`
   to snapshot current `effort:` distribution.
2. Run the first `/aih-update` (this refresh wipes your hand edits; known
   limitation — out of scope for M009).
3. Re-apply via per-agent invocation: for each divergent agent, run
   `/aih-calibrate --agent <name> --effort <level>`. Each invocation
   appends to the sidecar, closing the loop for future updates.

Alternatively, re-apply a preset that matches your intent
(`cost-optimized`, `balanced`, `quality-first`) — simpler if your edits
were uniform rather than per-agent custom.

## Adversarial-agent behavior (ADR-M008-C)

`plan-checker` and `contrarian` are preset-immune. Sidecar entries for
them only appear when the user invokes an explicit
`--agent plan-checker --effort <level>` (or the contrarian equivalent).
Absence from the sidecar means restore preserves the package default
(which is `max` by design).

This keeps restore from re-asserting a non-`max` value on adversarial
agents just because a preset once ran.

## Auto-mode-safe side-effect warning

When `last_preset=auto-mode-safe`, restore applies `permission_mode` +
`effort.*` from the sidecar AND prints a loud `!!` block to stdout
pointing the user at `/aih-calibrate --preset auto-mode-safe` to replay
side effects that the sidecar cannot auto-restore:

- removal of `permissionMode: bypassPermissions` from worktree agents
  (`implementer`, `frontend-dev`, `code-fixer`)
- widening of `auto-approve-bash.sh` SAFE_PATTERNS

These hook/frontmatter side effects revert on package refresh and must be
re-applied by re-running the preset.
