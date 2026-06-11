# aihaus Parallelism — worktree isolation + Owned-Files sharding

How aihaus runs multiple file-writing agents in parallel **without conflicts**.
Grounded in Claude Code's native worktree model + aihaus's merge-back stack.
Binding rule: **ADR-260529-A**.

## The hard constraint (do not design around it)

**Two agents can never edit the same file in parallel.** Claude Code's
worktree-branch-from escape is non-viable (issues #27749, #50850 — "not-planned").
Parallelism therefore comes **only from sharding into disjoint Owned-Files sets**
plus **sequential merge-back** — never two writers on one file.

## Isolation is a conditional default (by cohort)

A file-writing subagent runs in its own git worktree (`isolation: worktree` +
`permissionMode: bypassPermissions`) when the flow profile calls for it:

| Cohort | Isolate? | Rule |
|---|---|---|
| stateful 5 — `implementer`, `frontend-dev`, `code-fixer`, `executor`, `nyquist-auditor` | **always** | they mutate code; isolation already declared in frontmatter |
| `:doer` (other forward-edit agents) | **conditional** | isolate when the flow runs ≥2 writers with disjoint Owned-Files; a single sequential writer need not |
| `:verifier`, `:planner*`, `:adversarial` | **never** | read-only assessment — no writes, no worktree cost |

The runner records the isolation decision in the run's manifest/kanban Metadata so
resume + statusLine see it.

## Owned-Files sharding (the parallelism unit)

- Every story/task declares its **Owned Files**; the planner blocks overlaps before
  execution (same-file cross-story rule, ADR-M017-C).
- One story = one agent = one cohesive, disjoint file set → maximal safe parallelism.
- `merge-back.sh` enforces per-file Owned-Files with refuse-on-spill (exit 3); a
  single unexpected file aborts the merge. Recovery: `aih-milestone/annexes/merge-back-recovery.md`.

## Sequential merge-back + single-writer DB

Worktree agents work in parallel, but **merge-back is sequential** and the
operational DB (`.aihaus/state/kanban.db`) follows **single-writer discipline**
(ADR-004): each stage's lead writes its `gate_events` row + projection as its
merge-back completes — never parallel DB writers. That is the concurrency answer for
the shared kanban DB under parallel worktree agents.

## Budget

≤ ~5 worktrees per run is the safe default (native cap is 16 concurrent agents,
CPU-bound; ~500 ms `git worktree add` each). Native dynamic workflows
([fan-out.md](fan-out.md)) can orchestrate the fan-out — each agent gets its own
worktree, merge-back runs sequentially after.

## Teams (enabled, not active)

Claude Code **agent teams** are user-NL-gated — a skill **cannot** spawn a team
programmatically (ADR-260518-A). `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` ships
enabled for the user-driven path; aihaus parallelism uses **subagents + worktrees +
dynamic workflows**, not auto-spawned teams.
