# Install aihaus with a coding agent

aihaus is a repository-local package. It is not a Codex skill, Claude runtime,
plugin, website, or global agent installation. Use the versioned package asset
from a GitHub Release; do not clone the source repository for a normal customer
installation.

Run the following request from the root of the Git repository that should use
aihaus:

```text
Set up the released aihaus package in this repository.

Identity and scope:
- aihaus is not a Codex skill, Claude runtime, plugin, or global installation.
- Do not invoke skill-installer, install hooks, mutate user-level settings,
  start a site, upload repository data, or clone the source repository.
- Do not add aihaus to the consumer package.json or install it globally.

1. Verify that the current directory is the Git repository root and that Git,
   Node.js 22+, and npm are available.
2. Use the explicit GitHub Release tag supplied by the user. Replace both
   occurrences of <release-tag> below with that exact tag.
3. Run this one setup command:
      npm exec --yes --package=https://github.com/overdrive-dev/aihaus-flow/releases/download/<release-tag>/aihaus-flow-<release-tag>.tgz -- aihaus setup --target . --json
4. Treat the JSON result as authoritative. Require:
   - ok: true and scope: repository-local;
   - preflight Node and Git values;
   - source.distribution: github-release;
   - source.version, source.commit, and source.ref;
   - source.pinned: true;
   - verification.ok: true, including .aihaus/VERSION and the required package
     entry points;
   - created, refreshed, seeded, preserved, and adapters results;
   - cleanup.path: null and cleanup.pending: false.
5. Interpret ownership precisely. Paths in created/refreshed are package-owned;
   refreshing them may replace prior package files. Project memory listed in
   preserved and text outside bounded AIHAUS blocks remain user-owned. CLAUDE.md
   is a host adapter, not evidence of a Claude runtime dependency.
6. Read .aihaus/MAP.md and report version/ref provenance, package-owned changes,
   preserved content, adapter results, verification, warnings, and readiness.
```

## Source-install fallback

Use source installation only for aihaus development, unreleased evaluation, or
the current optional `aih-graph` binary helper:

```text
1. Refuse to continue if .aihaus-download already exists.
2. Clone https://github.com/overdrive-dev/aihaus-flow with --depth 1 into the
   temporary child directory .aihaus-download.
3. Run:
      node .aihaus-download/pkg/setup.mjs --target . --json
4. Treat source.pinned: false as unreleased unless the checkout is at the tag
   matching .aihaus/VERSION.
5. Resolve the real path and delete only the .aihaus-download child after all
   requested source helpers have finished.
```

## Optional local index through the source fallback

If the user asks for the code index, install the matching released `aih-graph`
binary into `.aihaus/bin/` before deleting the temporary clone. Indexing consent
must remain explicit; do not create `.aih-graph-consent` on the user's behalf.

After consent, verify with:

```bash
node .aihaus/tools/graph.mjs refresh --json
node .aihaus/tools/graph.mjs status --json
```

The index is generated local state. Project Markdown and source files remain the
source of truth.
