#!/bin/bash
set -euo pipefail

# DANGEROUS_PATTERNS migrated from auto-approve-bash.sh M007 baseline (M014/S02);
# source of truth post-S04. When S04 deletes auto-approve-bash.sh, this hook
# becomes the sole DANGEROUS_PATTERNS carrier. See ADR-008, ADR-009, K-003.
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

exit 0
