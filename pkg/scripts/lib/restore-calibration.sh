#!/usr/bin/env bash
# restore-calibration.sh — shared library sourced by update.sh and
# install.sh --update. Reads .aihaus/.calibration sidecar (schema v1
# legacy or v2 cohort-aware) and re-applies recorded calibration state
# to .aihaus/agents/*.md after an agents-directory wipe.
#
# Usage:
#   source "$(dirname "$0")/lib/restore-calibration.sh"
#   restore_calibration "${AIHAUS_DIR}"
#
# Contract:
#   - $1 is the .aihaus root (e.g. "$TARGET/.aihaus"). Must exist.
#   - Missing sidecar = silent no-op (return 0).
#   - schema=1 → legacy effort-only restore (byte-identical to v0.13.0)
#   - schema=2 → cohort-level apply first, per-agent overrides second
#   - Unknown schema = loud warning, no mutation (return 0).
#   - last_preset=auto-mode-safe emits the `!!` warning block on stdout.
#   - All state is confined to function locals — sourcing script's globals
#     are not polluted.
#
# Schema contract: <aihaus_root>/skills/aih-calibrate/annexes/state-file.md.
# Cohort membership (v2): <aihaus_root>/skills/aih-calibrate/annexes/cohorts.md.

restore_calibration() {
  local aihaus_root="$1"
  local state_file="${aihaus_root}/.calibration"
  [[ -f "$state_file" ]] || return 0

  # Schema gate — dispatch on version; unknown bails loudly.
  local schema
  schema=$(grep -E '^schema=' "$state_file" | head -1 | cut -d= -f2 | tr -d '[:space:]\r')
  if [[ "$schema" == "1" ]]; then
    _restore_calibration_v1 "$aihaus_root" "$state_file"
  elif [[ "$schema" == "2" ]]; then
    _restore_calibration_v2 "$aihaus_root" "$state_file"
  else
    echo "  warn: unknown .calibration schema='${schema}' — skipping restore"
    return 0
  fi

  # Loud warning when auto-mode-safe was the last preset — side effects
  # (auto-approve-bash.sh SAFE_PATTERNS widening + worktree agents'
  # permissionMode removal) are NOT auto-restored.
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

# Schema v1 — legacy effort-only per-agent restore. Byte-identical to
# v0.13.0 behavior (Check 27 A1-A4 is the guard; do NOT refactor).
_restore_calibration_v1() {
  local aihaus_root="$1"
  local state_file="$2"
  local restored=0 skipped=0
  local key value agent_file
  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^# ]] && continue
    [[ "$key" =~ ^(schema|permission_mode|last_preset|last_commit)$ ]] && continue
    value="${value%$'\r'}"
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
}

# Schema v2 — cohort-level (model, effort) apply first; per-agent
# overrides (<agent>.model=<m>, <agent>=<effort>) applied second so they
# win on conflict (apply-order semantics per ADR-M010-A). Cohort
# membership resolved from <aihaus_root>/skills/aih-calibrate/annexes/cohorts.md
# at runtime. ADR-M009-A absolute-restore preserved verbatim.
_restore_calibration_v2() {
  local aihaus_root="$1"
  local state_file="$2"
  local cohorts_md="${aihaus_root}/skills/aih-calibrate/annexes/cohorts.md"
  local restored=0 skipped=0
  local key value

  # Pass 1 — cohort-level apply. Missing cohorts.md → warn + skip this
  # pass (per-agent overrides still applied in Pass 2).
  if [[ ! -f "$cohorts_md" ]]; then
    echo "  warn: cohorts.md missing at ${cohorts_md} — skipping cohort-level restore; per-agent overrides still applied"
  else
    while IFS='=' read -r key value; do
      [[ -z "$key" || "$key" =~ ^# ]] && continue
      [[ "$key" =~ ^cohort\.(planner|doer|verifier|adversarial)\.(model|effort)$ ]] || continue
      value="${value%$'\r'}"
      [[ -z "$value" || "$value" =~ ^[[:space:]]+$ ]] && continue
      [[ "$value" == "custom" ]] && continue   # D-4 fallback: defer to per-agent

      local cohort_name field
      cohort_name="${key#cohort.}"
      field="${cohort_name#*.}"
      cohort_name="${cohort_name%.*}"

      # Extract cohort members from cohorts.md 5-col pipe-table layout.
      # Defensive strip: trailing non-[a-z:] chars from cohort column
      # (in case analyst-brief flag annotations ever slip through).
      local members
      members=$(awk -v c=":${cohort_name}" '
        /^\| +[0-9]+ +\|/ {
          split($0, f, "|")
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", f[3])
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", f[4])
          gsub(/[^a-z:]+$/, "", f[4])
          if (f[4] == c) { print f[3] }
        }
      ' "$cohorts_md")

      local member agent_file
      while IFS= read -r member; do
        [[ -z "$member" ]] && continue
        agent_file="${aihaus_root}/agents/${member}.md"
        if [[ -f "$agent_file" ]]; then
          if [[ "$field" == "model" ]]; then
            sed -i.bak "s/^model: .*/model: ${value}/" "$agent_file" && rm -f "${agent_file}.bak"
          else
            sed -i.bak "s/^effort: .*/effort: ${value}/" "$agent_file" && rm -f "${agent_file}.bak"
          fi
          restored=$((restored + 1))
        else
          skipped=$((skipped + 1))
          echo "  warn: .calibration cohort '${cohort_name}' references missing agent '${member}' — skipped"
        fi
      done <<< "$members"
    done < "$state_file"
  fi

  # Pass 2 — per-agent overrides (win over cohort-level via apply order).
  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^# ]] && continue
    [[ "$key" =~ ^(schema|permission_mode|last_preset|last_commit)$ ]] && continue
    value="${value%$'\r'}"
    [[ -z "$value" || "$value" =~ ^[[:space:]]+$ ]] && continue

    # Skip cohort.* — already handled in Pass 1. Unknown cohort names warn.
    if [[ "$key" =~ ^cohort\. ]]; then
      if ! [[ "$key" =~ ^cohort\.(planner|doer|verifier|adversarial)\.(model|effort)$ ]]; then
        local bad
        bad="${key#cohort.}"
        bad="${bad%.*}"
        echo "  warn: .calibration references unknown cohort '${bad}' — skipped"
        skipped=$((skipped + 1))
      fi
      continue
    fi

    # Detect dotted-key per-agent model override (<agent>.model=<m>)
    # vs. v1-compat effort entry (<agent>=<effort>).
    local agent field agent_file
    if [[ "$key" == *.model ]]; then
      agent="${key%.model}"
      field="model"
    else
      agent="$key"
      field="effort"
    fi

    agent_file="${aihaus_root}/agents/${agent}.md"
    if [[ -f "$agent_file" ]]; then
      if [[ "$field" == "model" ]]; then
        sed -i.bak "s/^model: .*/model: ${value}/" "$agent_file" && rm -f "${agent_file}.bak"
      else
        sed -i.bak "s/^effort: .*/effort: ${value}/" "$agent_file" && rm -f "${agent_file}.bak"
      fi
      restored=$((restored + 1))
    else
      skipped=$((skipped + 1))
      echo "  warn: .calibration references missing agent '${agent}' — skipped"
    fi
  done < "$state_file"

  if [[ "$skipped" -gt 0 ]]; then
    echo "  restored ${restored} calibration entry(ies) from .aihaus/.calibration (${skipped} skipped — missing agents/cohorts)"
  else
    echo "  restored ${restored} calibration entry(ies) from .aihaus/.calibration"
  fi
}
