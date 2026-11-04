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

## Working style

The agent chooses how to carry out each request: alone, with a planner and
executors, in parallel, or through a host multi-agent workflow engine when the
host enables one. It stays within the request, the selected room, Assignments
(routes, profiles, a recorded delegation policy, and concurrency limits),
Autonomy, `ops-safety.md`, and these rules. The task records who implemented,
who reviewed, and the profile used.

- Judgment passes. A behavior change gets a judgment pass on its candidate SHA
  before completion or integration; a covered, low-risk mechanical edit on the
  feature room's quick path needs none. The profile's reviewer, or the reviewer
  the user names, runs it, preferably from another model family when one is
  available. Only the user's request skips a required pass: the agent reports
  the result as unreviewed and names each skipped pass, and a skipped pass
  satisfies no Autonomy condition, while a valid receipt for the unchanged
  candidate SHA still does.
- Assumed decisions. A requirement resolved silently passes its own tests, and
  a spec spreads that choice to every executor, so assumed decisions are
  written down; they are not a stop. Record on the task each decision assumed
  on an ambiguous requirement that changes behavior users or callers can
  observe, including ambiguities a spec review reports as unlisted, and
  continue. Technical mechanics follow `conventions.md` and are not listed.
  Every judgment pass's brief includes the list, the reviewer checks each
  decision against the request, and the result reports the list so the user
  can overturn any decision. Ambiguity that no reasonable reading resolves, or
  that needs owner authority, is a business-rule question instead.
- Specs that drive executors. A read-only planner (profile planner model)
  returns the spec as `roles/planner.md` describes; the orchestrator saves it,
  and the task links it by path and revision. Before any dispatch, a judgment
  pass reviews the spec; its findings return to the planner in a fresh context,
  at most two cycles. Executors (profile executor model) implement the packets
  in parallel, each in its own files, running their own tests. After all
  packets, the orchestrator runs the full deterministic suite and allows one
  rework from its output; a final judgment pass then reviews the candidate SHA.
  Past either limit, the affected work pauses.
- Review fixes run in a fresh context (an executor or a new session briefed with
  the candidate diff and the findings), never by resuming the authoring session;
  continuing the author's conversation, by message or as a fork, counts as
  resuming. A fix and its recheck may run in the same host run. A spec amended
  after its review, by anyone, needs a new spec review within the same cycle
  limit. Spec and fix cycles recorded on the task count across runs against
  their limits (`roles/orchestrator.md` step 8): the session passes them into
  each run, the designated writer records each new cycle, and past a limit the
  affected work pauses until the user directs otherwise. Spec reviews, their
  verdict receipts, and rechecks follow `adversarial-review.md`.
- End to end. A task runs to completion and stops only for a business-rule
  question, a reached limit, a pause under `roles/orchestrator.md` step 8 or
  `ops-safety.md`, a step that outlasts the host's agent limits, or before the
  first remote write without authorization.

Keep orchestration thin: dispatch executors directly, one subagent, CLI run, or
host workflow agent per packet or outcome; run the deterministic checks; and
rely on summaries and `tools/scope-check.mjs`.

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
