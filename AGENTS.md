# aihaus repository map

aihaus is a downloadable GitHub package: no website, hosted service or state, or
global agent mutation. The publishable payload lives in `pkg/`; repository-only
tests, lab tooling, and docs live outside it.

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

Validation: `node tools/run-contract-tests.mjs`. See `docs/architecture.md` for
boundaries and `docs/provenance.md` before any deletion wave.

Maintainer runbook:

- Tasks: owner requests or open issues/PRs on `overdrive-dev/aihaus-flow`; never
  record repo facts or tasks in `pkg/.aihaus/memory/` (consumer template).
- main: `gh pr merge --squash --delete-branch`; no PR CI: before merging, the
  author runs the suite natively and with `--docker` (Linux); releases rerun it.
- Release: bump `pkg/VERSION`, `pkg/package.json`, `pkg/CHANGELOG.md`, and
  README install pins in the PR; after merge push tag `v<VERSION>` to run
  `package-release.yml`; retitle notes `AIHAUS FLOW v<VERSION>: <theme>` with
  What changed; Install or update; migration note with opt-out for new defaults.
- Suite ~50 s, run by the author (Codex sandbox can't spawn); Windows skips 1 test.
- Host A/B labs: follow `tools/lab/README.md` (recipe, isolation, pitfalls); at
  most two Claude sessions at once. Judge a change by model calls, cost, and
  time, not by how much text an agent reads.
- Setup replaces package-owned surfaces and never reseeds existing memory;
  `refresh.mjs` hashes memory templates. Ship new guidance through MAP,
  contracts, rooms, roles, or the router, not memory templates.
- No Assignments here; harness Working style applies. Profile: README `luna`.
