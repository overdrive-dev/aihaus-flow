# Local memory (per-machine, gitignored)

Artifacts here are **local-scoped**: per-machine / per-person, **never committed**.
This is the privacy/access boundary of the role model — sensitive or
environment-specific context that must not enter the shared (project) memory or
the shared aih-graph index.

Contrast with **project memory** (committed, shared): `.aihaus/decisions.md`,
`.aihaus/knowledge.md`, `.aihaus/project.md`, and the rest of `.aihaus/memory/**`.

## What lives here

- `environment-online.md` — online (staging/prod) env: deploy URLs, promote/
  rollback commands, **credential locations** (never the secrets themselves).
  Created by `aih-init` env-detection. Injected into agent context **only for
  profiles holding the `devops` role** (see `context-inject.sh` + `roles.md`),
  so builder/dev/qa agents never receive online env in their context.

## Rules

- Never store plaintext secrets — store **locations** only.
- This directory is gitignored in installed repos; do not commit its contents.
