# Conventions

- Durable facts, rules, decisions, and procedures are versioned Markdown.
- `.aihaus/state/` and caches are generated, ignored, and safely rebuildable.
- A task's status is its kanban folder, unless an accepted external tracker is the
  task authority; do not duplicate status in frontmatter.
- One active implementation task owns one worktree, branch, and reviewable change.
  Backend, frontend, migrations, and tests for the same outcome stay together;
  unrelated outcomes use separate worktrees.
- Coordination-only parent tasks do not own a product diff. Their independently
  deliverable child tasks each receive their own worktree.
- The kanban in a worktree is a branch-local snapshot, not a globally synchronized
  queue. One designated orchestrator or intake worktree owns task ingestion and
  status transitions.
- One writer owns each shared memory file or task transition at a time.
- Parallel writers must own disjoint file sets; shared files merge sequentially.
- Business-visible ambiguity is a rule gap. Ask once and record the answer.
- Technical mechanics follow repository conventions without option menus.
- Code changes take the first option that fully works: skip what nobody asked
  for and name it in the report; reuse what the repository already has, the
  way the surrounding code uses it; then the standard library or platform; then
  an installed dependency, never a new one for a few lines; only then the least
  new code that stays readable. Finish every caller, test, fixture, and export
  the change reaches.
- Add no abstraction, option, config, or code for later that the task does not
  need; deletion beats addition, and the repository's layers and interfaces
  stay. Never trade away, even in moved or merged code, validation at trust
  boundaries, error handling that prevents data loss, security, accessibility,
  calibration that physical hardware needs, or anything requested.
- A shortcut with a known limit carries a `shortcut: <the limit>, <when to
  upgrade>` comment.
- Claims cite `path:line`; executable claims also carry command and exit code.
- Production safety comes from external containment and least privilege, not
  from prompts, rooms, or hooks.
- Managed instruction-file edits use bounded markers and preserve user text.
- Package-owned files (MAP.md, conventions.md, REFRESH.md, roles/, rooms/,
  contracts/, tools/) are replaced on upgrade. Project routes, assignments, and
  runbooks belong in `.aihaus/memory/project/`.
- Procedure text in seeded memory READMEs (`memory/kanban/README.md`,
  `memory/project/README.md`) may date from an earlier version; where it
  conflicts with a package-owned file, the package-owned file wins. Accepted
  project decisions keep their authority under `contracts/harness.md`.

## Third-party notice

The change ladder above and the complexity lens in
`contracts/adversarial-review.md` are adapted from
[Ponytail](https://github.com/DietrichGebert/ponytail).

MIT License

Copyright (c) 2026 DietrichGebert

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
