# RUN-MANIFEST v3 template (aih-bugfix)

When Step 8 creates `.aihaus/bugfixes/[YYMMDD]-[slug]/RUN-MANIFEST.md`, use this v3 YAML shape.
All mutations go via `manifest-append.sh` (single-writer — never inline edits).

```
## Metadata
schema: v3
bugfix: [YYMMDD]-[slug]
branch: fix/[slug]
started: <ISO-8601 UTC>
phase: apply-fix
status: running
last_updated: <ISO-8601 UTC>

## Story Records
story_id|status|started_at|commit_sha|verified|notes
fix|in-progress||||

## Progress Log

## Checkpoints
| ts | story | agent | substep | event | result | sha |
|---|---|---|---|---|---|---|
```

- `manifest-append.sh --field last_updated --payload <ISO>` after each step.
- `manifest-append.sh --field status --payload <value>` to transition status.
- See `pkg/.aihaus/hooks/manifest-append.sh` for all supported modes.
