# Permission-Mode Tradeoff Matrix

This annex backs the `/aih-automode --enable` path. The 4-caveat numbered
list below is printed **verbatim** before the literal-word `auto` confirmation
prompt — do not drift its wording. Extracted from the former skill in M012/S04
per ADR-M012-A (skill-split decision).

## Mode Matrix

| Mode | Plans supported | Providers | `Bash(*)` behavior | Subagent `permissionMode` honored | Classifier latency | aihaus default |
|------|-----------------|-----------|--------------------|------------------------------------|---------------------|----------------|
| `bypassPermissions` | all | all | honored | honored | none | **YES (default)** |
| `auto` | Max, Team, Enterprise, API (not Pro) | Anthropic API only | **dropped** | **ignored** | classifier round-trip per non-read action | opt-in via `/aih-automode --enable` |
| `acceptEdits` | all | all | honored (but prompts on non-fs Bash) | honored | none | not a preset |
| `default` | all | all | honored only for read-only | honored | none | not a preset (would prompt constantly) |
| `dontAsk` | all | all | honored only for explicitly-allowed narrow rules | honored | none | not a preset (too restrictive for autonomous milestones) |

## Auto-Mode Caveats (printed before confirmation)

1. **Broad `Bash(*)` allow rules are silently dropped on entering auto
   mode.** aihaus ships `Bash(*)` in `templates/settings.local.json` as
   the single rule holding autonomous execution together; auto mode
   removes it without warning and routes every Bash call through the
   classifier, adding round-trip latency.
2. **Subagent `permissionMode: bypassPermissions` frontmatter is
   ignored under auto mode.** aihaus declares this on `implementer`,
   `frontend-dev`, and `code-fixer` specifically to enable unattended
   execution in worktrees; auto mode makes those declarations no-ops.
3. **Plan/provider restrictions:** auto mode requires Max/Team/Enterprise/API
   plan (not Pro), Anthropic API only (not Bedrock/Vertex/Foundry), and
   Opus 4.6/4.7 or Sonnet 4.6. A substantial slice of aihaus's userbase
   cannot activate it today.
4. **3-strikes pause:** 3 consecutive classifier blocks or 20 total
   pauses auto mode mid-session. For autonomous multi-story milestone
   execution, this is a story-killer that requires human intervention.

## Decision Tree — Should You Use Auto Mode?

Use `/aih-automode --enable` only if **all** of the following are true:

- **(a) Plan:** you are on Claude Max, Team, Enterprise, or API. Pro plan
  is not eligible; the skill detects this via `claude --print-config`
  pre-check and aborts before editing.
- **(b) Provider:** you are on Anthropic API directly, not Bedrock,
  Vertex, or Foundry. Auto mode is Anthropic-API-only.
- **(c) Model:** your default model is Opus 4.6, Opus 4.7, or Sonnet 4.6.
  Older models are unsupported by the classifier.
- **(d) Claude Code version:** v2.1.83 or later. The skill runs
  `claude --version` before writing and warns on lower versions that
  `defaultMode: auto` will be silently ignored.
- **(e) Classifier tolerance:** you accept the per-call classifier
  round-trip latency AND the 3-strikes mid-session pause. For a solo dev
  who is at the keyboard, this is fine. For autonomous overnight
  milestone execution, it is not.

If any of (a)–(e) fail: stay on `bypassPermissions`. The aihaus autonomy
contract (M005 + ADR-M008-B) assumes `bypassPermissions` + `Bash(*)` +
hook-based auto-approve; auto mode is an alternative, not an upgrade.

## Confirmation Prompt

After printing the 4-caveat list above, the skill asks:

> To confirm, type the literal word `auto` (any other response aborts):

Only the exact trimmed string `auto` (case-sensitive) proceeds.
Any other response — including `y`, `sim`, `yes`, `auto-mode`, empty enter —
aborts with the message *"Auto mode not enabled. No files were edited."*
and exits. No commit is created on abort.

## Rollback

After `/aih-automode --enable` applies:

- **Disable cleanly:** run `/aih-automode --disable` — reverts
  `defaultMode` to `bypassPermissions`, restores `permissionMode:
  bypassPermissions` on the 3 worktree agents, writes `.automode`
  with `enabled=false`. No confirmation required.
- **Revert just the permission mode:** not recommended to use
  `git revert HEAD` here since `/aih-automode --enable` does NOT create
  a git commit. Use `/aih-automode --disable` instead.

## References

- ADR-M008-B — Default permission mode stays `bypassPermissions`; auto is
  opt-in only. Binding.
- ADR-M012-A — skill-split rationale; `/aih-automode` as the dedicated
  permission-mode skill (split from the former calibration skill in M012).
- `_shared/autonomy-protocol.md` — one-question rule; no option menus
  even for destructive confirmations.
- `annexes/caveat-block.md` — verbatim caveat block text + confirmation
  prompt shape.
- `annexes/state-file.md` — `.automode` sidecar schema, gitignore, and
  idempotence contract.
