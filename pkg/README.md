# aihaus package

`pkg/` contains the installable aihaus payload.

The canonical installer is `setup.mjs`. It is cross-platform, repository-local,
and idempotent:

```bash
node pkg/setup.mjs --target . --json
```

It installs only the portable core from `pkg/.aihaus/`:

- `MAP.md` and `conventions.md`;
- six roles and three task rooms;
- harness, evidence, adversarial-review, and ops-safety contracts;
- deterministic tools;
- missing project-memory and file-kanban seeds.

Package-owned surfaces are refreshed on every run. Existing memory is never
overwritten. Existing root instructions are preserved outside bounded
`AIHAUS:START` / `AIHAUS:END` blocks.

The two scripts under `pkg/scripts/` install the optional released `aih-graph`
binary. They are not required by the portable instruction core.

The public product contract, usage, and verification commands are documented in
the repository [README](../README.md).
