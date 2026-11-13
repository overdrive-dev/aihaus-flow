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

## Host A/B sessions

Compare two package versions by running the same request in a fresh headless
session per version. Write the cells and pass criteria to
`.aihaus-lab/<name>/PLAN.md` before the candidate exists, and record any later
change to them in that file.

One consumer per arm, each installed from the checkout under test:

```text
AIHAUS_LAB_ROOT=.aihaus-lab/<name>/<arm> node <checkout>/tools/aihaus-lab.mjs init
```

Claude Code session, at most two at once (four ran out of memory):

```text
claude -p "<prompt>" --model opus --effort <level> --strict-mcp-config
  --tools <tools> --allowedTools <commands> --permission-mode acceptEdits
  --max-budget-usd 15 --output-format stream-json --verbose
```

- Set `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0`, or background workflows stop
  10 minutes after the last turn.
- Isolation, pick one:
  - `--restricted` loads no instruction file or user plugin, so the prompt must
    say to read `AGENTS.md`.
  - `--setting-sources project,local` plus a `--settings` file whose
    `claudeMdExcludes` lists this repository's `AGENTS.md` tests native loading
    without user plugins.
- `claude`, `codex`, and `gh` resolve only in PowerShell on the maintainer
  machine, not in Bash.
- Keep the prompt on one line. `claude` resolves to a `.cmd` shim that cuts the
  command line at the first newline and drops every flag after it.
- `pwsh -File` does not parse array arguments; pass lists as one
  comma-separated string.

Codex session, for a delegated executor:

```text
codex exec --json -m <model> -c 'model_reasoning_effort="xhigh"'
  -s danger-full-access --skip-git-repo-check -C <consumer> "<prompt>"
```

It reads the consumer's `AGENTS.md` and keeps the user's Codex plugins loaded;
multi-line prompts work.

What a headless session does on its own:

- A covered, low-risk mechanical edit takes the quick path and leaves one log
  record.
- A missing business rule stops the session with a question.
- A delegated agent needs a brief with the task, criteria, base, owned files,
  and files to read; without the Agent tool a session cannot run a review.

Measure tool calls or commands, cost or tokens, and seconds from the session
log, and check the outcome with hidden tests the agent never sees. Characters
read are a weak signal: in the v1.17.0 labs, two changes cut what agents read
by 17% and 60% without lowering their calls, cost, or time.
