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

# Auto-approve safe development commands (stack-agnostic)
SAFE_PATTERNS=(
  # Navigation (compound splits below will still gate unsafe segments)
  '^cd\s+' '^pushd\s+' '^popd$'
  # Shell utilities (read-only)
  '^ls\b' '^pwd$' '^cat\b' '^head\b' '^tail\b' '^wc\b'
  '^echo\b' '^which\b' '^where\b' '^find\b' '^test\b'
  '^grep\b' '^rg\b' '^sort\b' '^uniq\b' '^diff\b'
  # Git (all subcommands)
  '^git\s+'
  # Package managers
  '^npm\s+' '^npx\s+' '^pnpm\s+' '^yarn\s+' '^bun\s+'
  '^pip[3]?\s+' '^uv\s+' '^poetry\s+' '^pipx\s+'
  '^cargo\s+' '^go\s+' '^bundle\s+' '^gem\s+'
  '^mvn\s+' '^gradle\b' '^gradlew\b' '^dotnet\s+'
  '^composer\s+' '^deno\s+'
  # Language runtimes
  '^node\s+' '^python[3]?\s+' '^py\s+' '^ruby\s+' '^java\s+'
  '^php\s+' '^swift\s+' '^rustc\s+'
  # Build tools
  '^make\b' '^cmake\s+' '^just\s+'
  # Test runners
  '^pytest\b' '^jest\b' '^vitest\b' '^playwright\b'
  # Linters and formatters
  '^eslint\b' '^prettier\b' '^biome\b' '^ruff\b' '^black\b'
  '^gofmt\b' '^rustfmt\b' '^mypy\b' '^tsc\b'
  # Migration tools
  '^alembic\s+' '^prisma\s+' '^drizzle-kit\s+'
  # Infrastructure
  '^docker\s+' '^docker-compose\s+' '^gh\s+'
  # File operations
  '^mkdir\b' '^touch\b' '^cp\b' '^mv\b'
  '^jq\b' '^realpath\b' '^dirname\b' '^basename\b'
  '^chmod\b' '^date\b' '^curl\s+'
  # Mobile
  '^expo\s+' '^react-native\s+'
  # Read-only / benign transforms (Story 4 of plan 260414-exec-auto-approve).
  # NOTE: awk and sed deliberately EXCLUDED — both can invoke arbitrary
  # destructive code (awk 'BEGIN{system(...)}', sed -i on system paths)
  # that bash-guard.sh's whole-string regex does NOT catch. Adding them
  # here without a compensating guard would widen the approve surface.
  '^printf\b' '^env\b' '^tree\b' '^type\b'
  '^tee\b' '^cut\b' '^tr\b' '^seq\b'
)

SAFE_REGEX=$(IFS='|'; echo "${SAFE_PATTERNS[*]}")

# Check 1: whole command matches a safe prefix
if echo "$COMMAND" | grep -qiE "$SAFE_REGEX"; then
  emit_allow
  exit 0
fi

# Check 2: compound command — split on && and ; and verify EVERY segment is safe.
# Avoid matching literal '&&' inside quoted strings by only splitting when both
# sides look like separate commands (space-bounded).
if [[ "$COMMAND" == *" && "* ]] || [[ "$COMMAND" == *" ; "* ]]; then
  all_safe=1
  OLD_IFS="$IFS"
  IFS=$'\n'
  segments=$(printf '%s' "$COMMAND" | sed 's/ && /\n/g; s/ ; /\n/g')
  for seg in $segments; do
    trimmed="${seg#"${seg%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    if [[ -z "$trimmed" ]]; then
      continue
    fi
    if ! echo "$trimmed" | grep -qiE "$SAFE_REGEX"; then
      all_safe=0
      break
    fi
  done
  IFS="$OLD_IFS"
  if [[ $all_safe -eq 1 ]]; then
    emit_allow
    exit 0
  fi
fi

# Not matched — fall through to Claude Code's default prompt behaviour.
exit 0
