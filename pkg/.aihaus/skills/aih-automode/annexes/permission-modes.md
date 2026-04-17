# Permission-Mode Tradeoff Matrix

This annex backs the `/aih-calibrate --permission-mode` and `--preset
auto-mode-safe` paths. The 4-caveat numbered list below is printed
**verbatim** before the `auto-mode-safe` full-word confirmation prompt —
do not drift its wording.

## Mode Matrix

| Mode | Plans supported | Providers | `Bash(*)` behavior | Subagent `permissionMode` honored | Classifier latency | aihaus default |
|------|-----------------|-----------|--------------------|------------------------------------|---------------------|----------------|
| `bypassPermissions` | all | all | honored | honored | none | **YES (default)** |
| `auto` | Max, Team, Enterprise, API (not Pro) | Anthropic API only | **dropped** | **ignored** | classifier round-trip per non-read action | opt-in via `/aih-calibrate --preset auto-mode-safe` |
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

Use `--preset auto-mode-safe` only if **all** of the following are true:

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

## Confirmation Prompt (Phase 3 step 11)

After printing the 4-caveat list above, the skill asks:

> Esta operação troca o permission mode para `auto`. Para confirmar,
> digite a palavra `auto-mode` (qualquer outra resposta aborta):

Only the exact trimmed string `auto-mode` (case-sensitive) proceeds.
Any other response — including `y`, `sim`, `yes`, empty enter — aborts
with the message *"Auto mode não ativado. Nenhum arquivo foi editado."*
and exits. No commit is created on abort.

## Rollback

After `/aih-calibrate --preset auto-mode-safe` applies:

- **Revert everything:** `git revert HEAD` — restores
  `defaultMode: "bypassPermissions"`, re-inserts
  `permissionMode: bypassPermissions` on the 3 worktree agents, and
  reverts the `auto-approve-bash.sh` widening. Byte-identical.
- **Revert just the permission mode (keep hook widening):** not
  recommended — partial reverts leave the `auto-approve-bash.sh`
  widening orphaned. Use `git revert HEAD` and re-apply any hook
  patterns manually if you genuinely want them without auto mode.

## References

- ADR-M008-B — Default permission mode stays `bypassPermissions`; auto is
  opt-in only. Binding.
- PLAN.md Rev. 3 Part 5 — auto-mode opt-in prep rationale.
- `_shared/autonomy-protocol.md` — Phase-3 one-question rule; no option
  menus even for destructive confirmations.
