# aih-plan annex: attachments

Rules for handling pasted images / dragged files during planning.

## Source paths
- Pasted images: `~/.claude/image-cache/[uuid]/[n].png`
- Dragged files: absolute paths in message text

## Temp-slug flow (M004 story H)

**On first attachment mention** — before the final slug is determined (Phase 2):
1. Derive a temp slug: `YYMMDD-wip-HHMMSS-<rand4>` (date + UTC time + 4-char random, prevents concurrent-session collisions).
2. `mkdir -p .aihaus/plans/<temp-slug>/attachments/`
3. Copy the attachment: `cp <source> .aihaus/plans/<temp-slug>/attachments/[seq]-[short-desc].[ext]`. Seq is 2-digit zero-padded (01, 02, ...); short description derived from content (e.g., `login-error-screenshot`).
4. Describe with vision in one sentence.
5. Track the temp slug — reference it in subsequent work.

**On Phase 2 slug finalization:**
- `mv .aihaus/plans/<temp-slug>/ .aihaus/plans/<final-slug>/` — preserves all attachments under final name.

**Crash-recovery (F-M6):** on `aih-plan` entry, scan `.aihaus/plans/` for `*-wip-*` directories. If one is found alongside a matching finalized slug (rename crash mid-operation), prompt:
- (a) keep finalized, discard wip
- (b) keep wip, discard finalized
- (c) abort and inspect manually

## Manifest entry
Add a `## Attachments` section to PLAN.md:

```markdown
## Attachments
| # | File | Added | Description |
|---|------|-------|-------------|
| 01 | attachments/01-login-error.png | [ISO ts] | Login page showing "Network Error" |
```

## Limits + hygiene
- Reject files > 20 MB.
- Warn at 5+ attachments ("consider culling").
- Remind user: "If sensitive, crop/redact before committing — `.aihaus/` is git-tracked."
- Reference attachments by relative path in Proposed Approach when they inform decisions.
