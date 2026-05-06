#!/usr/bin/env bash
# tools/.fixtures/install-flow/duplicate-clone/setup.sh
#
# Builds two minimal "aihaus clone" fixtures with controlled HEAD commit
# timestamps under $1 (the test workspace / fake HOME).
#
# Usage: bash setup.sh <workspace>
#
# After this script runs, the workspace contains:
#   <workspace>/tools/aihaus/               — OLDER clone (ts ~2020-01-01)
#   <workspace>/Documents/GitHub/aihaus-flow/ — NEWER clone (ts ~2025-01-01)
#
# Both satisfy the discovery-chain candidate predicate:
#   [[ -d "${c}/pkg/.aihaus/skills" ]] && [[ -d "${c}/.git" ]]
#
# The NEWER clone should win tier-arbitration by HEAD commit timestamp.
# Verify by checking: git -C <path> log -1 --format=%ct
set -euo pipefail

WORKSPACE="${1:?usage: setup.sh <workspace>}"

# ---------------------------------------------------------------------------
# Helper: create a minimal aihaus candidate clone
# $1 = destination path
# $2 = ISO-8601 timestamp for the commit (GIT_AUTHOR_DATE / GIT_COMMITTER_DATE)
# $3 = commit message
# ---------------------------------------------------------------------------
make_clone() {
  local dest="$1" ts="$2" msg="$3"
  mkdir -p "${dest}/pkg/.aihaus/skills"
  touch "${dest}/pkg/.aihaus/skills/.keep"
  git -C "${dest}" init -q
  git -C "${dest}" config user.email "test@test.local"
  git -C "${dest}" config user.name "Test"
  GIT_AUTHOR_DATE="${ts}" GIT_COMMITTER_DATE="${ts}" \
    git -C "${dest}" commit -q --allow-empty -m "${msg}"
}

# Older clone at tier-5 path
OLDER="${WORKSPACE}/tools/aihaus"
make_clone "${OLDER}" "2020-01-01T00:00:00+00:00" "initial (old)"

# Newer clone at tier-6 path
NEWER="${WORKSPACE}/Documents/GitHub/aihaus-flow"
make_clone "${NEWER}" "2025-01-01T00:00:00+00:00" "initial (new)"

echo "setup.sh: created OLDER=${OLDER} (ts=$(git -C "${OLDER}" log -1 --format=%ct))"
echo "setup.sh: created NEWER=${NEWER} (ts=$(git -C "${NEWER}" log -1 --format=%ct))"
