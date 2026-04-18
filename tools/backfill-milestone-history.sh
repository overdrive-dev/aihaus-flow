#!/usr/bin/env bash
# backfill-milestone-history.sh — emit Milestone History table rows from
# .aihaus/milestones/M0NN-*/execution/MILESTONE-SUMMARY.md (or git log fallback).
#
# Usage:
#   bash tools/backfill-milestone-history.sh            # emit all rows (M001–M012 + any others)
#   bash tools/backfill-milestone-history.sh M013       # emit single row for M013
#
# Output: one Markdown table row per milestone to stdout, suitable for pasting
# into the Milestone History table in .aihaus/project.md.
#
# Column schema: | Milestone | Title | Completed | Summary |
# This matches the table header already present in project.md.
#
# Heuristics (in priority order):
#   1. MILESTONE-SUMMARY.md in execution/ — parse Status/Completed/Title fields.
#   2. RUN-MANIFEST.md Metadata.completed_at field.
#   3. git log on the milestone directory (mtime fallback).
#
# Reuse for M013 close:
#   bash tools/backfill-milestone-history.sh M013
# prints the single row; coordinator appends to project.md Milestone History.
#
# M013/S03 — initial population of 12 retrospective rows.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MILESTONES_ROOT="${REPO_ROOT}/.aihaus/milestones"

# ---------------------------------------------------------------------------
# Hardcoded metadata for all 12 pre-M013 milestones. Extracted from
# MILESTONE-SUMMARY.md, CHECK.md, VERIFICATION.md, and git log evidence.
# Using hardcoded values for clean, accurate table rows.
# Keys match the milestone directory slug exactly.
# ---------------------------------------------------------------------------
declare -A _HARDCODED_TITLES
_HARDCODED_TITLES["M001-aih-brainstorm"]="/aih-brainstorm skill + turn-log convention + contrarian agent"
_HARDCODED_TITLES["M002-port-to-cursor-feasibility"]="Cursor coexistence layer (documentation-only, ADR-002)"
_HARDCODED_TITLES["M003-260414-workflow-core-atomicity-invoke"]="Workflow core: ADR-003/004, 4 new hooks, RUN-MANIFEST v2"
_HARDCODED_TITLES["M004-260414-workflow-polish"]="Workflow polish: aih-plan enxugamento + annexes + session-log"
_HARDCODED_TITLES["M005-autonomy-quickwins"]="Autonomy quick wins: autonomy-protocol annex + skill rewiring"
_HARDCODED_TITLES["M006-cursor-native-install"]="Cursor native install: ADR-005, --platform flag, plugin.json"
_HARDCODED_TITLES["M007-260415-autoapprove-windows-cmds"]="Permission-surface triage: deny-list hook + bash-guard fix + ADR-008/009"
_HARDCODED_TITLES["M008-260416-opus-4-7-agent-upgrade"]="Opus 4.7 agent upgrade + /aih-calibrate skill (13th skill)"
_HARDCODED_TITLES["M009-260416-calibrate-survive-update"]="Preserve calibration state across /aih-update via .calibration sidecar"
_HARDCODED_TITLES["M010-260416-cohort-aliases-calibrate-v2"]="Cohort aliases + /aih-calibrate v2: --cohort/--model/--effort CLI"
_HARDCODED_TITLES["M011-260417-autonomy-state-gate"]="Autonomy state gate + milestone statusLine (ADR-M011-A/B)"
_HARDCODED_TITLES["M012-260417-cohorts-effort-automode"]="6-cohort taxonomy + /aih-effort rename + /aih-automode skill"

declare -A _HARDCODED_DATES
_HARDCODED_DATES["M001-aih-brainstorm"]="2026-04-13"
_HARDCODED_DATES["M002-port-to-cursor-feasibility"]="2026-04-14"
_HARDCODED_DATES["M003-260414-workflow-core-atomicity-invoke"]="2026-04-14"
_HARDCODED_DATES["M004-260414-workflow-polish"]="2026-04-14"
_HARDCODED_DATES["M005-autonomy-quickwins"]="2026-04-14"
_HARDCODED_DATES["M006-cursor-native-install"]="2026-04-14"
_HARDCODED_DATES["M007-260415-autoapprove-windows-cmds"]="2026-04-16"
_HARDCODED_DATES["M008-260416-opus-4-7-agent-upgrade"]="2026-04-16"
_HARDCODED_DATES["M009-260416-calibrate-survive-update"]="2026-04-16"
_HARDCODED_DATES["M010-260416-cohort-aliases-calibrate-v2"]="2026-04-17"
_HARDCODED_DATES["M011-260417-autonomy-state-gate"]="2026-04-17"
_HARDCODED_DATES["M012-260417-cohorts-effort-automode"]="2026-04-17"

declare -A _HARDCODED_SUMMARIES
_HARDCODED_SUMMARIES["M001-aih-brainstorm"]="Shipped /aih-brainstorm with 8-phase panel orchestration, contrarian + brainstorm-synthesizer agents, and ADR-001 (files-as-state)."
_HARDCODED_SUMMARIES["M002-port-to-cursor-feasibility"]="Established Cursor coexistence via ADR-002; documented verified/contradicted primitives; compat matrix seeded."
_HARDCODED_SUMMARIES["M003-260414-workflow-core-atomicity-invoke"]="Added invoke-guard, manifest-append, manifest-migrate, phase-advance hooks; RUN-MANIFEST v2 schema; ADR-003/004 accepted."
_HARDCODED_SUMMARIES["M004-260414-workflow-polish"]="Enxugado aih-plan core to 43 lines with 4 annexes; added temp-slug attachment, session-log subcommand, settings placeholder."
_HARDCODED_SUMMARIES["M005-autonomy-quickwins"]="Locked execution-autonomy rules in _shared/autonomy-protocol.md; wired all 13 skills; removed option menus and mid-run gates."
_HARDCODED_SUMMARIES["M006-cursor-native-install"]="Promoted Cursor to first-class install target (ADR-005); install.sh/uninstall.sh --platform flag; plugin.json manifest."
_HARDCODED_SUMMARIES["M007-260415-autoapprove-windows-cmds"]="Flipped auto-approve-bash.sh to deny-list; fixed bash-guard regex; additionalDirectories in settings template; ADR-008/009."
_HARDCODED_SUMMARIES["M008-260416-opus-4-7-agent-upgrade"]="Moved 22 coding/agentic agents to effort:xhigh (Opus 4.7); added /aih-calibrate skill with preset/per-agent/auto-mode-safe tuning."
_HARDCODED_SUMMARIES["M009-260416-calibrate-survive-update"]="Closed two calibration data-loss paths: .calibration sidecar (ADR-M009-A) survives /aih-update across all 4 update paths."
_HARDCODED_SUMMARIES["M010-260416-cohort-aliases-calibrate-v2"]="Introduced 4 cohort aliases (:planner/:doer/:verifier/:adversarial); --cohort/--model/--effort CLI; sidecar schema v2."
_HARDCODED_SUMMARIES["M011-260417-autonomy-state-gate"]="State-driven autonomy guard (regex+haiku backstop+paused short-circuit); statusline-milestone.sh pure reader; ADR-M011-A/B."
_HARDCODED_SUMMARIES["M012-260417-cohorts-effort-automode"]="Renamed /aih-calibrate→/aih-effort; new /aih-automode skill; 6-cohort taxonomy; sidecar .calibration→.effort (schema v3)."

# ---------------------------------------------------------------------------
# _extract_from_summary <summary_file>
# Sets variables: _title _completed _summary
# ---------------------------------------------------------------------------
_extract_from_summary() {
  local file="$1"
  _title="" _completed="" _summary=""

  # Title: first H1 or frontmatter-style "**Title:**" or "Milestone M0NN:..."
  local h1
  h1=$(grep -m1 '^# ' "$file" 2>/dev/null || true)
  if [[ -n "$h1" ]]; then
    _title="${h1#'# '}"
    # Strip "Milestone M0NN — " or "Milestone M0NN: " prefix if present
    _title=$(printf '%s' "$_title" | sed 's/^Milestone M[0-9]\{3\}[-: ]*//' | sed 's/^M[0-9]\{3\} Milestone[—: ]*//' | sed 's/^M[0-9]\{3\}[-: ]*//')
  fi

  # Completed: look for "**Completed:**" or "Completed:" lines
  local comp_line
  comp_line=$(grep -m1 'Completed:' "$file" 2>/dev/null | head -1 || true)
  if [[ -n "$comp_line" ]]; then
    # Extract date portion (YYYY-MM-DD)
    _completed=$(printf '%s' "$comp_line" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || true)
  fi

  # Summary: try "## Goal (delivered)" or "## Summary" or "## What shipped" first para
  local summary_text
  # Try "## Goal (delivered)" section
  summary_text=$(awk '/^## Goal \(delivered\)/{found=1; next} found && /^##/{exit} found && NF{print; exit}' "$file" 2>/dev/null || true)
  if [[ -z "$summary_text" ]]; then
    # Try "## Summary" section
    summary_text=$(awk '/^## Summary/{found=1; next} found && /^##/{exit} found && NF{print; exit}' "$file" 2>/dev/null || true)
  fi
  if [[ -z "$summary_text" ]]; then
    # Try "## What shipped" section
    summary_text=$(awk '/^## What shipped/{found=1; next} found && /^##/{exit} found && NF{print; exit}' "$file" 2>/dev/null || true)
  fi
  if [[ -n "$summary_text" ]]; then
    # Strip markdown bold, truncate to ~120 chars
    _summary=$(printf '%s' "$summary_text" | sed 's/\*\*//g' | sed 's/`//g' | cut -c1-120)
  fi
}

# ---------------------------------------------------------------------------
# _emit_row <milestone_id> <slug> <dir>
# ---------------------------------------------------------------------------
_emit_row() {
  local mid="$1"    # e.g. M001
  local slug="$2"   # e.g. M001-aih-brainstorm
  local dir="$3"    # absolute path to milestone directory

  local title="" completed="" summary=""

  # --- Use hardcoded metadata for known milestones (highest fidelity) ------
  if [[ -v "_HARDCODED_TITLES[$slug]" ]]; then
    title="${_HARDCODED_TITLES[$slug]}"
    completed="${_HARDCODED_DATES[$slug]}"
    summary="${_HARDCODED_SUMMARIES[$slug]}"
  else
    # --- Try MILESTONE-SUMMARY.md -------------------------------------------
    local summary_file="${dir}/execution/MILESTONE-SUMMARY.md"
    if [[ -f "$summary_file" ]]; then
      local _title _completed _summary
      _extract_from_summary "$summary_file"
      title="$_title"
      completed="$_completed"
      summary="$_summary"
    fi

    # --- Fallback: RUN-MANIFEST.md ------------------------------------------
    if [[ -z "$completed" ]]; then
      local manifest="${dir}/RUN-MANIFEST.md"
      if [[ -f "$manifest" ]]; then
        completed=$(grep -m1 'completed_at:' "$manifest" 2>/dev/null | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || true)
      fi
    fi

    # --- Fallback: git log on directory -------------------------------------
    if [[ -z "$completed" ]]; then
      completed=$(git -C "$REPO_ROOT" log --all --follow --format="%ad" --date=short -- \
        ".aihaus/milestones/${slug}/" 2>/dev/null | head -1 || true)
    fi

    # --- Fallback: directory mtime ------------------------------------------
    if [[ -z "$completed" ]]; then
      completed=$(date -r "$dir" '+%Y-%m-%d' 2>/dev/null || date '+%Y-%m-%d')
    fi

    # --- Extract title from slug if still empty ----------------------------
    if [[ -z "$title" ]]; then
      # e.g. "M001-aih-brainstorm" → "aih-brainstorm"
      title=$(printf '%s' "$slug" | sed "s/^${mid}-//" | sed 's/^[0-9]\{6\}-//' | tr '-' ' ')
    fi

    # --- Truncate summary --------------------------------------------------
    if [[ -z "$summary" ]]; then
      summary="(summary not found — see ${slug}/execution/MILESTONE-SUMMARY.md)"
    fi
  fi

  # Sanitize: strip pipe characters that would break the Markdown table
  title="${title//|/∣}"
  summary="${summary//|/∣}"
  # Truncate summary to 120 chars for table readability
  if [[ ${#summary} -gt 120 ]]; then
    summary="${summary:0:117}..."
  fi

  printf '| %s | %s | %s | %s |\n' "$mid" "$title" "$completed" "$summary"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if [[ ! -d "$MILESTONES_ROOT" ]]; then
  printf 'Error: milestones directory not found: %s\n' "$MILESTONES_ROOT" >&2
  printf 'Run from repo root or ensure .aihaus/milestones/ exists.\n' >&2
  exit 1
fi

TARGET_MILESTONE="${1:-}"

if [[ -n "$TARGET_MILESTONE" ]]; then
  # Single milestone mode: find the directory for the given ID
  mid=$(printf '%s' "$TARGET_MILESTONE" | tr '[:lower:]' '[:upper:]')
  found=0
  while IFS= read -r -d '' dir; do
    slug="$(basename "$dir")"
    dir_mid=$(printf '%s' "$slug" | grep -oE '^M[0-9]{3}' || true)
    if [[ "$dir_mid" == "$mid" ]]; then
      _emit_row "$mid" "$slug" "$dir"
      found=1
      break
    fi
  done < <(find "$MILESTONES_ROOT" -maxdepth 1 -type d -name 'M[0-9][0-9][0-9]-*' -print0 | sort -z)
  if [[ "$found" -eq 0 ]]; then
    printf 'Error: no milestone directory found for %s in %s\n' "$mid" "$MILESTONES_ROOT" >&2
    exit 1
  fi
else
  # All milestones mode: emit rows in order
  while IFS= read -r -d '' dir; do
    slug="$(basename "$dir")"
    mid=$(printf '%s' "$slug" | grep -oE '^M[0-9]{3}' || true)
    [[ -z "$mid" ]] && continue
    _emit_row "$mid" "$slug" "$dir"
  done < <(find "$MILESTONES_ROOT" -maxdepth 1 -type d -name 'M[0-9][0-9][0-9]-*' -print0 | sort -z)
fi
