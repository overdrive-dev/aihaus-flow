# Claude Context Bridge

`/aih-init` must keep Claude Code's native project-instruction entrypoints wired
to aihaus project memory so a fresh session does not start blind.

1. Ensure `.claude/` and `.claude/rules/` exist.
2. If `.claude/CLAUDE.md` is absent, copy
   `.aihaus/templates/claude/CLAUDE.md` to `.claude/CLAUDE.md`.
3. If `.claude/CLAUDE.md` exists but lacks
   `AIHAUS:CLAUDE-CONTEXT-START`, append the template block. Preserve all
   existing user text.
4. If `.claude/rules/aihaus-project-memory.md` is absent, copy
   `.aihaus/templates/claude/rules/aihaus-project-memory.md`.
5. If that rule file exists but lacks `AIHAUS:CLAUDE-RULES-START`, append the
   template block. Preserve all existing user text.

Do not overwrite existing Claude instructions. The bridge is additive and
idempotent.
