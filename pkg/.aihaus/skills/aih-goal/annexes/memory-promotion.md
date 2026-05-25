# aih-goal memory promotion

`/aih-goal` run artifacts are not durable memory by themselves. At finish, and
before any long pause caused by true blockers, promote reusable findings into
the repository memory surfaces that future runs read.

### Inputs

Read the current goal run directory:

- `GOAL.md`
- `TASKS.md`
- `RUN-MANIFEST.md`
- `tasks/*.md`
- `evidence/**` indexes or summaries
- returned agent payloads, including optional `aihaus:agent-memory` blocks

Also read existing durable memory before writing:

- `.aihaus/project.md`
- `.aihaus/decisions.md`
- `.aihaus/knowledge.md`
- `.aihaus/memory/workflows/*.md`
- `.aihaus/memory/agents/*.md`

Do not write to Claude internal memory paths such as
`~/.claude/projects/**/memory`. They are outside the repository boundary and are
blocked by `file-guard.sh`. If a tool or agent suggests that path, mirror the
durable fact into `.aihaus/memory/**` through this promotion phase instead.

### Durable outputs

Promote only reusable signal. Do not copy transient run logs.

- Architectural or product decisions -> `.aihaus/decisions.md`
- Reusable technical findings -> `.aihaus/knowledge.md`
- Workflow/source-system preferences -> `.aihaus/memory/workflows/*.md`
- Agent-role-specific lessons -> `.aihaus/memory/agents/<agent-name>.md`
- Project context recency -> `.aihaus/project.md` recent decisions/knowledge
  markers when those markers exist

### Required review record

Every run must leave a `### Memory Promotion` section in `RUN-MANIFEST.md` with
one of these outcomes:

- `promoted`: list target files and source evidence lines,
- `no-signal`: explain why nothing was durable,
- `deferred`: list the blocker and create pending `memory_events` rows.

### Curator path

When `knowledge-curator` is available, spawn it in goal-run mode with the run
directory and ask for its standard marker-fenced blocks. The orchestrator, not
the agent, applies those blocks.

If the curator is unavailable, the orchestrator still performs the same review
directly and records the reason in `RUN-MANIFEST.md`.

### Per-agent memory blocks

For every returned `aihaus:agent-memory` block:

1. Parse between `<!-- aihaus:agent-memory -->` and
   `<!-- aihaus:agent-memory:end -->`.
2. Verify the first body line is `path: .aihaus/memory/agents/<agent-name>.md`.
3. Verify `<agent-name>` is hyphen-only.
4. Create the target file if missing, or append with an ISO-8601 separator.
5. Record a `memory_events` row and audit entry when `.claude/audit/` exists.

Empty blocks are no-ops. Agents never write memory files directly.

Reject or defer any `aihaus:agent-memory` block whose `path:` targets
`.aihaus/memory/workflows/**`, `.aihaus/memory/global/**`,
`.aihaus/memory/frontend/**`, `.aihaus/memory/backend/**`,
`.aihaus/memory/reviews/**`, `~/.claude/**`, or an absolute path. Those are not
per-agent memory blocks.

### Project context refresh

After appending to `decisions.md`, `knowledge.md`, or workflow memory:

- refresh `project.md` recent decisions/knowledge marker blocks when present,
- never rewrite manual user content outside aihaus-owned markers,
- if markers are missing, append a `memory_events` row with status `deferred`
  instead of editing arbitrary prose.
