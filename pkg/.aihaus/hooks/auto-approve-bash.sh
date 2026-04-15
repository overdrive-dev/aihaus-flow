#!/bin/bash
set -euo pipefail

INPUT=$(cat)

# jq-optional input extraction
if command -v jq >/dev/null 2>&1; then
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
else
  COMMAND=$(echo "$INPUT" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"command"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' || echo "")
fi

# Emit allow JSON — jq or raw printf
emit_allow() {
  if command -v jq >/dev/null 2>&1; then
    jq -n '{ hookSpecificOutput: { hookEventName: "PermissionRequest", decision: { behavior: "allow" } } }'
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}\n'
  fi
}

# Auto-approve-by-default deny-list (M007/S02; see ADR-008, ADR-009).
# Semantic flip vs. pre-M007 SAFE_PATTERNS allowlist: commands auto-approve
# UNLESS a segment matches one of the DANGEROUS_PATTERNS below. Compound
# commands are split into segments; inclusive-OR — ANY dangerous segment
# fall-through to the UI prompt. See architecture.md §4.4 for the locked
# list; §4.5 for the line-by-line adversarial critique.
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
  'sed\s+-i\s+[^e]'

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

# Pre-compile into single -E regex (R-NEW-7 — one forked grep per segment
# regardless of deny-list length). Mirrors the SAFE_REGEX compile idiom
# from the pre-M007 shape.
DANGER_REGEX=$(IFS='|'; echo "${DANGEROUS_PATTERNS[*]}")

# Split the command into segments on &&, ||, ; — with OR without surrounding
# whitespace (CHECK.md Finding #5; architecture.md §4.6). Tightened from the
# pre-M007 space-bounded splitter so that `ls;rm -rf /` decomposes correctly.
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

if [[ $any_dangerous -eq 0 ]]; then
  emit_allow
  exit 0
fi

# At least one segment matched DANGEROUS_PATTERNS — fall through to
# Claude Code's default prompt behaviour (empty stdout, exit 0).
exit 0
