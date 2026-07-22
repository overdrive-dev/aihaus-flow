---
name: aih-init
description: Initialize or refresh repository-local aihaus project memory from verified local evidence when the user invokes $aih-init or explicitly requests aihaus initialization.
---

<!-- AIHAUS-MANAGED: repository-local-host-adapter-v1 -->

Read `.aihaus/MAP.md`, `.aihaus/contracts/harness.md`, `.aihaus/INIT.md`, and
`.aihaus/contracts/project-bootstrap.md`. Follow the provider-neutral bootstrap
contract exactly.

Run `node .aihaus/tools/init.mjs --repo . --json`. If
`readyForSynthesis` is false, preserve the memory templates and report the
missing authoritative project evidence. Otherwise synthesize only verified,
source-backed knowledge into `.aihaus/memory/project/`, preserving existing
content and never recording secrets. Rerun discovery and finish with
`node .aihaus/tools/init.mjs --repo . --status --json`.

Do not use global aihaus state, user-level settings, hooks, network access, or
legacy `/aih-env` behavior.
