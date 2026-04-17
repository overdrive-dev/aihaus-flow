# Caveat Block — `/aih-automode --enable`

The 4-caveat block below is printed **verbatim** before the literal-word
`auto` confirmation prompt. Do not drift its wording. Preserved byte-identical
from v0.15.0 `auto-mode-safe` preset output.

## 4-Caveat Block (print verbatim before confirmation)

```
Auto mode has 4 important caveats — read before confirming:

1. Broad `Bash(*)` allow rules are silently dropped on entering auto mode.
   aihaus ships `Bash(*)` in `templates/settings.local.json` as the single
   rule holding autonomous execution together; auto mode removes it without
   warning and routes every Bash call through the classifier, adding
   round-trip latency.

2. Subagent `permissionMode: bypassPermissions` frontmatter is ignored under
   auto mode. aihaus declares this on `implementer`, `frontend-dev`, and
   `code-fixer` specifically to enable unattended execution in worktrees;
   auto mode makes those declarations no-ops.

3. Plan/provider restrictions: auto mode requires Max/Team/Enterprise/API plan
   (not Pro), Anthropic API only (not Bedrock/Vertex/Foundry), and Opus
   4.6/4.7 or Sonnet 4.6. A substantial slice of aihaus's userbase cannot
   activate it today.

4. 3-strikes pause: 3 consecutive classifier blocks or 20 total pauses auto
   mode mid-session. For autonomous multi-story milestone execution, this is a
   story-killer that requires human intervention.
```

## Confirmation Prompt (print after caveats)

```
To confirm, type the literal word `auto` (any other response aborts):
```

Only the exact trimmed string `auto` (case-sensitive) proceeds.
Any other response — including `y`, `yes`, `auto-mode`, `sim`, empty enter —
aborts with: `Auto mode not enabled. No files were edited.`

## References

- `annexes/permission-modes.md` — full permission-mode tradeoff matrix +
  decision tree.
- ADR-M008-B — default permission mode stays `bypassPermissions`; auto is
  opt-in only.
- ADR-M012-A — skill-split rationale; sidecar contract.
