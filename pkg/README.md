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

It installs the portable core from `pkg/.aihaus/` plus package version metadata:

- installed package version from `pkg/VERSION`;
- `MAP.md` and `conventions.md`;
- six roles and three task rooms;
- harness, evidence, adversarial-review, and ops-safety contracts;
- deterministic tools;
- missing project-memory and file-kanban seeds.

Package-owned surfaces are refreshed on every run. Existing memory is never
overwritten. Existing root instructions are preserved outside bounded
`AIHAUS:START` / `AIHAUS:END` blocks. The JSON result distinguishes created and
refreshed package surfaces, seeded and preserved memory, adapter outcomes,
source version/commit/tag provenance, verification, warnings, and whether the
exact repository-local `.aihaus-download` source still needs cleanup.

Release packaging adds `RELEASE.json` with the exact tag and commit. The setup
report validates that metadata and reports `source.distribution` as
`github-release`. `package.json` intentionally has no dependencies or lifecycle
scripts.

The two scripts under `pkg/scripts/` install the optional released `aih-graph`
binary. They are not required by the portable instruction core.

The public product contract, usage, and verification commands are documented in
the repository [README](../README.md).
