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
- work without sending project memory to an aihaus service.

There is no aihaus account, website, hosted control plane, or cloud memory.
The portable workflow is a repository-local package. Thin repository-local
Claude Code and Codex skills expose its initialization routine without turning
aihaus into a global runtime, plugin, or user-level installation.

## Requirements

- a Git repository;
- Git available on the command line;
- Node.js 22 or newer with npm;
- a released aihaus tag for a reproducible installation.

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

Current published release (`v1.6.0`):

```bash
npm exec --yes --package=https://github.com/overdrive-dev/aihaus-flow/releases/download/v1.6.0/aihaus-flow-v1.6.0.tgz -- aihaus init --target . --json
```

For another release, replace both occurrences of `v1.6.0` with the same tag.

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

Starting with `v1.2.0`, the installed entry points are:

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
| `.aihaus/MAP.md`, `rooms/`, `roles/`, `contracts/`, `tools/` | Portable aihaus workflow | Package-owned; refreshed only when different or with `--force` |
| `.aihaus/VERSION` | Installed package version | Package-owned; refreshed only when different or with `--force` |
| `.aihaus/memory/project/` | Project rules, decisions, knowledge, and procedures | Project-owned and preserved |
| `.aihaus/memory/kanban/` | File-based task history | Project-owned and preserved |
| `AGENTS.md`, `CLAUDE.md` | Shared router in AGENTS; Claude imports it with `@AGENTS.md` | Only the bounded aihaus block is managed |
| `.claude/skills/aih-refresh/SKILL.md`, `.agents/skills/aih-refresh/SKILL.md` | Thin host-native wrappers around the portable bootstrap | Refreshed only when the aihaus ownership marker is present; otherwise preserved and reported as a conflict |
| `.gitignore` | Ignores local aihaus state and temporary download | Only the bounded aihaus block is managed |

Text outside `AIHAUS:START` / `AIHAUS:END` blocks is preserved, including user
instructions imported from AGENTS by Claude. Setup rejects malformed or repeated
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

### Delegate to specialist agents

aihaus keeps six general roles and two coordination levels: an orchestrator
assigns outcomes and executors perform them, with no distributor agent in
between. To route recurring specialist work such as security review, QA, or
release promotion, add an `Assignments` section to
`.aihaus/memory/project/procedures.md`. Upgrades never overwrite it.

| Assignment | Role | Load | Trigger | Context | Output | Next on pass / rework / blocked | Escalation |
|---|---|---|---|---|---|---|---|
| security | reviewer | `contracts/adversarial-review.md` plus project security notes | `payments/**`, `auth/**` | separate, read-only, candidate SHA | verdict receipt | qa / author / orchestrator | owner |
| qa | verifier | `contracts/evidence.md` | every task | separate, read-only, candidate SHA | evidence JSON | orchestrator / author / orchestrator | owner |

Reviews and verification run in a separate context against a fixed commit and
record a verdict receipt; a recheck never approves unrelated changes. Watching
for stalled agents, messaging, and process health stay with your host tool.

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

Normal and forced setup seed only newly introduced memory files and preserve
existing project memory plus text outside managed root blocks.
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
```

The repository can maintain an ignored nested consumer for real install/update
experiments:

```bash
node tools/aihaus-lab.mjs init --force --json
node tools/aihaus-lab.mjs verify --json
node tools/aihaus-lab.mjs reset --json
```

The controller verifies realpath containment and nested Git identity before
destructive reset or clean operations. CI runs the contract suite on Linux,
macOS, and Windows.

Architecture details live in [docs/architecture.md](docs/architecture.md); the
refactor/deletion ledger is [docs/provenance.md](docs/provenance.md).

## License

MIT. See [LICENSE](LICENSE).
