# Same-File Cross-Story Rule (aih-milestone/annexes/)

**Governing ADR:** ADR-M017-C (stale-base + same-file rule + D3 viability).
**Active since:** M017.
**D3 viability:** DISABLED post-M017 Path B (see execution/S05-FALLBACK-NOTE.md — Claude Code
issues #27749 and #50850 CLOSED / not-planned; `worktree-branch-from.sh` NOT shipped).

---

## What the rule enforces

No two stories in a milestone may declare the same file in their `## Owned Files` sections
unless a valid `cross-story-file:` declaration is present in the milestone plan AND D3 is
viable. Currently D3 is non-viable, so the escape hatch is DISABLED. Any overlap is a BLOCKER.

---

## Overlap detection algorithm

```python
# pseudocode — plan-checker executes equivalent logic at Step E3

owned = {}  # { path: [story_id, ...] }

for story_file in glob("stories/**/*.md"):
    story_id = parse_id(story_file)          # e.g. "S03"
    section  = extract_section(story_file, "## Owned Files")
    for line in section:
        path = strip_backticks_and_comment(line)   # "pkg/foo.sh — edit" → "pkg/foo.sh"
        if path:
            owned.setdefault(path, []).append(story_id)

for path, stories in owned.items():
    if len(stories) > 1:
        emit_blocker(path, stories)
```

**Worked example — M017 dogfood:**

| Path | Stories |
|------|---------|
| `pkg/.aihaus/templates/settings.local.json` | S02a, S02b, S04 |
| `pkg/.aihaus/skills/aih-milestone/SKILL.md` | S02c, S02d |

Both are overlaps. Both emit BLOCKER (grandfathered by ADR-M017-C — see below).

---

## BLOCKER emission format

```
BLOCKER: Owned-file overlap detected.
  File: <path>
  Stories: S<a>, S<b>[, S<c> ...]
  Resolution: merge S<a>+S<b> into one story, or add 'cross-story-file:' declaration.
```

> Note: with D3 non-viable (no `pkg/.aihaus/hooks/worktree-branch-from.sh`), the
> `cross-story-file:` declaration is REJECTED even if present. The only valid resolution
> is to merge the overlapping stories into one.

---

## Escape hatch — `cross-story-file:` declaration

**Grammar (two-hop):**
```yaml
cross-story-file: { path: <p>, first: S<a>, then: S<b> }
```

**Grammar (multi-hop — historical M017 dogfood example):**
```yaml
cross-story-file: { path: pkg/.aihaus/templates/settings.local.json, first: S02a, then: S02b, then: S04 }
```

The declaration asserts: stories touching `<path>` are intentionally sequenced; each
later story depends on the prior story's commit. All named stories must be in execution
order.

**D3-viability gate:** The escape hatch is ACCEPTED iff
`pkg/.aihaus/hooks/worktree-branch-from.sh` EXISTS at review time.

Detection heuristic for plan-checker:
```bash
[ -f pkg/.aihaus/hooks/worktree-branch-from.sh ] || hatch_disabled=true
```

Absent file → hatch REJECTED → overlap is still a BLOCKER even with a valid declaration.
This is the current state post-M017 Path B.

---

## M017 grandfather clause

M017 shipped two pre-rule overlaps:

1. `pkg/.aihaus/templates/settings.local.json` — S02a (SubagentStop) → S02b (SessionEnd) → S04 (PreToolUse)
2. `pkg/.aihaus/skills/aih-milestone/SKILL.md` — S02c (--abort) → S02d (pre-dispatch + sentinel + --skip-reap)

These were planned under the assumption D3 would ship viable. S01 NON-UNANIMOUS outcome
(P2 + P3 both `VERIFIED-no`) disabled D3 retroactively. The overlaps are explicitly
grandfathered in ADR-M017-C:

> "M017 wrote the same-file rule. Its own pre-rule plan declared two cross-story-file
> overlaps under the assumption D3 would ship viable. S01 proved D3 non-viable, which
> retroactively disables the escape hatch. The two M017 overlaps are grandfathered —
> documented and accepted as historical artifacts of the milestone that introduced the
> rule. Post-M017 milestones MUST merge overlapping stories."

The `cross-story-file:` declaration grammar is preserved for documentary purposes and
future re-enablement (see re-enablement path below).

**Meta-test forecast (S08):** plan-checker re-run on M017 PLAN emits BLOCKER on both
overlaps. S08 asserts this as the correct outcome; the grandfather is acknowledged
separately in ADR-M017-C, not via a rule bypass.

---

## Re-enablement path (future milestone)

If either Claude Code issue #27749 (pre-created worktree path) OR issue #50850
(source-branch control) is re-opened and resolved by Anthropic:

1. Flip K-002 in `pkg/.aihaus/knowledge.md` from "permanent" → "structurally handled"
2. Ship `pkg/.aihaus/hooks/worktree-branch-from.sh` (the hook S05 Path A did not ship)
3. The hatch becomes ACCEPTED automatically (file-existence heuristic passes)

No change to plan-checker or this annex is required — the heuristic resolves correctly.

---

## When to use

- Multi-story milestones where sequential editing of the same file is genuinely necessary
  (e.g., additive feature columns on a shared config).
- Only valid post-re-enablement (i.e., after D3 becomes viable).

## When NOT to use

- As a workaround to avoid merging stories. Merge overlapping stories first.
- When D3 is non-viable (current state). The hatch is REJECTED regardless of declaration.
- For agent frontmatter fields — `owned_paths:` is NOT a frontmatter field (PATTERNS gap #3).
  Plan-checker reads MANIFEST story blocks / story `.md` files only.
