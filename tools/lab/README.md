# Local aihaus lab

The generated lab lives at ignored `.aihaus-lab/consumer`. It is a persistent
nested Git repository with two local baseline tags. Only this controller,
fixture, and the acceptance tests are committed by the outer repository.

```text
node tools/aihaus-lab.mjs init
node tools/aihaus-lab.mjs status
node tools/aihaus-lab.mjs reset
node tools/aihaus-lab.mjs verify
```

`init --force` and `reset` are destructive only after realpath containment and
nested-repository identity checks pass. The fixture contains no credentials,
deploy configuration, or external-service dependency.

## Context retrieval probes

Node contracts exercise files and tools. To evaluate instruction-following, use
an isolated consumer under `.aihaus-lab/` and a fresh agent session with only the
task path and request. Record the host/model, sources actually read, actions,
and remaining gaps. Repeat on each native host before claiming host coverage.

- **Changed rule:** cite a committed rule in memory, then change its authoritative
  source in a newer commit. The agent must detect the stale claim, read the new
  source, and distinguish the current rule from its history.
- **Decision authority:** include accepted and proposed decisions plus a scoped
  instruction file. The agent must preserve their status/scope and surface a
  real business conflict instead of silently promoting the proposal.
- **Resumption:** reopen a review task in a fresh session with unchecked
  acceptance and blocked evidence. The agent must recover references from files,
  identify missing verification, and leave the task incomplete.

A read-only probe must not rebuild state or edit memory. Passing these examples
is evidence about those runs, not a guarantee of semantic correctness for all
tasks or models.
