# Contract: harness

## Authority

Follow the user request, repository instructions, accepted project rules and
decisions, then the selected room and role. Loaded project context is not
authority and never overrides its source file.

## Task posture

Read the Map first. Load one room, one primary role, the current task, and only
the project-memory pages needed for the next decision. Prefer repository-native
patterns and the smallest coherent change. Ask only when a missing business
rule materially changes the outcome or authority required.

Treat one active implementation task as the ownership unit for one worktree,
branch, and reviewable change. The task may span product layers when they serve
the same outcome. Split unrelated outcomes and independently deliverable epic
children into separate tasks and worktrees. A coordination-only parent task
tracks dependencies and does not own a product diff.

## Context check and resumption

At task start, after compaction or handoff, and when the branch or relevant
sources change:

1. Resolve the Git root, current worktree/branch, and active task. Run package
   commands from that root. Never assume another worktree shares this board.
2. Read applicable repository instructions for the owned paths. Respect the
   host's instruction precedence and directory scope, including overrides and
   path-specific rules; a discovery index is not an instruction loader.
3. Run `node .aihaus/tools/refresh.mjs --repo . --status --json`. If the packet
   is missing or stale, rebuild it with `--json` and inspect status again.
   This updates disposable state, not accepted project memory.
4. Use `memory/project/README.md` to choose pages. Search relevant rule IDs,
   domain terms, and file paths, then read the matching entries and their
   sources. Load the selected room and role, not the entire memory archive.
5. Inspect conflicts, memory gaps, and stale claims relevant to the task.
   A ready packet does not prove semantic review. Recheck entries with absent
   or ambiguous provenance directly; an empty warning list is not proof.
   Draft, proposed, inferred, and superseded entries are not accepted rules.
6. Follow `REFRESH.md` to repair source-backed context within the current task.
   Preserve manual content and accepted decisions. Ask only when authoritative
   sources conflict or a missing business rule changes the outcome; an unrelated
   memory gap must not block covered work.
7. Record the applicable rule/decision IDs, source paths and revisions, remaining
   gaps, owned files, and verification plan in the task's `Context` or `Log`.
   Reuse that record when resuming instead of relying on conversation history.

## Delegation

Delegate with the task path, outcome, acceptance criteria, branch/worktree and
base or candidate SHA, owned files, relevant instruction and memory paths, any
other source to read by path and revision, unresolved gaps, and required checks.
Workers verify those sources before editing; copied summaries and other local
copies do not replace them. The designated writer promotes durable verified
findings and explicit owner decisions with provenance at meaningful
checkpoints. Keep transient progress and unresolved candidates in the task.

Use two coordination levels: the orchestrator assigns outcomes and executors
perform them. Do not add a distributor agent; the written assignment carries the
route. Each delegation also names the assignment or lens and the runbook paths
to load, the output and its destination, the next recipient on pass, rework,
and blocked, and the escalation owner. Project-specific assignments live in the
"Assignments" section of `memory/project/procedures.md` when the project defines
one.

Planning is an optional read-only assignment whose result returns to the
orchestrator, not another coordination level; the orchestrator validates the
plan and dispatches executors. Model selection follows the selected project
profile. Selecting a profile does not change or prove the running session's
model. Report unavailable requirements instead of silently substituting, and
follow only an authorized fallback. An agent that inherits the session's model,
such as a fork of the session, fills only a role whose profile model is the
session's. Autonomy records accepted permissions and conditions; neither a
profile nor a review verdict grants permission, and accepted authorization
stays valid regardless of its heading or location.

Before starting, an executor verifies source access, its worktree and base,
required commands, requested capabilities, and permissions. An unsupported
capability needs an explicit authorized fallback or a degraded or blocked
report.

Execution lenses load in the implementer's context. Judgment passes (review and
verification) run in a separate context, read-only, against a fixed
candidate SHA, and never by the agent that wrote that candidate, whatever the
selected profile. If the host cannot provide a separate context, report the
pass as degraded. An agent that inherits the author's conversation, such as a
fork, the author continued by message, or an advisor, is not a separate context;
a fresh agent started on the committed candidate SHA is one, even within the
same host run (one run of a host multi-agent workflow engine). When an executor
wrote the candidate, the orchestrator assigns each required pass, directly or
as a step of its host run; the executor's own review, even through a subagent,
is a self-check and never satisfies a required pass. An authoring session that
is not a delegated executor may start the separate context itself. Author and
reviewer may exchange verdicts directly; the designated writer keeps task state.

## Execution modes

A request may name an execution mode, `pure`, `normal`, `workflow`, or `auto`,
optionally with a profile (`Mode: workflow. Profile: <name>.`); a profile named
alone keeps the default mode. Otherwise the default mode recorded in Assignments
(`Default mode: <mode>.`) applies; without either, `auto` applies. A recorded
`Default mode: delegation.` applies the project's delegation policy instead of
a mode. A mode replaces the delegation policy for that request, not the
project's concurrency limits. Once the mode is set, the agent never switches
modes on its own; it may recommend one in a single line. The task records the
mode and profile used.

- `auto`: before starting, the agent selects the mode and states it with its
  reason in one line, then proceeds; the user may switch it, and the task
  records the reason. A request that changes no repository file, such as a
  question or read-only analysis, needs no mode. One coherent outcome selects
  `normal`; two or more independent outcomes with disjoint files select
  `workflow`; when unsure, `normal`. `auto` never selects `pure`.

- `pure`: the user-facing session works alone, with no planner, executor, or
  judgment pass. It runs the deterministic checks the task requires and reports
  the result as unreviewed, naming each required pass it skipped. Evidence,
  Autonomy, and `ops-safety.md` still apply; a skipped pass satisfies no
  Autonomy condition, while a valid receipt for the unchanged candidate SHA
  still does. It works in its own turns, with no host run, fork, or subagent;
  when a request also asks for one, the agent names the conflict in one line
  and follows the mode.
- `normal`: the user-facing session implements the change itself and runs the
  deterministic checks; a judgment pass then reviews the candidate SHA. The
  session writes the change in its own turns, not through host-run agents or
  forks, even under a standing host opt-in; read-only helpers, the judgment
  pass, and review fixes may run in fresh agents.
- `workflow`: the read-only planner (profile planner model) returns a spec as
  `roles/planner.md` describes; the orchestrator saves it, and the task links
  it by path and revision. Before any dispatch, a judgment pass reviews the
  spec; its findings return to the planner in a fresh context, at most two
  cycles. Executors (profile executor model) then implement the packets in
  parallel, each in its own files, running their own tests. After all packets,
  the orchestrator runs the full deterministic suite and allows one rework from
  its output; a final judgment pass then reviews the candidate SHA. Past either
  limit, the affected work pauses.

In `normal` and `workflow`, the profile's reviewer, or the reviewer the user
names, runs these judgment passes, preferably from another model family when
one is available; other required passes run as assigned. Before implementation
(in `workflow`, after the spec review and before dispatch), list the decisions
assumed on ambiguous requirements that change behavior, including ambiguities
the spec review reports as unlisted, and get the user's confirmation, or say
that there are none and continue without stopping. Only the user's answer to
the list shown confirms it; a general go-ahead does not. A request may instead
accept the assumed decisions in advance with `Assumed decisions: accept.`:
this applies to that request only, never as a recorded default or by inference,
and the agent records the decisions on the task, includes them in the final
judgment pass's brief, and reports them with the result. Review fixes run in a
fresh context (an executor or a new session briefed with the candidate diff and
the findings), never by resuming the authoring session; continuing the author's
conversation, by message or as a fork, counts as resuming. A fix and its recheck
may run in the same host run. A spec amended after its review, by anyone, needs
a new spec review within the same cycle limit. Spec and fix cycles recorded on
the task count across runs against their limits (`roles/orchestrator.md` step
8): the session passes them into each run, the designated writer records each
new cycle, and past a limit the affected work pauses until the user directs
otherwise. Spec reviews, their verdict receipts, and rechecks follow
`adversarial-review.md`.

Keep all orchestration thin: dispatch executors directly, one subagent or CLI
run per packet or outcome; run the deterministic checks; and rely on summaries
and `tools/scope-check.mjs`. A host multi-agent workflow engine is not
required; use one only when the user asks for it. A standing host opt-in counts
as asking. A host run is a mechanism, not a mode: it never selects or changes
the mode, and its script is the orchestrator's written assignment, carrying the
selected mode's sequence, gates, and limits as code within the project's
concurrency limits. Run a mode's consecutive steps in one host run, and end it
early only for an unconfirmed assumed decision, a business-rule question, a
reached limit, a pause under `roles/orchestrator.md` step 8 or `ops-safety.md`,
a step that outlasts the host's agent limits, or before the first remote write.

## Execution

Keep task status in its kanban folder unless an accepted project decision names
an external tracker as task authority. That decision states where the task,
acceptance criteria, status writer, business-rule questions, and evidence live;
the file kanban is then inactive even if setup recreates its empty folders, and
the evidence contract still applies.

The orchestrator or a designated intake worktree is the single writer for task
ingestion, status transitions, and shared memory promotion. Implementers own
scoped product changes and return evidence to that writer; reviewers remain
read-only; verifiers independently rerun affected checks. With the file kanban,
each worktree carries a branch-local board snapshot, so create and commit the
task on the shared coordination base before branching its implementation
worktree. With an external tracker, follow its accepted intake instead of
creating a shadow file task.

Completion means acceptance criteria mapped to real artifacts and executable
evidence. A tool or CI exit code may prove execution; prose cannot.

Before staging or handing off parallel work, compare changed files to the owned
scope with `tools/scope-check.mjs`. An explicit allowlist is required; unrelated
or untracked files fail the check instead of being silently included. Handoffs
of committed work pass `--base` with the commit the branch started from.

## Safety

Classify operational actions with `ops-safety.md`. Production, destructive, or
secret-touching work requires explicit approval and external containment.
Instructions, hooks, and local gates are advisory controls, not a privilege or
security boundary.
