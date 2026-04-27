#!/bin/bash
set -euo pipefail

# DANGEROUS_PATTERNS: sole carrier since M014/S04 (PermissionRequest layer deleted).
# Pattern set migrated from M007 baseline; extended with M014/S02 additions.
# See ADR-008, ADR-009, ADR-M014-A, K-003.
#
# Categories (matching ADR-009's prompt-class taxonomy):
#   destructive-fs, priv-escalation, destructive-git, destructive-sql,
#   win-destructive, code-injection, code-via-pipe, supply-chain,
#   nuclear-docker, fork-bomb.
DANGEROUS_PATTERNS=(
  # --- destructive filesystem ops ---
  # NOTE: C:[\\] — character-class form is REQUIRED. A bare C:\\ after
  # shell single-quote unescape becomes C:\ and ERE parses the trailing
  # \) as an escaped literal, unbalancing the group → grep errors with
  # "Unmatched ( or \(". See architecture.md §11.4 escalation.
  '^rm\s+-rf\s+(/|~|\$HOME|C:[\\])'
  'shred\b'
  'dd\s+if=.*of=/dev/'
  'mkfs\.'
  '>\s*/dev/s[dr][a-z]'

  # --- privilege escalation ---
  '^sudo\b'
  '^doas\b'
  '^su\s'

  # --- destructive git ---
  'git\s+push\s+--force\s+(origin\s+)?(main|master|staging|production)'
  'git\s+clean\s+-fd[x]?\b'

  # --- destructive SQL ---
  'drop\s+(table|database)\b'
  'truncate\s+table\b'

  # --- Windows destructive (Git Bash / cmd.exe routed) ---
  '\bdel\s+/[FSQfsq]'
  '\berase\s+/[FSQfsq]'
  'rmdir\s+/[Ss]'
  'format\s+[A-Za-z]:'

  # --- code injection via interpreter flags ---
  "awk\\s+'[^']*BEGIN\\s*\\{[^}]*system"
  'sed\s+-i\s+[^-]'

  # --- code-via-pipe ---
  'curl\s+[^|]*\|\s*(ba)?sh\b'
  'wget\s+[^|]*\|\s*(ba)?sh\b'

  # --- supply chain (package publish) ---
  '^npm\s+publish\b'
  '^pnpm\s+publish\b'
  '^yarn\s+publish\b'
  '^pip\s+publish\b'
  '^cargo\s+publish\b'

  # --- nuclear docker ---
  'docker\s+system\s+prune\s+-a\b'

  # --- fork bomb ---
  ':\(\)\s*\{\s*:\|:&\s*\}\s*;:'
)

INPUT=$(cat)

# jq-optional: extract .tool_input.command with bash fallback.
if command -v jq >/dev/null 2>&1; then
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
else
  # Fallback: grep for "command": "value" within tool_input. Handles flat JSON.
  COMMAND=$(echo "$INPUT" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"command"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' || echo "")
fi

# Pre-compile into single -E regex (one forked grep per segment
# regardless of deny-list length).
DANGER_REGEX=$(IFS='|'; echo "${DANGEROUS_PATTERNS[*]}")

# Split the command into segments on &&, ||, ; — with OR without surrounding
# whitespace. Tightened so that `ls;rm -rf /` decomposes correctly.
any_dangerous=0
OLD_IFS="$IFS"
IFS=$'\n'
segments=$(printf '%s' "$COMMAND" | sed -E 's/[[:space:]]*(&&|\|\||;)[[:space:]]*/\n/g')
for seg in $segments; do
  # Trim leading/trailing whitespace
  trimmed="${seg#"${seg%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
  if [[ -z "$trimmed" ]]; then
    continue
  fi
  if echo "$trimmed" | grep -qiE "$DANGER_REGEX"; then
    any_dangerous=1
    break
  fi
done
IFS="$OLD_IFS"

if [[ $any_dangerous -eq 1 ]]; then
  echo "BLOCKED: Catastrophic command matched DANGEROUS_PATTERNS. Requires explicit user approval." >&2
  exit 2
fi

# --- ADR-260427-B: branch-switch soft-warn -----------------------------------
# Detect `git checkout <ref>` / `git switch <ref>` while a feature/bugfix/
# milestone RUN-MANIFEST shows status: running. Warn-only — never blocks.
# Mirrors git-add-guard.sh segment-and-deny grammar.
#
# Excludes: -b, --orphan, -c <name>, --detach, - (previous-branch), . (path),
# tracked-pathspec args (test via git ls-files --error-unmatch).
#
# Audit: .claude/audit/branch-switch-warn.jsonl (8 fields).
# Opt-out: AIHAUS_BRANCH_SWITCH_GUARD=0.

if [ "${AIHAUS_BRANCH_SWITCH_GUARD:-1}" = "0" ]; then
  exit 0
fi

# Quick reject if no segment looks like git checkout/switch.
if ! printf '%s' "$COMMAND" | grep -qE 'git[[:space:]]+(checkout|switch)\b'; then
  exit 0
fi

_bsw_ts() { date -u +%FT%TZ 2>/dev/null || echo ""; }

_bsw_audit() {
  local from_branch="$1" target_ref="$2" manifest_path="$3" manifest_status="$4"
  local audit_log="${AIHAUS_BRANCH_SWITCH_LOG:-.claude/audit/branch-switch-warn.jsonl}"
  mkdir -p "$(dirname "$audit_log")" 2>/dev/null || return 0
  local cmd_hash
  cmd_hash="$(printf '%s' "$COMMAND" | sha256sum 2>/dev/null | cut -c1-12 || printf 'nohash')"
  local sess="${CLAUDE_SESSION_ID:-unknown}"
  printf '{"ts":"%s","session_id":"%s","from_branch":"%s","target_ref":"%s","manifest_path":"%s","manifest_status":"%s","decision":"warn-allow","command_hash":"%s"}\n' \
    "$(_bsw_ts)" "$sess" \
    "$(printf '%s' "$from_branch" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
    "$(printf '%s' "$target_ref"  | sed 's/\\/\\\\/g; s/"/\\"/g')" \
    "$(printf '%s' "$manifest_path" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
    "$manifest_status" "$cmd_hash" \
    >> "$audit_log" 2>/dev/null || true
}

# Parse the FIRST git checkout/switch segment to extract the target ref.
# Returns empty if the segment is in file-mode or excluded.
_bsw_extract_target() {
  local seg="$1"
  # Match: git (checkout|switch) [args...]
  # Excluded forms (return empty):
  #   - has -b, --orphan, -c, --detach, - (alone), . (alone), -- (file-sep)
  #   - any tracked-pathspec arg
  local cmd_args
  cmd_args="$(printf '%s' "$seg" | sed -E 's/.*git[[:space:]]+(checkout|switch)[[:space:]]+//' )"

  # If there's a -- separator, downstream args are file-mode → exclude.
  case " $cmd_args " in *' -- '*) return 0 ;; esac

  # Walk tokens; first non-flag, non-`-`, non-`.` token is candidate target ref.
  local target=""
  for tok in $cmd_args; do
    case "$tok" in
      -b|--orphan)
        # Creates a NEW branch — not a switch we warn on.
        return 0
        ;;
      -c|-C|--track|--no-track|--start-point)
        # `git switch -c <name> [<ref>]` creates new branch. Allowed.
        return 0
        ;;
      --detach)
        return 0
        ;;
      -|.)
        # `-` previous-branch shortcut, `.` literal — skip.
        return 0
        ;;
      -*)
        # Other flags — skip and continue scanning for a positional arg.
        continue
        ;;
      *)
        # First positional arg.
        target="$tok"
        break
        ;;
    esac
  done

  [ -z "$target" ] && return 0

  # File-mode test: if the arg matches a tracked file/path, treat as file-mode.
  if git ls-files --error-unmatch -- "$target" >/dev/null 2>&1; then
    return 0
  fi
  # Also test if it's an existing path on disk (untracked file or directory).
  if [ -e "$target" ]; then
    return 0
  fi

  printf '%s' "$target"
}

# Find a running manifest (first match wins). Glob features, bugfixes, milestones.
_bsw_find_running_manifest() {
  local cand
  for cand in .aihaus/milestones/*/RUN-MANIFEST.md \
              .aihaus/features/*/RUN-MANIFEST.md \
              .aihaus/bugfixes/*/RUN-MANIFEST.md; do
    [ -f "$cand" ] || continue
    if awk '
      /^## Metadata$/ { in_meta=1; next }
      /^## / && in_meta { in_meta=0 }
      in_meta && /^status:[[:space:]]*running[[:space:]]*$/ { found=1; exit }
      END { exit !found }
    ' "$cand" 2>/dev/null; then
      printf '%s\n' "$cand"
      return 0
    fi
  done
  return 1
}

_bsw_manifest_branch() {
  local m="$1"
  awk '
    /^## Metadata$/ { in_meta=1; next }
    /^## / && in_meta { in_meta=0 }
    in_meta && /^branch:/ { sub(/^branch:[[:space:]]*/, ""); gsub(/[[:space:]]+$/, ""); print; exit }
  ' "$m" 2>/dev/null
}

# Iterate segments; warn on first detected branch-switch with running manifest mismatch.
OLD_IFS="$IFS"
IFS=$'\n'
for seg in $segments; do
  trimmed="${seg#"${seg%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
  [ -z "$trimmed" ] && continue

  # Only act on git checkout / git switch segments.
  if ! printf '%s' "$trimmed" | grep -qE '^git[[:space:]]+(checkout|switch)\b'; then
    continue
  fi

  TARGET="$(_bsw_extract_target "$trimmed" || true)"
  [ -z "$TARGET" ] && continue

  RUNNING_MANIFEST="$(_bsw_find_running_manifest || true)"
  [ -z "$RUNNING_MANIFEST" ] && continue

  CURRENT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo "")"
  MANIFEST_BRANCH="$(_bsw_manifest_branch "$RUNNING_MANIFEST")"

  # ADR-260427-B (revised): warn on ANY branch-switch while a manifest is
  # running. Leaving the manifest's branch mid-work IS the collision; staying
  # on a parallel branch and switching elsewhere is also worth surfacing.
  # User can dismiss intentionally.
  echo "aihaus: branch switch detected while ${RUNNING_MANIFEST} is running on ${MANIFEST_BRANCH:-<unknown>}; continue only if intentional. Set AIHAUS_BRANCH_SWITCH_GUARD=0 to silence." >&2
  _bsw_audit "$CURRENT_BRANCH" "$TARGET" "$RUNNING_MANIFEST" "running"
  break
done
IFS="$OLD_IFS"

exit 0
