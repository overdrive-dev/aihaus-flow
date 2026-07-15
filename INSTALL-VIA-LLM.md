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
   - bootstrap.command, bootstrap.instruction, and bootstrap.contract;
   - created, refreshed, seeded, preserved, and adapters results;
   - cleanup.path: null and cleanup.pending: false.
5. Interpret ownership precisely. Paths in created/refreshed are package-owned;
   refreshing them may replace prior package files. Project memory listed in
   preserved and text outside bounded AIHAUS blocks remain user-owned. CLAUDE.md
   is a host adapter, not evidence of a Claude runtime dependency.
6. Do not use /aih-init or /aih-env. Those are provider-specific commands from
   a different global installation model and are not part of this package.
7. Run the deterministic repository-local discovery command:
      node .aihaus/tools/init.mjs --repo . --json
   Require ok: true, mode: apply, a packet under
   .aihaus/state/bootstrap/discovery.json, source provenance, exclusions,
   conflicts, and a plan for all eight files under .aihaus/memory/project/.
8. Read .aihaus/INIT.md and .aihaus/contracts/project-bootstrap.md. Synthesize
   the packet into canonical Markdown one target at a time. Preserve existing
   content, cite repository-relative sources and the reviewed commit, and never
   convert an inference into an accepted rule or decision.
9. Do not read paths reported as skipped, record secret values, access the
   network, upload data, start a service, deploy, write outside this repository,
   or create .aih-graph-consent.
10. Rerun the discovery command, then run:
      node .aihaus/tools/init.mjs --repo . --status --json
    Require status.initialized: true and status.stale: false.
11. Report version/ref provenance, package-owned changes, preserved content,
    adapter results, bootstrap sources, canonical memory changes, conflicts,
    unresolved gaps, verification, warnings, and readiness.
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
5. Run node .aihaus/tools/init.mjs --repo . --json and follow
   .aihaus/INIT.md exactly as in the release installation.
6. Resolve the real path and delete only the .aihaus-download child after all
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
