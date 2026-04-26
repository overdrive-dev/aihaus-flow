#!/usr/bin/env bash
# worktree-reap.sh — L4 catastrophic-crash fallback reap (M017/S02d / ADR-M017-B)
# Wraps worktree-reconcile.sh --reap-locked mode.
# Default (no flags): scan-and-report + exit 0 WITHOUT deleting.
# --confirm-reap or AIHAUS_REAP_EXECUTE=1: prunes lock-markers >= age-days old.
#
# Usage:
#   bash .aihaus/hooks/worktree-reap.sh [--confirm-reap] [--age-days N]
#
# Env:
#   AIHAUS_REAP_DISABLED=1   — top-of-body no-op short-circuit
#   AIHAUS_REAP_EXECUTE=1    — alternative to --confirm-reap
#   AIHAUS_REAP_AGE_DAYS=N   — override default 14-day threshold
#   AIHAUS_AUDIT_LOG         — override audit log path (default .claude/audit/hook.jsonl)
#
# Refs: M017/S02d, ADR-M017-B, worktree-reconcile.sh --reap-locked (S02a).

set -euo pipefail

# ---- env bypass ---------------------------------------------------------------
if [ "${AIHAUS_REAP_DISABLED:-}" = "1" ]; then exit 0; fi

# ---- config -------------------------------------------------------------------
AUDIT_LOG="${AIHAUS_AUDIT_LOG:-.claude/audit/hook.jsonl}"
AGE_DAYS="${AIHAUS_REAP_AGE_DAYS:-14}"
EXECUTE=0

# ---- argument parsing ---------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --confirm-reap) EXECUTE=1; shift ;;
    --age-days)     AGE_DAYS="$2"; shift 2 ;;
    *)              shift ;;  # ignore unknown; wrap is tolerant
  esac
done
[ "${AIHAUS_REAP_EXECUTE:-}" = "1" ] && EXECUTE=1

# ---- audit helper -------------------------------------------------------------
_audit() {
  local phase="$1"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")"
  local entry
  entry="{\"ts\":\"${ts}\",\"event\":\"worktree-reap\",\"phase\":\"${phase}\",\"age_days\":${AGE_DAYS},\"execute\":${EXECUTE}}"
  if [ -n "${AUDIT_LOG}" ]; then
    mkdir -p "$(dirname "${AUDIT_LOG}")" 2>/dev/null || true
    printf '%s\n' "${entry}" >> "${AUDIT_LOG}" 2>/dev/null || true
  fi
}

# ---- non-git-dir guard --------------------------------------------------------
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

# ---- dispatch to reconcile.sh --reap-locked -----------------------------------
RECONCILE="${AIHAUS_RECONCILE_SH:-.aihaus/hooks/worktree-reconcile.sh}"

if [ "$EXECUTE" = "1" ]; then
  _audit "execute"
  bash "${RECONCILE}" --reap-locked --age-days "${AGE_DAYS}" --confirm
else
  _audit "scan"
  bash "${RECONCILE}" --reap-locked --age-days "${AGE_DAYS}"
  # Emit single-line pointer (no option menu — autonomy-protocol binding)
  echo "Run: bash .aihaus/hooks/worktree-reap.sh --confirm-reap" >&2
fi

exit 0
