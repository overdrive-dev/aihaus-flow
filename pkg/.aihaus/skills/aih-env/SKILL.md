---
name: aih-env
description: "Capture or update how the test environment, credentials, env access, and deploy work — persists to .aihaus/memory/workflows/environment.md, which every session and agent loads automatically. Run it once at setup, and again whenever new environment definitions surface during the project."
allowed-tools: Read Write Edit Bash Grep Glob
argument-hint: "[--show | --online]"
---

## Task

Interrogate and persist the project's **operational environment** so it is defined
**once** and then loaded by every session, every agent, and after every `/compact`
— never re-asked. The durable home is `.aihaus/memory/workflows/environment.md`,
which `templates/claude/CLAUDE.md` `@`-imports on every session start (and which
`context-inject.sh` carries to agents). This skill fills and **updates** that file
(merge, never clobber) as definitions emerge during the life of the project.

**Never store secret values** — only their *location* (Secrets Manager path, vault
entry, env-var name, password-manager item). Writing a plaintext credential, token,
or key is a hard error; capture where it lives, not what it is.

$ARGUMENTS

## Phase 1 — Load what already exists

- Read `.aihaus/memory/workflows/environment.md` — the durable env doc, marker block
  `AIHAUS:WORKFLOW-ENVIRONMENT-PROMPTS-START/END`. Note which fields are already
  filled; do **not** re-ask those unless the user wants to change them.
- Read `.aihaus/.profile` (role profile) and `.aihaus/project.md` for stack + role
  context. Read `.aihaus/memory/local/environment-online.md` if present (the
  devops-scoped online environment).
- `--show` → print the current resolved environment (durable, plus online only if
  the profile holds `devops`) and stop without asking anything.

## Phase 2 — Interrogate the gaps (one batch)

Ask **only the unfilled or stale** dimensions, in a single message — restate
anything already answered in the source and skip its question:

- **Test environment** — default is **local Docker** (the aihaus 3.0 default).
  Confirm how tests run (compose file + command), which DB/services spin up locally,
  and seed-data setup.
- **Credential locations** — where secrets live (Secrets Manager / Parameter Store /
  `.env` vault / password manager). **Locations and named test roles only.**
- **Env-var locations** — which file or secret store holds env vars per environment.
- **Env access by role** — which roles reach which environments. The **online
  boundary** (staging → prod) is **devops-only** (`workflows/roles.md` +
  `role-guard.sh`); builder/dev/qa stay offline-local.
- **Validation + deploy** — unit/integration command, Playwright/browser command +
  dev URL, CI job names, deploy path and promotion gates.

## Phase 3 — Persist (merge, role-scoped)

- **Durable + offline** facts → write into `environment.md` **between the
  `AIHAUS:WORKFLOW-ENVIRONMENT-PROMPTS-START/END` markers**, updating the matching
  bullet in place. Merge — preserve all other content byte-for-byte. This file is
  project-scoped (committed) and `@`-imported every session, so it loads once for
  everyone.
- **Online** facts (staging/prod URLs, online deploy + its credential *location*) →
  only when the profile holds `devops`; write to
  `.aihaus/memory/local/environment-online.md` (local, gitignored — never committed,
  and `context-inject.sh` keeps it out of non-devops contexts).
- Confirm in one line what was written and where, and that it now loads
  automatically for every session, agent, and `/compact` — no repetition.

## Autonomy

See `_shared/autonomy-protocol.md`. This skill is **interactive by design** — its
Phase 2 batch question is its purpose, not a forbidden execution-phase checkpoint.
After persisting it reports and stops; it does not loop.
