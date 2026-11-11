# aihaus

aihaus gives coding agents a shared, repository-local way to understand a
project, plan work, preserve decisions, and prove that a task is complete. It
installs as ordinary files in your Git repository, so the workflow travels with
the code and remains reviewable by your team.

Use aihaus when you want an agent to:

- follow project rules and prior decisions instead of starting from scratch;
- route feature, bug-fix, and research work through a consistent workflow;
- hand security, QA, or release work to independent agents with a defined
  next step;
- keep durable project memory in versioned Markdown;
- support completion claims with executable evidence;
- make the smallest complete change, reusing what already exists, with
  Ponytail's rules built in;
- work without sending project memory to an aihaus service.

There is no aihaus account, website, hosted control plane, or cloud memory.
The portable workflow is a repository-local package. Thin repository-local
Claude Code and Codex skills expose its initialization routine without turning
aihaus into a global runtime, plugin, or user-level installation.

## Requirements

- a Git repository;
- Git available on the command line;
- Node.js 22 or newer with npm;
- a released aihaus tag for a reproducible installation;
- for Claude Code, v2.1.281 or newer, which reads `AGENTS.md` without a
  `CLAUDE.md`.

Run installation commands from the root of the repository that will use
aihaus.

## Repository-local commands by host

This README documents the provider-neutral repository-local package.

| Host | Repository-local adapter | Initialization |
|---|---|---|
| Claude Code | `.claude/skills/aih-refresh/SKILL.md` | `/aih-refresh` |
| Codex | `.agents/skills/aih-refresh/SKILL.md` | `$aih-refresh`, or discover it through `/skills` |
| Grok or another coding agent | No host adapter required | `node .aihaus/tools/refresh.mjs --repo . --json` |

The exact custom slash form `/aih-refresh` is a Claude Code capability; Codex does
not expose repository skills through that spelling. The old global `/aih-env`
and multi-command Claude suite are not installed. aihaus does not add global
hooks or change user settings. Older documentation paths such as
`.aihaus/project.md` do not apply to this package. Its canonical project memory
is under `.aihaus/memory/project/`.

The repository-local host adapters are included starting with release `v1.2.0`.

## Set up with a coding agent

This is the recommended customer path. Choose a tag from
[GitHub Releases](https://github.com/overdrive-dev/aihaus-flow/releases), replace
`<release-tag>` below, and paste the prompt into your coding agent:

```text
Install aihaus release <release-tag> in this repository.

aihaus is a repository-local package with thin repository-local host adapters,
not a global skill, Claude runtime, plugin, or user-level installation. Do not
use skill-installer, change user-level agent settings, install global hooks, or
clone the source repository.

Follow the version-pinned installation contract at:
https://raw.githubusercontent.com/overdrive-dev/aihaus-flow/<release-tag>/INSTALL-VIA-LLM.md

Run the versioned GitHub Release package with npm exec and the `aihaus init`
command. Require source.distribution to be github-release and require
source.pinned and verification.ok to be true. Report the installed version,
package-owned changes, preserved content, adapters, hostCapabilities,
conflicts, warnings, and readiness.

Then run node .aihaus/tools/refresh.mjs --repo . --json. Read .aihaus/REFRESH.md and
.aihaus/contracts/project-bootstrap.md. Synthesize the discovered evidence into
.aihaus/memory/project/ only when readyForSynthesis is true. Otherwise preserve
the memory templates and report the blocker. Preserve existing content and
finish with node .aihaus/tools/refresh.mjs --repo . --status --json.
```

The full agent contract is also available in
[INSTALL-VIA-LLM.md](INSTALL-VIA-LLM.md). Always use the copy from the release
tag you are installing, not the copy from `main`.

## Set up from a GitHub Release

Current published release (`v1.16.0`):

```bash
npm exec --yes --package=https://github.com/overdrive-dev/aihaus-flow/releases/download/v1.16.0/aihaus-flow-v1.16.0.tgz -- aihaus init --target . --json
```

For another release, replace both occurrences of `v1.16.0` with the same tag.

This is the go-to command for both the first setup and later updates. npm keeps
the executable package in its cache; aihaus itself is installed as ordinary
repository-local files. The command does not add aihaus to the consumer's
`package.json`, create a visible source clone, or require a cleanup command.

## Confirm the installation

The setup JSON is the installation report. Starting with `v1.2.0`, it should
show the portable bootstrap, host capabilities, and collision status:

```json
{
  "ok": true,
  "scope": "repository-local",
  "mode": "apply",
  "forced": false,
  "changesRequired": true,
  "source": {
    "distribution": "github-release",
    "pinned": true,
    "ref": "<release-tag>"
  },
  "verification": {
    "ok": true
  },
  "bootstrap": {
    "command": "node .aihaus/tools/refresh.mjs --repo . --json",
    "instruction": ".aihaus/REFRESH.md"
  },
  "created": [],
  "refreshed": [],
  "unchanged": [],
  "hostCapabilities": {
    "claudeCode": {
      "available": true,
      "invoke": "/aih-refresh"
    },
    "codex": {
      "available": true,
      "invoke": "$aih-refresh",
      "customSlash": false
    }
  },
  "conflicts": [],
  "cleanup": {
    "path": null,
    "pending": false
  }
}
```

`cleanup.pending: false` confirms that the GitHub Release setup did not leave a
repository-local download directory behind.

Starting with `v1.4.0` (which renamed `INIT.md`/`init.mjs` from `v1.2.0`), the
installed entry points are:

- .aihaus/REFRESH.md;
- .aihaus/tools/refresh.mjs;
- .aihaus/contracts/project-bootstrap.md;
- `.claude/skills/aih-refresh/SKILL.md`;
- `.agents/skills/aih-refresh/SKILL.md`;
- `.aihaus/VERSION`;
- `.aihaus/MAP.md`;
- `.aihaus/contracts/harness.md`;
- `.aihaus/roles/orchestrator.md`;
- `.aihaus/rooms/feature/CONTEXT.md`.

## What setup changes

| Path | Purpose | Ownership on update |
|---|---|---|
| .aihaus/REFRESH.md | Provider-neutral memory synthesis routine | Package-owned; refreshed only when different or with `--force` |
| `.aihaus/MAP.md`, `conventions.md`, `rooms/`, `roles/`, `contracts/`, `tools/` | Portable aihaus workflow | Package-owned; refreshed only when different or with `--force` |
| `.aihaus/THIRD-PARTY-NOTICES.md` | Third-party attribution and license notices | Package-owned; refreshed only when different or with `--force` |
| `.aihaus/VERSION` | Installed package version | Package-owned; refreshed only when different or with `--force` |
| `.aihaus/memory/project/` | Project rules, decisions, knowledge, and procedures | Project-owned and preserved |
| `.aihaus/memory/kanban/` | File-based task history | Project-owned and preserved |
| `AGENTS.md` | Shared router that Codex and Claude Code both read | Only the bounded aihaus block is managed |
| `CLAUDE.md` | Only when the repository also has a `CLAUDE.md` with your own text, a `.claude/CLAUDE.md`, or a `CLAUDE.local.md`: Claude then reads those instead of `AGENTS.md`, so an `@AGENTS.md` import is added | Only the bounded aihaus block is managed; a `CLAUDE.md` holding only that block is removed when no longer needed |
| `.claude/skills/aih-refresh/SKILL.md`, `.agents/skills/aih-refresh/SKILL.md` | Thin host-native wrappers around the portable bootstrap | Refreshed only when the aihaus ownership marker is present; otherwise preserved and reported as a conflict |
| `.gitignore` | Ignores local aihaus state and temporary download | Only the bounded aihaus block is managed |

Text outside `AIHAUS:START` / `AIHAUS:END` blocks is preserved. Setup rejects malformed or repeated
markers and preflights known file/directory conflicts before applying changes.
A nonempty root `AGENTS.override.md` is preserved and reported in
`instructionWarnings`: Codex can load that file instead of `AGENTS.md` even when
its refresh skill is available.

## Initialize project memory

Setup installs preserved templates but does not guess project meaning. Run the
deterministic offline discovery command:

    node .aihaus/tools/refresh.mjs --repo . --json

It writes only the ignored packet
.aihaus/state/bootstrap/discovery.json. The packet contains source paths,
hashes, Git/worktree provenance, safe manifest and layout facts, exclusions,
conflicts, and a source plan for all eight canonical memory files. It does not
read excluded secret-bearing paths, access the network, upload data, run
services, or deploy.

The JSON includes `readyForSynthesis`, `evidenceLevel`, and `memoryReadiness`.
When `readyForSynthesis` is false, keep the templates unchanged and add an
authoritative project source such as a README, manifest, project brief, or
application code before trying again — or let the agent interview you and
record your answers in a root PROJECT-BRIEF.md, which becomes that
authoritative source. This prevents a fresh repository from being marked
initialized with invented or unresolved-only memory.

The status mode additionally reports two advisory signals: `memoryGaps`
(missing, template, or incomplete pages with candidate sources) and
`staleClaims` (cited sources changed/missing or review provenance absent or
ambiguous). Provenance belongs to each claim: a newer review on the same page
does not revalidate older claims. Dirty or untracked sources use their discovery
hash instead of a commit that does not contain those bytes. These are read-only
hints; discovery never rewrites memory. Readiness checks content and provenance
structure, not semantic truth or owner approval.

When `readyForSynthesis` is true, ask the active coding agent to follow
.aihaus/REFRESH.md and .aihaus/contracts/project-bootstrap.md. The agent reviews
candidate sources and updates .aihaus/memory/project/ without replacing
existing content or turning inferences into accepted rules. This semantic phase
is deliberately provider-neutral and reviewable instead of being hidden inside
deterministic code.

Host-native shortcuts call the same routine:

- Claude Code: `/aih-refresh` (restart the session if a newly installed skill is
  not yet visible);
- Codex: `$aih-refresh`, or select it through `/skills`;
- every host: `node .aihaus/tools/refresh.mjs --repo . --json`.

Preview without writing:

    node .aihaus/tools/refresh.mjs --repo . --dry-run --json

Check whether the discovery packet matches current inputs:

    node .aihaus/tools/refresh.mjs --repo . --status --json

Copy-paste prompt:

~~~text
Read .aihaus/MAP.md, .aihaus/contracts/harness.md,
.aihaus/contracts/project-bootstrap.md, and .aihaus/REFRESH.md. Run the local
bootstrap discovery command. Populate .aihaus/memory/project/ only if
readyForSynthesis is true, using verified repository evidence. Otherwise
preserve the templates and report the blocker. Preserve existing content, cite
source paths and the reviewed commit (or worktree/untracked discovery hash) on
each claim, keep inferences and conflicts explicit,
and do not read or record secrets. Do not use global aihaus state, network
access, or hosted state.
~~~

## Start using aihaus

After installation, use your coding agent normally from the repository. The
root adapter directs it to `.aihaus/MAP.md`, which selects only the workflow and
project memory needed for the request.

Before substantive work and after a handoff or context reset, the harness asks
the agent to check refresh status, retrieve relevant rules and decisions, and
verify their sources. Task Context/Log preserves the selected references, scope,
gaps, and required checks for resumption. The designated writer maintains
verified context during authorized work; a conflicting business rule needs an
owner decision. Unrelated memory gaps do not block covered work.

Example requests:

```text
Implement customer invoice export and prove each acceptance criterion.
```

```text
Diagnose why password reset emails are sent twice. Do not change code yet.
```

```text
Research the safest migration path for the users table and record the decision.
```

No special aihaus command is required for ordinary agent work.

### Lean code changes, with Ponytail's rules built in

Since v1.12.0, aihaus carries the core rules of
[Ponytail](https://github.com/DietrichGebert/ponytail) (MIT), so you do not
need to install the Ponytail plugin or skill to get them. The rules live in
`.aihaus/conventions.md`, which the Map tells every agent to load whenever
files may change. They apply on every host, including delegated executors.

- **Change ladder.** Take the first option that fully works:
  1. skip what nobody asked for, and say what was skipped;
  2. reuse what the repository already has;
  3. use the standard library or platform;
  4. use an installed dependency, never a new one for a few lines;
  5. otherwise, write the least new code that stays readable.
- **Still complete.** A change still covers every caller, test, fixture, and
  export it touches. It never cuts validation at trust boundaries, error
  handling that prevents data loss, security, accessibility, hardware
  calibration, or anything requested. The aihaus test and evidence rules still
  apply.
- **`shortcut:` comments.** A shortcut with a known limit carries
  `shortcut: <the limit>, <when to upgrade>`.
- **Review.** The complexity lens in `.aihaus/contracts/adversarial-review.md`
  looks for code that need not exist. A `shortcut:` that names its limit is a
  decision, not a finding, unless the expected load crosses that limit.
- **Reports.** Implementers name what they skipped or left unchecked.

The rules reach an agent through the aihaus router, not through a hook, so they
depend on the agent following the Map. aihaus does not install Ponytail and does
not ship these Ponytail features:

- the six skills: `/ponytail` with its `lite`, `full`, and `ultra` levels,
  `/ponytail-review`, `/ponytail-audit`, `/ponytail-debt`, `/ponytail-gain`, and
  `/ponytail-help`. They install on their own with
  `npx skills add DietrichGebert/ponytail` or come with the plugin;
- the reply style that ends every message with what was skipped and the risk;
- plugin integrations, where the host supports them: lifecycle hooks that load
  the rules at session start, after compaction, and into subagents; a persistent
  level; and, in Claude Code, the status band.

Install the skills or the plugin only if you want those features.
It does not conflict with
aihaus, and where the two differ, the aihaus test, evidence, and review
contracts decide. `/ponytail-review` can serve as a review lens, but it does not
produce the verdict receipt that `.aihaus/contracts/adversarial-review.md`
requires. Ponytail's MIT notice is in the installed
`.aihaus/THIRD-PARTY-NOTICES.md`.

To keep a different rule for a project, state it in your repository
instructions or in an accepted project rule. Both rank above package guidance.

### Delegate to specialist agents

aihaus keeps six general roles and two coordination levels: an orchestrator
assigns outcomes and executors perform them, with no distributor agent in
between. An optional planner returns its plan to the orchestrator, which still
dispatches every executor. Delegation settings live in
`.aihaus/memory/project/procedures.md`, which upgrades never overwrite. The
examples below are illustrative; they become rules only when you accept them in
that file.

To route recurring specialist work such as security review, QA, or release
promotion, add an `Assignments` section:

| Assignment | Role | Load | Trigger | Context | Output | Next on pass / rework / blocked | Escalation |
|---|---|---|---|---|---|---|---|
| security | reviewer | `contracts/adversarial-review.md` plus project security notes | `payments/**`, `auth/**` | separate, read-only, candidate SHA | verdict receipt | qa / author / orchestrator | owner |
| qa | verifier | `contracts/evidence.md` | every task | separate, read-only, candidate SHA | evidence JSON | orchestrator / author / orchestrator | owner |

In the same section, name profiles for the hosts and models you use. A profile
may use one provider or several:

| Profile | Role | Host / provider | Model | Effort | Invoked as |
|---|---|---|---|---|---|
| `claude` | orchestrator | Claude Code / Anthropic | `fable` | xhigh | the session you talk to |
| `claude` | planner (optional) | Claude Code / Anthropic | `opus` | xhigh | read-only subagent |
| `claude` | executors | Claude Code / Anthropic | `haiku` | max | one subagent per packet or outcome |
| `claude` | reviewer | Claude Code / Anthropic | `opus` | xhigh | subagent in a fresh context |
| `openai` | orchestrator | Codex / OpenAI | `gpt-6-astra` | xhigh | the session you talk to |
| `openai` | planner (optional), reviewer | Codex / OpenAI | `gpt-6-astra` | xhigh | `codex exec ... -s read-only` |
| `openai` | executors | Codex / OpenAI | `gpt-6.1-sol` | xhigh | one `codex exec` run per packet or outcome |
| `mixed` | orchestrator | Claude Code / Anthropic | `fable` | xhigh | the session you talk to |
| `mixed` | planner (optional), reviewer | Codex / OpenAI | `gpt-6-astra` | xhigh | `codex exec ... -s read-only` |
| `mixed` | executors | Claude Code / Anthropic | `haiku` | max | one subagent per packet or outcome |
| `luna` | orchestrator | Claude Code / Anthropic | `opus` | xhigh | the session you talk to |
| `luna` | planner | Claude Code / Anthropic | `opus` | xhigh | read-only subagent that returns the spec |
| `luna` | reviewer | Codex / OpenAI | `gpt-6.1-sol` | xhigh | `codex exec ... -s read-only` |
| `luna` | executors | Codex / OpenAI | `gpt-6-luna` | max | one `codex exec` run per packet |

Executors must be able to run the project's tests. On Windows, the Codex
unelevated sandbox blocks child processes (`node --test` fails with
`spawn EPERM`); run each Codex executor in an isolated worktree with
`-s danger-full-access`, or use the elevated sandbox. An agent that hosts a CLI
executor or reviewer waits for the process to exit, reads the exit code from a
file the process itself writes, and returns it with the result; a call that
was stopped or timed out yields no verdict, never an earlier round's findings.
A hosting agent's shell calls have a time limit, so it polls in bounded calls;
when a step can outlast the hosting agent, run it from the session's background
shell and start the next run from its recorded result. On Windows, a
workspace-write Codex executor cannot commit in a linked worktree (`index.lock`
is denied), so the hosting agent commits the packet.

A profile may also record triggers for when the planner runs and when
executors move to a stronger model. These triggers apply whenever the work uses
a planner or executors. In the example below, executors upgrade on the listed
triggers, and the planner also runs for large or unfamiliar scope under
orchestrator step 3. If an upgraded model is unavailable, the fallback rule below applies; the profile
model counts only when recorded as a fallback:

```text
Upgrades (claude): also run the planner for more than one outcome, an
unresolved business rule, auth, payments, or migrations. Executors move from
haiku to sonnet (max) for auth, payments, migrations, or a rule over open
inputs (filter, classifier, parser).
```

Then set the default for the session you talk to:

```text
Main session: orchestrator. Default profile: claude.
Limits: up to 4 executors; tests run one at a time.
```

With these defaults no kickoff prompt is needed: you talk in natural language.
The agent chooses how to carry out each request: alone, with a planner and
executors, in parallel, or through your host's multi-agent workflow when you
turn one on (Working style in the harness). Whatever it chooses:

- A behavior change gets a review in a separate context, by the profile's
  reviewer or one you name, preferably from another model family when one is
  available. A covered, low-risk mechanical edit needs none. Only you can skip
  a review, by asking in the request; the result is then reported as
  unreviewed.
- The agent does not stop to confirm its assumptions. It records each decision
  it assumed on an ambiguous requirement that changes what users or callers can
  observe, the reviewer checks them against your request, and the result lists
  them so you can overturn any. It still asks when a missing business rule
  would materially change the outcome.
- When a planner's spec drives parallel executors, the spec is reviewed before
  dispatch, the full suite runs after the packets, and the candidate gets a
  final review.
- Review fixes run in a fresh context, not in the session that wrote the code,
  and rechecks follow `adversarial-review.md`.
- The task runs end to end. It stops only for a business-rule question, a
  reached limit, a safety pause, or before the first remote write without
  authorization.

The session integrates within Autonomy unless you direct otherwise. Without
Assignments, the agent selects one room and one primary role per task. Selecting a profile does not switch the running session's
model; the agent reports unavailable requirements instead of silently
substituting. For each profile, record allowed fallbacks by role, or `none`.
If a requirement is unavailable, the agent uses only a recorded fallback and
reports the actual model/settings; otherwise it pauses the affected assignment.

A recorded `Delegation:` policy in Assignments, such as everything except
trivial requests, still applies. To steer one request, say so in plain words.
Example requests:

```text
Fix the typo in the install section. No review.
```

```text
Add CSV export to the invoice list and prove each criterion.
```

```text
Profile: luna. Fix the findings listed in docs/audit.md, in parallel.
```

Use a moving alias when the host supports one, or an exact model ID when
reproducibility matters. Record the requested alias/ID and the resolved
model/settings when exposed by the host; otherwise record that resolution was
unavailable.

Record what the orchestrator may do alone in an `Autonomy` section:

```markdown
## Autonomy

- May: push, open a change request, and squash-merge to the integration branch
  after green required checks and a `ship` verdict.
- Needs the owner: tags and releases, deploys, production actions.
```

List conditions with each permission; where merging deploys, for example,
merge only while no long-running job is active.

Neither a profile nor a review verdict grants permission. Without applicable
authorization from you or an accepted project rule, the orchestrator stops
before the first remote write and reports the integration-ready result.

Reviews and verification run in a separate context against a fixed commit and
record a verdict receipt; a recheck never approves unrelated changes. On a host
that does not reload instructions after compaction or a handoff, resume with:

```text
Resume <task> with its recorded profile; reload aihaus context and reconcile integrated work before acting.
```

Host-specific multi-agent options, such as Claude Code's ultracode, stay in
host configuration; the agent decides how to use them, and the rules above
still apply. Messaging and process watching use your host tool. A fork inherits
the session's conversation and model, so it never reviews or fixes review
findings.

## Update aihaus

Use the same `aihaus init` command with the newer release tag. Setup compares
the released package with the installed package and writes only missing or
different package-owned surfaces. Repeating the same release with unchanged
files is a no-op: `changesRequired` is false, `created` and `refreshed` are
empty, and package paths are listed in `unchanged`.

Preview an install or update without writing:

```bash
npm exec --yes --package=https://github.com/overdrive-dev/aihaus-flow/releases/download/<release-tag>/aihaus-flow-<release-tag>.tgz -- aihaus init --target . --check --json
```

Apply only required changes:

```bash
npm exec --yes --package=https://github.com/overdrive-dev/aihaus-flow/releases/download/<release-tag>/aihaus-flow-<release-tag>.tgz -- aihaus init --target . --json
```

Repair every package-owned surface even when it already matches:

```bash
npm exec --yes --package=https://github.com/overdrive-dev/aihaus-flow/releases/download/<release-tag>/aihaus-flow-<release-tag>.tgz -- aihaus init --target . --force --json
```

`--check` reports `wouldCreate`, `wouldCreateDirectories`, `wouldRefresh`, `wouldSeed`, and
`wouldRemove` and never writes adapters, state, memory, or package files.
`--force` still preserves
project memory, text outside managed root blocks, and user-owned host-skill
collisions. The two flags cannot be combined.

Normal and forced setup seed any missing memory page, never overwrite existing
project memory, and preserve text outside managed root blocks.
Host skill files are refreshed only when they contain the aihaus ownership
marker. A pre-existing user-owned skill at the same path is preserved and
listed in `conflicts` instead of being overwritten; that host capability then
reports `available: false` until the collision is reconciled.
Review `changesRequired`, `created`, `createdDirectories`, `refreshed`, `unchanged`, `seeded`,
`preserved`, `removed`, `wouldRemove`, `adapters`, `hostCapabilities`,
`conflicts`, and `instructionWarnings` before committing. Verification includes
required kanban/state directories. Starting with v1.3.0, setup removes known
repository-local artifacts from the retired graph runtime. Markdown project
memory and file-kanban tasks are never part of that cleanup.

Customized installations (local edits under `.aihaus/`, in managed AIHAUS
blocks, or in marked host skills) follow the runbook in
[INSTALL-VIA-LLM.md](INSTALL-VIA-LLM.md). Move local routes and runbooks into
project memory (`.aihaus/memory/project/`) before updating, because package-owned
files are replaced. Any update removes `.aihaus/INIT.md` when it exists, even if
customized; `--check` lists it in `wouldRemove`, so copy it first. When an
accepted project decision names an external tracker as task authority, the file
kanban is inactive even though setup still creates its empty folders.

## Install from source

Use this fallback when developing aihaus or evaluating an unreleased commit:

```bash
git clone --depth 1 https://github.com/overdrive-dev/aihaus-flow .aihaus-download
node .aihaus-download/pkg/setup.mjs --target . --json
rm -rf .aihaus-download
```

PowerShell cleanup:

```powershell
Remove-Item -LiteralPath .aihaus-download -Recurse -Force
```

A source checkout without the matching release tag reports
`source.pinned: false`. Do not describe it as a released installation. The
GitHub Release command remains the recommended customer path.

## Evidence and safety

aihaus expects executable completion criteria to be supported by tool- or
CI-produced evidence with exit code 0. Evidence documents can be checked with:

```bash
node .aihaus/tools/evidence-validate.mjs path/to/evidence.json
```

Small, covered, low-risk mechanical edits use the feature room's quick path:
one kanban log record via `task.mjs log`, instead of acceptance criteria and an
evidence document. The record and result list checks with exit codes; an
accepted project rule can require a full task for every change.

Moving a task to `done` requires checked, unique acceptance criteria, answered
business-rule questions, and an `Artifact: path/to/evidence.json` line in its
Evidence section. That repository-local document must validate as PASS and
cover exactly those criteria. Review may record blocked or incomplete work;
prose alone cannot close the task. Verification still requires inspecting the
artifacts: a JSON claim cannot independently prove who ran a command.

aihaus does not install global hooks, change user-level agent settings, or
upload repository data. Its prompts, adapters, and local checks improve
workflow consistency but are not a security sandbox. Continue using isolated
environments and least-privilege credentials for production work.

## Troubleshooting

- **`/aih-refresh` is missing in Claude Code:** verify
  `.claude/skills/aih-refresh/SKILL.md` exists, then restart the Claude Code
  session. Skills created after a session starts may require rediscovery.
- **`/aih-refresh` is missing in Codex:** use `$aih-refresh` or `/skills`. Codex
  repository skills do not promise the exact custom slash spelling. If
  `aih-refresh` is not listed after setup, restart Codex so it rediscovers skills.
- **Host skill conflict:** setup preserved a user-owned skill at the adapter
  path. Review `conflicts`; rename or reconcile it explicitly rather than
  deleting it automatically.
- **Claude Code ignores the shared router:** run `/memory` and look for
  `AGENTS.md`. Claude Code before v2.1.281 may not read it, and any
  `CLAUDE.md`, `.claude/CLAUDE.md`, or `CLAUDE.local.md` in the repository or a
  parent directory makes Claude read those instead. Rerun setup after adding one
  inside the repository. For a parent directory, move that file or create a
  repository `CLAUDE.md` with an `@AGENTS.md` line; setup keeps it.
- **Codex ignores the shared router:** inspect `instructionWarnings` for a
  nonempty root `AGENTS.override.md`. Reconcile its intended instructions with
  the shared router; setup preserves it rather than changing its precedence.
- **Memory remains partial:** inspect each target's content/provenance flags
  and relevant `memoryGaps`/`staleClaims`. Blank headings, unresolved-only text,
  and line-ending changes do not initialize memory. Reverify uncited claims;
  do not invent citations merely to satisfy the status check.
- **`readyForSynthesis: false`:** add authoritative project evidence such as a
  README, manifest, project brief, or application source. Do not fill memory
  with the repository name or aihaus installation metadata.
- **Bootstrap packet missing or stale:** run
  node .aihaus/tools/refresh.mjs --repo . --json, complete the synthesis in
  .aihaus/REFRESH.md, rerun discovery, and require status.stale to be false.
- **Conflicting bootstrap evidence:** preserve existing memory and report the
  conflict; do not choose a business rule or project identity silently.
- **`target must be the repository root`:** change to the Git repository root
  and rerun setup.
- **Node version error:** install Node.js 22 or newer.
- **Release asset not found:** confirm that both occurrences of `<release-tag>`
  in the command were replaced with the same published GitHub Release tag.
- **`.aihaus-download` already exists during a source install:** stop and
  confirm that it is a leftover aihaus clone before deleting it; never remove
  an unknown directory.
- **`source.pinned: false`:** use the versioned GitHub Release package rather
  than an untagged source checkout.
- **`verification.ok` is not true:** treat the installation as incomplete and
  keep the setup JSON for diagnosis.
- **Existing project instructions:** setup preserves text outside bounded
  `AIHAUS:START` / `AIHAUS:END` blocks.

## Developing aihaus

These commands are for contributors to aihaus itself, not consumers installing
it into another repository.

Run the contract suite:

```bash
node tools/run-contract-tests.mjs
node tools/run-contract-tests.mjs --docker
```

The `--docker` run repeats the suite on Linux in a `node:22` container and
needs Docker. There is no pull-request CI; the release workflow reruns the
suite on Linux before publishing.

The repository can maintain an ignored nested consumer for real install/update
experiments:

```bash
node tools/aihaus-lab.mjs init --force --json
node tools/aihaus-lab.mjs verify --json
node tools/aihaus-lab.mjs reset --json
```

The controller verifies realpath containment and nested Git identity before
destructive reset or clean operations.

Architecture details live in [docs/architecture.md](docs/architecture.md); the
refactor/deletion ledger is [docs/provenance.md](docs/provenance.md).

## License

MIT. See [LICENSE](LICENSE).
