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
