#!/usr/bin/env bash
# restore-effort.sh — shared library sourced by update.sh and
# install.sh --update. Reads .aihaus/.calibration (schema v2),
# .aihaus/.effort (schema v3), or .aihaus/.effort (schema v4) and
# re-applies recorded calibration state to .aihaus/agents/*.md after
# an agents-directory wipe.
#
# ADR references: ADR-M012-A (schema v3, 6-cohort taxonomy, migration),
#                 ADR-M009-A (sidecar ownership, absolute-restore, record-defer),
#                 ADR-260509-Y (schema v4, 5-cohort fork, v3→v4 migration).
#
# Usage:
#   source "$(dirname "$0")/lib/restore-effort.sh"
#   restore_effort "${AIHAUS_DIR}"
#
# Contract:
#   - $1 is the .aihaus root (e.g. "$TARGET/.aihaus"). Must exist.
#   - Missing sidecar = silent no-op (return 0).
#   - schema=4 -> v4 idempotent restore (5-cohort taxonomy, ADR-260509-Y).
#   - schema=3 -> v3 idempotent restore (6-cohort, read-compat through M028).
#     v3->v4 migration is triggered ONLY by update.sh post-M027 or aih-effort --status.
#   - schema=2 -> v2->v3 migration path (writes .effort, renames .calibration to .calibration.v2.bak).
#   - Unknown/missing schema = loud !! warning, no mutation (return 0).
#   - All state is confined to function locals -- sourcing script's globals
#     are not polluted.
#
# Schema contract: <aihaus_root>/skills/aih-effort/annexes/state-file.md.
# Cohort membership (v4/v3): <aihaus_root>/skills/aih-effort/annexes/cohorts.md.
#
# ---- Migration table (v2 -> v3) -------------------------------------------
# v2 field                          v3 destination                      Lossy? Warning shape
# schema=2                          schema=3                            no     silent
# permission_mode=bypassPermissions DROPPED                             no     silent
# permission_mode=auto              DROPPED + .automode enabled=true    yes    !! 4-line block (see restore-effort.sh emit block)
# last_preset=cost-optimized        last_preset=cost + verbatim effort  yes    !! effort-delta note per shifted cohort (FR-M10)
# last_preset=balanced              last_preset=balanced                no     silent
# last_preset=quality-first         last_preset=high + verbatim effort  yes    !! effort-delta note per shifted cohort (FR-M10)
# last_preset=auto-mode-safe        last_preset=balanced + .automode    yes    3-line !! block (see restore-effort.sh emit block)
# last_preset=performatic/unknown   last_preset=balanced                yes    1-line !! warn
# last_commit=<sha>                 last_commit=<sha>                   no     silent
# cohort.planner.model=X            cohort.planner-binding.model=X ONLY yes    !! planner-split warn (FR-M05)
# cohort.planner.effort=X           cohort.planner-binding.effort=X ONLY yes   !! planner-split warn (same block)
# cohort.doer.model=X               cohort.doer.model=X                 no     silent
# cohort.doer.effort=X              cohort.doer.effort=X                no     silent
# cohort.verifier.model=X           cohort.verifier.model=X             no     silent
# cohort.verifier.effort=X          cohort.verifier.effort=X            no     silent
# cohort.investigator.model=X       debugger.model=X + debug-session-manager.model=X + user-profiler.model=X  yes  !! investigator-deletion warn (FR-M06)
# cohort.investigator.effort=X      debugger=X + debug-session-manager=X + user-profiler=X                    yes  !! investigator-deletion warn (same block)
# cohort.adversarial.model=X        cohort.adversarial-scout.model=X ONLY  yes  !! adversarial-split warn (FR-M05 shape)
# cohort.adversarial.effort=X       cohort.adversarial-scout.effort=X ONLY yes  !! adversarial-split warn (same block)
# <agent>=<effort> (per-agent)      <agent>=<effort>                    no     silent
# <agent>.model=<m> (per-agent)     <agent>.model=<m>                   no     silent
#
# ---- Migration table (v3 -> v4) -------------------------------------------
# v3 field                             v4 destination                      Lossy? Warning shape
# schema=3                             schema=4                            no     silent
# cohort.adversarial-scout.model=X     cohort.adversarial.model=X          yes    INFO row in migration log
# cohort.adversarial-scout.effort=X    cohort.adversarial.effort=high       yes    INFO row (effort demoted to baseline high; per-agent max injected)
# cohort.adversarial-review.model=X    cohort.adversarial.model=X (if unset) yes  INFO row
# cohort.adversarial-review.effort=X   cohort.adversarial.effort=X          no     silent (if high)
# conflict: scout.effort != review.effort  ABORT + stable error grammar     yes    !! CONFLICT block
# plan-checker=<effort> (per-agent)    plan-checker=max INJECTED if absent  yes    INFO row (preset-immunity preservation)
# contrarian=<effort> (per-agent)      contrarian=max INJECTED if absent    yes    INFO row (same)
# plan-calibrator=<effort> (per-agent) plan-calibrator=max INJECTED if absent yes  INFO row (same)
# all other fields                     verbatim passthrough                  no     silent
#
# Preset effort-distribution delta reference (for FR-M10 warning):
#   cost-optimized -> cost:
#     :planner (opus, high) -> (opus, medium)    [effort shift]
#     :doer    (sonnet, high) -> (sonnet, medium) [effort shift]
#     :verifier (haiku, medium) -> no shift
#   quality-first -> high:
#     :planner-binding (opus, max) -> no shift
#     :planner (opus, max) -> (opus, xhigh)      [effort shift]
#     :doer (sonnet, high) -> no shift
#     :verifier (haiku, high) -> no shift
# ---------------------------------------------------------------------------

# ============================================================================
# is_preset_immune -- AUTHORITATIVE HELPER (F-010 resolution, R3 mitigation)
# Returns 0 (immune) for :adversarial (v4) and legacy v3 scout/review names.
# This is the SINGLE definition. All preset-write call sites MUST use this helper.
# No scattered `if cohort == "adversarial"` literals permitted (ADR-M012-A /
# ADR-260509-Y).
#
# v4 canonical name: :adversarial (merged from v3 :adversarial-scout +
# :adversarial-review per M027/S10 6→5 cohort fork).
# Legacy v3 names retained during 1-milestone deprecation window (M028).
#
# Post-S10 verification: rg '^is_preset_immune' pkg/scripts/ pkg/.aihaus/ = 1 match.
# PowerShell equivalent: Test-PresetImmune in pkg/scripts/install.ps1.
# ============================================================================
is_preset_immune() {
  local cohort="$1"
  case "$cohort" in
    :adversarial|adversarial) return 0 ;;
    # Legacy v3 names — retained through M028 deprecation window.
    :adversarial-scout|adversarial-scout) return 0 ;;
    :adversarial-review|adversarial-review) return 0 ;;
    *) return 1 ;;
  esac
}

restore_effort() {
  local aihaus_root="$1"
  local v2_file="${aihaus_root}/.calibration"
  local v3_file="${aihaus_root}/.effort"

  # Prefer v3 file if present; fall back to v2 for migration path.
  local state_file="" detected_schema=""

  if [[ -f "$v3_file" ]]; then
    state_file="$v3_file"
    detected_schema=$(grep -E '^schema=' "$v3_file" | head -1 | cut -d= -f2 | tr -d '[:space:]\r')
  elif [[ -f "$v2_file" ]]; then
    state_file="$v2_file"
    detected_schema=$(grep -E '^schema=' "$v2_file" | head -1 | cut -d= -f2 | tr -d '[:space:]\r')
  else
    return 0   # No sidecar -- silent no-op.
  fi

  if [[ -z "$detected_schema" ]]; then
    echo "  !!" >&2
    echo "  !!  Sidecar has no schema= line (pre-v1 file -- extremely rare)." >&2
    echo "  !!  Cannot auto-migrate. Delete ${state_file} and re-run:" >&2
    echo "  !!    /aih-effort --preset balanced" >&2
    echo "  !!" >&2
    return 0
  fi

  if [[ "$detected_schema" == "4" ]]; then
    # Idempotent v4 restore.
    _restore_effort_v4 "$aihaus_root" "$v3_file"
  elif [[ "$detected_schema" == "3" ]]; then
    # Idempotent v3 restore (read-compat through M028 deprecation window).
    # v3→v4 migration is triggered ONLY by update.sh post-M027 refresh or
    # by /aih-effort --status — NOT by a plain restore_effort call.
    # This keeps Check 29 idempotence invariant intact.
    _restore_effort_v4 "$aihaus_root" "$v3_file"
  elif [[ "$detected_schema" == "2" ]]; then
    # Migrate v2 -> v3 only (single-step). v3→v4 migration fires on next
    # explicit trigger (update.sh / aih-effort --status).
    _migrate_v2_to_v3 "$aihaus_root" "$v2_file" "$v3_file"
    if [[ -f "$v3_file" ]]; then
      _restore_effort_v4 "$aihaus_root" "$v3_file"
    fi
  else
    echo "  !!" >&2
    echo "  !!  Unknown sidecar schema='${detected_schema}' -- skipping restore." >&2
    echo "  !!  Delete the sidecar and re-run: /aih-effort --preset balanced" >&2
    echo "  !!" >&2
    return 0
  fi
}

# ============================================================================
# _migrate_v2_to_v3 -- v2 .calibration -> v3 .effort migration
# Writes new .effort, emits lossy-case !! warnings, renames original to .v2.bak.
# Does NOT auto-replay permission-mode side effects (ADR-M009-A record-defer).
# ============================================================================
_migrate_v2_to_v3() {
  local aihaus_root="$1"
  local v2_file="$2"
  local v3_file="$3"
  local tmp_file="${v3_file}.tmp"

  # ---- Parse all v2 fields --------------------------------------------------
  local v2_last_preset="" v2_last_commit="" v2_permission_mode=""
  local v2_planner_model="" v2_planner_effort=""
  local v2_doer_model="" v2_doer_effort=""
  local v2_verifier_model="" v2_verifier_effort=""
  local v2_investigator_model="" v2_investigator_effort=""
  local v2_adversarial_model="" v2_adversarial_effort=""
  # Per-agent overrides stored as lines for passthrough.
  local per_agent_effort_lines="" per_agent_model_lines=""

  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    value="${value%$'\r'}"
    [[ -z "$value" || "$value" =~ ^[[:space:]]+$ ]] && continue

    # Rebuild the value from everything after first '=' (in case value has '=').
    # (IFS='=' read -r key value already does max 2 splits correctly for simple keys.)
    case "$key" in
      schema)                     ;;   # Skip -- we know it's 2.
      last_preset)                v2_last_preset="$value" ;;
      last_commit)                v2_last_commit="$value" ;;
      permission_mode)            v2_permission_mode="$value" ;;
      cohort.planner.model)       v2_planner_model="$value" ;;
      cohort.planner.effort)      v2_planner_effort="$value" ;;
      cohort.doer.model)          v2_doer_model="$value" ;;
      cohort.doer.effort)         v2_doer_effort="$value" ;;
      cohort.verifier.model)      v2_verifier_model="$value" ;;
      cohort.verifier.effort)     v2_verifier_effort="$value" ;;
      cohort.investigator.model)  v2_investigator_model="$value" ;;
      cohort.investigator.effort) v2_investigator_effort="$value" ;;
      cohort.adversarial.model)   v2_adversarial_model="$value" ;;
      cohort.adversarial.effort)  v2_adversarial_effort="$value" ;;
      cohort.*)
        # Unknown v2 cohort -- skip (forward-compat).
        ;;
      *.model)
        per_agent_model_lines="${per_agent_model_lines}${key}=${value}"$'\n'
        ;;
      *)
        # Everything else is a per-agent effort entry.
        per_agent_effort_lines="${per_agent_effort_lines}${key}=${value}"$'\n'
        ;;
    esac
  done < "$v2_file"

  # ---- Derive v3 last_preset + collect drift note --------------------------
  local v3_last_preset="balanced"
  local preset_drift_note=""
  case "$v2_last_preset" in
    balanced)       v3_last_preset="balanced" ;;
    cost-optimized)
      v3_last_preset="cost"
      # FR-M10: effort distribution shifts between cost-optimized and cost.
      preset_drift_note="cost-optimized renamed to 'cost'; effort defaults shifted:"$'\n'"  !!    :planner high->medium; :doer high->medium"
      ;;
    quality-first)
      v3_last_preset="high"
      # FR-M10: quality-first renamed to 'high'; planner effort max->xhigh.
      preset_drift_note="quality-first renamed to 'high'; effort defaults shifted:"$'\n'"  !!    :planner max->xhigh"
      ;;
    auto-mode-safe) v3_last_preset="balanced" ;;
    "")             v3_last_preset="balanced" ;;
    *)
      v3_last_preset="balanced"
      echo "" >&2
      echo "  !!  v2 sidecar had unknown last_preset='${v2_last_preset}' -- reset to balanced." >&2
      echo "  !!" >&2
      ;;
  esac

  # ---- Compute lossy flags --------------------------------------------------
  local planner_lossy=0 adversarial_lossy=0 investigator_lossy=0

  [[ -n "$v2_planner_model" || -n "$v2_planner_effort" ]]         && planner_lossy=1
  [[ -n "$v2_adversarial_model" || -n "$v2_adversarial_effort" ]] && adversarial_lossy=1
  [[ -n "$v2_investigator_model" || -n "$v2_investigator_effort" ]] && investigator_lossy=1

  # ---- Write v3 .effort.tmp ------------------------------------------------
  local migration_ts
  migration_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u '+%Y-%m-%dT%H:%M:%SZ')"
  {
    printf '# aihaus effort state -- managed by /aih-effort, consumed by /aih-update\n'
    printf '# Schema: v3 -- 6 uniform cohorts + per-agent overrides\n'
    printf '# This file is USER-OWNED and derived state. Safe to delete. Do not commit.\n'
    printf '# Migrated from schema v2 (.calibration) on %s\n' "$migration_ts"
    printf '\n'
    printf 'schema=3\n'
    printf 'last_preset=%s\n' "$v3_last_preset"
    [[ -n "$v2_last_commit" ]] && printf 'last_commit=%s\n' "$v2_last_commit"
    printf '\n'
    printf '# Cohort-level rows (migrated from v2)\n'

    # planner -> planner-binding ONLY (lossy split, FR-M05).
    [[ -n "$v2_planner_model" ]]  && printf 'cohort.planner-binding.model=%s\n' "$v2_planner_model"
    [[ -n "$v2_planner_effort" ]] && printf 'cohort.planner-binding.effort=%s\n' "$v2_planner_effort"

    # doer -- direct passthrough.
    [[ -n "$v2_doer_model" ]]   && printf 'cohort.doer.model=%s\n' "$v2_doer_model"
    [[ -n "$v2_doer_effort" ]]  && printf 'cohort.doer.effort=%s\n' "$v2_doer_effort"

    # verifier -- direct passthrough.
    [[ -n "$v2_verifier_model" ]]  && printf 'cohort.verifier.model=%s\n' "$v2_verifier_model"
    [[ -n "$v2_verifier_effort" ]] && printf 'cohort.verifier.effort=%s\n' "$v2_verifier_effort"

    # adversarial -> adversarial-scout ONLY (lossy split, FR-M05 shape).
    [[ -n "$v2_adversarial_model" ]]  && printf 'cohort.adversarial-scout.model=%s\n' "$v2_adversarial_model"
    [[ -n "$v2_adversarial_effort" ]] && printf 'cohort.adversarial-scout.effort=%s\n' "$v2_adversarial_effort"

    # investigator -> per-agent overrides (lossy deletion, FR-M06).
    if [[ "$investigator_lossy" -eq 1 ]]; then
      printf '\n'
      printf '# investigator cohort deleted in v3 -- re-emitted as per-agent overrides (FR-M06)\n'
      [[ -n "$v2_investigator_model" ]]  && printf 'debugger.model=%s\n' "$v2_investigator_model"
      [[ -n "$v2_investigator_model" ]]  && printf 'debug-session-manager.model=%s\n' "$v2_investigator_model"
      [[ -n "$v2_investigator_model" ]]  && printf 'user-profiler.model=%s\n' "$v2_investigator_model"
      [[ -n "$v2_investigator_effort" ]] && printf 'debugger=%s\n' "$v2_investigator_effort"
      [[ -n "$v2_investigator_effort" ]] && printf 'debug-session-manager=%s\n' "$v2_investigator_effort"
      [[ -n "$v2_investigator_effort" ]] && printf 'user-profiler=%s\n' "$v2_investigator_effort"
    fi

    # Per-agent effort overrides passthrough.
    if [[ -n "$per_agent_effort_lines" ]]; then
      printf '\n'
      printf '# Per-agent effort overrides\n'
      printf '%s' "$per_agent_effort_lines"
    fi

    # Per-agent model overrides passthrough.
    if [[ -n "$per_agent_model_lines" ]]; then
      printf '\n'
      printf '# Per-agent model overrides\n'
      printf '%s' "$per_agent_model_lines"
    fi
  } > "$tmp_file"

  # ---- Emit .automode if auto-mode-safe or permission_mode=auto (FR-M07) ---
  if [[ "$v2_last_preset" == "auto-mode-safe" || "$v2_permission_mode" == "auto" ]]; then
    local automode_file="${aihaus_root}/.automode"
    {
      printf 'enabled=true\n'
      printf 'last_enabled_at=%s\n' "$migration_ts"
    } > "$automode_file"
  fi

  # ---- Atomic swap: tmp -> v3, rename v2 to .v2.bak -----------------------
  mv "$tmp_file" "$v3_file"
  mv "$v2_file" "${v2_file}.v2.bak"

  echo "  migrated .aihaus/.calibration -> .aihaus/.effort (schema v2 -> v3)"

  # ---- Emit lossy-case !! warnings to stderr (FR-M05, FR-M06, FR-M07, FR-M10) -
  if [[ "$planner_lossy" -eq 1 ]]; then
    echo "" >&2
    echo "  !!  v2 sidecar had cohort.planner.* settings (planner cohort split -- FR-M05)." >&2
    echo "  !!  Applied to :planner-binding ONLY (4 agents: architect, planner," >&2
    echo "  !!    product-manager, roadmapper)." >&2
    echo "  !!  :planner (13 agents) remains at v3 balanced default." >&2
    echo "  !!  To also calibrate :planner, run: /aih-effort --cohort :planner --effort <X>" >&2
    echo "" >&2
  fi

  if [[ "$adversarial_lossy" -eq 1 ]]; then
    echo "" >&2
    echo "  !!  v2 sidecar had cohort.adversarial.* settings (adversarial split -- FR-M05)." >&2
    echo "  !!  Applied to :adversarial-scout ONLY (contrarian, plan-checker)." >&2
    echo "  !!  :adversarial-review (reviewer, code-reviewer) stays at v3 balanced default." >&2
    echo "  !!  To mirror to review tier: /aih-effort --cohort :adversarial-review --effort <X>" >&2
    echo "" >&2
  fi

  if [[ "$investigator_lossy" -eq 1 ]]; then
    echo "" >&2
    echo "  !!  v2 sidecar had cohort.investigator.* settings (cohort deleted -- FR-M06)." >&2
    echo "  !!  :investigator removed in v3; settings preserved as per-agent overrides for:" >&2
    echo "  !!    debugger, debug-session-manager, user-profiler" >&2
    echo "  !!  Review .aihaus/.effort to confirm these overrides are still intended." >&2
    echo "" >&2
  fi

  if [[ "$v2_last_preset" == "auto-mode-safe" || "$v2_permission_mode" == "auto" ]]; then
    echo "" >&2
    echo "  !!  v2 sidecar had last_preset=auto-mode-safe." >&2
    echo "  !!    State migrated to .aihaus/.automode (enabled=true)." >&2
    echo "  !!    Side effects (defaultMode=auto, worktree frontmatter, SAFE_PATTERNS) are NOT replayed." >&2
    echo "  !!    Permission auto-mode removed in v0.18.0/M014. Use bash .aihaus/auto.sh for DSP launch." >&2
    echo "" >&2
  fi

  if [[ -n "$preset_drift_note" ]]; then
    echo "" >&2
    echo "  !!  Preset renamed during migration -- effort distribution may differ:" >&2
    echo "  !!    ${preset_drift_note}" >&2
    echo "  !!  Absolute per-cohort values from v2 were preserved verbatim (ADR-M009-A)." >&2
    echo "  !!  To apply v3 preset defaults: /aih-effort --preset ${v3_last_preset}" >&2
    echo "" >&2
  fi
}

# ============================================================================
# _restore_effort_v3 -- idempotent v3 restore loop (legacy, read-compat through M028)
# v3 sidecars are restored idempotently via _restore_effort_v4 (which accepts
# v3 cohort names during the deprecation window). v3→v4 migration is NOT triggered
# by a plain restore_effort call — only by update.sh post-M027 or aih-effort --status.
# Pass 1: cohort-level (model, effort) apply (skipping preset-immune via helper).
# Pass 2: per-agent overrides -- always win over cohort-level (apply-order ADR-M012-A).
# ============================================================================
_restore_effort_v3() {
  local aihaus_root="$1"
  local state_file="$2"
  # v3 cohort names accepted by _restore_effort_v4 during M028 deprecation window.
  _restore_effort_v4 "$aihaus_root" "$state_file"
}

# ============================================================================
# _restore_effort_v4 -- idempotent v4 restore loop (ADR-260509-Y, M027/S10)
# Accepts both v4 cohort names (:adversarial) and legacy v3 names
# (:adversarial-scout, :adversarial-review) during M028 deprecation window.
# Pass 1: cohort-level (model, effort) apply (skipping preset-immune via helper).
# Pass 2: per-agent overrides -- always win over cohort-level (apply-order ADR-M012-A).
# ============================================================================
_restore_effort_v4() {
  local aihaus_root="$1"
  local state_file="$2"
  local cohorts_md="${aihaus_root}/skills/aih-effort/annexes/cohorts.md"
  local restored=0 skipped=0
  local key value

  # Pass 1 -- cohort-level apply. Missing cohorts.md -> warn + skip pass.
  if [[ ! -f "$cohorts_md" ]]; then
    echo "  warn: cohorts.md missing at ${cohorts_md} -- skipping cohort-level restore; per-agent overrides still applied"
  else
    while IFS='=' read -r key value; do
      [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
      # Accept v4 cohort names (5) + legacy v3 names during deprecation window.
      [[ "$key" =~ ^cohort\.(planner-binding|planner|doer|verifier|adversarial|adversarial-scout|adversarial-review)\.(model|effort)$ ]] || continue
      value="${value%$'\r'}"
      [[ -z "$value" || "$value" =~ ^[[:space:]]+$ ]] && continue
      [[ "$value" == "custom" ]] && continue  # Defer to per-agent overrides.

      local cohort_name field
      cohort_name="${key#cohort.}"
      # field is the last dot-segment (model or effort).
      field="${cohort_name##*.}"
      cohort_name="${cohort_name%.*}"

      # Skip preset-immune cohorts (is_preset_immune helper -- R3 / ADR-M012-A / ADR-260509-Y).
      if is_preset_immune "$cohort_name"; then
        continue
      fi

      # Normalize legacy v3 cohort names to v4 canonical name.
      case "$cohort_name" in
        adversarial-scout|adversarial-review) cohort_name="adversarial" ;;
      esac

      # Extract members from cohorts.md 5-col pipe-table.
      # Column layout: | # | Agent | Cohort | Model | Effort |
      # Cohort column (f[4]) matches :<cohort_name> exactly.
      local members
      members=$(awk -v c=":${cohort_name}" '
        /^\| +[0-9]+ +\|/ {
          split($0, f, "|")
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", f[3])
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", f[4])
          gsub(/[^a-z:_-]+$/, "", f[4])
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
          echo "  warn: .effort cohort '${cohort_name}' references missing agent '${member}' -- skipped"
        fi
      done <<< "$members"
    done < "$state_file"
  fi

  # Pass 2 -- per-agent overrides (win over cohort-level via apply order).
  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    [[ "$key" =~ ^(schema|last_preset|last_commit)$ ]] && continue
    value="${value%$'\r'}"
    [[ -z "$value" || "$value" =~ ^[[:space:]]+$ ]] && continue

    # Skip cohort.* -- handled in Pass 1. Warn on unknown cohort names
    # (warn for anything not in v4 5-set + legacy v3 names).
    if [[ "$key" =~ ^cohort\. ]]; then
      if ! [[ "$key" =~ ^cohort\.(planner-binding|planner|doer|verifier|adversarial|adversarial-scout|adversarial-review)\.(model|effort)$ ]]; then
        local bad
        bad="${key#cohort.}"
        bad="${bad%.*}"
        echo "  warn: .effort references unknown cohort '${bad}' -- skipped"
        skipped=$((skipped + 1))
      fi
      continue
    fi

    # Dotted per-agent model vs. effort entry.
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
      echo "  warn: .effort references missing agent '${agent}' -- skipped"
    fi
  done < "$state_file"

  if [[ "$skipped" -gt 0 ]]; then
    echo "  restored ${restored} effort entry(ies) from .aihaus/.effort (${skipped} skipped -- missing agents/cohorts)"
  else
    echo "  restored ${restored} effort entry(ies) from .aihaus/.effort"
  fi
}

# ============================================================================
# _migrate_v3_to_v4 -- v3 .effort -> v4 .effort migration (ADR-260509-Y)
# Folds :adversarial-scout + :adversarial-review → :adversarial.
# Preserves/injects per-agent effort=max for plan-checker, contrarian, plan-calibrator.
# Writes .effort.v3.backup BEFORE any mutation. Aborts on parse fail.
# ============================================================================
_migrate_v3_to_v4() {
  local aihaus_root="$1"
  local v3_file="$2"
  local v4_file="$3"
  local v3_backup="$4"
  local tmp_file="${v4_file}.v4.tmp"

  # ---- Step 1: Abort on parse fail check ------------------------------------
  # Scan for malformed lines (non-comment, non-blank, no '=' separator).
  local line_num=0 parse_error=0
  while IFS= read -r raw_line; do
    line_num=$((line_num + 1))
    # Strip CRLF.
    local line="${raw_line%$'\r'}"
    # Skip blank lines and comments.
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    # Every non-blank non-comment line must contain '='.
    if [[ "$line" != *=* ]]; then
      echo "  !!" >&2
      echo "  !!  v3 sidecar parse fail at line ${line_num}: '${line}'" >&2
      echo "  !!  No '=' separator found. Migration aborted. v3 file preserved." >&2
      echo "  !!" >&2
      parse_error=1
      break
    fi
  done < "$v3_file"
  if [[ "$parse_error" -eq 1 ]]; then
    return 1
  fi

  # ---- Step 2: Write .effort.v3.backup BEFORE mutation ----------------------
  if ! cp "$v3_file" "$v3_backup"; then
    echo "  !!" >&2
    echo "  !!  Could not write v3 backup at ${v3_backup}. Migration aborted." >&2
    echo "  !!" >&2
    return 1
  fi

  # ---- Step 3: Parse v3 fields ----------------------------------------------
  local v3_last_preset="" v3_last_commit=""
  local v3_scout_model="" v3_scout_effort=""
  local v3_review_model="" v3_review_effort=""
  local per_agent_effort_lines="" per_agent_model_lines=""
  # Track preset-immune per-agent overrides for injection check.
  local has_plan_checker_effort=0 has_contrarian_effort=0 has_plan_calibrator_effort=0
  local other_cohort_lines=""

  while IFS='=' read -r key rest; do
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    local value="${rest%$'\r'}"
    value="${value#"${value%%[! ]*}"}"  # ltrim
    [[ -z "$value" || "$value" =~ ^[[:space:]]+$ ]] && continue

    case "$key" in
      schema)                              ;;   # Skip.
      last_preset)                         v3_last_preset="$value" ;;
      last_commit)                         v3_last_commit="$value" ;;
      cohort.adversarial-scout.model)      v3_scout_model="$value" ;;
      cohort.adversarial-scout.effort)     v3_scout_effort="$value" ;;
      cohort.adversarial-review.model)     v3_review_model="$value" ;;
      cohort.adversarial-review.effort)    v3_review_effort="$value" ;;
      cohort.*)
        # All other cohort lines pass through verbatim.
        other_cohort_lines="${other_cohort_lines}${key}=${value}"$'\n'
        ;;
      plan-checker|plan-checker.effort)    has_plan_checker_effort=1 ; per_agent_effort_lines="${per_agent_effort_lines}${key}=${value}"$'\n' ;;
      contrarian|contrarian.effort)        has_contrarian_effort=1   ; per_agent_effort_lines="${per_agent_effort_lines}${key}=${value}"$'\n' ;;
      plan-calibrator|plan-calibrator.effort) has_plan_calibrator_effort=1 ; per_agent_effort_lines="${per_agent_effort_lines}${key}=${value}"$'\n' ;;
      *.model)
        per_agent_model_lines="${per_agent_model_lines}${key}=${value}"$'\n'
        ;;
      *)
        per_agent_effort_lines="${per_agent_effort_lines}${key}=${value}"$'\n'
        ;;
    esac
  done < "$v3_file"

  # ---- Step 4: Conflict detection for scout vs review effort ----------------
  if [[ -n "$v3_scout_effort" && -n "$v3_review_effort" && "$v3_scout_effort" != "$v3_review_effort" ]]; then
    echo "  !!" >&2
    echo "  !!  CONFLICT: v3 sidecar has conflicting effort for :adversarial-scout (${v3_scout_effort})" >&2
    echo "  !!    and :adversarial-review (${v3_review_effort})." >&2
    echo "  !!  Migration aborted. Restore backup: cp '${v3_backup}' '${v3_file}'" >&2
    echo "  !!  To resolve: bash update.sh --target . --resolve-cohort-merge <effort-value>" >&2
    echo "  !!" >&2
    # Restore backup (we already wrote it; remove it to signal clean state).
    rm -f "$v3_backup"
    return 1
  fi

  # ---- Step 5: Derive v4 :adversarial cohort settings ----------------------
  # Model: prefer scout model, then review model (both should be opus; warn if differ).
  local v4_adv_model=""
  if [[ -n "$v3_scout_model" ]]; then
    v4_adv_model="$v3_scout_model"
  elif [[ -n "$v3_review_model" ]]; then
    v4_adv_model="$v3_review_model"
  fi

  # Effort: cohort baseline = high; per-agent max overrides carry the sub-distinction.
  # We do NOT propagate scout.effort=max to cohort-level (would override all 6 members).
  local v4_adv_effort="high"  # Cohort baseline.
  # (scout.effort=max handled by per-agent injection below.)

  # ---- Step 6: Write v4 .effort.tmp ----------------------------------------
  local migration_ts
  migration_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u '+%Y-%m-%dT%H:%M:%SZ')"
  {
    printf '# aihaus effort state -- managed by /aih-effort, consumed by /aih-update\n'
    printf '# Schema: v4 -- 5-cohort taxonomy (ADR-260509-Y); no permission_mode field.\n'
    printf '# This file is USER-OWNED and derived state. Safe to delete. Do not commit.\n'
    printf '# Migrated from schema v3 on %s\n' "$migration_ts"
    printf '\n'
    printf 'schema=4\n'
    [[ -n "$v3_last_preset" ]] && printf 'last_preset=%s\n' "$v3_last_preset"
    [[ -n "$v3_last_commit" ]] && printf 'last_commit=%s\n' "$v3_last_commit"
    printf '\n'
    printf '# Cohort-level rows (migrated from v3)\n'
    # Pass through non-adversarial cohort rows verbatim.
    [[ -n "$other_cohort_lines" ]] && printf '%s' "$other_cohort_lines"
    # Write folded :adversarial cohort (if any scout/review settings existed).
    if [[ -n "$v4_adv_model" ]]; then
      printf 'cohort.adversarial.model=%s\n' "$v4_adv_model"
      echo "  migrated cohort.adversarial-scout.model + cohort.adversarial-review.model → cohort.adversarial.model=${v4_adv_model}"
    fi
    # We deliberately do NOT write cohort.adversarial.effort (preset-immune: not calibrated).
    printf '\n'
    printf '# Per-agent overrides (preset-immunity preservation -- ADR-260509-Y)\n'
    printf '# plan-checker, contrarian, plan-calibrator carry (opus, max) via per-agent override.\n'
  } > "$tmp_file"

  # ---- Step 7: Inject preset-immunity per-agent overrides ------------------
  local injected_lines=""
  if [[ "$has_plan_checker_effort" -eq 0 ]]; then
    injected_lines="${injected_lines}plan-checker=max"$'\n'
    echo "  migrated: injected per-agent override plan-checker=max (preset-immunity preservation; v4 cohort baseline would have demoted to high)"
  fi
  if [[ "$has_contrarian_effort" -eq 0 ]]; then
    injected_lines="${injected_lines}contrarian=max"$'\n'
    echo "  migrated: injected per-agent override contrarian=max (preset-immunity preservation; v4 cohort baseline would have demoted to high)"
  fi
  if [[ "$has_plan_calibrator_effort" -eq 0 ]]; then
    injected_lines="${injected_lines}plan-calibrator=max"$'\n'
    echo "  migrated: injected per-agent override plan-calibrator=max (preset-immunity preservation; v4 cohort baseline would have demoted to high)"
  fi

  # Append injected + existing per-agent lines.
  {
    [[ -n "$injected_lines" ]] && printf '%s' "$injected_lines"
    if [[ -n "$per_agent_effort_lines" ]]; then
      printf '\n'
      printf '# Per-agent effort overrides (from v3)\n'
      printf '%s' "$per_agent_effort_lines"
    fi
    if [[ -n "$per_agent_model_lines" ]]; then
      printf '\n'
      printf '# Per-agent model overrides (from v3)\n'
      printf '%s' "$per_agent_model_lines"
    fi
  } >> "$tmp_file"

  # ---- Step 8: Atomic swap: tmp → v4 ----------------------------------------
  if ! mv "$tmp_file" "$v4_file"; then
    echo "  !!" >&2
    echo "  !!  Could not write v4 file at ${v4_file}. Migration aborted." >&2
    echo "  !!  v3 backup preserved at ${v3_backup}" >&2
    echo "  !!" >&2
    return 1
  fi

  echo "  migrated .aihaus/.effort schema v3 → v4 (5-cohort taxonomy, ADR-260509-Y)"
  echo "  v3 backup preserved at ${v3_backup}"
}
