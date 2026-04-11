#!/bin/bash
set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Auto-approve safe development commands (stack-agnostic)
SAFE_PATTERNS=(
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
)

SAFE_REGEX=$(IFS='|'; echo "${SAFE_PATTERNS[*]}")

if echo "$COMMAND" | grep -qiE "$SAFE_REGEX"; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PermissionRequest",
      decision: { behavior: "allow" }
    }
  }'
  exit 0
fi

exit 0
