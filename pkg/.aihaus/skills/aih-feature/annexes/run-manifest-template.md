# RUN-MANIFEST v3 template (aih-feature)

When Step 6 creates `.aihaus/features/[YYMMDD]-[slug]/RUN-MANIFEST.md`, use this v3 YAML shape.
All mutations go via `manifest-append.sh` (single-writer — never inline edits).

```
## Metadata
schema: v3
feature: [YYMMDD]-[slug]
branch: feature/[slug]
started: <ISO-8601 UTC>
phase: implement
status: running
last_updated: <ISO-8601 UTC>

## Invoke stack

## Story Records
story_id|status|started_at|commit_sha|verified|notes

## Progress Log

## Checkpoints
| ts | story | agent | substep | event | result | sha |
|---|---|---|---|---|---|---|
```

- `manifest-append.sh --field last_updated --payload <ISO>` after each step.
- `manifest-append.sh --field status --payload <value>` to transition status.
- See `pkg/.aihaus/hooks/manifest-append.sh` for all supported modes.
