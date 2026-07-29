---
name: aih-refresh
description: Initialize or refresh repository-local aihaus project memory from verified local evidence when the user invokes $aih-refresh or explicitly requests an aihaus memory refresh.
---

<!-- AIHAUS-MANAGED: repository-local-host-adapter-v1 -->

Read `.aihaus/MAP.md`, `.aihaus/contracts/harness.md`, `.aihaus/REFRESH.md`, and
`.aihaus/contracts/project-bootstrap.md`. Follow the provider-neutral bootstrap
contract exactly.

Run `node .aihaus/tools/refresh.mjs --repo . --json`. If
`readyForSynthesis` is false, preserve the memory templates and report the
missing authoritative project evidence, or offer the scope interview from
`.aihaus/REFRESH.md` and record owner answers in PROJECT-BRIEF.md before
rerunning discovery. Otherwise synthesize only verified,
source-backed knowledge into `.aihaus/memory/project/`, preserving existing
content and never recording secrets. Rerun discovery and finish with
`node .aihaus/tools/refresh.mjs --repo . --status --json`.

Do not use global aihaus state, user-level settings, hooks, network access, or
legacy `/aih-env` behavior.
