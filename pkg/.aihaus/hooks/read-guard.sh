#!/usr/bin/env bash
set -euo pipefail

# read-guard.sh — PreToolUse hook that blocks reads of sensitive paths.
# Created M014/S02. Registered in settings.local.json in S04.
#
# Dual-path per LD-4 (READ_GUARD_MODE env var):
#   tool_name (default per S01 Option 2 fallback):
#     Reads tool_name from stdin JSON; skips non-Read tools; then filters path.
#   matcher:
#     Assumes settings-level matcher:Read fired; reads tool_input.file_path
#     directly (no tool_name filter needed).
#
# Both paths deny the same deny-list (M007 baseline + hardenings):
#   **/.env, **/.env.*        — environment secrets
#   **/*.pem, **/*.key        — TLS/SSH private material
#   **/credentials*           — cloud credentials files
#   **/id_rsa*, **/id_dsa*,   — SSH private keys
#   **/id_ecdsa*, **/id_ed25519*
#
# On deny: non-zero exit + stderr "BLOCKED: read of sensitive path <file>"
# On allow: exit 0 silent
#
# Override mode via env: READ_GUARD_MODE=matcher read-guard.sh
# Default is tool_name (safer fallback; works regardless of whether the
# settings-level Read matcher is accepted by the Claude Code version in use).

READ_GUARD_MODE="${READ_GUARD_MODE:-tool_name}"

INPUT=$(cat)

# Glob-style deny patterns (applied via case statement — no external tools needed).
# Matches on the basename or path suffix. Using case for portability.
_is_sensitive_path() {
  local path="$1"
  # Normalize to forward slashes for consistent matching
  local norm_path
  norm_path="${path//\\//}"
  # Extract basename for basename-only checks
  local base
  base="${norm_path##*/}"

  case "$base" in
    # .env and .env.* variants
    .env|.env.*)
      return 0 ;;
    # PEM certificates and TLS keys
    *.pem)
      return 0 ;;
    # Private keys (generic .key suffix)
    *.key)
      return 0 ;;
    # SSH private key families
    id_rsa|id_rsa.pub)
      return 0 ;;
    id_rsa_*)
      return 0 ;;
    id_dsa|id_dsa.pub)
      return 0 ;;
    id_dsa_*)
      return 0 ;;
    id_ecdsa|id_ecdsa.pub)
      return 0 ;;
    id_ecdsa_*)
      return 0 ;;
    id_ed25519|id_ed25519.pub)
      return 0 ;;
    id_ed25519_*)
      return 0 ;;
  esac

  # credentials* — prefix match on basename
  case "$base" in
    credentials*)
      return 0 ;;
  esac

  # Also check path-level .env in any directory component (e.g. /foo/.env)
  case "/$norm_path" in
    */.env|*/.env.*)
      return 0 ;;
  esac

  return 1
}

case "$READ_GUARD_MODE" in

  # ---- matcher path -----------------------------------------------------------
  # Settings-level matcher:Read fires this hook only for Read tool calls.
  # tool_input.file_path is the path being read.
  matcher)
    if command -v jq >/dev/null 2>&1; then
      FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")
    else
      FILE_PATH=$(printf '%s' "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"file_path"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' || echo "")
    fi

    if [[ -z "$FILE_PATH" ]]; then
      exit 0
    fi

    if _is_sensitive_path "$FILE_PATH"; then
      echo "BLOCKED: read of sensitive path ${FILE_PATH}" >&2
      exit 2
    fi
    exit 0
    ;;

  # ---- tool_name path (default) -----------------------------------------------
  # This hook may fire for any tool; filter to Read only, then check the path.
  tool_name)
    if command -v jq >/dev/null 2>&1; then
      TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
      FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")
    else
      TOOL_NAME=$(printf '%s' "$INPUT" | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"tool_name"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' || echo "")
      FILE_PATH=$(printf '%s' "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"file_path"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' || echo "")
    fi

    # Only act on Read tool calls
    if [[ "$TOOL_NAME" != "Read" ]]; then
      exit 0
    fi

    if [[ -z "$FILE_PATH" ]]; then
      exit 0
    fi

    if _is_sensitive_path "$FILE_PATH"; then
      echo "BLOCKED: read of sensitive path ${FILE_PATH}" >&2
      exit 2
    fi
    exit 0
    ;;

  *)
    # Unknown mode: fail-closed
    echo "BLOCKED: read-guard.sh unknown READ_GUARD_MODE='${READ_GUARD_MODE}'" >&2
    exit 2
    ;;
esac
