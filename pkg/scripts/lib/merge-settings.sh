#!/usr/bin/env bash
# merge-settings.sh — shared settings.local.json merge logic with
# pre-merge backup. Sourced by install.sh and update.sh.
#
# Exports (set as side effect of merge_settings):
#   AIHAUS_SETTINGS_BACKUP_PATH  — absolute path of created .bak file,
#                                   or empty if no prior settings file existed
#                                   (first-install case = nothing to back up)
#
# Usage:
#   source "$(dirname "$0")/lib/merge-settings.sh"
#   merge_settings "${SETTINGS_DST}" "${SETTINGS_SRC}"
#
# Behavior:
#   - If SETTINGS_DST does not exist: cp SETTINGS_SRC → SETTINGS_DST.
#     No backup (nothing to preserve). Stdout: "settings: copied template".
#   - If SETTINGS_DST exists:
#     1. Create timestamped backup at SETTINGS_DST.bak.<epoch>
#     2. Deep-merge SETTINGS_SRC over SETTINGS_DST via jq (preferred)
#        or python (fallback). Replacement semantics for arrays
#        (template wins on permissions.allow); object keys deep-merge.
#     3. If pre-merge backup had granular Bash entries but no Bash(*),
#        emit a one-line migration hint to stdout.
#
# Exit codes: 0 (success or skipped), 1 (merge failed).

merge_settings() {
  local dst="$1" src="$2"
  AIHAUS_SETTINGS_BACKUP_PATH=""

  if [[ ! -f "$src" ]]; then
    echo "  warn: settings template missing at $src, skipping merge"
    return 0
  fi

  if [[ ! -f "$dst" ]]; then
    cp "$src" "$dst"
    echo "  settings: copied template"
    return 0
  fi

  # Pre-merge backup.
  local ts
  ts="$(date +%s)"
  local bak="${dst}.bak.${ts}"
  cp "$dst" "$bak"
  AIHAUS_SETTINGS_BACKUP_PATH="$bak"

  # Merge.
  if command -v jq >/dev/null 2>&1; then
    local tmp
    tmp="$(mktemp)"
    if ! jq -s '.[0] * .[1]' "$dst" "$src" > "$tmp"; then
      echo "  error: jq merge failed; restoring from backup"
      cp "$bak" "$dst"
      rm -f "$tmp"
      return 1
    fi
    mv "$tmp" "$dst"
    echo "  settings: merged via jq (backup at $bak)"
  elif command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 || command -v py >/dev/null 2>&1; then
    local py_bin
    py_bin="$(command -v python3 || command -v python || command -v py)"
    if ! "$py_bin" - "$dst" "$src" <<'PY'
import json, sys

dst_path, src_path = sys.argv[1], sys.argv[2]
with open(dst_path, "r", encoding="utf-8") as fh:
    dst = json.load(fh)
with open(src_path, "r", encoding="utf-8") as fh:
    src = json.load(fh)

def deep_merge(base, overlay):
    if isinstance(base, dict) and isinstance(overlay, dict):
        out = dict(base)
        for k, v in overlay.items():
            out[k] = deep_merge(base.get(k), v) if k in base else v
        return out
    return overlay if overlay is not None else base

merged = deep_merge(dst, src)
with open(dst_path, "w", encoding="utf-8") as fh:
    json.dump(merged, fh, indent=2)
PY
    then
      echo "  error: python merge failed; restoring from backup"
      cp "$bak" "$dst"
      return 1
    fi
    echo "  settings: merged via python (backup at $bak)"
  else
    echo "  warn: neither jq nor python available; leaving settings.local.json untouched"
    rm -f "$bak"
    AIHAUS_SETTINGS_BACKUP_PATH=""
    return 0
  fi

  # Post-merge defaultMode preserve — user intent wins on this single scalar.
  # Reads .aihaus/.calibration's permission_mode field and overwrites
  # .permissions.defaultMode in $dst so /aih-calibrate choices survive
  # /aih-update (which otherwise lets the template's defaultMode win via
  # overlay). Only touches .permissions.defaultMode; allow/deny/hook paths
  # still follow template-wins. Missing sidecar or empty value = no-op.
  # Schema contract: pkg/.aihaus/skills/aih-calibrate/annexes/state-file.md.
  local target_root
  target_root="$(dirname "$(dirname "$dst")")"
  local state_file="${target_root}/.aihaus/.calibration"
  if [[ -f "$state_file" ]]; then
    local state_schema user_mode
    state_schema=$(grep -E '^schema=' "$state_file" | head -1 | cut -d= -f2 | tr -d '[:space:]\r')
    user_mode=$(grep -E '^permission_mode=' "$state_file" | head -1 | cut -d= -f2 | tr -d '[:space:]\r')
    if [[ "$state_schema" == "1" && -n "$user_mode" ]]; then
      local pm_tmp
      pm_tmp="$(mktemp)"
      local preserved=0
      if command -v jq >/dev/null 2>&1; then
        if jq --arg mode "$user_mode" '.permissions.defaultMode = $mode' "$dst" > "$pm_tmp"; then
          mv "$pm_tmp" "$dst"
          preserved=1
        else
          rm -f "$pm_tmp"
        fi
      elif command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 || command -v py >/dev/null 2>&1; then
        local pm_py_bin
        pm_py_bin="$(command -v python3 || command -v python || command -v py)"
        if "$pm_py_bin" - "$dst" "$user_mode" "$pm_tmp" <<'PY'
import json, sys
dst_path, mode, tmp_path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(dst_path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
data.setdefault("permissions", {})["defaultMode"] = mode
with open(tmp_path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2)
PY
        then
          mv "$pm_tmp" "$dst"
          preserved=1
        else
          rm -f "$pm_tmp"
        fi
      else
        rm -f "$pm_tmp"
      fi
      if [[ "$preserved" = "1" ]]; then
        echo "  settings: defaultMode preserved from .aihaus/.calibration ($user_mode)"
      else
        echo "  warn: defaultMode preserve step failed; leaving merged template value"
      fi
    fi
  fi

  # Post-merge migration hint (Story 3 logic, gated on jq availability for
  # the regex queries; silent if jq missing).
  _autonomy_post_merge_hint "$bak"
}

# Internal: emit the migration hint if pre-merge backup had granular
# Bash(X *) entries without Bash(*).
_autonomy_post_merge_hint() {
  local bak="$1"
  [[ -f "$bak" ]] || return 0

  local had_wildcard="" had_granular=""

  # Prefer jq; fall back to python so the hint works on jq-less machines.
  if command -v jq >/dev/null 2>&1; then
    had_wildcard=$(jq -r '.permissions.allow // [] | any(. == "Bash(*)")' "$bak" 2>/dev/null || echo "")
    had_granular=$(jq -r '.permissions.allow // [] | any(. ; test("^Bash\\([^)]+\\*\\)$"))' "$bak" 2>/dev/null || echo "")
  elif command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 || command -v py >/dev/null 2>&1; then
    local py_bin
    py_bin="$(command -v python3 || command -v python || command -v py)"
    local bak_path="$bak"
    if command -v cygpath >/dev/null 2>&1; then
      bak_path="$(cygpath -w "$bak" 2>/dev/null || echo "$bak")"
    fi
    local py_out
    py_out=$("$py_bin" -c "
import json, re, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
allow = d.get('permissions', {}).get('allow', [])
has_wildcard = any(x == 'Bash(*)' for x in allow)
has_granular = any(re.match(r'^Bash\([^)]+\*\)$', x) for x in allow)
print('wildcard:' + ('true' if has_wildcard else 'false'))
print('granular:' + ('true' if has_granular else 'false'))
" "$bak_path" 2>/dev/null) || return 0
    had_wildcard=$(echo "$py_out" | grep '^wildcard:' | cut -d: -f2)
    had_granular=$(echo "$py_out" | grep '^granular:' | cut -d: -f2)
  else
    return 0
  fi

  if [[ "$had_wildcard" = "false" && "$had_granular" = "true" ]]; then
    echo ""
    echo "  ℹ Settings migrated: permissions.allow replaced by template defaults"
    echo "    (includes Bash(*) wildcard). Backup saved at:"
    echo "    $bak"
    echo "    If you prefer narrow permissions, edit .claude/settings.local.json"
    echo "    and re-add your specific Bash(command *) entries."
  fi
}
