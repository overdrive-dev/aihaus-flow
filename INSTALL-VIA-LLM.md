# Install aihaus with a coding agent

Run the following request from the root of the Git repository that should use
aihaus:

```text
Install the repository-local aihaus package here.

1. Verify that the current directory is the Git repository root and that Git
   and Node.js 22+ are available.
2. Clone https://github.com/overdrive-dev/aihaus-flow with --depth 1 into the
   temporary child directory .aihaus-download.
3. Run:
      node .aihaus-download/pkg/setup.mjs --target . --json
4. Read the JSON result and verify these files exist:
      .aihaus/MAP.md
      .aihaus/contracts/harness.md
      .aihaus/roles/orchestrator.md
      .aihaus/rooms/feature/CONTEXT.md
5. Delete only the temporary .aihaus-download clone after resolving its real
   path and confirming it is inside this repository.
6. Do not install global hooks, mutate user-level agent settings, start a site,
   or upload repository data.
7. Read .aihaus/MAP.md and report the installed package surface plus any files
   that setup preserved rather than replaced.
```

## Optional local index

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
