#!/usr/bin/env bash
# restore-calibration.sh — shared library sourced by update.sh and
# install.sh --update. Reads .aihaus/.calibration sidecar (schema v1)
# and re-applies recorded per-agent effort tiers to .aihaus/agents/*.md
# after an agents-directory wipe.
#
# Usage:
#   source "$(dirname "$0")/lib/restore-calibration.sh"
#   restore_calibration "${AIHAUS_DIR}"
#
# Contract:
#   - $1 is the .aihaus root (e.g. "$TARGET/.aihaus"). Must exist.
#   - Missing sidecar = silent no-op (return 0).
#   - Unknown schema = loud warning, no mutation (return 0).
#   - last_preset=auto-mode-safe emits the `!!` warning block on stdout.
#   - All state is confined to function locals — sourcing script's globals
#     are not polluted.
#
# Schema contract: pkg/.aihaus/skills/aih-calibrate/annexes/state-file.md.

restore_calibration() {
  local aihaus_root="$1"
  local state_file="${aihaus_root}/.calibration"
  [[ -f "$state_file" ]] || return 0

  # Schema gate — unknown versions bail with a loud warning, leave defaults.
  local schema
  schema=$(grep -E '^schema=' "$state_file" | head -1 | cut -d= -f2 | tr -d '[:space:]\r')
  if [[ "$schema" != "1" ]]; then
    echo "  warn: unknown .calibration schema='${schema}' — skipping restore"
    return 0
  fi

  local restored=0 skipped=0
  local key value agent_file
  while IFS='=' read -r key value; do
    # Skip blank lines and comments.
    [[ -z "$key" || "$key" =~ ^# ]] && continue
    # Skip metadata keys — only per-agent lines past this point.
    [[ "$key" =~ ^(schema|permission_mode|last_preset|last_commit)$ ]] && continue
    # CRLF normalization — Windows-authored sidecars (F-008).
    value="${value%$'\r'}"
    # Defensive: whitespace-only values skip.
    [[ -z "$value" || "$value" =~ ^[[:space:]]+$ ]] && continue

    agent_file="${aihaus_root}/agents/${key}.md"
    if [[ -f "$agent_file" ]]; then
      sed -i.bak "s/^effort: .*/effort: ${value}/" "$agent_file" && rm -f "${agent_file}.bak"
      restored=$((restored + 1))
    else
      skipped=$((skipped + 1))
      echo "  warn: .calibration references missing agent '${key}' — skipped"
    fi
  done < "$state_file"

  if [[ "$skipped" -gt 0 ]]; then
    echo "  restored ${restored} per-agent effort override(s) from .aihaus/.calibration (${skipped} skipped — missing agents)"
  else
    echo "  restored ${restored} per-agent effort override(s) from .aihaus/.calibration"
  fi

  # Loud warning when auto-mode-safe was the last preset — side effects
  # (auto-approve-bash.sh SAFE_PATTERNS widening + worktree agents'
  # permissionMode removal) are NOT auto-restored and must be re-applied
  # by re-running the preset.
  local last_preset
  last_preset=$(grep -E '^last_preset=' "$state_file" | head -1 | cut -d= -f2 | tr -d '[:space:]\r')
  if [[ "$last_preset" == "auto-mode-safe" ]]; then
    echo ""
    echo "  !!  Your last preset was auto-mode-safe, but side effects"
    echo "  !!  (auto-approve-bash.sh SAFE_PATTERNS widening + worktree"
    echo "  !!  agents' permissionMode removal) are NOT auto-restored."
    echo "  !!  Classifier pauses may occur until you re-run:"
    echo "  !!    /aih-calibrate --preset auto-mode-safe"
    echo ""
  fi
}
