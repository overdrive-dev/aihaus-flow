# Pre-flight: Cross-skill branch-collision check (ADR-260427-C)

Run this check before any `git checkout -b feature/[slug]` or `git checkout -b fix/[slug]` op. The cost is one shell command + a few file reads; the benefit is detecting concurrent-skill races before they corrupt branch state.

## Why this exists

Two `claude --dangerously-skip-permissions` processes against the same working tree can race on `git checkout -b`. Without an inter-process mutex, the loser's branch creation may target a SHA that includes the winner's uncommitted edits — leading to silent misroute (per the 2026-04-27 audit).

This pre-flight is **read-only**; it surfaces the collision so the user can decide before proceeding. It does not block. The full lock-leak prevention stack (ADR-M017-B L1-L4) is milestone-scoped and not extended here per ADR-260427-C scope rationale.

## Procedure

1. **Glob running manifests:**

   ```bash
   for cand in .aihaus/milestones/*/RUN-MANIFEST.md \
               .aihaus/features/*/RUN-MANIFEST.md \
               .aihaus/bugfixes/*/RUN-MANIFEST.md; do
     [ -f "$cand" ] || continue
     # Parse Metadata block for `status: running` (lowercase, per RUN-MANIFEST schema-v2)
     awk '
       /^## Metadata$/ { in_meta=1; next }
       /^## / && in_meta { in_meta=0 }
       in_meta && /^status:[[:space:]]*running[[:space:]]*$/ { found=1; exit }
       END { exit !found }
     ' "$cand" 2>/dev/null && echo "$cand"
   done
   ```

2. **For each running manifest, capture its `branch:` field** (lowercase YAML):

   ```bash
   awk '
     /^## Metadata$/ { in_meta=1; next }
     /^## / && in_meta { in_meta=0 }
     in_meta && /^branch:/ { sub(/^branch:[[:space:]]*/, ""); gsub(/[[:space:]]+$/, ""); print; exit }
   ' "$manifest"
   ```

3. **Compare** against `git branch --show-current`. If different, set warn flag.

4. **Dirty-tree heuristic:** `git status --porcelain` — non-empty + warn flag → surface collision.

   *Why this heuristic instead of milestone's `## Owned Files` parse:* feature/bugfix RUN-MANIFESTs do not carry `## Owned Files` (that section is a milestone-only convention per `aih-milestone/annexes/same-file-rule.md` + `merge-back.sh:160-191`). The dirty-tree signal is weaker but available without schema parity.

## Reaction

If warn flag set, surface ONE concrete sentence — no option menus:

> *"Aihaus detectou um manifest rodando em `<manifest-path>` na branch `<other-branch>`. Continuar em `<current-branch>` pode colidir. Continuar?"*

Wait for affirmative ("y" / "sim" / "vai" / "go" / Enter). Anything else aborts the branch op. Per `_shared/autonomy-protocol.md` — single concrete question, no enumerated alternatives, no delegated typing.

## When this check is skipped

- User explicitly said "stay on this branch" / "don't create a branch" — no branch op = no collision possible.
- No running manifests exist anywhere under `.aihaus/{milestones,features,bugfixes}/` — no peer to collide with.
- Working tree is clean — branch creation cannot capture another session's dirty edits.

## Threat model captured

- **Defended:** two concurrent claude sessions creating branches against the same dirty working tree. Pre-flight surfaces the collision; user decides intentionally.
- **NOT defended:** the same scenario where the user dismisses the warn without reading. True fix requires inter-process mutex (deferred to follow-up per ADR-260427-C).
- **NOT defended:** scenario where the OTHER session has already committed and is between operations. The warn still surfaces (a manifest is running) but the dirty-tree signal is silent. Acceptable: the manifest existence alone is the warn driver.

## Audit trail

This check produces no audit log of its own. The downstream `bash-guard.sh` branch-switch detector (ADR-260427-B) writes `.claude/audit/branch-switch-warn.jsonl` for the actual `git checkout` op. Reading both streams together gives full picture: what was about to happen vs what the user authorized.

## Related

- ADR-260427-C — scope rationale (why feature/bugfix-scoped, not extending L1-L4)
- ADR-260427-B — sibling branch-switch soft-warn at the bash-guard layer
- ADR-M017-B — milestone-scoped L1-L4 lock-leak prevention (the full pattern this check is a proportional first step toward)
- `pkg/.aihaus/memory/global/gotchas.md` — concurrent-claude-sessions race entry
