# Install aihaus with a coding agent

aihaus is a repository-local package with thin repository-local host adapters.
It is not a global Codex skill, Claude runtime, plugin, website, or user-level
agent installation. Use the versioned package asset from a GitHub Release; do
not clone the source repository for a normal customer installation.

Run the following request from the root of the Git repository that should use
aihaus:

```text
Set up the released aihaus package in this repository.

Identity and scope:
- aihaus is not a global Codex skill, Claude runtime, plugin, or user-level
  installation. Its host skills are ordinary files inside this repository.
- Do not invoke skill-installer, install hooks, mutate user-level settings,
  start a site, upload repository data, or clone the source repository.
- Do not add aihaus to the consumer package.json or install it globally.

1. Verify that the current directory is the Git repository root and that Git,
   Node.js 22+, and npm are available.
2. Use the explicit GitHub Release tag supplied by the user. Replace both
   occurrences of <release-tag> below with that exact tag.
3. An optional read-only preview is available. It must not create or change any
   repository file:
      npm exec --yes --package=https://github.com/overdrive-dev/aihaus-flow/releases/download/<release-tag>/aihaus-flow-<release-tag>.tgz -- aihaus setup --target . --check --json
   In this mode require mode: check, created/refreshed/seeded to be empty, and
   inspect changesRequired, wouldCreate, wouldRefresh, wouldSeed, and
   wouldRemove. On a first installation verification.ok may be false because
   the preview does not write the missing package surface.
4. Run the setup command to install or update only missing or changed package
   surfaces:
      npm exec --yes --package=https://github.com/overdrive-dev/aihaus-flow/releases/download/<release-tag>/aihaus-flow-<release-tag>.tgz -- aihaus setup --target . --json
5. Treat the JSON result as authoritative. Require:
   - ok: true and scope: repository-local;
   - mode: apply and forced: false for a normal setup;
   - changesRequired plus created, refreshed, unchanged, seeded, preserved,
     removed, and wouldRemove;
   - preflight Node and Git values;
   - source.distribution: github-release;
   - source.version, source.commit, and source.ref;
   - source.pinned: true;
   - verification.ok: true, including .aihaus/VERSION and the required package
     entry points;
   - bootstrap.command, bootstrap.instruction, and bootstrap.contract;
   - adapters, hostCapabilities, and conflicts results;
   - cleanup.path: null and cleanup.pending: false.
6. Interpret ownership precisely. Paths in created/refreshed are package-owned;
   refreshing them may replace prior package files. Project memory listed in
   preserved and text outside bounded AIHAUS blocks remain user-owned. CLAUDE.md
   is a host adapter, not evidence of a Claude runtime dependency. The setup
   may refresh `.claude/skills/aih-init/SKILL.md` and
   `.agents/skills/aih-init/SKILL.md` only when their aihaus ownership marker is
   present. It must preserve a user-owned collision, report it in conflicts,
   and set that host capability's available field to false.
   Repeating an unchanged release should report changesRequired: false, empty
   created/refreshed arrays, and package paths under unchanged. Use --force
   only for explicit package repair; it still must preserve project memory,
   text outside managed blocks, and user-owned host-skill collisions.
   Starting with v1.3.0, removed/wouldRemove report cleanup of known artifacts
   from the retired graph runtime; Markdown memory and kanban files are outside
   that cleanup allowlist.
7. Do not use /aih-env or any old global command suite. Claude Code may expose
   the repository skill as /aih-init. Codex exposes it as $aih-init or through
   /skills; do not claim that Codex supports the exact custom /aih-init slash
   form. If a newly installed skill is not visible, restart that host. The
   provider-neutral command below remains canonical.
8. Run the deterministic repository-local discovery command:
      node .aihaus/tools/init.mjs --repo . --json
   Require ok: true, mode: apply, a packet under
   .aihaus/state/bootstrap/discovery.json, source provenance, exclusions,
   conflicts, readiness fields, and a plan for all eight files under
   .aihaus/memory/project/.
9. Read .aihaus/INIT.md and .aihaus/contracts/project-bootstrap.md. Synthesize
   the packet into canonical Markdown one target at a time only when
   readyForSynthesis is true. If false, preserve all memory templates and report
   the evidence blocker. Preserve existing content, cite repository-relative
   sources and the reviewed commit, and never convert an inference into an
   accepted rule or decision.
10. Do not read paths reported as skipped, record secret values, access the
   network, upload data, start a service, deploy, or write outside this
   repository.
11. After synthesis, rerun the discovery command, then run:
      node .aihaus/tools/init.mjs --repo . --status --json
    Require status.initialized: true, status.memoryReadiness: ready, and
    status.stale: false. When synthesis was blocked for insufficient evidence,
    require status.initialized: false and status.memoryReadiness: uninitialized
    instead.
12. Report version/ref provenance, package-owned changes, preserved content,
    adapter and hostCapabilities results, bootstrap sources, canonical memory
    changes, conflicts, unresolved gaps, verification, warnings, and readiness.
```

## Source-install fallback

Use source installation only for aihaus development or unreleased evaluation:

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
