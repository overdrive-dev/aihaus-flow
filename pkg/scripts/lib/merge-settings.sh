#!/usr/bin/env bash
# merge-settings.sh --- shared settings.local.json merge logic with
# pre-merge backup. Sourced by install.sh and update.sh.
#
# Exports (set as side effect of merge_settings):
#   AIHAUS_SETTINGS_BACKUP_PATH  --- absolute path of created .bak file,
#                                   or empty if no prior settings file existed
#                                   (first-install case = nothing to back up)
#
# Usage:
#   source "$(dirname "$0")/lib/merge-settings.sh"
#   merge_settings "${SETTINGS_DST}" "${SETTINGS_SRC}"
#
# Behavior:
#   - If SETTINGS_DST does not exist: cp SETTINGS_SRC -> SETTINGS_DST.
#     No backup (nothing to preserve). Stdout: "settings: copied template".
#   - If SETTINGS_DST exists:
#     1. Create timestamped backup at SETTINGS_DST.bak.<epoch>
#     2. Deep-merge SETTINGS_SRC over SETTINGS_DST via jq (preferred)
#        or python (fallback). Object keys deep-merge.
#        v0.34.0+ behavior: .hooks.<Event>[N].hooks[] arrays merge by .command;
#        package-managed aihaus hook commands absent from the template are pruned,
#        user/custom commands are preserved, and .hooks.<Event>[] arrays merge by
#        matcher+command identity. All other arrays retain replacement semantics.
#        See ADR-260514-B.
#     3. If pre-merge backup had granular Bash entries but no Bash(*),
#        emit a one-line migration hint to stdout.
#
# Exit codes: 0 (success or skipped), 1 (merge failed).
#
# Env-var hooks:
#   AIHAUS_FORCE_PYTHON_MERGE=1  --- skip jq even if available; use Python path
#   AIHAUS_RECOMPUTE_MERGE=1     --- re-merge with template-wins semantics (used by
#                                   update.sh drift-detect recompute prompt)

merge_settings() {
  local dst="$1" src="$2"
  AIHAUS_SETTINGS_BACKUP_PATH=""

  # Python is the canonical merge path. The older jq implementation is kept
  # below for reference but disabled because it fails on object-without-hooks
  # fixtures when jq is present on Windows hosts.
  local HAS_JQ=0

  # AIHAUS_RECOMPUTE_MERGE consumer (M030/S05 integration fix per INTEGRATION W4).
  # When set, indicates a deliberate user-triggered recompute on already-installed
  # state (e.g., from update.sh drift-detect "Y" prompt or install.ps1 equivalent),
  # NOT a first-time merge. Behavior delta: emit a tracing line and suppress the
  # legacy granular-Bash migration hint (user has already passed that gate). The
  # core dual by-shape merge below is template-wins on collision regardless, so
  # the recompute correctly closes hook-wiring drift without behavioral surprise.
  local RECOMPUTE_MODE=0
  if [ "${AIHAUS_RECOMPUTE_MERGE:-}" = "1" ]; then
    RECOMPUTE_MODE=1
    echo "  settings: recompute mode (AIHAUS_RECOMPUTE_MERGE=1) --- closing drift"
  fi

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

  # Merge --- dual by-shape array semantics per ADR-260514-B.
  # .hooks.<Event>[] (outer, matcher+hooks shape): position-paired merge.
  # .hooks.<Event>[N].hooks[] (inner, command shape): union by .command.
  # All other arrays: replacement semantics (template wins).
  if [ "$HAS_JQ" = "1" ]; then
    local tmp
    tmp="$(mktemp)"
    if ! jq -s '
# Schema migration (M041/S5): older Claude Code versions accepted hook events
# as a single object {matcher, hooks}; newer versions require an array
# [{matcher, hooks}]. Pre-existing settings.local.json files frozen at the
# older schema get silently ignored by Claude Code today — startup warning
# observed in field installs: "Hook event must be an array; received
# object. Entry ignored.". Normalize-on-merge auto-heals these on next
# install.sh / update.sh pass.
def normalize_event_value(v):
  if (v | type) == "object" and ((v | has("matcher")) or (v | has("hooks"))) then
    [v]
  else
    v
  end;

def normalize_hooks_block(h):
  if (h | type) == "object" then
    (h | to_entries | map({key, value: normalize_event_value(.value)}) | from_entries)
  else
    h
  end;

def normalize_root(root):
  if (root | type) == "object" and (root | has("hooks")) then
    root + {hooks: normalize_hooks_block(root.hooks)}
  else
    root
  end;

def has_matcher_hooks(arr):
  (arr | length) > 0 and
  (arr | all(type == "object" and (.matcher? != null) and (.hooks? != null)));

def has_command(arr):
  (arr | length) > 0 and
  (arr | all(type == "object" and (.command? != null)));

def merge_inner_by_command(base; overlay):
  overlay + (base | map(select(.command as $c | overlay | any(.command == $c) | not)));

def merge_hooks_arrays(base_arr; overlay_arr):
  if ((base_arr | length) == 0) then overlay_arr
  elif ((overlay_arr | length) == 0) then base_arr
  elif (has_matcher_hooks(base_arr) and has_matcher_hooks(overlay_arr)) then
    ([ range([base_arr|length, overlay_arr|length] | min) ] |
      map(. as $i |
        {
          "matcher": (overlay_arr[$i].matcher // base_arr[$i].matcher),
          "hooks": merge_inner_by_command(base_arr[$i].hooks; overlay_arr[$i].hooks)
        }
        + (overlay_arr[$i] | to_entries | map(select(.key != "matcher" and .key != "hooks")) | from_entries)
      )) +
    (overlay_arr[([base_arr|length, overlay_arr|length] | min):]) +
    (base_arr[([base_arr|length, overlay_arr|length] | min):])
  elif (has_command(base_arr) and has_command(overlay_arr)) then
    merge_inner_by_command(base_arr; overlay_arr)
  else
    overlay_arr
  end;

def deep_merge_with_hooks(base; overlay):
  if (base | type) == "object" and (overlay | type) == "object" then
    base + (overlay | to_entries | map(
      if .key == "hooks" then
        {key: "hooks", value: (
          base.hooks as $bh |
          overlay.hooks as $oh |
          if ($bh | type) == "object" and ($oh | type) == "object" then
            $bh + ($oh | to_entries | map(
              .key as $event |
              if ($bh | has($event)) then
                {key: $event, value: merge_hooks_arrays($bh[$event]; .value)}
              else
                {key: $event, value: .value}
              end
            ) | from_entries)
          else
            $oh
          end
        )}
      else
        {key: .key, value: deep_merge_with_hooks(base[.key]; .value)}
      end
    ) | from_entries)
  else
    overlay
  end;

deep_merge_with_hooks(normalize_root(.[0]); normalize_root(.[1]))
' "$dst" "$src" > "$tmp"; then
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

def normalize_root(root):
    if not isinstance(root, dict) or not isinstance(root.get("hooks"), dict):
        return root
    out = dict(root)
    hooks = dict(root["hooks"])
    for event, value in list(hooks.items()):
        if isinstance(value, dict) and ("matcher" in value or "hooks" in value):
            hooks[event] = [value]
    out["hooks"] = hooks
    return out

def has_matcher_hooks(lst):
    return bool(lst and all(
        isinstance(e, dict) and "matcher" in e and "hooks" in e
        for e in lst
    ))

def has_command(lst):
    return bool(lst and all(
        isinstance(e, dict) and "command" in e
        for e in lst
    ))

def hook_command(entry):
    if isinstance(entry, dict):
        return entry.get("command")
    return None

def is_aihaus_hook_command(command):
    return isinstance(command, str) and (
        ".aihaus/hooks/" in command or ".claude/hooks/" in command
    )

def entry_commands(entry):
    if not isinstance(entry, dict):
        return set()
    hooks = entry.get("hooks", [])
    if not isinstance(hooks, list):
        return set()
    return {
        command
        for command in (hook_command(hook) for hook in hooks)
        if command
    }

def entries_match(base_entry, overlay_entry):
    if not isinstance(base_entry, dict) or not isinstance(overlay_entry, dict):
        return False
    if base_entry.get("matcher") != overlay_entry.get("matcher"):
        return False
    return bool(entry_commands(base_entry) & entry_commands(overlay_entry))

def prune_surplus_hook_entry(entry):
    if not isinstance(entry, dict):
        return entry
    hooks = entry.get("hooks")
    if not isinstance(hooks, list):
        return entry
    custom_hooks = [
        hook
        for hook in hooks
        if not is_aihaus_hook_command(hook_command(hook))
    ]
    if not custom_hooks:
        return None
    pruned = dict(entry)
    pruned["hooks"] = custom_hooks
    return pruned

def merge_inner_by_command(base, overlay):
    # Template (overlay) wins and defines canonical aihaus hooks. Preserve
    # user/custom commands, but prune stale package-managed aihaus hook commands.
    result = list(overlay)
    overlay_commands = {
        command
        for command in (hook_command(entry) for entry in overlay)
        if command
    }
    for entry in overlay:
        command = hook_command(entry)
        if command:
            overlay_commands.add(command)
    for entry in base:
        command = hook_command(entry)
        if command and command in overlay_commands:
            continue
        if is_aihaus_hook_command(command):
            continue
        result.append(entry)
    return result

def merge_hooks_arrays(base_arr, overlay_arr):
    """Dual by-shape merge for .hooks.<Event>[] arrays.
    Outer: {matcher, hooks} shape -> position-paired merge with recursion.
    Inner: {command} shape -> union by .command (template wins on collision).
    Other: replacement semantics.
    """
    if not base_arr:
        return overlay_arr
    if not overlay_arr:
        return base_arr
    if has_matcher_hooks(base_arr) and has_matcher_hooks(overlay_arr):
        # outer shape: merge canonical template entries with matching installed
        # entries by matcher+command identity. This survives inserted/removed
        # package hook entries without shifting later hook blocks.
        used_base = set()
        result = []
        for overlay_entry in overlay_arr:
            match_idx = None
            for idx, base_entry in enumerate(base_arr):
                if idx in used_base:
                    continue
                if entries_match(base_entry, overlay_entry):
                    match_idx = idx
                    break
            if match_idx is None:
                result.append(overlay_entry)
                continue
            used_base.add(match_idx)
            base_entry = base_arr[match_idx]
            bh = base_entry.get("hooks", [])
            oh = overlay_entry.get("hooks", [])
            merged_inner = merge_hooks_arrays(bh, oh)
            # template wins on matcher and metadata, custom user hooks survive.
            entry = dict(base_entry)
            entry.update(overlay_entry)
            entry["hooks"] = merged_inner
            result.append(entry)
        for idx, base_entry in enumerate(base_arr):
            if idx in used_base:
                continue
            pruned = prune_surplus_hook_entry(base_entry)
            if pruned is not None:
                result.append(pruned)
        return result
    if has_command(base_arr) and has_command(overlay_arr):
        return merge_inner_by_command(base_arr, overlay_arr)
    # default: replacement
    return overlay_arr

def deep_merge(base, overlay):
    if isinstance(base, dict) and isinstance(overlay, dict):
        out = dict(base)
        for k, v in overlay.items():
            if k == "hooks" and k in base:
                # hooks key: apply event-level merge with by-shape array semantics
                b_hooks = base[k]
                if isinstance(b_hooks, dict) and isinstance(v, dict):
                    merged_hooks = dict(b_hooks)
                    for event, event_arr in v.items():
                        if event in b_hooks and isinstance(b_hooks[event], list) and isinstance(event_arr, list):
                            merged_hooks[event] = merge_hooks_arrays(b_hooks[event], event_arr)
                        else:
                            merged_hooks[event] = event_arr
                    out[k] = merged_hooks
                else:
                    out[k] = v
            elif k in base:
                out[k] = deep_merge(base.get(k), v)
            else:
                out[k] = v
        return out
    return overlay if overlay is not None else base

merged = deep_merge(normalize_root(dst), normalize_root(src))
# jq-compatible byte layout: explicit separators (no trailing space before
# comma) + trailing newline so successive jq/python invocations on the same
# file produce identical bytes. See M009 QA-REVIEW M-001.
with open(dst_path, "w", encoding="utf-8") as fh:
    json.dump(merged, fh, indent=2, separators=(",", ": "))
    fh.write("\n")
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

  _normalize_hook_command_paths "$dst"

  # Post-merge defaultMode preserve --- user intent wins on this single scalar.
  # Reads .aihaus/.calibration's permission_mode field and overwrites
  # .permissions.defaultMode in $dst so /aih-effort choices survive
  # /aih-update (which otherwise lets the template's defaultMode win via
  # overlay). Only touches .permissions.defaultMode; allow/deny/hook paths
  # still follow template-wins. Missing sidecar or empty value = no-op.
  # Schema contract: pkg/.aihaus/skills/aih-effort/annexes/state-file.md.
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
      if [ "$HAS_JQ" = "1" ]; then
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
# jq-compatible byte layout --- see M009 QA-REVIEW M-001.
with open(tmp_path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, separators=(",", ": "))
    fh.write("\n")
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
  # Skip on RECOMPUTE_MODE: user has already passed the migration gate; the hint
  # would emit a stale "migrate to granular Bash" message that doesn't apply.
  if [ "${RECOMPUTE_MODE:-0}" = "0" ]; then
    _autonomy_post_merge_hint "$bak"
  fi
}

_normalize_hook_command_paths() {
  local dst="$1"
  [[ -f "$dst" ]] || return 0
  grep -Fq '.claude/hooks/' "$dst" 2>/dev/null || return 0

  local tmp
  tmp="$(mktemp)" || return 0

  if command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1 || command -v py >/dev/null 2>&1; then
    local py_bin
    py_bin="$(command -v python3 || command -v python || command -v py)"
    if "$py_bin" - "$dst" "$tmp" <<'PY'
import json
import sys

src, dst = sys.argv[1], sys.argv[2]
with open(src, "r", encoding="utf-8") as fh:
    data = json.load(fh)

def normalize(obj):
    if isinstance(obj, dict):
        out = {}
        for key, value in obj.items():
            if key == "command" and isinstance(value, str):
                out[key] = value.replace(".claude/hooks/", ".aihaus/hooks/")
            else:
                out[key] = normalize(value)
        return out
    if isinstance(obj, list):
        normalized = [normalize(item) for item in obj]
        if all(isinstance(item, dict) and "command" in item for item in normalized):
            seen = set()
            deduped = []
            for item in normalized:
                command = item.get("command")
                if command in seen:
                    continue
                seen.add(command)
                deduped.append(item)
            return deduped
        return normalized
    return obj

with open(dst, "w", encoding="utf-8") as fh:
    json.dump(normalize(data), fh, indent=2, separators=(",", ": "))
    fh.write("\n")
PY
    then
      mv "$tmp" "$dst"
      echo "  settings: normalized hook paths to .aihaus/hooks"
      return 0
    fi
  fi

  if sed 's#\.claude/hooks/#.aihaus/hooks/#g' "$dst" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$dst"
    echo "  settings: normalized hook paths to .aihaus/hooks"
  else
    rm -f "$tmp"
    echo "  warn: could not normalize .claude/hooks settings paths"
  fi
}

# Internal: emit the migration hint if pre-merge backup had granular
# Bash(X *) entries without Bash(*).
_autonomy_post_merge_hint() {
  local bak="$1"
  [[ -f "$bak" ]] || return 0

  local had_wildcard="" had_granular=""

  # Prefer jq; fall back to python so the hint works on jq-less machines.
  if [ "${HAS_JQ:-0}" = "1" ]; then
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

  # Detect legacy permissions.allow -> post-M014 strip transition.
  # The template since v0.18.0 ships with NO permissions.{defaultMode,allow,deny}
  # --- autonomy comes from launching via `bash .aihaus/auto.sh` (DSP wrapper)
  # and PreToolUse hooks (bash-guard, file-guard, read-guard) provide safety.
  # If the user's prior settings had any permissions.allow entries, jq's deep
  # merge keeps them (granular OR wildcard) --- the merged result still works,
  # just carries vestigial keys. Surface the situation so the user knows.
  if [[ "$had_wildcard" = "true" || "$had_granular" = "true" ]]; then
    echo ""
    echo "  Legacy permissions.allow detected in your settings --- preserved as-is."
    echo "    Since v0.18.0 (M014), the template ships with no permissions.{allow,deny,defaultMode}."
    echo "    Autonomy comes from launching via 'bash .aihaus/auto.sh' (DSP wrapper);"
    echo "    safety lives in PreToolUse hooks (bash-guard, file-guard, read-guard)."
    echo "    To complete the migration, you can remove the permissions.allow array entirely."
    echo "    Backup of prior settings: $bak"
  fi
}
