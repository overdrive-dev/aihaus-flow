#!/usr/bin/env bash
# test-auto-close.sh — regression harness for manifest-auto-close.sh
# Drives 14 fixtures under tests/fixtures/stale-manifests-260502/
#
# Each fixture dir contains:
#   RUN-MANIFEST.md — the manifest under test
#   EXPECTED.md     — key=value: result=..., reason=..., [integration_ref=...]
#   SUMMARY.md      — (optional) present for fixtures that need it
#   project.md      — (optional) for F-PROJECT-MD-LIST
#
# Strategy: each fixture runs in a temporary git sandbox repo. The hook is
# invoked from INSIDE the sandbox directory so that git commands resolve against
# the sandbox's refs, not the aihaus-flow repo.
#
# Exit 0 if all 14 pass; non-zero otherwise.
set -euo pipefail

# ---- resolve paths -----------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
FIXTURES_ROOT="${REPO_ROOT}/tests/fixtures/stale-manifests-260502"
HOOK="${REPO_ROOT}/pkg/.aihaus/hooks/manifest-auto-close.sh"

# ---- result tracking ---------------------------------------------------------
PASS=0
FAIL=0
FAIL_NAMES=()

# ---- helper: read key from EXPECTED.md ---------------------------------------
expected_val() {
  local key="$1" file="$2"
  grep "^${key}=" "$file" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r\n' || true
}

# ---- helper: run one fixture -------------------------------------------------
run_fixture() {
  local name="$1"
  local fixture_dir="${FIXTURES_ROOT}/${name}"
  local expected_file="${fixture_dir}/EXPECTED.md"

  if [[ ! -d "$fixture_dir" ]]; then
    printf "[FAIL] %-40s — fixture directory not found\n" "$name"
    FAIL=$((FAIL + 1))
    FAIL_NAMES+=("$name")
    return
  fi
  if [[ ! -f "$expected_file" ]]; then
    printf "[FAIL] %-40s — EXPECTED.md not found\n" "$name"
    FAIL=$((FAIL + 1))
    FAIL_NAMES+=("$name")
    return
  fi

  # Read expected values
  local exp_result exp_reason exp_int_ref
  exp_result="$(expected_val "result" "$expected_file")"
  exp_reason="$(expected_val "reason" "$expected_file")"
  exp_int_ref="$(expected_val "integration_ref" "$expected_file")"

  # ---- Set up temp sandbox git repo ----------------------------------------
  local sandbox
  sandbox="$(mktemp -d)"

  cleanup_sandbox() {
    rm -rf "$sandbox" 2>/dev/null || true
  }
  # Register cleanup; will be overridden per-fixture then restored
  trap 'cleanup_sandbox' EXIT

  # Init git repo in sandbox (detached from aihaus-flow)
  git -C "$sandbox" init -q --initial-branch=main 2>/dev/null \
    || git -C "$sandbox" init -q 2>/dev/null || true
  git -C "$sandbox" config user.email "test@test.com"
  git -C "$sandbox" config user.name "Test"
  git -C "$sandbox" config core.autocrlf false

  # Create initial commit on main
  printf 'init\n' > "${sandbox}/README.md"
  git -C "$sandbox" add README.md
  git -C "$sandbox" commit -q -m "init"

  # ---- Parse branch name from fixture manifest ------------------------------
  local manifest_source="${fixture_dir}/RUN-MANIFEST.md"
  local branch_name=""
  # Try v3 YAML format first: "branch: ..."
  branch_name="$(grep -E '^branch:' "${manifest_source}" | head -1 \
    | sed 's/^branch:[[:space:]]*//' | tr -d '\r\n' || true)"
  # Fall back to v1 markdown format: "**Branch:** ..."
  if [[ -z "$branch_name" ]]; then
    branch_name="$(grep -iE '^\*\*Branch:\*\*' "${manifest_source}" | head -1 \
      | sed -E 's/^\*\*Branch:\*\*[[:space:]]*//' | tr -d '\r\n' || true)"
  fi

  # ---- Create fixture branch and integration refs in sandbox ----------------
  case "$name" in
    F-MISSING-BRANCH)
      # Branch must NOT exist; create an integration ref so condition 3 is reachable
      git -C "$sandbox" update-ref refs/remotes/origin/staging \
        "$(git -C "$sandbox" rev-parse HEAD)"
      ;;
    F-NO-INTEGRATION-REF)
      # Branch exists but NO integration refs at all
      if [[ -n "$branch_name" ]]; then
        git -C "$sandbox" checkout -q -b "$branch_name"
        printf 'feature\n' > "${sandbox}/feature.txt"
        git -C "$sandbox" add feature.txt
        git -C "$sandbox" commit -q -m "feature commit"
        git -C "$sandbox" checkout -q main
      fi
      # Intentionally leave NO remote tracking refs
      ;;
    F-PROJECT-MD-LIST)
      # Branch merged into origin/release/2026 (declared in project.md)
      if [[ -n "$branch_name" ]]; then
        git -C "$sandbox" checkout -q -b "$branch_name"
        printf 'feature\n' > "${sandbox}/feature.txt"
        git -C "$sandbox" add feature.txt
        git -C "$sandbox" commit -q -m "feature commit"
        git -C "$sandbox" checkout -q main
        git -C "$sandbox" merge -q "$branch_name" --no-edit 2>/dev/null || true
        # Create integration ref origin/release/2026 (contains branch)
        git -C "$sandbox" update-ref refs/remotes/origin/release/2026 \
          "$(git -C "$sandbox" rev-parse HEAD)"
      fi
      ;;
    *)
      # Default: create branch, merge to main, set origin/staging pointing to HEAD
      if [[ -n "$branch_name" ]]; then
        git -C "$sandbox" checkout -q -b "$branch_name"
        printf 'feature-%s\n' "$name" > "${sandbox}/feature-${name}.txt"
        git -C "$sandbox" add "feature-${name}.txt"
        git -C "$sandbox" commit -q -m "feat: ${name}"
        git -C "$sandbox" checkout -q main
        git -C "$sandbox" merge -q "$branch_name" --no-edit 2>/dev/null || true
        # origin/staging contains the merged branch
        git -C "$sandbox" update-ref refs/remotes/origin/staging \
          "$(git -C "$sandbox" rev-parse HEAD)"
      fi
      ;;
  esac

  # ---- Copy manifest into sandbox under .aihaus/features/<name>/ ------------
  local run_dir="${sandbox}/.aihaus/features/${name}"
  mkdir -p "$run_dir"
  cp "$manifest_source" "${run_dir}/RUN-MANIFEST.md"

  # Copy SUMMARY.md if present
  if [[ -f "${fixture_dir}/SUMMARY.md" ]]; then
    cp "${fixture_dir}/SUMMARY.md" "${run_dir}/SUMMARY.md"
  fi

  # For F-PROJECT-MD-LIST: place project.md at .aihaus/project.md
  if [[ "$name" == "F-PROJECT-MD-LIST" ]] && [[ -f "${fixture_dir}/project.md" ]]; then
    cp "${fixture_dir}/project.md" "${sandbox}/.aihaus/project.md"
  fi

  # ---- Prepare audit log path -----------------------------------------------
  local audit_log="${sandbox}/.claude/audit/hook.jsonl"
  mkdir -p "$(dirname "$audit_log")"

  # ---- Build env overrides for special fixtures ------------------------------
  # F-NO-INTEGRATION-REF: empty override prevents fallback to defaults
  local int_refs_override_set=0
  if [[ "$name" == "F-NO-INTEGRATION-REF" ]]; then
    int_refs_override_set=1
  fi

  # ---- Run the hook from INSIDE the sandbox ---------------------------------
  # Critical: run with CWD=sandbox so git commands resolve against sandbox refs.
  # Use a subshell to avoid polluting the harness's environment and working dir.
  local hook_exit=0
  local manifest_abs="${run_dir}/RUN-MANIFEST.md"
  local audit_abs="$audit_log"

  if [[ $int_refs_override_set -eq 1 ]]; then
    (
      cd "$sandbox"
      AIHAUS_AUDIT_LOG="$audit_abs" \
      AIHAUS_INTEGRATION_REFS_OVERRIDE="" \
        bash "$HOOK" --manifest "$manifest_abs" > /dev/null 2>&1
    ) || hook_exit=$?
  else
    (
      cd "$sandbox"
      AIHAUS_AUDIT_LOG="$audit_abs" \
        bash "$HOOK" --manifest "$manifest_abs" > /dev/null 2>&1
    ) || hook_exit=$?
  fi

  # ---- Read the audit log line -----------------------------------------------
  local actual_result="" actual_reason="" actual_int_ref=""
  if [[ -f "$audit_log" ]]; then
    local last_line
    last_line="$(grep '"hook":"manifest-auto-close"' "$audit_log" 2>/dev/null | tail -1 || true)"
    if [[ -n "$last_line" ]]; then
      actual_result="$(printf '%s' "$last_line" \
        | grep -oE '"result":"[^"]*"' | head -1 | sed 's/"result":"//;s/"//' || true)"
      actual_reason="$(printf '%s' "$last_line" \
        | grep -oE '"reason":"[^"]*"' | head -1 | sed 's/"reason":"//;s/"//' || true)"
      # integration_ref may be null or a quoted string
      local ir_raw
      ir_raw="$(printf '%s' "$last_line" \
        | grep -oE '"integration_ref":"[^"]*"' | head -1 \
        | sed 's/"integration_ref":"//;s/"//' || true)"
      actual_int_ref="$ir_raw"
    fi
  fi

  # ---- Assert ----------------------------------------------------------------
  local fail_msg=""
  if [[ "$actual_result" != "$exp_result" ]]; then
    fail_msg="result: got='${actual_result}' want='${exp_result}'"
  elif [[ "$actual_reason" != "$exp_reason" ]]; then
    fail_msg="reason: got='${actual_reason}' want='${exp_reason}'"
  elif [[ -n "$exp_int_ref" && "$actual_int_ref" != "$exp_int_ref" ]]; then
    fail_msg="integration_ref: got='${actual_int_ref}' want='${exp_int_ref}'"
  fi

  if [[ -n "$fail_msg" ]]; then
    printf "[FAIL] %-40s — %s\n" "$name" "$fail_msg"
    FAIL=$((FAIL + 1))
    FAIL_NAMES+=("$name")
  else
    printf "[PASS] %-40s — result=%s reason=%s\n" "$name" "$actual_result" "$actual_reason"
    PASS=$((PASS + 1))
  fi

  # ---- Cleanup ---------------------------------------------------------------
  cleanup_sandbox
  trap - EXIT
}

# ---- run all 14 fixtures -----------------------------------------------------
printf "Running manifest-auto-close.sh fixture suite\n"
printf "Fixture root: %s\n\n" "$FIXTURES_ROOT"

FIXTURES=(
  case-1
  case-2
  case-3
  case-4
  case-5
  case-6
  case-7
  case-8
  case-9
  F-CRASH-RESUME
  F-V1-MARKDOWN
  F-NO-INTEGRATION-REF
  F-MISSING-BRANCH
  F-PROJECT-MD-LIST
)

for fixture in "${FIXTURES[@]}"; do
  run_fixture "$fixture"
done

# ---- summary -----------------------------------------------------------------
TOTAL=$((PASS + FAIL))
printf "\n"
printf "%d/%d passing\n" "$PASS" "$TOTAL"

if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  printf "Failing fixtures: %s\n" "${FAIL_NAMES[*]}"
  exit 1
fi
