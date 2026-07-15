# aihaus package

`pkg/` contains the installable aihaus payload and the npm-compatible package
used to build versioned GitHub Release assets.

The customer command is `aihaus setup`. A GitHub Release exposes it through its
versioned tarball without adding aihaus to the consumer's `package.json`:

```bash
npm exec --yes --package=https://github.com/overdrive-dev/aihaus-flow/releases/download/<release-tag>/aihaus-flow-<release-tag>.tgz -- aihaus setup --target . --json
```

`cli.mjs` forwards setup to the canonical `setup.mjs` implementation. The
installer remains cross-platform, repository-local, and idempotent. Maintainers
can run it directly from source:

```bash
node pkg/setup.mjs --target . --json
```

Preview without writing, or explicitly repair every package-owned surface:

```bash
node pkg/setup.mjs --target . --check --json
node pkg/setup.mjs --target . --force --json
```

It installs the portable core from `pkg/.aihaus/` plus package version metadata:

- installed package version from `pkg/VERSION`;
- `MAP.md` and `conventions.md`;
- six roles and three task rooms;
- harness, evidence, adversarial-review, and ops-safety contracts;
- deterministic tools;
- missing project-memory and file-kanban seeds.
- thin repository-local initialization skills for Claude Code and Codex.

Package-owned surfaces are compared by content and only missing or different
paths are written. An unchanged rerun is a no-op. `--check` reports planned
changes without writing; `--force` rewrites package-owned paths. Existing
memory is never overwritten, including in force mode. Existing root
instructions are preserved outside bounded
`AIHAUS:START` / `AIHAUS:END` blocks. Host skills are refreshed only when the
aihaus ownership marker is present. User-owned collisions are preserved and
reported. The JSON result distinguishes created, refreshed, unchanged, and
planned package surfaces; seeded and preserved memory; adapter and
host-capability outcomes; conflicts; source version/commit/tag provenance;
verification; warnings; and whether the exact repository-local
`.aihaus-download` source still needs cleanup.

Release packaging adds `RELEASE.json` with the exact tag and commit. The setup
report validates that metadata and reports `source.distribution` as
`github-release`. `package.json` intentionally has no dependencies or lifecycle
scripts.

The two scripts under `pkg/scripts/` install the optional released `aih-graph`
binary. They are not required by the portable instruction core.

## Provider-neutral project bootstrap

Setup also installs .aihaus/tools/init.mjs, .aihaus/INIT.md, and the
project-bootstrap contract. The deterministic command is Node-only, offline,
and repository-scoped:

    node .aihaus/tools/init.mjs --repo . --json

It writes only the ignored discovery packet under
.aihaus/state/bootstrap/. Dry-run and status modes do not write. The packet maps
safe source evidence to all eight canonical memory files, while the active
agent performs semantic synthesis under .aihaus/INIT.md. Existing memory,
secret-bearing paths, global configuration, graph consent, and files outside
the Git repository remain untouched.

Discovery reports `readyForSynthesis`, `evidenceLevel`, and `memoryReadiness`.
Generated aihaus routers and host skills do not count as project evidence. An
empty repository remains uninitialized and keeps its memory templates until an
authoritative project source is available.

Claude Code exposes the thin wrapper as `/aih-init`. Codex exposes its
repository skill as `$aih-init` or through `/skills`; exact custom slash parity
is not promised. Both wrappers delegate to the same provider-neutral Node and
Markdown contract.

The public product contract, usage, and verification commands are documented in
the repository [README](../README.md).
