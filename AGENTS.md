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

Maintainer runbook:

- Tasks come from GitHub issues/PRs on `overdrive-dev/aihaus-flow`.
  `pkg/.aihaus/memory/` is the shipped consumer template; never record this
  repository's facts or tasks there.
- Integration branch is `main` (squash merge). `package-ci.yml` runs the
  contract suite on Ubuntu, macOS, and Windows for package paths.
- Release: bump `pkg/VERSION`, `pkg/package.json`, `pkg/CHANGELOG.md`, and
  README install pins in the PR; after merge push tag `v<VERSION>` to run
  `package-release.yml`.
- The suite takes about 30 s; Windows skips one symlink test.
