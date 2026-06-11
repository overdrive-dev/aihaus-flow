# Claude Context Bridge

`/aih-init` must keep Claude Code's native project-instruction entrypoints wired
to aihaus project memory so a fresh session does not start blind.

1. Ensure `.claude/` and `.claude/rules/` exist.
2. If `.claude/CLAUDE.md` is absent, copy
   `.aihaus/templates/claude/CLAUDE.md` to `.claude/CLAUDE.md`.
3. If `.claude/CLAUDE.md` exists with the managed aihaus markers, sync that
   managed block from the template. Preserve all user text outside the markers.
   If the markers are absent, append the template block.
4. If `.claude/rules/aihaus-project-memory.md` is absent, copy
   `.aihaus/templates/claude/rules/aihaus-project-memory.md`.
5. If that rule file exists with the managed aihaus markers, sync that managed
   block from the template. Preserve all user text outside the markers. If the
   markers are absent, append the template block.

Do not overwrite user-authored Claude instructions. The bridge owns only the
marked aihaus blocks and is idempotent.

### First-position harness import (M050/S03, ADR-260611-B)

The managed block's **first import** is `@../.aihaus/protocols/harness.md` —
the single ≤2KB aihaus harness (condensed autonomy law, 3-tier memory map,
gate grammar). It must stay first inside the
`AIHAUS:CLAUDE-CONTEXT-START/END` markers so every main session loads the law
before any other context. Propagation is automatic: `ensure_block()` in
`project-context-refresh.sh` rewrites the marker span from the template, and
`scrub_large_claude_imports` strips only the `decisions.md` / `knowledge.md`
imports, so the harness import survives refresh. `claude-context-verify.sh`
reports it under the required-imports list.
