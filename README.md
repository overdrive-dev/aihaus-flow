# aihaus

aihaus gives coding agents a shared, repository-local way to understand a
project, plan work, preserve decisions, and prove that a task is complete. It
installs as ordinary files in your Git repository, so the workflow travels with
the code and remains reviewable by your team.

Use aihaus when you want an agent to:

- follow project rules and prior decisions instead of starting from scratch;
- route feature, bug-fix, and research work through a consistent workflow;
- keep durable project memory in versioned Markdown;
- support completion claims with executable evidence;
- work without sending project memory to an aihaus service.

There is no aihaus account, website, hosted control plane, or cloud memory. It
is not a Codex skill, Claude runtime, plugin, or global installation.

## Requirements

- a Git repository;
- Git available on the command line;
- Node.js 22 or newer with npm;
- a released aihaus tag for a reproducible installation.

Run installation commands from the root of the repository that will use
aihaus.

## Set up with a coding agent

This is the recommended customer path. Choose a tag from
[GitHub Releases](https://github.com/overdrive-dev/aihaus-flow/releases), replace
`<release-tag>` below, and paste the prompt into your coding agent:

```text
Install aihaus release <release-tag> in this repository.

aihaus is a repository-local package, not a Codex skill, Claude runtime,
plugin, or global installation. Do not use skill-installer, change user-level
agent settings, install global hooks, or clone the source repository.

Follow the version-pinned installation contract at:
https://raw.githubusercontent.com/overdrive-dev/aihaus-flow/<release-tag>/INSTALL-VIA-LLM.md

Run the versioned GitHub Release package with npm exec and the `aihaus setup`
command. Require source.distribution to be github-release and require
source.pinned and verification.ok to be true. Report the installed version,
package-owned changes, preserved content, adapters, warnings, and readiness.
```

The full agent contract is also available in
[INSTALL-VIA-LLM.md](INSTALL-VIA-LLM.md). Always use the copy from the release
tag you are installing, not the copy from `main`.

## Set up from a GitHub Release

Replace `<release-tag>` with the release you want:

```bash
npm exec --yes --package=https://github.com/overdrive-dev/aihaus-flow/releases/download/<release-tag>/aihaus-flow-<release-tag>.tgz -- aihaus setup --target . --json
```

This is the go-to command for both the first setup and later updates. npm keeps
the executable package in its cache; aihaus itself is installed as ordinary
repository-local files. The command does not add aihaus to the consumer's
`package.json`, create a visible source clone, or require a cleanup command.

## Confirm the installation

The setup JSON is the installation report. A released installation should show:

```json
{
  "ok": true,
  "scope": "repository-local",
  "source": {
    "distribution": "github-release",
    "pinned": true,
    "ref": "<release-tag>"
  },
  "verification": {
    "ok": true
  },
  "cleanup": {
    "path": null,
    "pending": false
  }
}
```

`cleanup.pending: false` confirms that the GitHub Release setup did not leave a
repository-local download directory behind.

The installed entry points are:

- `.aihaus/VERSION`;
- `.aihaus/MAP.md`;
- `.aihaus/contracts/harness.md`;
- `.aihaus/roles/orchestrator.md`;
- `.aihaus/rooms/feature/CONTEXT.md`.

## What setup changes

| Path | Purpose | Ownership on update |
|---|---|---|
| `.aihaus/MAP.md`, `rooms/`, `roles/`, `contracts/`, `tools/` | Portable aihaus workflow | Package-owned and refreshed |
| `.aihaus/VERSION` | Installed package version | Package-owned and refreshed |
| `.aihaus/memory/project/` | Project rules, decisions, knowledge, and procedures | Project-owned and preserved |
| `.aihaus/memory/kanban/` | File-based task history | Project-owned and preserved |
| `AGENTS.md`, `CLAUDE.md` | Thin host routers | Only the bounded aihaus block is managed |
| `.gitignore` | Ignores local aihaus state and temporary download | Only the bounded aihaus block is managed |

Text outside `AIHAUS:START` / `AIHAUS:END` blocks is preserved. `CLAUDE.md` is
an adapter for compatible hosts, not a dependency on Claude.

## Start using aihaus

After installation, use your coding agent normally from the repository. The
root adapter directs it to `.aihaus/MAP.md`, which selects only the workflow and
project memory needed for the request.

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

## Update aihaus

Repeat the GitHub Release setup command using the newer release tag. Setup
refreshes package-owned workflow files, seeds newly introduced memory files,
and preserves existing project memory plus text outside managed root blocks.
Review the `created`, `refreshed`, `seeded`, `preserved`, and `adapters` fields
in the JSON report before committing the update.

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

## Optional local code index

`aih-graph/` adds repository relationship and search commands. It stores its
generated index locally and never replaces project source files or Markdown
memory. The current binary helper is available through the source-install
fallback; run it before `.aihaus-download` is removed.

Install a released binary while the temporary clone still exists:

```bash
bash .aihaus-download/pkg/scripts/install-aih-graph-binary.sh --bin .aihaus/bin/aih-graph
```

On Windows:

```powershell
& .aihaus-download/pkg/scripts/install-aih-graph-binary.ps1 -Bin .aihaus/bin/aih-graph.exe
```

To enable indexing, create `.aih-graph-consent` in the repository or use the
engine's one-run consent flag, then use the repository-local wrapper:

```bash
node .aihaus/tools/graph.mjs refresh --json
node .aihaus/tools/graph.mjs query --json "authentication boundary"
node .aihaus/tools/graph.mjs impact --json path/to/file
```

aihaus will not create `.aih-graph-consent` on your behalf. After consent,
generated results remain local and Markdown continues to be the source of
truth. See
[aih-graph/PRD.md](aih-graph/PRD.md) for the detailed capability contract.

## Evidence and safety

aihaus expects executable completion criteria to be supported by tool- or
CI-produced evidence with exit code 0. Evidence documents can be checked with:

```bash
node .aihaus/tools/evidence-validate.mjs path/to/evidence.json
```

aihaus does not install global hooks, change user-level agent settings, upload
repository data, or enable indexing consent during normal setup. Its prompts,
adapters, and local checks improve workflow consistency but are not a security
sandbox. Continue using isolated environments and least-privilege credentials
for production work.

## Troubleshooting

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

Go contributors should also run:

```bash
go test ./...
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
macOS, and Windows, plus the `aih-graph` release matrix.

Architecture details live in [docs/architecture.md](docs/architecture.md); the
refactor/deletion ledger is [docs/provenance.md](docs/provenance.md).

## License

MIT. See [LICENSE](LICENSE).
