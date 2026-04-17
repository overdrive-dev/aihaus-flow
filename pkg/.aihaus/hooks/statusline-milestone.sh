#!/usr/bin/env bash
# statusline-milestone.sh — pure-reader statusLine emitter for Claude Code.
#
# Emits a single line on stdout: `M0XX · SNN/total · phase:X · agents:N · sha:abc1234`
# when an active milestone RUN-MANIFEST is found; otherwise exits 0 with empty
# stdout. Read-only: no writes, no mkdir, no flock. Worktree-safe by
# construction (no guard needed since no writes).
#
# Q-4 resolution order (M011 architecture § 3.1):
#   1. $MANIFEST_PATH env set + file exists → use it.
#   2. Else glob .aihaus/milestones/M0*/RUN-MANIFEST.md; first with
#      `^status: running` in Metadata → use it.
#   3. Else exit 0 with empty stdout.
#
# F-07 relaxed format regex: accepts sha:none | sha:- | sha:<hex7+> plus `?`
# in the denominator when total-stories is unresolvable (F-08).
#
# Budget: typical ~5 ms on a 100-line manifest; hard cap ~20 ms.

set -uo pipefail

# --- Step 1/2: resolve MANIFEST ---
MANIFEST=""
if [ -n "${MANIFEST_PATH:-}" ] && [ -f "${MANIFEST_PATH}" ]; then
  MANIFEST="$MANIFEST_PATH"
else
  # Fallback glob — first running-status manifest under .aihaus/milestones/
  # Silent on any match error; exit 0 with no output is acceptable per spec.
  for cand in .aihaus/milestones/M0*/RUN-MANIFEST.md; do
    [ -f "$cand" ] || continue
    if awk '/^## Metadata$/ {on=1; next} /^## / {on=0} on && /^status:[[:space:]]*running[[:space:]]*$/ {found=1; exit} END {exit !found}' "$cand" 2>/dev/null; then
      MANIFEST="$cand"
      break
    fi
  done
fi

# Step 3 — no active milestone → exit silent.
[ -n "$MANIFEST" ] || exit 0
[ -f "$MANIFEST" ] || exit 0

# --- parse fields (best-effort; never stderr) ---

# Milestone id from directory name (M0NN-<slug>)
MS_DIR="$(dirname "$MANIFEST")"
MS_ID="$(basename "$MS_DIR" | awk -F- '{print $1}')"
[ -n "$MS_ID" ] || MS_ID="-"

# Metadata.phase
PHASE="$(awk '/^## Metadata$/ {on=1; next} /^## / {on=0} on && /^phase:/ {sub(/^phase:[[:space:]]*/, ""); print; exit}' "$MANIFEST" 2>/dev/null || true)"
PHASE="${PHASE:--}"
# normalize: squash whitespace to single token
PHASE="$(printf '%s' "$PHASE" | tr -d '\r' | awk '{print $1}')"
[ -n "$PHASE" ] || PHASE="-"

# Story Records: count non-empty pipe rows (current = last; we report the count)
SNN="$(awk '
  /^## Story Records$/ {on=1; next}
  /^## / && on {on=0}
  on && /\|/ && $0 !~ /^\|[[:space:]]*-+[[:space:]]*\|/ && $0 !~ /^\|[[:space:]]*story[[:space:]]*\|/ {c++}
  END {print c+0}
' "$MANIFEST" 2>/dev/null || echo 0)"

# Total stories — try PRD first (one dir up from manifest dir's parent)
TOTAL="?"
PRD="$MS_DIR/PRD.md"
if [ -f "$PRD" ]; then
  # Try "## In Scope — N stories" header first.
  T="$(awk 'match($0, /^## In Scope.*[-—][[:space:]]*([0-9]+)[[:space:]]*stor/, m) {print m[1]; exit}' "$PRD" 2>/dev/null || true)"
  if [ -z "$T" ]; then
    # Fallback: count rows in first Rollout/Order table after "## Rollout".
    T="$(awk '
      /^## Rollout/ {in_roll=1; next}
      /^## / && in_roll {exit}
      in_roll && /^\|/ && $0 !~ /^\|[[:space:]]*-+[[:space:]]*\|/ && $0 !~ /^\|[[:space:]]*[Oo]rder[[:space:]]*\|/ {c++}
      END {print c+0}
    ' "$PRD" 2>/dev/null || echo 0)"
  fi
  # Validate: must be numeric and > 0
  case "$T" in
    ''|*[!0-9]*) TOTAL="?" ;;
    0) TOTAL="?" ;;
    *) TOTAL="$T" ;;
  esac
fi

# Invoke stack depth
AGENTS="$(awk '
  /^## Invoke stack$/ {on=1; next}
  /^## / && on {on=0}
  on && /\|/ && $0 !~ /^\|[[:space:]]*-+[[:space:]]*\|/ && $0 !~ /^\|[[:space:]]*skill[[:space:]]*\|/ {c++}
  END {print c+0}
' "$MANIFEST" 2>/dev/null || echo 0)"

# Short SHA
SHA="$(git rev-parse --short HEAD 2>/dev/null || echo none)"
case "$SHA" in
  ''|*[!a-f0-9]*) SHA="none" ;;
esac

# --- emit (single line, middle-dot separator per spec) ---
# Format: M0XX · SNN/total · phase:X · agents:N · sha:abc1234
printf 'M%s · S%s/%s · phase:%s · agents:%s · sha:%s\n' \
  "${MS_ID#M}" "$SNN" "$TOTAL" "$PHASE" "$AGENTS" "$SHA"
exit 0
