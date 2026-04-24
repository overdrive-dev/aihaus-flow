# Per-Agent Memory: `aihaus:agent-memory` Block Contract

This annex documents the parse contract and emission threshold for the
`aihaus:agent-memory` fenced block. Every agent definition references this file
in its **Per-agent memory (optional)** section.

## Parse Contract (LOCKED — M016-S15a)

### Block delimiters

```
<!-- aihaus:agent-memory -->
path: .aihaus/memory/agents/<agent-name>.md
## <date> <slug>
...body lines (free-form markdown)...
<!-- aihaus:agent-memory:end -->
```

- Opening delimiter: `<!-- aihaus:agent-memory -->`
- Closing delimiter: `<!-- aihaus:agent-memory:end -->`
- HTML-comment delimiters mirror existing curator block conventions.

### Path line (required, first line of body)

```
path: .aihaus/memory/agents/<agent-name>.md
```

- Exactly one path per block (no multi-file `===` delimiters).
- `<agent-name>` must be hyphen-only (no underscores) — filename-prefix-guard
  precondition enforced at smoke-test and completion-protocol Step 4.7b.

### Body

All lines after the `path:` line are free-form markdown. Recommended structure:

```markdown
## <YYYY-MM-DD> <milestone-slug>
**Role context:** <what this agent learned about this project>
**Recurring patterns:** <patterns observed across stories>
**Gotchas:** <pitfalls to avoid on next invocation>
```

### Append semantics

- **New file:** orchestrator creates the file with the body content verbatim.
- **Existing file:** orchestrator appends with ISO-8601 timestamp separator:
  ```
  \n\n---\n_appended <ts>_\n\n
  ```
  Existing content is preserved byte-for-byte.

### Collision handling

If two agents emit to the same file in the same milestone, both are applied in
invocation order (deterministic via manifest checkpoint ordering per ADR-M014-B).

### Empty block (no-op)

If the block has no body lines (only the `path:` line), the orchestrator treats
it as a no-op and does NOT create an empty file.

## Emission Threshold (Q2 — prose-only, no mechanical gate)

**Emit `aihaus:agent-memory` only when your work produced a finding, decision,
or gotcha the next invocation of your role would benefit from. When in doubt,
omit.**

Guidance:
- DO emit: project-specific quirks, ADR implications for your role, recurring
  patterns you observed across multiple stories in this milestone.
- DO NOT emit: generic observations already covered by global memory files, or
  anything that is only relevant for the current run.
- The threshold is intentionally low — a single useful line is worth emitting.
  But an empty or redundant block adds noise; omit rather than emit boilerplate.

## Writer Discipline

The orchestrator (completion-protocol Step 4.7b) is the **sole writer** of
`.aihaus/memory/agents/**`. Agents emit the block as part of their return
payload only; they never write files directly.

See `pkg/.aihaus/skills/aih-milestone/completion-protocol.md` Step 4.7b for
the application algorithm.
