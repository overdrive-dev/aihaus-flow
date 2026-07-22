# aihaus repository map

aihaus is a downloadable GitHub package, not a website. The publishable payload
lives in `pkg/`; repository-only tests, lab tooling, and docs live outside it.

Before changing the package:

1. Read `pkg/.aihaus/contracts/harness.md` for the operating contract.
2. Read `pkg/.aihaus/MAP.md` and load only the matching room/contracts.
3. Treat Markdown project memory and file kanban as truth.
4. Keep user content and global instruction files untouched.

Implementation rules:

- Prefer six general roles plus task-specific room context over specialist
  prompt proliferation.
- Keep safety/evidence checks as deterministic local tools. Host hooks are
  optional adapters, never the portable source of truth.
- Preserve existing behavior until replacement contract tests are green.
- Do not add a room, role, hook, or state store without a failing lab scenario
  that demonstrates the need.
- Generated dogfood state belongs only under ignored `.aihaus-lab/`.

Validation:

```text
node tools/run-contract-tests.mjs
```

See `docs/architecture.md` for boundaries and `docs/provenance.md` before any
deletion wave.
