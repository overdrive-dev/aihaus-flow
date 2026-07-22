# Conventions

- Durable facts, rules, decisions, and procedures are versioned Markdown.
- `.aihaus/state/` and caches are generated, ignored, and safely rebuildable.
- A task's status is its kanban folder; do not duplicate status in frontmatter.
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
- Claims cite `path:line`; executable claims also carry command and exit code.
- Production safety comes from external containment and least privilege, not
  from prompts, rooms, or hooks.
- Managed instruction-file edits use bounded markers and preserve user text.
