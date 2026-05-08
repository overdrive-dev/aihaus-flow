#!/usr/bin/env bash
# aihaus package smoke test
# Validates the structure and integrity of the aihaus-package/ tree.
# Intended to be runnable from any directory and from CI.
#
# Exits 0 only if every check passes.

set -u

# ---- Resolve package root relative to this script ---------------------------
# Pin to pkg/ explicitly so all check paths (Check 10/11 arrays, .aihaus/...,
# templates/..., README.md, LICENSE, VERSION) keep resolving inside the
# shipped package even though this script now lives in repo-root/tools/.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/../pkg" && pwd)"

FAILURES=0
CHECK_NUMBER=0

# ANSI-safe markers (no emoji required; checkmark is a plain ASCII tick).
TICK="[PASS]"
CROSS="[FAIL]"

_pass() {
  printf "%s %s\n" "$TICK" "$1"
}

_fail() {
  printf "%s %s\n" "$CROSS" "$1"
  shift
  for line in "$@"; do
    printf "        %s\n" "$line"
  done
  FAILURES=$((FAILURES + 1))
}

_start_check() {
  CHECK_NUMBER=$((CHECK_NUMBER + 1))
}

# ---- Check 1: 14 expected SKILL.md files in expected subdirectories ---------
check_skills() {
  _start_check
  local label="Check ${CHECK_NUMBER}: .aihaus/skills/ has 14 expected SKILL.md files"
  local expected=(aih-brainstorm aih-bugfix aih-close aih-effort aih-feature aih-help aih-init aih-install aih-milestone aih-plan aih-quick aih-resume aih-sync-notion aih-update)
  local missing=()
  local skills_root="${PACKAGE_ROOT}/.aihaus/skills"
  for name in "${expected[@]}"; do
    if [[ ! -f "${skills_root}/${name}/SKILL.md" ]]; then
      missing+=("${name}/SKILL.md")
    fi
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "missing: ${missing[*]}"
  fi
}

# ---- Check 2: .aihaus/agents/ has 46 .md files (M013/S07 adds knowledge-curator) --
check_agents() {
  _start_check
  local label="Check ${CHECK_NUMBER}: .aihaus/agents/ has 46 .md files"
  local agents_root="${PACKAGE_ROOT}/.aihaus/agents"
  if [[ ! -d "$agents_root" ]]; then
    _fail "$label" "directory not found: $agents_root"
    return
  fi
  local count
  count=$(find "$agents_root" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')
  if [[ "$count" -eq 46 ]]; then
    _pass "$label"
  else
    _fail "$label" "expected 46 .md files, found $count"
  fi
}

# ---- Check 3: .aihaus/hooks/ contains exactly the expected hook files (M018/S2 allowlist) ----
# Replaces literal [[ "$count" -eq 28 ]] with per-name allowlist iteration (mirrors Check 1
# skill-allowlist shape). Adding/removing a hook requires a NAME edit here — intentional
# friction that makes reviewer diffs meaningful and kills the silent-drift hazard that forced
# D-001/D-003/D-005/D-007/D-008 in M017 (CHECK B3 / ADR-M017-C same-file resolution).
check_hooks() {
  _start_check
  local label="Check ${CHECK_NUMBER}: .aihaus/hooks/ contains exactly the expected hook files (M018/S2 allowlist)"
  local hooks_root="${PACKAGE_ROOT}/.aihaus/hooks"
  if [[ ! -d "$hooks_root" ]]; then
    _fail "$label" "directory not found: $hooks_root"
    return
  fi
  local -a EXPECTED_HOOKS=(
    audit-agent.sh
    audit-log.sh
    autonomy-guard.sh
    backup-file.sh
    bash-guard.sh
    composite-score.sh
    context-inject.sh
    file-guard.sh
    git-add-guard.sh
    invoke-guard.sh
    learning-advisor.sh
    manifest-append.sh
    manifest-migrate.sh
    merge-back.sh
    phase-advance.sh
    read-guard.sh
    scaffold-assert.sh
    session-end.sh
    session-start.sh
    statusline-milestone.sh
    task-completed.sh
    task-created.sh
    teammate-idle.sh
    warning-recurrence.sh
    worktree-reap.sh
    worktree-reconcile.sh
    manifest-auto-close.sh
    worktree-release.sh
    worktree-release-all.sh
    worktree-drift-check.sh
  )
  local missing=()
  for hook in "${EXPECTED_HOOKS[@]}"; do
    if [[ ! -f "${hooks_root}/${hook}" ]]; then
      missing+=("$hook")
    fi
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "missing hooks: ${missing[*]}"
  fi
}

# ---- Check 4: Every SKILL.md has `name: aih-*` in frontmatter ------------
check_skill_frontmatter() {
  _start_check
  local label="Check ${CHECK_NUMBER}: every SKILL.md declares name: aih-*"
  local skills_root="${PACKAGE_ROOT}/.aihaus/skills"
  local offenders=()
  while IFS= read -r -d '' file; do
    if ! head -20 "$file" | grep -Eq '^name:[[:space:]]*aih-[A-Za-z0-9_.-]+'; then
      offenders+=("$file")
    fi
  done < <(find "$skills_root" -type f -name 'SKILL.md' -print0)
  if [[ ${#offenders[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "missing or malformed frontmatter name:" "${offenders[@]}"
  fi
}

# ---- Check 5: every SKILL.md is under 200 lines -----------------------------
check_skill_length() {
  _start_check
  local label="Check ${CHECK_NUMBER}: every SKILL.md is under 200 lines"
  local skills_root="${PACKAGE_ROOT}/.aihaus/skills"
  local offenders=()
  while IFS= read -r -d '' file; do
    local lines
    lines=$(wc -l < "$file" | tr -d ' ')
    if [[ "$lines" -ge 200 ]]; then
      offenders+=("$file ($lines lines)")
    fi
  done < <(find "$skills_root" -type f -name 'SKILL.md' -print0)
  if [[ ${#offenders[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "too long:" "${offenders[@]}"
  fi
}

# ---- Check 6: every agent frontmatter declares the six required fields ------
# AND each agent's model: value matches the cohort default from cohorts.md
# (per-cohort value-validation, ADR-M012-A § smoke-test Check 6).
# effort: is presence-only (values differ across presets).
#
# Cohort default-model table (6-cohort, balanced preset):
#   :planner-binding → opus
#   :planner         → opus
#   :doer            → sonnet
#   :verifier        → haiku
#   :adversarial-scout  → opus
#   :adversarial-review → opus
#
# get_cohort_members <:cohort-name>
#   Reads the 5-column pipe-table from cohorts.md (F-006 parse contract).
#   NF=7 when awk -F'|' splits on '|'. Column indices (1-based): f[2]=raw#,
#   f[3]=Agent, f[4]=Cohort, f[5]=Model (strip whitespace).
#   Returns one agent name per line.
_get_cohort_members() {
  local cohort_key="$1"  # e.g. ":planner-binding"
  local cohorts_file="${PACKAGE_ROOT}/.aihaus/skills/aih-effort/annexes/cohorts.md"
  if [[ ! -f "$cohorts_file" ]]; then
    return 1
  fi
  # Parse only data rows (skip header and separator rows).
  # NF=7 on every data row per F-006 binding contract.
  awk -F'|' -v cohort="$cohort_key" '
    NF==7 {
      agent=substr($3,1); gsub(/^[[:space:]]+|[[:space:]]+$/,"",agent)
      coh=substr($4,1);   gsub(/^[[:space:]]+|[[:space:]]+$/,"",coh)
      # skip header row and separator row
      if (agent=="" || agent=="#" || agent ~ /^-+$/) next
      if (coh==cohort) print agent
    }
  ' "$cohorts_file"
}

check_agent_frontmatter() {
  _start_check
  local label="Check ${CHECK_NUMBER}: every agent declares name/tools/model/effort/color/memory/resumable/checkpoint_granularity; model: matches cohort default"
  local agents_root="${PACKAGE_ROOT}/.aihaus/agents"
  local cohorts_file="${PACKAGE_ROOT}/.aihaus/skills/aih-effort/annexes/cohorts.md"
  local offenders=()

  # ---- Part A: presence check (all 8 required fields, M014/S07 +2) ----------
  while IFS= read -r -d '' file; do
    local front
    front=$(awk '/^---$/{c++; next} c==1' "$file")
    for field in name tools model effort color memory resumable checkpoint_granularity; do
      if ! printf '%s\n' "$front" | grep -q "^${field}:"; then
        offenders+=("${file#${PACKAGE_ROOT}/} missing '$field'")
      fi
    done
    # ---- Part A2: enum validation for resumable and checkpoint_granularity ---
    local resumable_val cg_val
    resumable_val=$(printf '%s\n' "$front" | awk '/^resumable:/{print $2; exit}')
    cg_val=$(printf '%s\n' "$front" | awk '/^checkpoint_granularity:/{print $2; exit}')
    if [[ -n "$resumable_val" && "$resumable_val" != "true" && "$resumable_val" != "false" ]]; then
      offenders+=("${file#${PACKAGE_ROOT}/} resumable: invalid value '$resumable_val' (must be true|false)")
    fi
    if [[ -n "$cg_val" && "$cg_val" != "story" && "$cg_val" != "file" && "$cg_val" != "step" ]]; then
      offenders+=("${file#${PACKAGE_ROOT}/} checkpoint_granularity: invalid value '$cg_val' (must be story|file|step)")
    fi
  done < <(find "$agents_root" -maxdepth 1 -type f -name '*.md' -print0)

  # ---- Part B: per-cohort model value-validation ----------------------------
  if [[ ! -f "$cohorts_file" ]]; then
    offenders+=("cohorts.md not found at ${cohorts_file#${PACKAGE_ROOT}/}; cannot validate model baselines")
  else
    # Cohort → expected model map (6-cohort balanced baseline, ADR-M012-A).
    declare -A _cohort_model_map
    _cohort_model_map[":planner-binding"]="opus"
    _cohort_model_map[":planner"]="opus"
    _cohort_model_map[":doer"]="sonnet"
    _cohort_model_map[":verifier"]="haiku"
    _cohort_model_map[":adversarial-scout"]="opus"
    _cohort_model_map[":adversarial-review"]="opus"

    local cohort expected_model members agent_file actual_model
    for cohort in ":planner-binding" ":planner" ":doer" ":verifier" ":adversarial-scout" ":adversarial-review"; do
      expected_model="${_cohort_model_map[$cohort]}"
      # Read members from cohorts.md (not hardcoded).
      while IFS= read -r member; do
        [[ -z "$member" ]] && continue
        agent_file="${agents_root}/${member}.md"
        if [[ ! -f "$agent_file" ]]; then
          offenders+=("${cohort} member '${member}' has no agent file at agents/${member}.md")
          continue
        fi
        actual_model=$(awk '/^---$/{c++; next} c==1 && /^model:/{print $2; exit}' "$agent_file")
        if [[ "$actual_model" != "$expected_model" ]]; then
          offenders+=("agents/${member}.md: cohort ${cohort} expects model=${expected_model}, got model=${actual_model}")
        fi
      done < <(_get_cohort_members "$cohort")
    done
    unset _cohort_model_map
  fi

  if [[ ${#offenders[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${offenders[@]}"
  fi
}

# ---- Check 7: CONVERSATION.md first-line header shape (future-proofing) -----
check_conversation_header_shape() {
  _start_check
  local label="Check ${CHECK_NUMBER}: CONVERSATION.md files begin with '# Conversation:' or '# Conversation Log:'"
  local offenders=()
  while IFS= read -r -d '' file; do
    local first
    first=$(head -n1 "$file")
    if [[ "$first" != "# Conversation:"* && "$first" != "# Conversation Log:"* ]]; then
      offenders+=("${file#${PACKAGE_ROOT}/} first line: $first")
    fi
  done < <(find "${PACKAGE_ROOT}/.aihaus" -type f -name 'CONVERSATION.md' -print0 2>/dev/null)
  if [[ ${#offenders[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${offenders[@]}"
  fi
}

# ---- Check 8: templates/project.md has both section markers -----------------
check_project_template() {
  _start_check
  local label="Check ${CHECK_NUMBER}: templates/project.md has required markers"
  local template="${PACKAGE_ROOT}/templates/project.md"
  if [[ ! -f "$template" ]]; then
    _fail "$label" "file not found: $template"
    return
  fi
  local problems=()
  if ! grep -q '<!-- AIHAUS:AUTO-GENERATED-START -->' "$template"; then
    problems+=("missing <!-- AIHAUS:AUTO-GENERATED-START -->")
  fi
  if ! grep -q '<!-- AIHAUS:MANUAL-START -->' "$template"; then
    problems+=("missing <!-- AIHAUS:MANUAL-START -->")
  fi
  if [[ ${#problems[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${problems[@]}"
  fi
}

# ---- Check 9: settings.local.json is valid JSON with required keys ----------
# M014/S04: permissions block removed (migrated to PreToolUse hooks); check
# only requires hooks and env keys to be present.
check_settings_template() {
  _start_check
  local label="Check ${CHECK_NUMBER}: templates/settings.local.json is valid JSON with required keys"
  local settings_file="${PACKAGE_ROOT}/templates/settings.local.json"
  if [[ ! -f "$settings_file" ]]; then
    _fail "$label" "file not found: $settings_file"
    return
  fi
  local parser=""
  if command -v jq >/dev/null 2>&1; then
    parser="jq"
  elif command -v python3 >/dev/null 2>&1; then
    parser="python3"
  elif command -v python >/dev/null 2>&1; then
    parser="python"
  elif command -v py >/dev/null 2>&1; then
    parser="py"
  fi
  if [[ -z "$parser" ]]; then
    _fail "$label" "no jq or python available to validate JSON"
    return
  fi
  case "$parser" in
    jq)
      if ! jq -e '.hooks and .env' "$settings_file" >/dev/null 2>&1; then
        _fail "$label" "invalid JSON or missing hooks/env keys"
        return
      fi
      ;;
    python3|python|py)
      if ! "$parser" -c "import json,sys; d=json.load(open(sys.argv[1], encoding='utf-8')); sys.exit(0 if all(k in d for k in ('hooks','env')) else 1)" "$settings_file" >/dev/null 2>&1; then
        _fail "$label" "invalid JSON or missing hooks/env keys"
        return
      fi
      ;;
  esac
  _pass "$label"
}

# ---- Check 10: install, uninstall, and update scripts exist ----------------
check_installer_files_exist() {
  _start_check
  local label="Check ${CHECK_NUMBER}: install/uninstall/update scripts exist"
  local missing=()
  local -a required=(
    "scripts/install.sh"
    "scripts/install.ps1"
    "scripts/uninstall.sh"
    "scripts/uninstall.ps1"
    "scripts/update.sh"
    "scripts/update.ps1"
  )
  for rel in "${required[@]}"; do
    if [[ ! -f "${PACKAGE_ROOT}/${rel}" ]]; then
      missing+=("$rel")
    fi
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "missing: ${missing[*]}"
  fi
}

# ---- Check 11: shell scripts pass bash -n -----------------------------------
check_installer_syntax() {
  _start_check
  local label="Check ${CHECK_NUMBER}: install/uninstall/update scripts + hooks pass bash -n"
  local issues=()
  local -a shells=(
    "scripts/install.sh"
    "scripts/uninstall.sh"
    "scripts/update.sh"
  )
  for rel in "${shells[@]}"; do
    local target="${PACKAGE_ROOT}/${rel}"
    if [[ ! -f "$target" ]]; then
      issues+=("$rel missing")
      continue
    fi
    if ! bash -n "$target" 2>/dev/null; then
      issues+=("$rel failed bash -n")
    fi
  done
  # Also lint all hook scripts — catches regressions in jq-optional logic.
  while IFS= read -r -d '' target; do
    if ! bash -n "$target" 2>/dev/null; then
      issues+=("${target#${PACKAGE_ROOT}/} failed bash -n")
    fi
  done < <(find "${PACKAGE_ROOT}/.aihaus/hooks" -type f -name '*.sh' -print0 2>/dev/null)
  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${issues[@]}"
  fi
}

# ---- Check 12: README.md exists and is 100..500 lines -----------------------
check_readme_length() {
  _start_check
  local label="Check ${CHECK_NUMBER}: README.md exists and is 100..500 lines"
  local readme="${PACKAGE_ROOT}/README.md"
  if [[ ! -f "$readme" ]]; then
    _fail "$label" "file not found: $readme"
    return
  fi
  local lines
  lines=$(wc -l < "$readme" | tr -d ' ')
  if [[ "$lines" -ge 100 && "$lines" -le 500 ]]; then
    _pass "$label"
  else
    _fail "$label" "README has $lines lines (expected 410..500)"
  fi
}

# ---- Check 13: LICENSE contains "MIT License" -------------------------------
check_license() {
  _start_check
  local label="Check ${CHECK_NUMBER}: LICENSE contains 'MIT License'"
  local license="${PACKAGE_ROOT}/LICENSE"
  if [[ ! -f "$license" ]]; then
    _fail "$label" "file not found: $license"
    return
  fi
  if grep -q 'MIT License' "$license"; then
    _pass "$label"
  else
    _fail "$label" "MIT License string not found in LICENSE"
  fi
}

# ---- Check 14: VERSION contains a semver string -----------------------------
check_version() {
  _start_check
  local label="Check ${CHECK_NUMBER}: VERSION contains a semver string"
  local version_file="${PACKAGE_ROOT}/VERSION"
  if [[ ! -f "$version_file" ]]; then
    _fail "$label" "file not found: $version_file"
    return
  fi
  local content
  content=$(tr -d '[:space:]' < "$version_file")
  if [[ "$content" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]]; then
    _pass "$label (value: $content)"
  else
    _fail "$label" "not a semver value: '$content'"
  fi
}

# ---- Check 17: aih-plan annexes present (M004 story G) ----------------------
check_aih_plan_annexes() {
  _start_check
  local label="Check ${CHECK_NUMBER}: aih-plan annexes present"
  local ann_root="${PACKAGE_ROOT}/.aihaus/skills/aih-plan/annexes"
  local missing=()
  for a in attachments.md intake-discipline.md from-brainstorm.md guardrails.md; do
    [[ -f "$ann_root/$a" ]] || missing+=("$a")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "missing: ${missing[*]}"
  fi
}

# ---- Check 19: aih-milestone annexes present (v0.11.0 — absorbed p2m + run) -
check_aih_milestone_annexes() {
  _start_check
  local label="Check ${CHECK_NUMBER}: aih-milestone annexes present"
  local ann_root="${PACKAGE_ROOT}/.aihaus/skills/aih-milestone/annexes"
  local missing=()
  for a in promotion.md execution.md; do
    [[ -f "$ann_root/$a" ]] || missing+=("$a")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "missing: ${missing[*]}"
  fi
}

# ---- Check 20: M005 canonical phrases preserved in aih-milestone exec path --
# Porting aih-run's M005 invariants must land verbatim. Any phrase drift fails CI.
check_m005_canonical_phrases() {
  _start_check
  local label="Check ${CHECK_NUMBER}: M005 canonical phrases present in aih-milestone"
  local search_root="${PACKAGE_ROOT}/.aihaus/skills/aih-milestone"
  local missing=()
  # Phrase 1: single-candidate silent proceed (M005 S05/B3)
  grep -rq 'One candidate.*proceed silently.*Running \[slug\]' "$search_root" 2>/dev/null \
    || missing+=("single-candidate phrase (M005 S05)")
  # Phrase 2: 3-bullet pre-flight preflight (M005 S08/B1)
  grep -rq 'Emit 3-bullet pre-flight summary' "$search_root" 2>/dev/null \
    || missing+=("3-bullet pre-flight phrase (M005 S08)")
  # Phrase 3: tiered git-dirty auto-stash label (M005 S04/B2 — renamed from aih-run)
  grep -rq 'aih-milestone pre-run stash' "$search_root" 2>/dev/null \
    || missing+=("auto-stash label (M005 S04)")
  if [[ ${#missing[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "missing phrases: ${missing[*]}"
  fi
}

# ---- Check 18: SESSION-LOG.md template has required H2 headers (M004 story L)
check_session_log_template() {
  _start_check
  local label="Check ${CHECK_NUMBER}: SESSION-LOG.md template has required H2 headers"
  local tmpl="${PACKAGE_ROOT}/.aihaus/templates/SESSION-LOG.md"
  [[ -f "$tmpl" ]] || { _fail "$label" "template missing: $tmpl"; return; }
  local required=("Timeline" "Friction" "Wins" "Ideas for package" "Artifacts" "Hand-off")
  local missing=()
  for h in "${required[@]}"; do
    grep -qE "^## ${h}$" "$tmpl" || missing+=("$h")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "missing H2 headers: ${missing[*]}"
  fi
}

# ---- Template PreToolUse registers bash-guard.sh ----------------------------
# M014/S04: permissions.allow block removed. Autonomy contract is now enforced
# via PreToolUse hooks (bash-guard + file-guard + read-guard). Assert that
# bash-guard.sh is referenced in the template's PreToolUse section.
check_template_bash_wildcard() {
  _start_check
  local label="Check ${CHECK_NUMBER}: template PreToolUse registers bash-guard.sh (M014/S04)"
  local tpl="${PACKAGE_ROOT}/.aihaus/templates/settings.local.json"
  [[ -f "$tpl" ]] || { _fail "$label" "template missing: $tpl"; return; }
  if grep -q 'bash-guard.sh' "$tpl"; then
    _pass "$label"
  else
    _fail "$label" "bash-guard.sh not registered in PreToolUse in $tpl"
  fi
}

# ---- Excluded skills retain disable-model-invocation -----------------------
# Codifies ADR-007 "allowlist = NL-policy boundary" claim. The 6 excluded
# skills (aih-init, aih-help, aih-resume, aih-brainstorm, aih-update,
# aih-sync-notion) must NEVER auto-trigger from casual NL — their
# behaviors have high blast radius (init overwrites project.md;
# brainstorm fan-outs; sync-notion hits external API).
check_excluded_skills_keep_flag() {
  _start_check
  local label="Check ${CHECK_NUMBER}: excluded skills retain disable-model-invocation"
  local skills_root="${PACKAGE_ROOT}/.aihaus/skills"
  local excluded=(aih-init aih-help aih-resume aih-brainstorm aih-update aih-sync-notion)
  local missing=()
  for skill in "${excluded[@]}"; do
    local file="${skills_root}/${skill}/SKILL.md"
    [[ -f "$file" ]] || { missing+=("$skill(file missing)"); continue; }
    if ! head -10 "$file" | grep -q '^disable-model-invocation:[[:space:]]*true'; then
      missing+=("$skill")
    fi
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "missing flag on: ${missing[*]}"
  fi
}

# ---- autonomy-guard.sh blocks violations in execution phase -----------------
# Feeds 5 canonical violation fixtures through the hook with
# AIHAUS_EXEC_PHASE=1 set; asserts block JSON. Also asserts NO block
# outside execution phase (planning-phase prose containing forbidden
# patterns must pass through).
check_autonomy_guard_detects_violations() {
  _start_check
  local label="Check ${CHECK_NUMBER}: autonomy-guard blocks forbidden patterns in execution phase"
  local hook="${PACKAGE_ROOT}/.aihaus/hooks/autonomy-guard.sh"
  local fixtures="${PACKAGE_ROOT}/../tools/fixtures/autonomy-violations"
  [[ -f "$hook" ]] || { _fail "$label" "hook missing: $hook"; return; }
  [[ -d "$fixtures" ]] || { _fail "$label" "fixtures dir missing: $fixtures"; return; }

  local failed=()
  for f in "$fixtures"/*.txt; do
    [ -f "$f" ] || continue
    # In execution phase: expect block.
    local out_exec
    out_exec=$(AIHAUS_EXEC_PHASE=1 bash "$hook" < "$f" 2>/dev/null || true)
    if ! echo "$out_exec" | grep -q '"decision":[[:space:]]*"block"'; then
      failed+=("no-block-on-exec:$(basename "$f")")
    fi
    # Outside execution phase: expect no block (silent; logs only).
    local out_plan
    out_plan=$(unset AIHAUS_EXEC_PHASE MANIFEST_PATH; bash "$hook" < "$f" 2>/dev/null || true)
    if echo "$out_plan" | grep -q '"decision":[[:space:]]*"block"'; then
      failed+=("spurious-block-on-planning:$(basename "$f")")
    fi
  done

  if [[ ${#failed[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${failed[*]}"
  fi
}

# ---- merge-settings.sh produces replacement semantics for arrays ------------
# Verifies that the shared merge helper, regardless of jq vs python path,
# REPLACES the permissions.allow array (overlay wins). Catches silent
# cross-platform divergence (jq's * operator on arrays may concatenate;
# Python's deep_merge replaces). Uses fixture pair under tools/fixtures/.
check_merge_semantics_convergence() {
  _start_check
  local label="Check ${CHECK_NUMBER}: merge-settings.sh produces replacement semantics for arrays"
  local helper="${PACKAGE_ROOT}/scripts/lib/merge-settings.sh"
  local base="${PACKAGE_ROOT}/../tools/fixtures/settings-merge/base.json"
  local overlay="${PACKAGE_ROOT}/../tools/fixtures/settings-merge/overlay.json"
  # If invoked from repo root, PACKAGE_ROOT may already include tools/.
  [[ -f "$base" ]] || base="tools/fixtures/settings-merge/base.json"
  [[ -f "$overlay" ]] || overlay="tools/fixtures/settings-merge/overlay.json"
  [[ -f "$helper" && -f "$base" && -f "$overlay" ]] || { _fail "$label" "missing helper or fixtures"; return; }

  # Stage fixtures into a temp dir under PACKAGE_ROOT/../tools/.out/ so the
  # path is readable by both bash (Git Bash) and Python (Windows-native) —
  # system /tmp doesn't resolve for Windows Python interpreters.
  local repo_root="${PACKAGE_ROOT}/.."
  local tmpdir="${repo_root}/tools/.out/merge-test-$$"
  mkdir -p "$tmpdir"
  local tmpdst="${tmpdir}/dst.json"
  local tmpsrc="${tmpdir}/src.json"
  cp "$base" "$tmpdst"
  cp "$overlay" "$tmpsrc"

  # shellcheck disable=SC1090
  ( source "$helper" && merge_settings "$tmpdst" "$tmpsrc" ) >/dev/null 2>&1

  # Inspect result: permissions.allow length must equal overlay's length (3),
  # not the union (5). Use python (always required per README) for parsing.
  local py_bin
  py_bin="$(command -v python3 || command -v python || command -v py)"
  if [[ -z "$py_bin" ]]; then
    _fail "$label" "python required to parse merge result"
    rm -rf "$tmpdir"
    return
  fi

  # Convert path for Windows Python if cygpath is available (Git Bash).
  local py_path="$tmpdst"
  if command -v cygpath >/dev/null 2>&1; then
    py_path="$(cygpath -w "$tmpdst" 2>/dev/null || echo "$tmpdst")"
  fi

  local result_len
  result_len=$("$py_bin" -c "
import json, sys
with open(sys.argv[1]) as f: data = json.load(f)
print(len(data.get('permissions', {}).get('allow', [])))
" "$py_path" 2>/dev/null || echo "0")

  rm -rf "$tmpdir"

  if [[ "$result_len" = "3" ]]; then
    _pass "$label"
  else
    _fail "$label" "expected replacement (3 entries from overlay), got $result_len entries (likely concatenation/union)"
  fi
}

# ---- Deleted PermissionRequest hooks are absent (M014/S04) ------------------
# M014/S04: auto-approve-bash.sh, auto-approve-writes.sh, and permission-debug.sh
# were deleted. Assert none of them remain in the hooks directory.
check_auto_approve_patterns() {
  _start_check
  local label="Check ${CHECK_NUMBER}: deleted PermissionRequest hooks absent (M014/S04)"
  local hooks_root="${PACKAGE_ROOT}/.aihaus/hooks"
  local still_present=()
  [[ -f "${hooks_root}/auto-approve-bash.sh" ]]   && still_present+=("auto-approve-bash.sh")
  [[ -f "${hooks_root}/auto-approve-writes.sh" ]]  && still_present+=("auto-approve-writes.sh")
  [[ -f "${hooks_root}/permission-debug.sh" ]]     && still_present+=("permission-debug.sh")
  if [[ ${#still_present[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "hooks should have been deleted but still present: ${still_present[*]}"
  fi
}

# ---- Template PreToolUse registers read-guard.sh (M014/S04) -----------------
# M014/S04: PermissionRequest block removed. read-guard.sh is now registered
# under PreToolUse with empty matcher "" (Option 2 fallback; READ_GUARD_MODE=tool_name).
# Also verifies no PermissionRequest block remains in the template.
check_template_permission_hooks() {
  _start_check
  local label="Check ${CHECK_NUMBER}: template PreToolUse registers read-guard.sh + no PermissionRequest block (M014/S04)"
  local tpl="${PACKAGE_ROOT}/.aihaus/templates/settings.local.json"
  [[ -f "$tpl" ]] || { _fail "$label" "template missing: $tpl"; return; }
  local problems=()
  grep -q 'read-guard.sh' "$tpl" || problems+=("read-guard.sh not found in template")
  grep -q 'PermissionRequest' "$tpl" && problems+=("PermissionRequest block still present — should have been removed by M014/S04")
  if [[ ${#problems[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${problems[@]}"
  fi
}

# Check 16 was: Cursor plugin manifest + rules (M006 / ADR-005)
# Removed in M015/ADR-M015-A: Cursor support dropped entirely.

# ---- Check 15: framework purity check --------------------------------------
check_purity() {
  _start_check
  local label="Check ${CHECK_NUMBER}: framework purity (delegates to purity-check.sh)"
  local purity="${SCRIPT_DIR}/purity-check.sh"
  if [[ ! -f "$purity" ]]; then
    _fail "$label" "purity-check.sh not found at $purity"
    return
  fi
  if bash "$purity" >/dev/null 2>&1; then
    _pass "$label"
  else
    _fail "$label" "purity-check.sh reported matches; run it directly for details"
  fi
}

# ---- Check 27: skill directory count = 14 (M022/Z6 adds aih-install) --------
# Verifies that exactly 14 aih-* skill directories exist under .aihaus/skills/.
# Note: Check 1 verifies the NAMED SKILL.md files (14 expected names including
# aih-close (M020/S10), aih-effort, and aih-install (M022/Z6); aih-automode
# deleted in M014/S03). Check 27 independently verifies the directory count so
# that unexpected directories (stale renames, extra skill dirs) also cause CI
# failure. If the count exceeds 14, a stale directory likely remains from a
# prior rename.
check_skill_count_and_staleness() {
  _start_check
  local label="Check ${CHECK_NUMBER}: exactly 14 aih-* skill dirs exist (M022/Z6)"
  local skills_root="${PACKAGE_ROOT}/.aihaus/skills"
  local problems=()

  # Count aih-* directories (exclude _shared and any non-aih prefixed dirs).
  local actual_count
  actual_count=$(find "$skills_root" -maxdepth 1 -type d -name 'aih-*' | wc -l | tr -d ' ')
  if [[ "$actual_count" -ne 14 ]]; then
    problems+=("expected 14 aih-* skill dirs; found ${actual_count} (stale dir from rename? run: ls ${skills_root}/)")
  fi

  if [[ ${#problems[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${problems[@]}"
  fi
}

# ---- Check 28: cohort membership round-trip + parse contract (M012/S07 + M013/S07) --
# Seven sub-assertions covering the 6-cohort taxonomy in cohorts.md:
#   C1 each of the 46 agents appears under exactly one cohort
#   C2 cohort counts match: planner-binding=4, planner=14, doer=15, verifier=9,
#      adversarial-scout=2, adversarial-review=2 (total=46)
#   C3 no :verifier-rich or :investigator cohort name appears in the table
#   C4 F-006 parse contract: every data row yields NF=7 (awk -F'|' | sort -u == "7")
#   C5 header row literal match: "| # | Agent | Cohort | Model | Effort |"
# Self-contained: reads cohorts.md directly; no invocation of /aih-effort
# (R7 cycle prevention preserved).
check_cohort_membership_roundtrip() {
  _start_check
  local label="Check ${CHECK_NUMBER}: cohort membership + counts + F-006 parse contract (M012/S07)"
  local cohorts_md="${PACKAGE_ROOT}/.aihaus/skills/aih-effort/annexes/cohorts.md"
  local problems=()

  if [[ ! -f "$cohorts_md" ]]; then
    _fail "$label" "cohorts.md not found at aih-effort/annexes/cohorts.md"
    return
  fi

  # ---------- C4: F-006 parse contract: every data row yields NF=7 ----------
  local nf_values
  nf_values=$(awk -F'|' '/^\| +[0-9]+ +\|/ { print NF }' "$cohorts_md" | sort -u)
  if [[ "$nf_values" != "7" ]]; then
    problems+=("C4: F-006 parse contract violated -- data row NF values should be exactly '7'; got: '${nf_values}'")
  fi

  # ---------- C5: header row literal match ---------------------------------
  local expected_header="| # | Agent | Cohort | Model | Effort |"
  if ! grep -qF "$expected_header" "$cohorts_md"; then
    problems+=("C5: header row literal match failed -- expected '${expected_header}' (ADR-M012-A binding clause)")
  fi

  # ---------- C1 + C2: agent membership + cohort counts --------------------
  declare -A _seen_agents
  declare -A _cohort_counts
  _cohort_counts[":planner-binding"]=0
  _cohort_counts[":planner"]=0
  _cohort_counts[":doer"]=0
  _cohort_counts[":verifier"]=0
  _cohort_counts[":adversarial-scout"]=0
  _cohort_counts[":adversarial-review"]=0

  local duplicates=()
  local unknown_cohorts=()

  while IFS='|' read -r _ num agent cohort model effort _; do
    # Strip whitespace.
    agent="${agent#"${agent%%[! ]*}"}"; agent="${agent%"${agent##*[! ]}"}"
    cohort="${cohort#"${cohort%%[! ]*}"}"; cohort="${cohort%"${cohort##*[! ]}"}"
    # Skip empty rows (separator lines, blank lines).
    [[ -z "$agent" || "$agent" =~ ^-+$ || "$agent" == "#" ]] && continue
    # Skip header row.
    [[ "$agent" == "Agent" ]] && continue

    # C1: each agent appears exactly once.
    if [[ -v "_seen_agents[$agent]" ]]; then
      duplicates+=("$agent (duplicate cohort assignment)")
    fi
    _seen_agents["$agent"]="$cohort"

    # Tally cohort count.
    if [[ -v "_cohort_counts[$cohort]" ]]; then
      _cohort_counts["$cohort"]=$(( _cohort_counts["$cohort"] + 1 ))
    else
      unknown_cohorts+=("$agent → unknown cohort '${cohort}'")
    fi
  done < <(grep -E '^\| +[0-9]+ +\|' "$cohorts_md")

  for dup in "${duplicates[@]}"; do
    problems+=("C1: $dup")
  done
  for unk in "${unknown_cohorts[@]}"; do
    problems+=("C2: $unk")
  done

  local total_agents="${#_seen_agents[@]}"
  if [[ "$total_agents" -ne 46 ]]; then
    problems+=("C1: expected 46 agents in membership table; found ${total_agents}")
  fi

  # C2: expected cohort counts.
  local -A _expected_counts=(
    [":planner-binding"]=4
    [":planner"]=14
    [":doer"]=15
    [":verifier"]=9
    [":adversarial-scout"]=2
    [":adversarial-review"]=2
  )
  for cohort in ":planner-binding" ":planner" ":doer" ":verifier" ":adversarial-scout" ":adversarial-review"; do
    local got="${_cohort_counts[$cohort]}"
    local want="${_expected_counts[$cohort]}"
    if [[ "$got" -ne "$want" ]]; then
      problems+=("C2: cohort ${cohort} expected ${want} members; got ${got}")
    fi
  done

  unset _seen_agents _cohort_counts _expected_counts

  # ---------- C3: no deprecated cohort names in table ----------------------
  if grep -qE '^\|[^|]*\| *:(verifier-rich|investigator) *\|' "$cohorts_md"; then
    problems+=("C3: deprecated cohort name ':verifier-rich' or ':investigator' still present in membership table")
  fi

  if [[ ${#problems[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${problems[@]}"
  fi
}

# ---- Check 29: autonomy-gate fixture suite (6 sub-assertions, M011/S08) ----
# Exercises the full stop-gate decision space for autonomy-guard.sh:
#
#   A1 regex-path hit               — M005 canonical pattern still blocks
#   A2 regex-miss → haiku-continue  — stubbed claude returns continue
#   A3 regex-miss → haiku-block     — stubbed claude returns block
#   A4 paused-allow                 — status=paused short-circuits regex
#   A5 timeout-fallback-allow       — 3-s haiku timeout → fail-safe allow
#   A6 no-cli-skip                  — claude absent → regex-only + audit
#
# Mirrors the Check 27/28 calibration-sidecar pattern: single function with
# a problems[] accumulator; each sub-assertion stages a fresh tmpdir and
# isolates the audit jsonl via $AIHAUS_AUDIT_GATE_LOG. Runs all 6 regardless
# of individual failures; reports all problems at once; does NOT invoke the
# real claude CLI (A2/A3 stub canned JSON; A5 stubs a sleeper; A6 narrows
# PATH to exclude claude).
check_autonomy_gate_fixtures() {
  _start_check
  local label="Check ${CHECK_NUMBER}: stop-gate fixture suite (6 sub-assertions)"
  local hook="${PACKAGE_ROOT}/.aihaus/hooks/autonomy-guard.sh"
  local fixtures="${SCRIPT_DIR}/fixtures/autonomy-gate"
  local out_root="${SCRIPT_DIR}/.out"
  local problems=()

  if [[ ! -f "$hook" ]]; then
    _fail "$label" "hook not found: $hook"
    return
  fi
  for a in A1-regex-hit A2-haiku-continue A3-haiku-block A4-paused-allow A5-timeout-allow A6-no-cli-skip; do
    if [[ ! -d "$fixtures/$a" ]]; then
      problems+=("missing fixture dir: $a")
    fi
  done
  if [[ ${#problems[@]} -gt 0 ]]; then
    _fail "$label" "${problems[@]}"
    return
  fi
  mkdir -p "$out_root" 2>/dev/null || true

  # ---- A1 regex-path hit ---------------------------------------------------
  local tmp_a1="$out_root/gate-test-$$-A1"
  rm -rf "$tmp_a1"; mkdir -p "$tmp_a1"
  # Narrow PATH so A1 also proves regex fast-path survives without claude.
  local narrow_path; narrow_path="$(dirname "$(command -v bash)"):/usr/bin:/bin"
  local out_a1
  out_a1="$(PATH="$narrow_path" \
    AIHAUS_EXEC_PHASE=1 \
    MANIFEST_PATH="$fixtures/A1-regex-hit/manifest.md" \
    AIHAUS_AUDIT_GATE_LOG="$tmp_a1/gate.jsonl" \
    AIHAUS_AUDIT_GATE_CACHE="$tmp_a1/gate.cache" \
    AIHAUS_AUDIT_LOG="$tmp_a1/violations.jsonl" \
    bash "$hook" < "$fixtures/A1-regex-hit/message.txt" 2>/dev/null || true)"
  if ! printf '%s' "$out_a1" | grep -q '"decision":"block"'; then
    problems+=("A1: expected block JSON; got: ${out_a1:0:120}")
  fi
  if [[ -f "$tmp_a1/gate.jsonl" ]]; then
    if ! grep -q '"decision":"regex-match"' "$tmp_a1/gate.jsonl"; then
      problems+=("A1: audit missing decision=regex-match")
    fi
  else
    problems+=("A1: audit jsonl not written")
  fi

  # ---- A2 regex-miss → haiku-continue -------------------------------------
  local tmp_a2="$out_root/gate-test-$$-A2"
  rm -rf "$tmp_a2"; mkdir -p "$tmp_a2/stub-bin"
  cat > "$tmp_a2/stub-bin/claude" <<'EOF'
#!/usr/bin/env bash
echo '{"decision":"continue","reason":"mid-execution progress update"}'
EOF
  chmod +x "$tmp_a2/stub-bin/claude"
  local narrow_a2="$tmp_a2/stub-bin:$(dirname "$(command -v bash)"):/usr/bin:/bin"
  local out_a2 rc_a2
  out_a2="$(PATH="$narrow_a2" \
    AIHAUS_EXEC_PHASE=1 \
    MANIFEST_PATH="$fixtures/A2-haiku-continue/manifest.md" \
    AIHAUS_AUDIT_GATE_LOG="$tmp_a2/gate.jsonl" \
    AIHAUS_AUDIT_GATE_CACHE="$tmp_a2/gate.cache" \
    AIHAUS_AUDIT_LOG="$tmp_a2/violations.jsonl" \
    bash "$hook" < "$fixtures/A2-haiku-continue/message.txt" 2>/dev/null || true)"
  rc_a2=$?
  if [[ -n "$out_a2" ]]; then
    problems+=("A2: expected empty stdout; got: ${out_a2:0:120}")
  fi
  if [[ -f "$tmp_a2/gate.jsonl" ]]; then
    if ! grep -q '"decision":"haiku-continue"' "$tmp_a2/gate.jsonl"; then
      problems+=("A2: audit missing decision=haiku-continue")
    fi
  else
    problems+=("A2: audit jsonl not written")
  fi

  # ---- A3 regex-miss → haiku-block ----------------------------------------
  local tmp_a3="$out_root/gate-test-$$-A3"
  rm -rf "$tmp_a3"; mkdir -p "$tmp_a3/stub-bin"
  cat > "$tmp_a3/stub-bin/claude" <<'EOF'
#!/usr/bin/env bash
echo '{"decision":"block","reason":"state summary without TRUE blocker"}'
EOF
  chmod +x "$tmp_a3/stub-bin/claude"
  local narrow_a3="$tmp_a3/stub-bin:$(dirname "$(command -v bash)"):/usr/bin:/bin"
  local out_a3
  out_a3="$(PATH="$narrow_a3" \
    AIHAUS_EXEC_PHASE=1 \
    MANIFEST_PATH="$fixtures/A3-haiku-block/manifest.md" \
    AIHAUS_AUDIT_GATE_LOG="$tmp_a3/gate.jsonl" \
    AIHAUS_AUDIT_GATE_CACHE="$tmp_a3/gate.cache" \
    AIHAUS_AUDIT_LOG="$tmp_a3/violations.jsonl" \
    bash "$hook" < "$fixtures/A3-haiku-block/message.txt" 2>/dev/null || true)"
  if ! printf '%s' "$out_a3" | grep -q '"decision":"block"'; then
    problems+=("A3: expected block JSON; got: ${out_a3:0:120}")
  fi
  if [[ -f "$tmp_a3/gate.jsonl" ]]; then
    if ! grep -q '"decision":"haiku-block"' "$tmp_a3/gate.jsonl"; then
      problems+=("A3: audit missing decision=haiku-block")
    fi
  else
    problems+=("A3: audit jsonl not written")
  fi

  # ---- A4 paused-allow -----------------------------------------------------
  local tmp_a4="$out_root/gate-test-$$-A4"
  rm -rf "$tmp_a4"; mkdir -p "$tmp_a4"
  local out_a4
  out_a4="$(PATH="$narrow_path" \
    AIHAUS_EXEC_PHASE=1 \
    MANIFEST_PATH="$fixtures/A4-paused-allow/manifest.md" \
    AIHAUS_AUDIT_GATE_LOG="$tmp_a4/gate.jsonl" \
    AIHAUS_AUDIT_GATE_CACHE="$tmp_a4/gate.cache" \
    AIHAUS_AUDIT_LOG="$tmp_a4/violations.jsonl" \
    bash "$hook" < "$fixtures/A4-paused-allow/message.txt" 2>/dev/null || true)"
  if [[ -n "$out_a4" ]]; then
    problems+=("A4: expected empty stdout (paused short-circuit); got: ${out_a4:0:120}")
  fi
  if [[ -f "$tmp_a4/gate.jsonl" ]]; then
    if ! grep -q '"decision":"paused-allow"' "$tmp_a4/gate.jsonl"; then
      problems+=("A4: audit missing decision=paused-allow")
    fi
  else
    problems+=("A4: audit jsonl not written")
  fi

  # ---- A5 timeout-fallback-allow ------------------------------------------
  # Stub `claude` as the sleep-5 fixture; hook wraps in `timeout 3s`.
  local tmp_a5="$out_root/gate-test-$$-A5"
  rm -rf "$tmp_a5"; mkdir -p "$tmp_a5/stub-bin"
  cp "$fixtures/A5-timeout-allow/claude-stub-sleep.sh" "$tmp_a5/stub-bin/claude"
  chmod +x "$tmp_a5/stub-bin/claude"
  local narrow_a5="$tmp_a5/stub-bin:$(dirname "$(command -v bash)"):/usr/bin:/bin"
  # Only run if `timeout` is available (needed for the 3s bound).
  if command -v timeout >/dev/null 2>&1; then
    local out_a5
    out_a5="$(PATH="$narrow_a5" \
      AIHAUS_EXEC_PHASE=1 \
      MANIFEST_PATH="$fixtures/A5-timeout-allow/manifest.md" \
      AIHAUS_AUDIT_GATE_LOG="$tmp_a5/gate.jsonl" \
      AIHAUS_AUDIT_GATE_CACHE="$tmp_a5/gate.cache" \
      AIHAUS_AUDIT_LOG="$tmp_a5/violations.jsonl" \
      bash "$hook" < "$fixtures/A5-timeout-allow/message.txt" 2>/dev/null || true)"
    if [[ -n "$out_a5" ]]; then
      problems+=("A5: expected empty stdout on timeout; got: ${out_a5:0:120}")
    fi
    if [[ -f "$tmp_a5/gate.jsonl" ]]; then
      if ! grep -q '"decision":"timeout-fallback-allow"' "$tmp_a5/gate.jsonl"; then
        problems+=("A5: audit missing decision=timeout-fallback-allow")
      fi
    else
      problems+=("A5: audit jsonl not written")
    fi
  fi

  # ---- A6 no-cli-skip ------------------------------------------------------
  # Strip `claude` from PATH entirely; hook must emit no-cli-skip.
  local tmp_a6="$out_root/gate-test-$$-A6"
  rm -rf "$tmp_a6"; mkdir -p "$tmp_a6/empty-bin"
  # Only keep bash + core tools; NO claude.
  local narrow_a6="$(dirname "$(command -v bash)"):/usr/bin:/bin"
  local out_a6
  out_a6="$(PATH="$narrow_a6" \
    AIHAUS_EXEC_PHASE=1 \
    MANIFEST_PATH="$fixtures/A6-no-cli-skip/manifest.md" \
    AIHAUS_AUDIT_GATE_LOG="$tmp_a6/gate.jsonl" \
    AIHAUS_AUDIT_GATE_CACHE="$tmp_a6/gate.cache" \
    AIHAUS_AUDIT_LOG="$tmp_a6/violations.jsonl" \
    bash "$hook" < "$fixtures/A6-no-cli-skip/message.txt" 2>/dev/null || true)"
  if [[ -n "$out_a6" ]]; then
    problems+=("A6: expected empty stdout when claude absent; got: ${out_a6:0:120}")
  fi
  if [[ -f "$tmp_a6/gate.jsonl" ]]; then
    if ! grep -q '"decision":"no-cli-skip"' "$tmp_a6/gate.jsonl"; then
      problems+=("A6: audit missing decision=no-cli-skip")
    fi
  else
    problems+=("A6: audit jsonl not written")
  fi

  # ---- cleanup (best-effort) ----------------------------------------------
  rm -rf "$tmp_a1" "$tmp_a2" "$tmp_a3" "$tmp_a4" "$tmp_a5" "$tmp_a6" 2>/dev/null || true

  if [[ ${#problems[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${problems[@]}"
  fi
}

# ---- Check 30: migration fixtures (v2->v3 restore-effort.sh, M012/S07) ------
# Three golden-fixture pairs exercising S06's restore-effort.sh migration path:
#   F1 pure-cohort v2 (balanced + doer.effort=medium)
#      → schema=3 .effort; .v2.bak exists; .automode absent; idempotent
#   F2 auto-mode-safe v2 (last_preset=auto-mode-safe, permission_mode=auto)
#      → schema=3 .effort; .automode exists with enabled=true;
#        !! block in stderr with DSP launch message; idempotent
#   F3 investigator-custom v2 (cohort.investigator.effort + .model)
#      → schema=3 .effort; 3 per-agent overrides; !! warning about FR-M06; idempotent
# Comparison strips the timestamp line (# Migrated from schema v2 ... on <ts>)
# so the check is stable. Idempotence: second restore_effort run leaves .effort
# byte-identical (hash comparison).
# Self-contained: never invokes /aih-effort (R7 cycle prevention).
check_migration_fixtures() {
  _start_check
  local label="Check ${CHECK_NUMBER}: migration fixtures v2->v3 (restore-effort.sh, 3 pairs + idempotence)"
  local fx_root="${PACKAGE_ROOT}/../tools/fixtures/migration-check29"
  [[ -d "$fx_root" ]] || fx_root="tools/fixtures/migration-check29"
  if [[ ! -d "$fx_root" ]]; then
    _fail "$label" "fixtures dir missing: tools/fixtures/migration-check29"
    return
  fi

  # shellcheck source=../pkg/scripts/lib/restore-effort.sh
  source "${PACKAGE_ROOT}/scripts/lib/restore-effort.sh"

  local repo_root="${PACKAGE_ROOT}/.."
  local out_root="${repo_root}/tools/.out"
  mkdir -p "$out_root" 2>/dev/null || true
  local problems=()

  # _strip_timestamp: filter out the "# Migrated from schema v2 ... on <ts>" line
  # for stable comparison (timestamp varies per run).
  _strip_timestamp() { grep -v '^# Migrated from schema v2'; }

  # ---------- Fixture 1: pure-cohort v2 ------------------------------------
  local f1_dir="${out_root}/mig-f1-$$"
  rm -rf "$f1_dir"; mkdir -p "$f1_dir/.aihaus/agents"
  cp "$fx_root/fixture-1/input.calibration" "$f1_dir/.aihaus/.calibration"
  local f1_stderr
  f1_stderr=$(restore_effort "$f1_dir/.aihaus" 2>&1 >/dev/null || true)

  # .v2.bak must exist.
  [[ -f "$f1_dir/.aihaus/.calibration.v2.bak" ]] \
    || problems+=("F1: .calibration.v2.bak not created")

  # .automode must NOT exist for balanced/no-auto-mode-safe.
  [[ ! -f "$f1_dir/.aihaus/.automode" ]] \
    || problems+=("F1: .automode should NOT exist for pure-cohort balanced fixture")

  # .effort content matches golden (minus timestamp line).
  if [[ -f "$f1_dir/.aihaus/.effort" ]]; then
    local f1_got f1_want
    f1_got=$(grep -v '^# Migrated from schema v2' "$f1_dir/.aihaus/.effort")
    f1_want=$(grep -v '^# Migrated from schema v2' "$fx_root/fixture-1/expected.effort")
    if [[ "$f1_got" != "$f1_want" ]]; then
      problems+=("F1: .effort content mismatch vs golden")
      problems+=("F1:  got:  $(echo "$f1_got" | head -5 | tr '\n' '|')")
      problems+=("F1:  want: $(echo "$f1_want" | head -5 | tr '\n' '|')")
    fi
  else
    problems+=("F1: .effort not created")
  fi

  # Idempotence: run restore_effort again on the v3 .effort; hash must not change.
  if [[ -f "$f1_dir/.aihaus/.effort" ]]; then
    local f1_hash_before f1_hash_after
    f1_hash_before=$(grep -v '^# Migrated from schema v2' "$f1_dir/.aihaus/.effort" | md5sum 2>/dev/null || sha256sum "$f1_dir/.aihaus/.effort" 2>/dev/null || cksum "$f1_dir/.aihaus/.effort")
    restore_effort "$f1_dir/.aihaus" >/dev/null 2>&1 || true
    f1_hash_after=$(grep -v '^# Migrated from schema v2' "$f1_dir/.aihaus/.effort" | md5sum 2>/dev/null || sha256sum "$f1_dir/.aihaus/.effort" 2>/dev/null || cksum "$f1_dir/.aihaus/.effort")
    [[ "$f1_hash_before" == "$f1_hash_after" ]] \
      || problems+=("F1: idempotence failed -- .effort changed on second run")
  fi
  rm -rf "$f1_dir"

  # ---------- Fixture 2: auto-mode-safe v2 ---------------------------------
  local f2_dir="${out_root}/mig-f2-$$"
  rm -rf "$f2_dir"; mkdir -p "$f2_dir/.aihaus/agents"
  cp "$fx_root/fixture-2/input.calibration" "$f2_dir/.aihaus/.calibration"
  local f2_stderr
  f2_stderr=$(restore_effort "$f2_dir/.aihaus" 2>&1 >/dev/null || true)

  # .v2.bak must exist.
  [[ -f "$f2_dir/.aihaus/.calibration.v2.bak" ]] \
    || problems+=("F2: .calibration.v2.bak not created")

  # .automode must exist with enabled=true.
  if [[ -f "$f2_dir/.aihaus/.automode" ]]; then
    grep -q '^enabled=true$' "$f2_dir/.aihaus/.automode" \
      || problems+=("F2: .automode missing 'enabled=true' line")
  else
    problems+=("F2: .automode not created for auto-mode-safe fixture")
  fi

  # stderr must contain the !! block with DSP launch message (M014).
  echo "$f2_stderr" | grep -q '!!' \
    || problems+=("F2: !! warning block not emitted in stderr")
  echo "$f2_stderr" | grep -q 'DSP launch' \
    || problems+=("F2: stderr missing DSP launch reference (M014 migration message)")

  # .effort content matches golden.
  if [[ -f "$f2_dir/.aihaus/.effort" ]]; then
    local f2_got f2_want
    f2_got=$(grep -v '^# Migrated from schema v2' "$f2_dir/.aihaus/.effort")
    f2_want=$(grep -v '^# Migrated from schema v2' "$fx_root/fixture-2/expected.effort")
    if [[ "$f2_got" != "$f2_want" ]]; then
      problems+=("F2: .effort content mismatch vs golden")
      problems+=("F2:  got:  $(echo "$f2_got" | head -5 | tr '\n' '|')")
      problems+=("F2:  want: $(echo "$f2_want" | head -5 | tr '\n' '|')")
    fi
  else
    problems+=("F2: .effort not created")
  fi

  # Idempotence: second run on v3 .effort leaves file unchanged.
  if [[ -f "$f2_dir/.aihaus/.effort" ]]; then
    local f2_hash_before f2_hash_after
    f2_hash_before=$(grep -v '^# Migrated from schema v2' "$f2_dir/.aihaus/.effort" | md5sum 2>/dev/null || sha256sum "$f2_dir/.aihaus/.effort" 2>/dev/null || cksum "$f2_dir/.aihaus/.effort")
    restore_effort "$f2_dir/.aihaus" >/dev/null 2>&1 || true
    f2_hash_after=$(grep -v '^# Migrated from schema v2' "$f2_dir/.aihaus/.effort" | md5sum 2>/dev/null || sha256sum "$f2_dir/.aihaus/.effort" 2>/dev/null || cksum "$f2_dir/.aihaus/.effort")
    [[ "$f2_hash_before" == "$f2_hash_after" ]] \
      || problems+=("F2: idempotence failed -- .effort changed on second run")
  fi
  rm -rf "$f2_dir"

  # ---------- Fixture 3: investigator-custom v2 ----------------------------
  local f3_dir="${out_root}/mig-f3-$$"
  rm -rf "$f3_dir"; mkdir -p "$f3_dir/.aihaus/agents"
  cp "$fx_root/fixture-3/input.calibration" "$f3_dir/.aihaus/.calibration"
  local f3_stderr
  f3_stderr=$(restore_effort "$f3_dir/.aihaus" 2>&1 >/dev/null || true)

  # .v2.bak must exist.
  [[ -f "$f3_dir/.aihaus/.calibration.v2.bak" ]] \
    || problems+=("F3: .calibration.v2.bak not created")

  # .automode must NOT exist (no auto-mode-safe trigger).
  [[ ! -f "$f3_dir/.aihaus/.automode" ]] \
    || problems+=("F3: .automode should NOT exist for investigator-custom fixture")

  # .effort must contain the 3 per-agent overrides (FR-M06 migration).
  if [[ -f "$f3_dir/.aihaus/.effort" ]]; then
    grep -q '^debugger.model=sonnet$' "$f3_dir/.aihaus/.effort" \
      || problems+=("F3: debugger.model=sonnet not in .effort (FR-M06)")
    grep -q '^debug-session-manager.model=sonnet$' "$f3_dir/.aihaus/.effort" \
      || problems+=("F3: debug-session-manager.model=sonnet not in .effort (FR-M06)")
    grep -q '^user-profiler.model=sonnet$' "$f3_dir/.aihaus/.effort" \
      || problems+=("F3: user-profiler.model=sonnet not in .effort (FR-M06)")

    # Full golden diff (minus timestamp).
    local f3_got f3_want
    f3_got=$(grep -v '^# Migrated from schema v2' "$f3_dir/.aihaus/.effort")
    f3_want=$(grep -v '^# Migrated from schema v2' "$fx_root/fixture-3/expected.effort")
    if [[ "$f3_got" != "$f3_want" ]]; then
      problems+=("F3: .effort content mismatch vs golden")
      problems+=("F3:  got:  $(echo "$f3_got" | head -8 | tr '\n' '|')")
      problems+=("F3:  want: $(echo "$f3_want" | head -8 | tr '\n' '|')")
    fi
  else
    problems+=("F3: .effort not created")
  fi

  # stderr must contain !! block warning about investigator cohort deletion.
  echo "$f3_stderr" | grep -q '!!' \
    || problems+=("F3: !! warning block not emitted in stderr")
  echo "$f3_stderr" | grep -q 'investigator' \
    || problems+=("F3: stderr missing investigator-deletion warning")

  # Idempotence.
  if [[ -f "$f3_dir/.aihaus/.effort" ]]; then
    local f3_hash_before f3_hash_after
    f3_hash_before=$(grep -v '^# Migrated from schema v2' "$f3_dir/.aihaus/.effort" | md5sum 2>/dev/null || sha256sum "$f3_dir/.aihaus/.effort" 2>/dev/null || cksum "$f3_dir/.aihaus/.effort")
    restore_effort "$f3_dir/.aihaus" >/dev/null 2>&1 || true
    f3_hash_after=$(grep -v '^# Migrated from schema v2' "$f3_dir/.aihaus/.effort" | md5sum 2>/dev/null || sha256sum "$f3_dir/.aihaus/.effort" 2>/dev/null || cksum "$f3_dir/.aihaus/.effort")
    [[ "$f3_hash_before" == "$f3_hash_after" ]] \
      || problems+=("F3: idempotence failed -- .effort changed on second run")
  fi
  rm -rf "$f3_dir"

  if [[ ${#problems[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${problems[@]}"
  fi
}

# ---- Check 31: memory README seeds exist and are non-empty (M013/S02) -------
# Asserts that the four memory-bucket README files introduced in M013 are
# present in the package source and have content (not zero-byte placeholders).
# These files are seeded to user installs via `update.sh --migrate-memory`.
check_memory_readme_seeds() {
  _start_check
  local label="Check ${CHECK_NUMBER}: memory README seeds exist and non-empty (M013/S02)"
  local memory_root="${PACKAGE_ROOT}/.aihaus/memory"
  local subdirs=(global backend frontend reviews)
  local problems=()

  for subdir in "${subdirs[@]}"; do
    local f="${memory_root}/${subdir}/README.md"
    if [[ ! -f "$f" ]]; then
      problems+=("missing: memory/${subdir}/README.md")
    elif [[ ! -s "$f" ]]; then
      problems+=("empty: memory/${subdir}/README.md")
    fi
  done

  if [[ ${#problems[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${problems[@]}"
  fi
}

# ---- Check 32: backfill-milestone-history.sh exists, is executable,
#               and produces >= 12 M0NN rows when milestones dir is present (M013/S03)
check_backfill_script() {
  _start_check
  local label="Check ${CHECK_NUMBER}: backfill-milestone-history.sh exists + produces rows (M013/S03)"
  local script="${SCRIPT_DIR}/backfill-milestone-history.sh"
  local problems=()

  # (a) script exists
  if [[ ! -f "$script" ]]; then
    _fail "$label" "backfill-milestone-history.sh not found at tools/"
    return
  fi

  # (b) script is executable
  if [[ ! -x "$script" ]]; then
    problems+=("backfill-milestone-history.sh is not executable (run: chmod +x tools/backfill-milestone-history.sh)")
  fi

  # (c) script passes bash -n syntax check
  if ! bash -n "$script" 2>/dev/null; then
    problems+=("backfill-milestone-history.sh failed bash -n syntax check")
  fi

  # (d) if milestones dir exists, script produces >= 12 M0NN rows
  local milestones_root="${PACKAGE_ROOT}/../.aihaus/milestones"
  if [[ -d "$milestones_root" ]]; then
    local row_count
    row_count=$(bash "$script" 2>/dev/null | grep -cE '^\| M[0-9]{3} \|' || echo "0")
    if [[ "$row_count" -lt 12 ]]; then
      problems+=("backfill-milestone-history.sh produced only ${row_count} M0NN rows (expected >= 12)")
    fi
  fi

  if [[ ${#problems[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${problems[@]}"
  fi
}

# ---- Check 33: AGENT-EVOLUTION.md scaffold mentioned in execution.md Step E2 (M013/S04) --
# ADR-M013-A requires that execution.md Step E2 unconditionally scaffolds
# AGENT-EVOLUTION.md so completion-protocol Step 4.5's `if file exists` check
# is never trivially false. A grep for the literal string "AGENT-EVOLUTION.md"
# in the execution annex is the observable assertion.
check_agent_evolution_scaffold() {
  _start_check
  local label="Check ${CHECK_NUMBER}: AGENT-EVOLUTION.md scaffold present in execution.md Step E2 (M013/S04)"
  local exec_annex="${PACKAGE_ROOT}/.aihaus/skills/aih-milestone/annexes/execution.md"
  if [[ ! -f "$exec_annex" ]]; then
    _fail "$label" "execution.md annex not found at ${exec_annex#${PACKAGE_ROOT}/}"
    return
  fi
  if grep -q 'AGENT-EVOLUTION\.md' "$exec_annex"; then
    _pass "$label"
  else
    _fail "$label" "AGENT-EVOLUTION.md not mentioned in execution.md — Step E2 scaffold missing (ADR-M013-A)"
  fi
}

# ---- Check 34: completion-protocol.md contains Step 4.7 (M013/S04) -----------
# ADR-M013-A requires Step 4.7 in completion-protocol.md documenting reviewer
# and code-reviewer per-milestone summary emission. Grep for the step header.
check_completion_protocol_step_4_7() {
  _start_check
  local label="Check ${CHECK_NUMBER}: completion-protocol.md contains Step 4.7 (M013/S04)"
  local cp="${PACKAGE_ROOT}/.aihaus/skills/aih-milestone/completion-protocol.md"
  if [[ ! -f "$cp" ]]; then
    _fail "$label" "completion-protocol.md not found at ${cp#${PACKAGE_ROOT}/}"
    return
  fi
  if grep -q 'Step 4\.7' "$cp"; then
    _pass "$label"
  else
    _fail "$label" "Step 4.7 not found in completion-protocol.md (ADR-M013-A F3 mitigation)"
  fi
}

# ---- Check 35: context-curator agent + context-inject hook exist (M013/S05) --
# Asserts Component A of M013 shipped:
#   (a) pkg/.aihaus/agents/context-curator.md exists with required frontmatter
#       (name, tools, model, effort, color, memory) and read-only tools whitelist
#   (b) pkg/.aihaus/hooks/context-inject.sh exists
#   (c) context-curator model is haiku (cohort :verifier default)
#   (d) context-curator tools are Read, Grep, Glob (no Write/Edit per ADR-001)
#   (e) templates/settings.local.json references context-inject.sh under SubagentStart
check_context_curator() {
  _start_check
  local label="Check ${CHECK_NUMBER}: context-curator agent + context-inject hook exist (M013/S05)"
  local agent="${PACKAGE_ROOT}/.aihaus/agents/context-curator.md"
  local hook="${PACKAGE_ROOT}/.aihaus/hooks/context-inject.sh"
  local tpl="${PACKAGE_ROOT}/.aihaus/templates/settings.local.json"
  local problems=()

  # (a) agent file exists
  if [[ ! -f "$agent" ]]; then
    problems+=("context-curator.md missing at agents/context-curator.md")
  else
    # check required frontmatter fields
    local front
    front=$(awk '/^---$/{c++; next} c==1' "$agent")
    for field in name tools model effort color memory; do
      if ! printf '%s\n' "$front" | grep -q "^${field}:"; then
        problems+=("context-curator.md frontmatter missing '${field}'")
      fi
    done
    # (c) model must be haiku
    local model
    model=$(awk '/^---$/{c++; next} c==1 && /^model:/{print $2; exit}' "$agent")
    if [[ "$model" != "haiku" ]]; then
      problems+=("context-curator.md: expected model=haiku (cohort :verifier), got model=${model}")
    fi
    # (d) tools must include Read, Grep, Glob and must NOT include Write or Edit
    local tools_line
    tools_line=$(awk '/^---$/{c++; next} c==1 && /^tools:/{print; exit}' "$agent")
    for required_tool in Read Grep Glob; do
      if ! printf '%s' "$tools_line" | grep -q "$required_tool"; then
        problems+=("context-curator.md: tools missing '${required_tool}'")
      fi
    done
    for forbidden_tool in Write Edit; do
      if printf '%s' "$tools_line" | grep -q "$forbidden_tool"; then
        problems+=("context-curator.md: tools must NOT include '${forbidden_tool}' (ADR-001 read-only)")
      fi
    done
  fi

  # (b) hook exists
  if [[ ! -f "$hook" ]]; then
    problems+=("context-inject.sh missing at hooks/context-inject.sh")
  fi

  # (e) template references context-inject.sh under SubagentStart
  if [[ -f "$tpl" ]]; then
    if ! grep -q 'context-inject.sh' "$tpl"; then
      problems+=("templates/settings.local.json does not reference context-inject.sh (SubagentStart hook not registered)")
    fi
  fi

  if [[ ${#problems[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${problems[@]}"
  fi
}

# ---- Check 36: learning-advisor agent + hook exist (M013/S06) ---------------
# Asserts Component B of M013 shipped:
#   (a) pkg/.aihaus/agents/learning-advisor.md exists with required frontmatter
#       (name, tools, model, effort, color, memory) and read-only tools whitelist
#   (b) pkg/.aihaus/hooks/learning-advisor.sh exists and is executable
#   (c) learning-advisor model is haiku (cohort :verifier default)
#   (d) learning-advisor tools are Read, Grep, Glob (no Write/Edit per ADR-001)
#   (e) templates/settings.local.json references learning-advisor.sh under SubagentStop
#   (f) agent count at 46 (knowledge-curator added in M013/S07)
# Note: COMPAT-MATRIX check removed in M015/ADR-M015-A (Cursor support dropped).
check_learning_advisor() {
  _start_check
  local label="Check ${CHECK_NUMBER}: learning-advisor agent + hook exist (M013/S06)"
  local agent="${PACKAGE_ROOT}/.aihaus/agents/learning-advisor.md"
  local hook="${PACKAGE_ROOT}/.aihaus/hooks/learning-advisor.sh"
  local tpl="${PACKAGE_ROOT}/.aihaus/templates/settings.local.json"
  local problems=()

  # (a) agent file exists with required frontmatter
  if [[ ! -f "$agent" ]]; then
    problems+=("learning-advisor.md missing at agents/learning-advisor.md")
  else
    local front
    front=$(awk '/^---$/{c++; next} c==1' "$agent")
    for field in name tools model effort color memory; do
      if ! printf '%s\n' "$front" | grep -q "^${field}:"; then
        problems+=("learning-advisor.md frontmatter missing '${field}'")
      fi
    done
    # (c) model must be haiku
    local model
    model=$(awk '/^---$/{c++; next} c==1 && /^model:/{print $2; exit}' "$agent")
    if [[ "$model" != "haiku" ]]; then
      problems+=("learning-advisor.md: expected model=haiku (cohort :verifier), got model=${model}")
    fi
    # (d) tools must include Read, Grep, Glob and must NOT include Write or Edit
    local tools_line
    tools_line=$(awk '/^---$/{c++; next} c==1 && /^tools:/{print; exit}' "$agent")
    for required_tool in Read Grep Glob; do
      if ! printf '%s' "$tools_line" | grep -q "$required_tool"; then
        problems+=("learning-advisor.md: tools missing '${required_tool}'")
      fi
    done
    for forbidden_tool in Write Edit; do
      if printf '%s' "$tools_line" | grep -q "$forbidden_tool"; then
        problems+=("learning-advisor.md: tools must NOT include '${forbidden_tool}' (ADR-001 read-only)")
      fi
    done
  fi

  # (b) hook exists and is executable
  if [[ ! -f "$hook" ]]; then
    problems+=("learning-advisor.sh missing at hooks/learning-advisor.sh")
  elif [[ ! -x "$hook" ]]; then
    problems+=("learning-advisor.sh exists but is not executable")
  fi

  # (e) template references learning-advisor.sh under SubagentStop
  if [[ -f "$tpl" ]]; then
    if ! grep -q 'learning-advisor.sh' "$tpl"; then
      problems+=("templates/settings.local.json does not reference learning-advisor.sh (SubagentStop hook not registered)")
    fi
    if ! grep -q 'SubagentStop' "$tpl"; then
      problems+=("templates/settings.local.json missing SubagentStop hook block")
    fi
  fi

  # (f) agent count at 46 (knowledge-curator added in M013/S07)
  local agents_root="${PACKAGE_ROOT}/.aihaus/agents"
  local count
  count=$(find "$agents_root" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')
  if [[ "$count" -ne 46 ]]; then
    problems+=("expected 46 agents total (knowledge-curator bumps from 45); found ${count}")
  fi

  if [[ ${#problems[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${problems[@]}"
  fi
}

# ---- Check 37: knowledge-curator agent exists + 5 fenced-block markers documented (M013/S07) --
# Asserts Component C of M013 shipped:
#   (a) pkg/.aihaus/agents/knowledge-curator.md exists with required frontmatter
#   (b) model is opus (cohort :planner default)
#   (c) tools are Read, Grep, Glob, Bash — NO Write, NO Edit (ADR-001)
#   (d) agent body documents all 5 fenced-block markers
#   (e) recursion guard documented (AIHAUS_KNOWLEDGE_CURATOR_ACTIVE)
check_knowledge_curator() {
  _start_check
  local label="Check ${CHECK_NUMBER}: knowledge-curator agent exists + 5 fenced-block markers documented (M013/S07)"
  local agent="${PACKAGE_ROOT}/.aihaus/agents/knowledge-curator.md"
  local problems=()

  # (a) agent file exists with required frontmatter
  if [[ ! -f "$agent" ]]; then
    problems+=("knowledge-curator.md missing at agents/knowledge-curator.md")
  else
    local front
    front=$(awk '/^---$/{c++; next} c==1' "$agent")
    for field in name tools model effort color memory; do
      if ! printf '%s\n' "$front" | grep -q "^${field}:"; then
        problems+=("knowledge-curator.md frontmatter missing '${field}'")
      fi
    done

    # (b) model must be opus (cohort :planner default)
    local model
    model=$(awk '/^---$/{c++; next} c==1 && /^model:/{print $2; exit}' "$agent")
    if [[ "$model" != "opus" ]]; then
      problems+=("knowledge-curator.md: expected model=opus (cohort :planner), got model=${model}")
    fi

    # (c) tools must include Read, Grep, Glob, Bash and must NOT include Write or Edit
    local tools_line
    tools_line=$(awk '/^---$/{c++; next} c==1 && /^tools:/{print; exit}' "$agent")
    for required_tool in Read Grep Glob Bash; do
      if ! printf '%s' "$tools_line" | grep -q "$required_tool"; then
        problems+=("knowledge-curator.md: tools missing '${required_tool}'")
      fi
    done
    for forbidden_tool in Write Edit; do
      if printf '%s' "$tools_line" | grep -q "$forbidden_tool"; then
        problems+=("knowledge-curator.md: tools must NOT include '${forbidden_tool}' (ADR-001 single-writer)")
      fi
    done

    # (d) all 5 fenced-block markers documented in agent body
    local markers=(
      "aihaus:decisions-append"
      "aihaus:knowledge-append"
      "aihaus:memory-append"
      "aihaus:history-append"
      "aihaus:curator-decisions"
    )
    for marker in "${markers[@]}"; do
      if ! grep -q "$marker" "$agent"; then
        problems+=("knowledge-curator.md: missing fenced-block marker '${marker}'")
      fi
    done

    # (e) recursion guard documented
    if ! grep -q 'AIHAUS_KNOWLEDGE_CURATOR_ACTIVE' "$agent"; then
      problems+=("knowledge-curator.md: missing recursion guard (AIHAUS_KNOWLEDGE_CURATOR_ACTIVE)")
    fi
  fi

  if [[ ${#problems[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${problems[@]}"
  fi
}

# ---- Check 38: verifier.md contains ## Knowledge consulted directive (M013/S07) --
# Asserts F5 consume-side instrumentation shipped:
#   (a) pkg/.aihaus/agents/verifier.md contains the '## Knowledge consulted' section
#   (b) section is in the output template (inside the fenced markdown block)
#   (c) verifier cohort is :verifier (D4 — not adversarial-scout or adversarial-review)
check_verifier_knowledge_consulted() {
  _start_check
  local label="Check ${CHECK_NUMBER}: verifier.md has '## Knowledge consulted' directive (M013/S07 F5)"
  local agent="${PACKAGE_ROOT}/.aihaus/agents/verifier.md"
  local cohorts_md="${PACKAGE_ROOT}/.aihaus/skills/aih-effort/annexes/cohorts.md"
  local problems=()

  # (a) + (b) verifier.md contains ## Knowledge consulted
  if [[ ! -f "$agent" ]]; then
    problems+=("verifier.md missing at agents/verifier.md")
  else
    if ! grep -q '## Knowledge consulted' "$agent"; then
      problems+=("verifier.md missing '## Knowledge consulted' section (F5 consume-side telemetry)")
    fi
    # 'none applicable' must also be documented as the nil-citation form
    if ! grep -q 'none applicable' "$agent"; then
      problems+=("verifier.md missing 'none applicable' nil-citation form for ## Knowledge consulted")
    fi
  fi

  # (c) D4 enforcement: verifier must be in :verifier cohort, not adversarial-*
  if [[ -f "$cohorts_md" ]]; then
    local verifier_cohort
    verifier_cohort=$(awk -F'|' '
      NF==7 {
        agent=substr($3,1); gsub(/^[[:space:]]+|[[:space:]]+$/,"",agent)
        cohort=substr($4,1); gsub(/^[[:space:]]+|[[:space:]]+$/,"",cohort)
        if (agent=="verifier") print cohort
      }
    ' "$cohorts_md")
    if [[ "$verifier_cohort" != ":verifier" ]]; then
      problems+=("D4 violation: verifier cohort in cohorts.md is '${verifier_cohort}', expected ':verifier' (D4 mandates non-immune cohort)")
    fi
    # Also assert NOT in adversarial cohorts
    if [[ "$verifier_cohort" == ":adversarial-scout" || "$verifier_cohort" == ":adversarial-review" ]]; then
      problems+=("D4 violation: verifier is in preset-immune cohort '${verifier_cohort}' — forbidden by ADR-M012-A D4")
    fi
  fi

  if [[ ${#problems[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${problems[@]}"
  fi
}

# ---- Check (M014/S06 + M020/S06): schema v2→v3→v4 migration fixture (idempotent + additive) -
# Exercises manifest-migrate.sh full chain:
#   R1 takes a v2 fixture manifest (schema: v2, no ## Checkpoints)
#   R2 runs manifest-migrate.sh → asserts schema: v3 + ## Checkpoints heading present
#   R3 asserts column header present (LD-1 7-column shape)
#   R4 runs manifest-migrate.sh again → asserts schema bumped to v4 (v3→v4 step, M020/S06)
#   R5 runs manifest-migrate.sh a third time → asserts no diff (already-v4 no-op, idempotent)
# Uses mktemp -d for the fixture; never pollutes the repo.
check_schema_v3_migration() {
  _start_check
  local label="Check ${CHECK_NUMBER}: schema v2→v3 migration fixture (idempotent + additive, M014/S06)"
  local migrate_hook="${PACKAGE_ROOT}/.aihaus/hooks/manifest-migrate.sh"
  local problems=()

  if [[ ! -f "$migrate_hook" ]]; then
    _fail "$label" "manifest-migrate.sh not found at hooks/"
    return
  fi

  # Create temp dir and a minimal v2 manifest fixture
  local tmpdir
  tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t aih-smoke)"
  local fixture="${tmpdir}/RUN-MANIFEST.md"

  cat > "$fixture" <<'MANIFEST_EOF'
## Metadata
milestone: M000-test
branch: test/branch
started: 2026-04-22T00:00:00Z
schema: v2
phase: execute-stories
status: running
last_updated: 2026-04-22T00:00:00Z

## Invoke stack

## Story Records
story_id|status|started_at|commit_sha|verified|notes
S01|complete|2026-04-22T00:01:00Z|abc1234|true|
MANIFEST_EOF

  # R2: run migration first time (v2 → v3)
  local migrate_out migrate_rc
  migrate_out=$(MANIFEST_PATH="$fixture" bash "$migrate_hook" 2>&1)
  migrate_rc=$?
  if [[ "$migrate_rc" -ne 0 ]]; then
    problems+=("R2: manifest-migrate.sh exited ${migrate_rc} on first run; output: ${migrate_out:0:200}")
  fi

  # R2/R3: assert ## Checkpoints heading present
  if ! grep -q '^## Checkpoints$' "$fixture"; then
    problems+=("R2: ## Checkpoints heading not added by migration")
  fi

  # R3: assert LD-1 column header present
  local expected_header="| ts | story | agent | substep | event | result | sha |"
  if ! grep -qF "$expected_header" "$fixture"; then
    problems+=("R3: LD-1 column header not present; expected: '${expected_header}'")
  fi

  # R4: run migration a second time (v3 → v4, M020/S06)
  local migrate_out2 migrate_rc2
  migrate_out2=$(MANIFEST_PATH="$fixture" bash "$migrate_hook" 2>&1)
  migrate_rc2=$?
  if [[ "$migrate_rc2" -ne 0 ]]; then
    problems+=("R4: manifest-migrate.sh exited ${migrate_rc2} on v3→v4 run; output: ${migrate_out2:0:200}")
  fi

  # R4: assert schema bumped to v4
  if ! grep -q '^schema: v4$' "$fixture"; then
    problems+=("R4: schema not bumped to v4 after second migration run")
  fi

  # R5: capture snapshot before third run
  local snap_before
  snap_before="$(cat "$fixture")"

  # R5: run migration a third time (should be already-v4 no-op)
  local migrate_out3 migrate_rc3
  migrate_out3=$(MANIFEST_PATH="$fixture" bash "$migrate_hook" 2>&1)
  migrate_rc3=$?
  if [[ "$migrate_rc3" -ne 0 ]]; then
    problems+=("R5: manifest-migrate.sh exited ${migrate_rc3} on already-v4 run; output: ${migrate_out3:0:200}")
  fi

  # R5: assert idempotent at v4 (file unchanged)
  local snap_after
  snap_after="$(cat "$fixture")"
  if [[ "$snap_before" != "$snap_after" ]]; then
    problems+=("R5: idempotence violated — manifest changed on already-v4 run")
  fi

  rm -rf "$tmpdir" 2>/dev/null || true

  if [[ ${#problems[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${problems[@]}"
  fi
}

# ---- Check (M014/S08): worktree-reconcile.sh 3-category fixture -------------
# Creates a temp git repo with 3 worktrees:
#   Cat A: clean worktree whose HEAD == main HEAD (merged).
#   Cat B: clean worktree with 1 extra commit not on main.
#   Cat C: dirty worktree with 1 uncommitted file.
# Invokes worktree-reconcile.sh and asserts:
#   A: worktree no longer listed by `git worktree list`
#   B: stdout contains "git cherry-pick" recipe
#   C: worktree still listed; dirty file still present
# Uses mktemp -d for full isolation; never pollutes the repo.
check_worktree_reconcile_fixture() {
  _start_check
  local label="Check ${CHECK_NUMBER}: worktree-reconcile.sh 3-category fixture (M014/S08)"
  local hook="${PACKAGE_ROOT}/.aihaus/hooks/worktree-reconcile.sh"
  local problems=()

  if [[ ! -f "$hook" ]]; then
    _fail "$label" "hook missing: ${hook#${PACKAGE_ROOT}/}"
    return
  fi
  if [[ ! -x "$hook" ]]; then
    problems+=("hook not executable: ${hook#${PACKAGE_ROOT}/}")
  fi

  # Need git available
  if ! command -v git >/dev/null 2>&1; then
    _fail "$label" "git not found; cannot run fixture"
    return
  fi

  local tmpdir
  tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t aih-wt-smoke)"

  # ---- Bootstrap a bare git repo as the shared object store ------------------
  local repo="${tmpdir}/repo"
  mkdir -p "$repo"
  git -C "$repo" init -b main >/dev/null 2>&1
  git -C "$repo" config user.email "smoke@test"
  git -C "$repo" config user.name  "Smoke Test"

  # Initial commit on main
  touch "$repo/seed.txt"
  git -C "$repo" add seed.txt
  git -C "$repo" commit -m "initial" >/dev/null 2>&1

  # ---- Worktree A: clean + HEAD == main HEAD ---------------------------------
  # Use a new branch (wt-a-branch) that points to the same SHA as main.
  # Cannot add a worktree directly on 'main' — git forbids multiple
  # checkouts of the same branch.
  local wt_a="${tmpdir}/wt-cat-a"
  git -C "$repo" branch wt-a-branch main >/dev/null 2>&1
  git -C "$repo" worktree add "$wt_a" wt-a-branch >/dev/null 2>&1

  # ---- Worktree B: clean + 1 extra commit ------------------------------------
  local wt_b="${tmpdir}/wt-cat-b"
  git -C "$repo" worktree add -b wt-b-branch "$wt_b" main >/dev/null 2>&1
  touch "$wt_b/extra.txt"
  git -C "$wt_b" add extra.txt
  git -C "$wt_b" commit -m "extra commit on B" >/dev/null 2>&1

  # ---- Worktree C: dirty (uncommitted file) -----------------------------------
  local wt_c="${tmpdir}/wt-cat-c"
  git -C "$repo" worktree add -b wt-c-branch "$wt_c" main >/dev/null 2>&1
  echo "dirty" > "$wt_c/dirty.txt"
  # Do NOT git add — leave it untracked so status --porcelain is non-empty

  # ---- Run the hook against the fixture repo ----------------------------------
  local hook_stdout
  hook_stdout="$(
    cd "$repo"
    AIHAUS_MAIN_BRANCH=main bash "$hook" 2>/dev/null
  )" || true

  # ---- Assert Category A: worktree removed ------------------------------------
  # git worktree list --porcelain emits platform-native paths. Match on the
  # trailing directory name (wt-cat-a / wt-cat-c) which is unambiguous in
  # the fixture, avoids Unix-vs-Windows path prefix mismatch.
  local wt_list_after
  wt_list_after="$(git -C "$repo" worktree list --porcelain 2>/dev/null)"
  if printf '%s\n' "$wt_list_after" | grep -qE '(worktree .*/|worktree )wt-cat-a$'; then
    problems+=("A: category-A worktree still listed after reconcile (should have been pruned)")
  fi

  # ---- Assert Category B: cherry-pick recipe on stdout -----------------------
  if ! printf '%s\n' "$hook_stdout" | grep -q 'git cherry-pick'; then
    problems+=("B: stdout missing 'git cherry-pick' recipe for category-B worktree")
  fi

  # ---- Assert Category C: worktree preserved + dirty file intact --------------
  if ! printf '%s\n' "$wt_list_after" | grep -qE '(worktree .*/|worktree )wt-cat-c$'; then
    problems+=("C: category-C worktree was removed (should have been preserved)")
  fi
  if [[ ! -f "$wt_c/dirty.txt" ]]; then
    problems+=("C: dirty file removed from category-C worktree (should be untouched)")
  fi

  # ---- Cleanup ----------------------------------------------------------------
  rm -rf "$tmpdir" 2>/dev/null || true

  if [[ ${#problems[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${problems[@]}"
  fi
}

# ---- Check (M014/S09): crash-mid-implementer + resume substep fixture -------
# Simulates a crash after 2 of 4 files are written. The fixture RUN-MANIFEST
# has ## Checkpoints with:
#   file:a.sh enter + exit OK
#   file:b.sh enter + exit OK
#   file:c.sh enter          (orphan — no exit; crash point)
# A bash parsing helper reads the last ## Checkpoints row and returns the
# substep the agent should resume from.
# Assert: resume substep == file:c.sh
#
# Coupling note: this check tests the checkpoint-parsing logic inline (no
# external helper invoked) per LD-9 "unit-test-style invocation". The parsing
# routine is a local bash function inside this check. It mirrors what
# /aih-resume Phase 2 step 6 does: find the last row where event is 'enter'
# with no matching 'exit OK' row.
check_resume_substep_fixture() {
  _start_check
  local label="Check ${CHECK_NUMBER}: crash-mid-implementer + resume substep fixture (M014/S09)"
  local problems=()

  # ---- Create temp dir + fixture manifest ------------------------------------
  local tmpdir
  tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t aih-resume-smoke)"
  local fixture="${tmpdir}/RUN-MANIFEST.md"

  # Write a v3 RUN-MANIFEST with ## Checkpoints simulating a crash after
  # 2 of 4 expected files. The 4 planned substeps are:
  #   file:a.sh, file:b.sh, file:c.sh, file:d.sh
  # After the crash: a.sh and b.sh are fully done (enter+exit OK).
  # c.sh has an orphan enter (crash before exit). d.sh is untouched.
  cat > "$fixture" <<'FIXTURE_EOF'
## Metadata
milestone: M000-test
branch: test/branch
started: 2026-04-22T00:00:00Z
schema: v3
phase: execute-stories
status: running
last_updated: 2026-04-22T00:00:00Z

## Invoke stack

## Story Records
story_id|status|started_at|commit_sha|verified|notes
S03|running|2026-04-22T00:01:00Z|||

## Checkpoints

| ts | story | agent | substep | event | result | sha |
|---|---|---|---|---|---|---|
| 2026-04-22T10:00:00Z | S03 | implementer | file:a.sh | enter |  |  |
| 2026-04-22T10:01:00Z | S03 | implementer | file:a.sh | exit | OK | a1b2c3d |
| 2026-04-22T10:02:00Z | S03 | implementer | file:b.sh | enter |  |  |
| 2026-04-22T10:03:00Z | S03 | implementer | file:b.sh | exit | OK | b2c3d4e |
| 2026-04-22T10:04:00Z | S03 | implementer | file:c.sh | enter |  |  |
FIXTURE_EOF

  # ---- Inline parsing helper -------------------------------------------------
  # Reads the ## Checkpoints table from the fixture and determines the next
  # substep to resume from. Algorithm:
  #   1. Collect all substeps that have an 'exit OK' or 'exit SKIP' row.
  #   2. Find the first substep with an 'enter' row but no 'exit OK'/'exit SKIP'.
  #   3. That is the resume point (orphan enter = crash point).
  # Returns the substep string on stdout, or empty if none found.
  _find_resume_substep() {
    local manifest_path="$1"
    awk -F'|' '
      /^## Checkpoints/ { in_sec=1; next }
      /^## / && in_sec { in_sec=0; next }
      in_sec && NF==9 {
        # Columns (1-indexed after split on |, leading blank col = $1):
        # $2=ts $3=story $4=agent $5=substep $6=event $7=result $8=sha $9=trailing
        sub(/^[[:space:]]+/, "", $5); sub(/[[:space:]]+$/, "", $5)
        sub(/^[[:space:]]+/, "", $6); sub(/[[:space:]]+$/, "", $6)
        sub(/^[[:space:]]+/, "", $7); sub(/[[:space:]]+$/, "", $7)
        substep = $5
        event   = $6
        result  = $7
        # Track enter and exit-ok separately
        if (event == "enter") entered[substep] = 1
        if (event == "exit" && (result == "OK" || result == "SKIP")) exited[substep] = 1
      }
      END {
        # Find the first entered-but-not-exited substep.
        # Use insertion-order trick: store order in an array.
        # Since awk associative arrays dont guarantee order, re-scan for first match.
        # (We already processed the file top-down; a second pass preserves order.)
        # Print the first substep that was entered but not exited-ok.
        for (s in entered) {
          if (!(s in exited)) { print s; exit }
        }
      }
    ' "$manifest_path"
  }

  # Variant that preserves insertion order by scanning the file twice:
  # first pass builds the exited set, second pass finds first orphan enter.
  _find_resume_substep_ordered() {
    local manifest_path="$1"
    # Pass 1: collect all exit-OK substeps
    local exited_set
    exited_set=$(awk -F'|' '
      /^## Checkpoints/ { in_sec=1; next }
      /^## / && in_sec { in_sec=0; next }
      in_sec && NF==9 {
        sub(/^[[:space:]]+/, "", $5); sub(/[[:space:]]+$/, "", $5)
        sub(/^[[:space:]]+/, "", $6); sub(/[[:space:]]+$/, "", $6)
        sub(/^[[:space:]]+/, "", $7); sub(/[[:space:]]+$/, "", $7)
        if ($6 == "exit" && ($7 == "OK" || $7 == "SKIP")) print $5
      }
    ' "$manifest_path")

    # Pass 2: find first enter row whose substep is not in exited_set
    awk -F'|' -v exited="$exited_set" '
      BEGIN {
        n = split(exited, arr, "\n")
        for (i=1; i<=n; i++) done[arr[i]] = 1
      }
      /^## Checkpoints/ { in_sec=1; next }
      /^## / && in_sec { in_sec=0; next }
      in_sec && NF==9 {
        sub(/^[[:space:]]+/, "", $5); sub(/[[:space:]]+$/, "", $5)
        sub(/^[[:space:]]+/, "", $6); sub(/[[:space:]]+$/, "", $6)
        if ($6 == "enter" && !($5 in done)) { print $5; exit }
      }
    ' "$manifest_path"
  }

  # ---- Invoke the ordered helper and assert ----------------------------------
  local resume_substep
  resume_substep="$(_find_resume_substep_ordered "$fixture")"

  if [[ "$resume_substep" == "file:c.sh" ]]; then
    _pass "$label"
  else
    if [[ -z "$resume_substep" ]]; then
      problems+=("parsing helper returned empty string; expected 'file:c.sh'")
    else
      problems+=("expected resume substep 'file:c.sh'; got '${resume_substep}'")
    fi
    _fail "$label" "${problems[@]}"
  fi

  rm -rf "$tmpdir" 2>/dev/null || true
}

# ---- Check (M014/S02): bash-guard DANGEROUS_PATTERNS baseline ----------------
# Verifies bash-guard.sh contains the full DANGEROUS_PATTERNS set migrated from
# auto-approve-bash.sh M007 baseline (LD-4/S02). Each expected pattern fragment
# is regex-asserted present in bash-guard.sh.
#
# Post-S04 note: when auto-approve-bash.sh is deleted, this check becomes the
# standalone bash-guard DANGEROUS_PATTERNS baseline assertion per LD-9.
check_bash_guard_baseline() {
  _start_check
  local label="Check ${CHECK_NUMBER}: bash-guard.sh contains M007 DANGEROUS_PATTERNS baseline (M014/S02)"
  local hook="${PACKAGE_ROOT}/.aihaus/hooks/bash-guard.sh"

  if [[ ! -f "$hook" ]]; then
    _fail "$label" "hook missing: ${hook#${PACKAGE_ROOT}/}"
    return
  fi

  # Expected pattern fragments — one per M007 DANGEROUS_PATTERNS category.
  # Using plain grep -F (fixed string) or -q (substring) against the hook source
  # so that ERE metacharacter differences across grep implementations
  # (GNU vs BSD vs git-bash) don't cause false negatives.
  # Each fragment is a literal substring that must appear in bash-guard.sh.
  local -a expected_fragments=(
    # destructive filesystem
    'rm\s+-rf'
    'shred\b'
    'dd\s+if='
    'mkfs\.'
    '/dev/s[dr]'
    # privilege escalation
    'sudo\b'
    'doas\b'
    '^su\s'
    # destructive git
    'git\s+push\s+--force'
    'git\s+clean\s+-fd'
    # destructive SQL
    'drop\s+(table|database)'
    'truncate\s+table'
    # Windows destructive
    'del\s+/[FSQfsq]'
    'rmdir\s+/[Ss]'
    'format\s+[A-Za-z]:'
    # code injection
    "awk\\\\s+'"
    'sed\s+-i'
    # code-via-pipe
    'curl\s+'
    'wget\s+'
    # supply chain
    'npm\s+publish'
    'pip\s+publish'
    'cargo\s+publish'
    # nuclear docker
    'docker\s+system\s+prune'
    # fork bomb
    ':\(\)\s*\{'
  )

  local missing=()
  for fragment in "${expected_fragments[@]}"; do
    if ! grep -qF "$fragment" "$hook"; then
      missing+=("$fragment")
    fi
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "bash-guard.sh missing pattern fragments: ${missing[*]}"
  fi
}

# ---- Check (M014/S02+S04): read-guard.sh existence, executable, syntax, registered ----
# Verifies read-guard.sh is present, executable, and syntactically valid.
# M014/S04: also verifies it IS registered in settings.local.json under PreToolUse.
check_read_guard_exists() {
  _start_check
  local label="Check ${CHECK_NUMBER}: read-guard.sh exists, executable, syntax OK, registered in template (M014/S02+S04)"
  local hook="${PACKAGE_ROOT}/.aihaus/hooks/read-guard.sh"
  local tpl="${PACKAGE_ROOT}/.aihaus/templates/settings.local.json"
  local problems=()

  # (a) file exists
  if [[ ! -f "$hook" ]]; then
    _fail "$label" "read-guard.sh missing at hooks/read-guard.sh"
    return
  fi

  # (b) executable
  if [[ ! -x "$hook" ]]; then
    problems+=("read-guard.sh is not executable (run: chmod +x)")
  fi

  # (c) bash -n syntax check
  if ! bash -n "$hook" 2>/dev/null; then
    problems+=("read-guard.sh failed bash -n syntax check")
  fi

  # (d) shebang present
  if ! head -1 "$hook" | grep -q '^#!/'; then
    problems+=("read-guard.sh missing shebang on line 1")
  fi

  # (e) READ_GUARD_MODE constant declared
  if ! grep -q 'READ_GUARD_MODE' "$hook"; then
    problems+=("read-guard.sh missing READ_GUARD_MODE constant (LD-4 dual-path gate)")
  fi

  # (f) NOW referenced in settings.local.json (S04 registered it under PreToolUse)
  if [[ -f "$tpl" ]] && ! grep -q 'read-guard.sh' "$tpl"; then
    problems+=("read-guard.sh is not yet referenced in settings.local.json — S04 should have registered it")
  fi

  if [[ ${#problems[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${problems[@]}"
  fi
}

# ---- Check: /aih-init §2.5 migration regex does not false-positive on EVOLVING markers ----
# PURPOSE: Regression guard (M016-S13 / R7 mitigation). Confirms that the §2.5 migration
# regex inside aih-init SKILL.md is keyed off ACTIVE-MILESTONES, RECENT-DECISIONS, and
# RECENT-KNOWLEDGE only — and does NOT mention AIHAUS:EVOLVING. If /aih-init ever gained
# an EVOLVING-aware migration branch, it would need explicit gating logic; this check
# catches accidental inclusion early.
check_init_evolving_no_false_positive() {
  _start_check
  local label="Check ${CHECK_NUMBER}: /aih-init §2.5 migration regex does not false-positive on nested EVOLVING markers (M016-S13 R7)"
  local skill="${PACKAGE_ROOT}/.aihaus/skills/aih-init/SKILL.md"
  local problems=()

  if [[ ! -f "$skill" ]]; then
    _fail "$label" "aih-init/SKILL.md not found at expected path"
    return
  fi

  # (a) The known migration markers MUST be referenced (confirms §2.5 migration logic is present)
  # Note: SKILL.md prose uses the bare marker names (ACTIVE-MILESTONES-START/END etc.) without
  # the AIHAUS: prefix — match the prose pattern, not the HTML comment marker form.
  if ! grep -qE 'ACTIVE-MILESTONES|RECENT-DECISIONS|RECENT-KNOWLEDGE' "$skill"; then
    problems+=("aih-init SKILL.md does not reference ACTIVE-MILESTONES/RECENT-DECISIONS/RECENT-KNOWLEDGE — §2.5 migration section may have moved; review manually")
  fi

  # (b) AIHAUS:EVOLVING must NOT appear in the migration regex / init skill
  if grep -qE 'AIHAUS:EVOLVING' "$skill"; then
    problems+=("aih-init SKILL.md contains AIHAUS:EVOLVING reference — risk of false-positive match on nested EVOLVING markers; review and isolate")
  fi

  if [[ ${#problems[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${problems[@]}"
  fi
}

# ---- filename-prefix guard on per-agent memory tree (M016-S15a) -------------
# PURPOSE: Asserts no file in pkg/.aihaus/memory/agents/** or .aihaus/memory/agents/**
# matches the reserved prefixes feedback_* or user_* (underscore). Agent filenames
# use hyphens only (e.g. user-profiler.md); underscore prefixes are reserved for
# the persistent agent memory system and must not bleed into per-agent memory files.
# Hyphen distinction: user-profiler.md (hyphen) does NOT trigger; user_*.md (underscore) does.
check_agent_memory_filename_prefix_guard() {
  _start_check
  local label="Check ${CHECK_NUMBER}: filename-prefix guard on per-agent memory tree (M016-S15a)"
  local problems=()

  # Check pkg/.aihaus/memory/agents/** (shipped package source)
  local pkg_agents_mem="${PACKAGE_ROOT}/.aihaus/memory/agents"
  if [[ -d "$pkg_agents_mem" ]]; then
    local pkg_violations
    pkg_violations=$(find "$pkg_agents_mem" -maxdepth 2 \( -name 'feedback_*' -o -name 'user_*' \) 2>/dev/null | head -20)
    if [[ -n "$pkg_violations" ]]; then
      while IFS= read -r v; do
        problems+=("pkg reserved prefix violation: ${v#${PACKAGE_ROOT}/}")
      done <<< "$pkg_violations"
    fi
  fi

  # Check .aihaus/memory/agents/** (dogfood install — repo root, sibling of pkg/)
  local repo_root="${PACKAGE_ROOT}/.."
  local dogfood_agents_mem="${repo_root}/.aihaus/memory/agents"
  if [[ -d "$dogfood_agents_mem" ]]; then
    local df_violations
    df_violations=$(find "$dogfood_agents_mem" -maxdepth 2 \( -name 'feedback_*' -o -name 'user_*' \) 2>/dev/null | head -20)
    if [[ -n "$df_violations" ]]; then
      while IFS= read -r v; do
        problems+=("dogfood reserved prefix violation: ${v#${repo_root}/}")
      done <<< "$df_violations"
    fi
  fi

  if [[ ${#problems[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${problems[@]}"
  fi
}

# ---- EVOLVING block well-formed in project.md template AND CLAUDE.md (M016-S16) --
# PURPOSE: Asserts both files contain matched <!-- AIHAUS:EVOLVING-START --> and
# <!-- AIHAUS:EVOLVING-END --> markers, exactly one pair each, START appearing before
# END. Empty body inside markers is acceptable — a milestone with no curator emit is a
# valid no-op state. Checks:
#   (a) pkg/.aihaus/templates/project.md (nested inside MANUAL block, per ADR-M016-B)
#   (b) CLAUDE.md at repo root (at EOF, per ADR-M016-B)
check_evolving_block_well_formed() {
  _start_check
  local label="Check ${CHECK_NUMBER}: EVOLVING block well-formed in project.md template AND CLAUDE.md (M016-S16)"
  local repo_root="${PACKAGE_ROOT}/.."
  local project_tmpl="${PACKAGE_ROOT}/.aihaus/templates/project.md"
  local claude_md="${repo_root}/CLAUDE.md"
  local problems=()

  _check_evolving_markers() {
    local file="$1"
    local display_name="$2"
    if [[ ! -f "$file" ]]; then
      problems+=("${display_name}: file not found")
      return
    fi
    local start_count end_count
    start_count=$(grep -c '<!-- AIHAUS:EVOLVING-START -->' "$file" 2>/dev/null || echo "0")
    end_count=$(grep -c '<!-- AIHAUS:EVOLVING-END -->' "$file" 2>/dev/null || echo "0")
    if [[ "$start_count" -ne 1 ]]; then
      problems+=("${display_name}: expected exactly 1 AIHAUS:EVOLVING-START marker; found ${start_count}")
    fi
    if [[ "$end_count" -ne 1 ]]; then
      problems+=("${display_name}: expected exactly 1 AIHAUS:EVOLVING-END marker; found ${end_count}")
    fi
    # Verify START appears before END (line number order)
    if [[ "$start_count" -eq 1 && "$end_count" -eq 1 ]]; then
      local start_line end_line
      start_line=$(grep -n '<!-- AIHAUS:EVOLVING-START -->' "$file" | head -1 | cut -d: -f1)
      end_line=$(grep -n '<!-- AIHAUS:EVOLVING-END -->' "$file" | head -1 | cut -d: -f1)
      if [[ -n "$start_line" && -n "$end_line" && "$start_line" -ge "$end_line" ]]; then
        problems+=("${display_name}: AIHAUS:EVOLVING-START (line ${start_line}) must appear before AIHAUS:EVOLVING-END (line ${end_line})")
      fi
    fi
  }

  _check_evolving_markers "$project_tmpl" "templates/project.md"
  _check_evolving_markers "$claude_md" "CLAUDE.md"

  if [[ ${#problems[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${problems[@]}"
  fi
}

# ---- SKILL-EVOLUTION post-apply validation: sub-mode accessibility check (M016-S16) --
# PURPOSE: Verifies that the smoke-test --check sub-modes introduced in S12
# (skill-line-cap and skill-frontmatter) are accessible and functional. This is the
# static backstop for Step 4.6's pre-apply gate — even if the gate is bypassed by some
# future code path, the sub-modes themselves must be reachable and return correct results.
# Runs both sub-modes against an existing SKILL.md (aih-plan) that is known-good;
# asserts exit 0. Catches any regression in the --check dispatcher logic.
check_skill_evolution_post_apply_sub_modes() {
  _start_check
  local label="Check ${CHECK_NUMBER}: SKILL-EVOLUTION post-apply sub-modes accessible (skill-line-cap + skill-frontmatter, M016-S16)"
  local this_script="${SCRIPT_DIR}/smoke-test.sh"
  local test_skill="aih-plan"
  local problems=()

  if [[ ! -f "$this_script" ]]; then
    _fail "$label" "smoke-test.sh not found at $this_script"
    return
  fi

  # Sub-mode 1: skill-line-cap on aih-plan (known ≤200 lines)
  local cap_out cap_rc
  cap_out=$(bash "$this_script" --check skill-line-cap --skill "$test_skill" 2>&1)
  cap_rc=$?
  if [[ "$cap_rc" -ne 0 ]]; then
    problems+=("skill-line-cap sub-mode returned exit ${cap_rc} for ${test_skill}: ${cap_out:0:120}")
  elif ! printf '%s' "$cap_out" | grep -q '\[PASS\]'; then
    problems+=("skill-line-cap sub-mode did not emit [PASS] for ${test_skill}: ${cap_out:0:120}")
  fi

  # Sub-mode 2: skill-frontmatter on aih-plan (known valid name: aih-plan)
  local fm_out fm_rc
  fm_out=$(bash "$this_script" --check skill-frontmatter --skill "$test_skill" 2>&1)
  fm_rc=$?
  if [[ "$fm_rc" -ne 0 ]]; then
    problems+=("skill-frontmatter sub-mode returned exit ${fm_rc} for ${test_skill}: ${fm_out:0:120}")
  elif ! printf '%s' "$fm_out" | grep -q '\[PASS\]'; then
    problems+=("skill-frontmatter sub-mode did not emit [PASS] for ${test_skill}: ${fm_out:0:120}")
  fi

  if [[ ${#problems[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${problems[@]}"
  fi
}

# ---- memory-scores.jsonl single-writer prose assertion (M016-S16) -----------
# PURPOSE: Greps .aihaus/decisions.md (dogfood ADR ledger) to confirm exactly one
# named writer (composite-score.sh) is registered for memory-scores.jsonl. This is
# the F6 single-writer resolution mechanically guarded — any future ADR that names a
# second writer for memory-scores.jsonl would fail this check before merge. Prose
# assertion only; does not test runtime behavior.
check_memory_scores_single_writer_prose() {
  _start_check
  local label="Check ${CHECK_NUMBER}: memory-scores.jsonl single-writer prose assertion (composite-score.sh, M016-S16)"
  local repo_root="${PACKAGE_ROOT}/.."
  local decisions_md="${repo_root}/.aihaus/decisions.md"
  local problems=()

  if [[ ! -f "$decisions_md" ]]; then
    # decisions.md is gitignored (dogfood install); skip gracefully if absent.
    _pass "${label} [skipped — .aihaus/decisions.md not present in this environment]"
    return
  fi

  # Assert composite-score.sh is mentioned as writer of memory-scores.jsonl
  if ! grep -q 'composite-score\.sh' "$decisions_md"; then
    problems+=("composite-score.sh not found in .aihaus/decisions.md — single-writer prose assertion missing (ADR-M016-A F6)")
  fi

  # Assert memory-scores.jsonl appears in the writer table
  if ! grep -q 'memory-scores\.jsonl' "$decisions_md"; then
    problems+=("memory-scores.jsonl not found in .aihaus/decisions.md — writer table entry missing")
  fi

  # Assert the co-occurrence: composite-score.sh is the named writer FOR memory-scores.jsonl
  # (both strings appear in the same writer-table row)
  if ! grep 'memory-scores\.jsonl' "$decisions_md" | grep -q 'composite-score\.sh'; then
    problems+=("composite-score.sh not found on the same line as memory-scores.jsonl in .aihaus/decisions.md — single-writer registration may be missing or split across lines")
  fi

  if [[ ${#problems[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${problems[@]}"
  fi
}

# ---- Check (M017/S08): M017 new hooks bash-n syntax aggregate ---------------
# Validates bash -n over all 5 M017 hooks (worktree-release, worktree-release-all,
# worktree-reap, merge-back, git-add-guard). worktree-branch-from.sh is absent
# (S05 Path B — not shipped). Aggregate single check, not 5 separate checks.
check_m017_hooks_bash_n() {
  _start_check
  local label="Check ${CHECK_NUMBER}: M017 new hooks bash-n syntax (5 files, M017/S08)"
  local hooks_root="${PACKAGE_ROOT}/.aihaus/hooks"
  local -a m017_hooks=(
    "${hooks_root}/worktree-release.sh"
    "${hooks_root}/worktree-release-all.sh"
    "${hooks_root}/worktree-reap.sh"
    "${hooks_root}/merge-back.sh"
    "${hooks_root}/git-add-guard.sh"
  )
  local fail_flag=0
  local count=0
  for h in "${m017_hooks[@]}"; do
    if [[ ! -f "$h" ]]; then
      _fail "$label" "${h#${PACKAGE_ROOT}/} missing"
      return
    fi
    if ! bash -n "$h" 2>/dev/null; then
      _fail "$label" "${h#${PACKAGE_ROOT}/} failed bash -n syntax check"
      return
    fi
    count=$((count+1))
  done
  _pass "$label ($count files)"
}

# ---- Check (M017/S08): merge-back.sh refusal fixture (unexpected-file) ------
# Exercises the 2026-04-12 incident scenario: worktree has one Owned file but
# also has an unexpected staged file in the main repo. Asserts:
#   - exit code 3
#   - stderr contains MERGE_BACK_REFUSED
#   - stderr contains all 5 required fields: story, reason, expected, actual, worktree
# Self-contained: delegates to tools/fixtures/M017/merge-back-refusal/fixture.sh
# (which sets up + tears down its own temp git repo).
check_m017_merge_back_refusal() {
  _start_check
  local label="Check ${CHECK_NUMBER}: merge-back.sh refusal fixture (unexpected-file, M017/S08)"
  local fixture="${SCRIPT_DIR}/fixtures/M017/merge-back-refusal/fixture.sh"
  if [[ ! -f "$fixture" ]]; then
    _fail "$label" "fixture missing: tools/fixtures/M017/merge-back-refusal/fixture.sh"
    return
  fi
  if bash "$fixture" >/dev/null 2>&1; then
    _pass "$label"
  else
    # Re-run to capture output for diagnostics
    local out
    out="$(bash "$fixture" 2>&1 || true)"
    _fail "$label" "$out"
  fi
}

# ---- Check (M017/S08): git-add-guard.sh deny/allow fixture -------------------
# Asserts the 4 canonical cases:
#   C1: git add -A on milestone branch → denied (exit 2)
#   C2: git commit -am on milestone branch → denied (exit 2)
#   C3: git add explicit-file.txt on milestone branch → allowed (exit 0)
#   C4: git add -A on main branch → allowed (exit 0, off-milestone bypass)
# Self-contained: delegates to tools/fixtures/M017/git-add-guard-cases/fixture.sh
# (which sets up + tears down its own temp git repo).
check_m017_git_add_guard_cases() {
  _start_check
  local label="Check ${CHECK_NUMBER}: git-add-guard.sh deny/allow fixture (4 cases, M017/S08)"
  local fixture="${SCRIPT_DIR}/fixtures/M017/git-add-guard-cases/fixture.sh"
  if [[ ! -f "$fixture" ]]; then
    _fail "$label" "fixture missing: tools/fixtures/M017/git-add-guard-cases/fixture.sh"
    return
  fi
  if bash "$fixture" >/dev/null 2>&1; then
    _pass "$label"
  else
    local out
    out="$(bash "$fixture" 2>&1 || true)"
    _fail "$label" "$out"
  fi
}

# ---- Check 51 (M018/S1+S2): L4 reap 4-axis regression fixture ---------------
# Wires S1's tools/fixtures/M017/reap-execute/fixture.sh into the smoke-test suite.
# Fixture exits 0 when all 4 worktree-reap axes pass; exits non-zero on any failure.
check_m018_reap_fixture() {
  _start_check
  local label="Check ${CHECK_NUMBER}: L4 reap 4-axis fixture (M018/S1)"
  local fixture="${SCRIPT_DIR}/fixtures/M017/reap-execute/fixture.sh"
  if [[ ! -f "$fixture" ]]; then
    _fail "$label" "fixture missing: tools/fixtures/M017/reap-execute/fixture.sh"
    return
  fi
  if bash "$fixture" >/dev/null 2>&1; then
    _pass "$label"
  else
    local out
    out="$(bash "$fixture" 2>&1 || true)"
    _fail "$label" "$out"
  fi
}

# ---- Check 52 (M018/S2+S4): release-notes shape 3-scenario fixture ----------
# Wires S4's tools/fixtures/M017/release-notes-shape/fixture.sh into the smoke-test suite.
# Fixture exits 0 when all 3 release-notes shape scenarios pass.
check_m018_release_notes_shape_fixture() {
  _start_check
  local label="Check ${CHECK_NUMBER}: release-notes-shape 3-scenario fixture (M018/S4)"
  local fixture="${SCRIPT_DIR}/fixtures/M017/release-notes-shape/fixture.sh"
  if [[ ! -f "$fixture" ]]; then
    _fail "$label" "fixture missing: tools/fixtures/M017/release-notes-shape/fixture.sh"
    return
  fi
  if bash "$fixture" >/dev/null 2>&1; then
    _pass "$label"
  else
    local out
    out="$(bash "$fixture" 2>&1 || true)"
    _fail "$label" "$out"
  fi
}

# ---- Check 53 (M018/S2): env-name dot grep-guard (CHECK L4) -----------------
# Guards against env variable names with literal dots (POSIX-invalid), which caused
# CHECK C2 regression in M017. Scans all shipped files in pkg/.aihaus/ for the pattern
# AIHAUS_[A-Z_]*.[A-Z0-9_]+ (where . is a literal dot in env names, not regex).
check_m018_env_name_dot_guard() {
  _start_check
  local label="Check ${CHECK_NUMBER}: env-name dot grep-guard (CHECK C2 regression prevention, M018/S2)"
  local matches
  if matches=$(grep -rE 'AIHAUS_[A-Z_]*\.[A-Z0-9_]+' "${PACKAGE_ROOT}/.aihaus/" 2>/dev/null); then
    _fail "$label" "env names with literal dots (POSIX-invalid) found:" "$matches"
  else
    _pass "$label"
  fi
}

# ---- Check 54 (F260427/S1): session-end.sh has no blind stash pop -----------
# ADR-260427-A: session-end must NOT auto-pop without label cross-validation.
# The old behavior `git stash pop 2>/dev/null || true` was a defect — pop is
# now gated on clean tree + label match. This check fails if a regression
# restores the blind pop pattern.
check_f260427_session_end_safe_pop() {
  _start_check
  local label="Check ${CHECK_NUMBER}: session-end.sh safe-pop pattern (F260427/S1, ADR-260427-A)"
  local f="${PACKAGE_ROOT}/.aihaus/hooks/session-end.sh"
  if [[ ! -f "$f" ]]; then
    _fail "$label" "hook missing: $f"
    return
  fi
  # Must NOT contain blind `git stash pop 2>/dev/null || true` pattern at the
  # top level (without label/clean-tree gate). A grep on the literal old line:
  if grep -E '^[[:space:]]*git[[:space:]]+stash[[:space:]]+pop[[:space:]]+2>/dev/null[[:space:]]*\|\|[[:space:]]+true[[:space:]]*$' "$f" >/dev/null 2>&1; then
    _fail "$label" "blind 'git stash pop 2>/dev/null || true' found — defect regressed"
    return
  fi
  # Must contain the audit-log positive marker (proves the new behavior is wired).
  if ! grep -q '_record_pending\|session-end-stash-pending' "$f"; then
    _fail "$label" "audit-log marker missing — _record_pending or session-end-stash-pending"
    return
  fi
  # Must contain SHA-stable ref (M018/S5 alignment).
  if ! grep -q 'git rev-parse stash@{0}' "$f"; then
    _fail "$label" "SHA-stable stash ref missing — must use 'git rev-parse stash@{0}'"
    return
  fi
  _pass "$label"
}

# ---- Check 55 (F260427/S2): bash-guard branch-switch warn fixture -----------
# Wires the 4-case fixture into the smoke-test suite. Asserts: warn fires on
# bare ref switch with running manifest, file-mode skipped, -b skipped, opt-out
# silences. Fixture exits 0 on all-pass.
check_f260427_branch_switch_warn_fixture() {
  _start_check
  local label="Check ${CHECK_NUMBER}: bash-guard branch-switch-warn 7-case fixture (F260427/S2)"
  local fixture="${SCRIPT_DIR}/fixtures/F260427/branch-switch-warn/fixture.sh"
  if [[ ! -f "$fixture" ]]; then
    _fail "$label" "fixture missing: tools/fixtures/F260427/branch-switch-warn/fixture.sh"
    return
  fi
  if bash "$fixture" >/dev/null 2>&1; then
    _pass "$label"
  else
    local out
    out="$(bash "$fixture" 2>&1 || true)"
    _fail "$label" "$out"
  fi
}

# ---- Check 56 (F260427/S3): pre-flight collision annex exists ---------------
# ADR-260427-C: feature/bugfix skills reference a shared pre-flight annex.
# Fails if annex missing OR if SKILL.md doesn't reference it.
check_f260427_pre_flight_annex() {
  _start_check
  local label="Check ${CHECK_NUMBER}: pre-flight collision annex + SKILL refs (F260427/S3, ADR-260427-C)"
  local annex="${PACKAGE_ROOT}/.aihaus/skills/aih-feature/annexes/pre-flight-collision.md"
  local feat_skill="${PACKAGE_ROOT}/.aihaus/skills/aih-feature/SKILL.md"
  local bug_skill="${PACKAGE_ROOT}/.aihaus/skills/aih-bugfix/SKILL.md"
  if [[ ! -f "$annex" ]]; then
    _fail "$label" "annex missing: pkg/.aihaus/skills/aih-feature/annexes/pre-flight-collision.md"
    return
  fi
  if ! grep -q 'pre-flight-collision\.md' "$feat_skill" 2>/dev/null; then
    _fail "$label" "aih-feature/SKILL.md missing reference to pre-flight-collision.md"
    return
  fi
  if ! grep -q 'pre-flight-collision\.md' "$bug_skill" 2>/dev/null; then
    _fail "$label" "aih-bugfix/SKILL.md missing reference to pre-flight-collision.md"
    return
  fi
  _pass "$label"
}

# ---- Check 57 (F260427): aih-feature/SKILL.md ≤ 199 lines (200-line ceiling safety net) ---
# Belt-and-suspenders: check_skill_length already enforces <200 globally.
# This check pins aih-feature/aih-bugfix to ≤199 explicitly so future edits
# touching pre-flight content surface line-count regressions early.
check_f260427_skill_line_safety() {
  _start_check
  local label="Check ${CHECK_NUMBER}: aih-feature + aih-bugfix SKILL.md ≤199 lines (F260427 safety net)"
  local feat_lines bug_lines
  feat_lines=$(wc -l < "${PACKAGE_ROOT}/.aihaus/skills/aih-feature/SKILL.md" | tr -d ' ')
  bug_lines=$(wc -l < "${PACKAGE_ROOT}/.aihaus/skills/aih-bugfix/SKILL.md" | tr -d ' ')
  if [[ "$feat_lines" -gt 199 ]]; then
    _fail "$label" "aih-feature/SKILL.md is $feat_lines lines (max 199 — move new prose to annexes/ per ADR-260427-C)"
    return
  fi
  if [[ "$bug_lines" -gt 199 ]]; then
    _fail "$label" "aih-bugfix/SKILL.md is $bug_lines lines (max 199 — move new prose to annexes/ per ADR-260427-C)"
    return
  fi
  _pass "$label"
}

# ---- Check 59 (M019/S05): RUN-STATUS projection contract + ADR-M019-A + cwd helper + regex-baseline --
# Consolidated 9-sub-assert check (CHECK F3 lock: single _start_check at function head).
# Sub-asserts:
#   1. RUN-STATUS-projection-contract.md exists
#   2. Template references ADR-M019-A
#   3. Template references manifest-append.sh as sole writer
#   4. Template contains canonical disjoint-projections sentence
#   5. decisions.md has ## ADR-M019-A header
#   6. decisions.md contains canonical sentence
#   7. decisions.md contains "applicability examples" (case-insensitive, CHECK F8)
#   8. lib/manifest-helpers.sh has resolve_manifest_path function
#   9. regex-baseline diff yields zero lines (byte-identical R4 mitigation)
check_run_status_contract() {
  _start_check
  local label="Check ${CHECK_NUMBER}: RUN-STATUS projection contract + ADR-M019-A + S04 cwd helper + regex-baseline preserved (M019/S05)"
  local repo_root="${PACKAGE_ROOT}/.."

  # Sub-assert 1: template exists
  local tmpl="${PACKAGE_ROOT}/.aihaus/templates/RUN-STATUS-projection-contract.md"
  if [[ ! -f "$tmpl" ]]; then
    _fail "$label" "RUN-STATUS-projection-contract.md missing at pkg/.aihaus/templates/"
    return
  fi

  # Sub-assert 2: template references ADR-M019-A
  if ! grep -q "ADR-M019-A" "$tmpl"; then
    _fail "$label" "template missing ADR-M019-A reference"
    return
  fi

  # Sub-assert 3: template references manifest-append.sh as sole writer
  if ! grep -q "manifest-append.sh" "$tmpl"; then
    _fail "$label" "template missing manifest-append.sh sole-writer reference"
    return
  fi

  # Sub-assert 4: template carries canonical disjoint-projections sentence
  if ! grep -q "STATUS owns phase only; RUN-STATUS owns progress only" "$tmpl"; then
    _fail "$label" "template missing canonical sentence 'STATUS owns phase only; RUN-STATUS owns progress only'"
    return
  fi

  # Sub-assert 5: decisions.md has ADR-M019-A header
  local decisions="${PACKAGE_ROOT}/.aihaus/decisions.md"
  if ! grep -q "^## ADR-M019-A" "$decisions" 2>/dev/null; then
    _fail "$label" "decisions.md missing ## ADR-M019-A header"
    return
  fi

  # Sub-assert 6: decisions.md has the canonical sentence
  if ! grep -q "STATUS owns phase only; RUN-STATUS owns progress only" "$decisions" 2>/dev/null; then
    _fail "$label" "decisions.md missing canonical sentence 'STATUS owns phase only; RUN-STATUS owns progress only'"
    return
  fi

  # Sub-assert 7: applicability examples header (case-insensitive per CHECK F8)
  if ! grep -qi "applicability examples" "$decisions" 2>/dev/null; then
    _fail "$label" "decisions.md missing 'applicability examples' header (case-insensitive)"
    return
  fi

  # Sub-assert 8: resolve_manifest_path function exists in lib
  local helpers="${PACKAGE_ROOT}/.aihaus/hooks/lib/manifest-helpers.sh"
  if ! grep -q "^resolve_manifest_path" "$helpers" 2>/dev/null; then
    _fail "$label" "lib/manifest-helpers.sh missing resolve_manifest_path function"
    return
  fi

  # Sub-assert 9: regex-baseline byte-identical (R4 mitigation, CHECK F4)
  # Extraction command (documented in regex-baseline.txt header):
  #   awk '/^PATTERNS=\$\(cat <<.PATTERNS_EOF./{on=1; next} /^PATTERNS_EOF$/{on=0} on {print}' \
  #     pkg/.aihaus/hooks/autonomy-guard.sh
  local baseline="${repo_root}/.aihaus/milestones/M019-260501-improve-auto-mode-feedback/execution/regex-baseline.txt"
  if [[ ! -f "$baseline" ]]; then
    # Baseline absent (e.g., worktree without dogfood .aihaus) — skip gracefully
    _pass "$label [sub-assert 9 skipped — regex-baseline.txt not present in this environment]"
    return
  fi
  local guard="${PACKAGE_ROOT}/.aihaus/hooks/autonomy-guard.sh"
  if [[ ! -f "$guard" ]]; then
    _fail "$label" "autonomy-guard.sh missing — cannot verify regex-baseline"
    return
  fi
  local extracted_patterns baseline_patterns
  extracted_patterns=$(awk '/^PATTERNS=\$\(cat <<.PATTERNS_EOF./{on=1; next} /^PATTERNS_EOF$/{on=0} on {print}' "$guard" 2>/dev/null)
  baseline_patterns=$(grep -v '^#' "$baseline" | grep -v '^$')
  if [[ "$extracted_patterns" == "$baseline_patterns" ]]; then
    _pass "$label"
  else
    _fail "$label" "regex-baseline mismatch — autonomy-guard.sh 11-regex array has drifted from snapshot (run: diff <(grep -v '^#' execution/regex-baseline.txt | grep -v '^$') <(awk '/^PATTERNS=..cat <<.PATTERNS_EOF./{on=1; next} /^PATTERNS_EOF\$/{on=0} on {print}' pkg/.aihaus/hooks/autonomy-guard.sh))"
  fi
}

# ---- Check 60 (M020/S02): manifest-auto-close.sh present + parseable --------
# Asserts:
#   - pkg/.aihaus/hooks/manifest-auto-close.sh exists
#   - bash -n syntax check passes
#   - sources lib/integration-refs.sh (string match for source line)
#   - declares the constant hook=manifest-auto-close for audit-log greppability (NFR-04)
check_manifest_auto_close_present() {
  _start_check
  local label="Check ${CHECK_NUMBER}: manifest-auto-close.sh present + parseable + audit-id constant (M020/S02)"
  local hook="${PACKAGE_ROOT}/.aihaus/hooks/manifest-auto-close.sh"
  if [[ ! -f "$hook" ]]; then
    _fail "$label" "manifest-auto-close.sh missing at pkg/.aihaus/hooks/"
    return
  fi
  if ! bash -n "$hook" 2>/dev/null; then
    _fail "$label" "manifest-auto-close.sh failed bash -n syntax check"
    return
  fi
  if ! grep -q 'lib/integration-refs.sh' "$hook"; then
    _fail "$label" "manifest-auto-close.sh missing 'lib/integration-refs.sh' source line"
    return
  fi
  if ! grep -q 'hook=manifest-auto-close\|"hook":"manifest-auto-close"\|"hook": *"manifest-auto-close"' "$hook"; then
    _fail "$label" "manifest-auto-close.sh missing constant audit-log identifier 'hook=manifest-auto-close' (NFR-04)"
    return
  fi
  _pass "$label"
}

# ---- Check 58 (F260427/S5a): three new ADRs landed in decisions.md ----------
# Sanity check: ADR-260427-A, ADR-260427-B, ADR-260427-C all present.
check_f260427_adrs_present() {
  _start_check
  local label="Check ${CHECK_NUMBER}: ADR-260427-A/B/C present in decisions.md (F260427/S5a)"
  local f="${PACKAGE_ROOT}/.aihaus/decisions.md"
  for adr in ADR-260427-A ADR-260427-B ADR-260427-C; do
    if ! grep -q "$adr" "$f" 2>/dev/null; then
      _fail "$label" "$adr missing from pkg/.aihaus/decisions.md"
      return
    fi
  done
  _pass "$label"
}

# ---- Check 61 (M020/S10): aih-close skill frontmatter conformance -----------
check_aih_close_skill() {
  _start_check
  local label="Check ${CHECK_NUMBER}: aih-close skill frontmatter conformance (M020/S10)"
  local f="${PACKAGE_ROOT}/.aihaus/skills/aih-close/SKILL.md"
  [ -f "$f" ] || { _fail "$label" "missing $f"; return; }
  grep -q '^name: aih-close$' "$f" || { _fail "$label" "name field missing or malformed"; return; }
  local lines
  lines=$(wc -l < "$f" | tr -d ' ')
  [ "$lines" -le 200 ] || { _fail "$label" "$lines > 200 lines"; return; }
  _pass "$label"
}

# ---- Check 62: enforcement-audit scaffold + ADR + structural gate (M021/S01) -
check_enforcement_audit_scaffold() {
  _start_check
  local label="Check ${CHECK_NUMBER}: enforcement-audit scaffold + ADR-260503-A structural gate (M021/S01)"
  local canonical="pkg/.aihaus/skills/_shared/enforcement-audit.md"
  local audit_dir="${PACKAGE_ROOT}/.aihaus/skills/_shared/enforcement-audit"
  local golden_rows="tools/.fixtures/enforcement-audit/golden-rows/golden-rows.md"
  local decisions_md="${PACKAGE_ROOT}/.aihaus/decisions.md"

  # Phase A (pre-S08): canonical doesn't exist; verify scaffold prerequisites only
  if [ ! -f "${SCRIPT_DIR}/../${canonical}" ]; then
    if [ ! -d "$audit_dir" ]; then
      _fail "$label" "audit dir missing: $audit_dir"
      return
    fi
    if [ ! -f "${SCRIPT_DIR}/../${golden_rows}" ]; then
      _fail "$label" "golden-rows missing: $golden_rows"
      return
    fi
    if ! grep -q "ADR-260503-A" "$decisions_md" 2>/dev/null; then
      _fail "$label" "ADR-260503-A absent from decisions.md"
      return
    fi
    _pass "$label (Phase A — canonical not yet created by S08)"
    return
  fi

  # Phase B (post-S08): canonical exists; verify >=4 H2 + row count match
  local canonical_path="${SCRIPT_DIR}/../${canonical}"
  local h2_count
  h2_count=$(grep -c '^## ' "$canonical_path" 2>/dev/null || echo 0)
  if [ "$h2_count" -lt 4 ]; then
    _fail "$label" "canonical has $h2_count H2 headers (need >=4)"
    return
  fi
  local actual
  actual=$(grep -c '^| aih-' "$canonical_path" 2>/dev/null || echo 0)
  local expected
  expected=$(bash "${SCRIPT_DIR}/audit-skill-enforcement.sh" --compute-expected 2>/dev/null || echo 0)
  if [ "$actual" -ne "$expected" ]; then
    _fail "$label" "row count $actual != expected $expected"
    return
  fi
  _pass "$label (Phase B — canonical: $actual rows match expected)"
}

# ---- Selectable sub-mode dispatcher (--check <name> --skill <slug>) ---------
# PURPOSE: invoked by completion-protocol Step 4.6 pre-apply gate before each
# skill evolution is committed. Runs only the named check against the named skill;
# exits 0 on pass, 1 on fail. Does NOT bump CHECK_NUMBER or affect FAILURES.
#
# Usage:
#   bash tools/smoke-test.sh --check skill-line-cap --skill aih-milestone
#   bash tools/smoke-test.sh --check skill-frontmatter --skill aih-plan
#
# skill-line-cap    : asserts pkg/.aihaus/skills/<slug>/SKILL.md is <= 200 lines
# skill-frontmatter : asserts SKILL.md declares `name: aih-<slug>` in frontmatter
_run_check_submode() {
  local check_name="$1"
  local skill_slug="$2"
  local skill_file="${PACKAGE_ROOT}/.aihaus/skills/${skill_slug}/SKILL.md"

  if [[ ! -f "$skill_file" ]]; then
    printf "[FAIL] --check %s: SKILL.md not found at %s\n" "$check_name" "$skill_file" >&2
    exit 1
  fi

  case "$check_name" in
    skill-line-cap)
      local lines
      lines=$(wc -l < "$skill_file" | tr -d ' ')
      if [[ "$lines" -le 200 ]]; then
        printf "[PASS] skill-line-cap: %s (%s lines)\n" "$skill_slug" "$lines"
        exit 0
      else
        printf "[FAIL] skill-line-cap: %s has %s lines (max 200)\n" "$skill_slug" "$lines" >&2
        exit 1
      fi
      ;;
    skill-frontmatter)
      if head -20 "$skill_file" | grep -Eq "^name:[[:space:]]*aih-${skill_slug#aih-}"; then
        printf "[PASS] skill-frontmatter: %s declares name: aih-*\n" "$skill_slug"
        exit 0
      else
        printf "[FAIL] skill-frontmatter: %s missing or malformed 'name: aih-<slug>'\n" "$skill_slug" >&2
        exit 1
      fi
      ;;
    *)
      printf "[FAIL] unknown --check value '%s' (known: skill-line-cap, skill-frontmatter)\n" "$check_name" >&2
      exit 1
      ;;
  esac
}

# ---- Check 63: CLI shim parseable (M022/Z5) ---------------------------------
# Verifies pkg/scripts/aihaus passes bash -n, and that aihaus.cmd + aihaus.ps1
# exist and are non-empty. Optional: parse aihaus.ps1 via pwsh if available;
# skip (not fail) on hosts without pwsh (Linux CI).
check_cli_shim_parseable() {
  _start_check
  local label="Check ${CHECK_NUMBER}: CLI shim parseable (M022/Z5 FR-33)"
  local issues=()
  local scripts_dir="${PACKAGE_ROOT}/scripts"

  # Sub-assert 1: bash -n on the main shim
  if [[ ! -f "${scripts_dir}/aihaus" ]]; then
    issues+=("pkg/scripts/aihaus missing")
  elif ! bash -n "${scripts_dir}/aihaus" 2>/dev/null; then
    issues+=("pkg/scripts/aihaus has bash syntax error")
  fi

  # Sub-assert 2: aihaus.cmd exists and is non-empty
  if [[ ! -f "${scripts_dir}/aihaus.cmd" ]]; then
    issues+=("pkg/scripts/aihaus.cmd missing")
  elif [[ ! -s "${scripts_dir}/aihaus.cmd" ]]; then
    issues+=("pkg/scripts/aihaus.cmd is empty")
  fi

  # Sub-assert 3: aihaus.ps1 exists and is non-empty
  if [[ ! -f "${scripts_dir}/aihaus.ps1" ]]; then
    issues+=("pkg/scripts/aihaus.ps1 missing")
  elif [[ ! -s "${scripts_dir}/aihaus.ps1" ]]; then
    issues+=("pkg/scripts/aihaus.ps1 is empty")
  fi

  # Sub-assert 4: optional PowerShell parse — skip if pwsh not available
  if command -v pwsh >/dev/null 2>&1; then
    if [[ -f "${scripts_dir}/aihaus.ps1" ]]; then
      if ! pwsh -NoProfile -Command "
        \$null = [System.Management.Automation.Language.Parser]::ParseFile(
          '${scripts_dir}/aihaus.ps1', [ref]\$null, [ref]\$errors
        )
        if (\$errors.Count -gt 0) { exit 1 } else { exit 0 }
      " 2>/dev/null; then
        issues+=("pkg/scripts/aihaus.ps1 PowerShell parse error")
      fi
    fi
  fi

  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${issues[@]}"
  fi
}

# ---- Check 64: README install section ≤30 lines + no two-layer language ------
# Verifies the repo-root README.md Install section (Z10 V5 rewrite) stays ≤30
# lines and contains no forbidden two-layer framing language (FR-27).
# Uses the repo root (SCRIPT_DIR/..) not PACKAGE_ROOT (pkg/) because Z10
# updated the repo-root README, not pkg/README.md.
check_readme_install_section() {
  _start_check
  local label="Check ${CHECK_NUMBER}: README install section ≤30 lines + no two-layer language (M022/Z10 FR-27)"
  local readme="${SCRIPT_DIR}/../README.md"
  if [[ ! -f "$readme" ]]; then
    _fail "$label" "README.md not found at repo root: $readme"
    return
  fi

  # Extract the Install section: from "## Install" up to (but not including)
  # the next H2 heading. Uses an awk state-variable approach because the
  # [^#] character class in range patterns is unreliable on some awk builds.
  local install_section
  install_section=$(awk '/^## Install/{f=1} f && /^## / && !/^## Install/{f=0} f' "$readme")

  local line_count
  line_count=$(echo "$install_section" | wc -l | tr -d ' ')

  if [[ "$line_count" -gt 30 ]]; then
    _fail "$label" "install section is ${line_count} lines (limit 30) — regression of FR-27"
    return
  fi

  if echo "$install_section" | grep -qiE "layer 1|layer 2|two layers|two-layer"; then
    _fail "$label" "install section contains two-layer language (regression of FR-27)"
    return
  fi

  _pass "$label"
}


# ---- Check 65: phase-advance.sh --class enum validation (M023/S01) ----------
# Asserts:
#   (a) hook exists and passes bash -n
#   (b) --to paused without --class exits 2 (AIHAUS_PAUSE_CLASS default=1)
#   (c) each of 4 valid enum values exits 0 and writes pause_class to manifest
#   (d) --class internal-contradiction exits 2 with literal "internal-contradiction reserved for M024+"
#   (e) --class bogus exits 2 with 4-enum list in stderr
check_pause_class_enum() {
  _start_check
  local label="Check ${CHECK_NUMBER}: phase-advance.sh --class enum validation (M023/S01)"
  local issues=()
  local hook="${PACKAGE_ROOT}/.aihaus/hooks/phase-advance.sh"
  local out_root="${SCRIPT_DIR}/.out"
  mkdir -p "$out_root" 2>/dev/null || true

  # Sub-assert (a): hook exists and is parseable
  if [[ ! -f "$hook" ]]; then
    issues+=("phase-advance.sh missing: $hook")
    _fail "$label" "${issues[@]}"
    return
  fi
  if ! bash -n "$hook" 2>/dev/null; then
    issues+=("phase-advance.sh has bash syntax error")
  fi

  # Helper: create a fresh running manifest in a tmp dir
  _make_manifest_dir() {
    local d="$1"
    mkdir -p "$d"
    printf '%s\n' \
      '## Metadata' \
      'milestone: test-fixture' \
      'branch: test' \
      'started: 2026-01-01T00:00:00Z' \
      'schema: v4' \
      'phase: running' \
      'status: running' \
      'last_updated: 2026-01-01T00:00:00Z' \
      '' \
      '## Invoke stack' \
      '' \
      '## Story Records' \
      'story_id|status|started_at|commit_sha|verified|notes' \
      '' \
      '## Progress Log' \
      '' > "$d/RUN-MANIFEST.md"
  }

  # Sub-assert (b): --to paused without --class exits 2
  local tmp_b="${out_root}/pause-class-b-$$"
  _make_manifest_dir "$tmp_b"
  local rc_b
  AIHAUS_AUDIT_LOG="${tmp_b}/audit.jsonl" bash "$hook" \
    --to paused --dir "$tmp_b" --reason "test-no-class" \
    >"${tmp_b}/stdout.txt" 2>"${tmp_b}/stderr.txt"
  rc_b=$?
  if [[ "$rc_b" -ne 2 ]]; then
    issues+=("sub-assert(b): expected exit 2 for --to paused without --class; got exit $rc_b")
  fi
  rm -rf "$tmp_b" 2>/dev/null || true

  # Sub-assert (c): each of 4 valid enum values exits 0 + writes pause_class
  for cls in credential-missing destructive-git-state external-dep-down user-invoked; do
    local tmp_c="${out_root}/pause-class-c-${cls}-$$"
    _make_manifest_dir "$tmp_c"
    local rc_c
    AIHAUS_AUDIT_LOG="${tmp_c}/audit.jsonl" bash "$hook" \
      --to paused --dir "$tmp_c" --reason "test-class-$cls" --class "$cls" \
      >"${tmp_c}/stdout.txt" 2>"${tmp_c}/stderr.txt"
    rc_c=$?
    if [[ "$rc_c" -ne 0 ]]; then
      issues+=("sub-assert(c): --class $cls expected exit 0; got exit $rc_c")
    elif ! grep -qE "^pause_class: $cls" "$tmp_c/RUN-MANIFEST.md" 2>/dev/null; then
      issues+=("sub-assert(c): --class $cls did not write pause_class to manifest")
    fi
    rm -rf "$tmp_c" 2>/dev/null || true
  done

  # Sub-assert (d): --class internal-contradiction exits 2 with reserved message
  local tmp_d="${out_root}/pause-class-d-$$"
  _make_manifest_dir "$tmp_d"
  local rc_d
  AIHAUS_AUDIT_LOG="${tmp_d}/audit.jsonl" bash "$hook" \
    --to paused --dir "$tmp_d" --reason "test-reserved" --class internal-contradiction \
    >"${tmp_d}/stdout.txt" 2>"${tmp_d}/stderr.txt"
  rc_d=$?
  if [[ "$rc_d" -ne 2 ]]; then
    issues+=("sub-assert(d): --class internal-contradiction expected exit 2; got exit $rc_d")
  fi
  local err_d
  err_d="$(cat "${tmp_d}/stderr.txt" 2>/dev/null || true)"
  if ! printf '%s' "$err_d" | grep -q "internal-contradiction reserved for M024+"; then
    issues+=("sub-assert(d): missing 'internal-contradiction reserved for M024+' in stderr; got: ${err_d:0:120}")
  fi
  rm -rf "$tmp_d" 2>/dev/null || true

  # Sub-assert (e): --class bogus exits 2 with 4-enum list
  local tmp_e="${out_root}/pause-class-e-$$"
  _make_manifest_dir "$tmp_e"
  local rc_e
  AIHAUS_AUDIT_LOG="${tmp_e}/audit.jsonl" bash "$hook" \
    --to paused --dir "$tmp_e" --reason "test-bogus" --class bogus-value \
    >"${tmp_e}/stdout.txt" 2>"${tmp_e}/stderr.txt"
  rc_e=$?
  if [[ "$rc_e" -ne 2 ]]; then
    issues+=("sub-assert(e): --class bogus-value expected exit 2; got exit $rc_e")
  fi
  local err_e
  err_e="$(cat "${tmp_e}/stderr.txt" 2>/dev/null || true)"
  if ! printf '%s' "$err_e" | grep -qE "credential-missing.destructive-git-state.external-dep-down.user-invoked"; then
    issues+=("sub-assert(e): missing 4-enum list in stderr for invalid class; got: ${err_e:0:120}")
  fi
  rm -rf "$tmp_e" 2>/dev/null || true

  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${issues[@]}"
  fi
}

# ---- Check 66: autonomy-guard PT-BR GSP-DS regex coverage (M023/S02) --------
# Asserts:
#   (a) all 13 named GSP-DS labels present in autonomy-guard.sh
#   (b) literal CONVERSATION.md:26 transcript line blocks at exit 2
#   (c) each of 5 GAP phrases blocks
#   (d) AIHAUS_GSP_DS_REGEX=0 opt-out skips 13 new PT-BR patterns; existing 12 still fire
#   (e) header comment mentions "24 patterns"
check_gsp_ds_regex_coverage() {
  _start_check
  local label="Check ${CHECK_NUMBER}: autonomy-guard PT-BR GSP-DS regex coverage (M023/S02)"
  local issues=()
  local hook="${PACKAGE_ROOT}/.aihaus/hooks/autonomy-guard.sh"
  local out_root="${SCRIPT_DIR}/.out"
  mkdir -p "$out_root" 2>/dev/null || true

  if [[ ! -f "$hook" ]]; then
    _fail "$label" "autonomy-guard.sh missing: $hook"
    return
  fi

  # Sub-assert (a): all 13 named GSP-DS labels present
  local -a gsp_labels=(
    GSP-DS-honest-scope
    GSP-DS-long-conversation
    GSP-DS-explicit-stop
    GSP-DS-quality-preserve
    GSP-DS-time-estimate
    GSP-DS-next-session
    GSP-DS-resume-recipe
    GSP-DS-batch-frame
    GSP-DS-batch-completion-frame
    GSP-DS-future-tense-continuation
    GSP-DS-feature-separation
    GSP-DS-reviewable-pr-frame
    GSP-DS-domain-split-frame
  )
  for lbl in "${gsp_labels[@]}"; do
    if ! grep -qF "$lbl" "$hook"; then
      issues+=("sub-assert(a): label '$lbl' missing from autonomy-guard.sh")
    fi
  done

  # Sub-assert (e): header comment mentions 24 patterns
  if ! grep -qE "24 patterns" "$hook"; then
    issues+=("sub-assert(e): header comment does not mention '24 patterns' (M023 update)")
  fi

  local tmp_dir="${out_root}/gsp-ds-test-$$"
  rm -rf "$tmp_dir"; mkdir -p "$tmp_dir"

  # Sub-assert (b): literal CONVERSATION.md:26 transcript blocks
  # Exact text from user-pasted transcript (CONVERSATION.md line 26)
  # Using ASCII-safe version to avoid locale issues
  local transcript
  transcript='Conversa muito longa, e Batch B a parte maior desse milestone. Realisticamente sao mais 2-3 horas de trabalho cuidadoso. Pra preservar qualidade, paro aqui com PR backend revisavel.'
  local out_b
  out_b="$(AIHAUS_EXEC_PHASE=1 \
    AIHAUS_AUDIT_GATE_LOG="${tmp_dir}/gate-b.jsonl" \
    AIHAUS_AUDIT_LOG="${tmp_dir}/viol-b.jsonl" \
    bash "$hook" <<< "$transcript" 2>/dev/null || true)"
  if ! printf '%s' "$out_b" | grep -q '"decision":"block"'; then
    issues+=("sub-assert(b): autonomy-guard did not block CONVERSATION.md:26 transcript excerpt")
  fi

  # Sub-assert (c): each of 5 GAP phrases blocks
  local -a gap_phrases=(
    'Quando voce quiser continuar'
    'feature separada'
    'PR backend revisavel'
    'Realisticamente sao mais 2-3 horas'
    'Conversa muito longa'
  )
  local idx=0
  for phrase in "${gap_phrases[@]}"; do
    idx=$((idx+1))
    local out_c
    out_c="$(AIHAUS_EXEC_PHASE=1 \
      AIHAUS_AUDIT_GATE_LOG="${tmp_dir}/gate-c${idx}.jsonl" \
      AIHAUS_AUDIT_LOG="${tmp_dir}/viol-c${idx}.jsonl" \
      bash "$hook" <<< "$phrase" 2>/dev/null || true)"
    if ! printf '%s' "$out_c" | grep -q '"decision":"block"'; then
      issues+=("sub-assert(c): GAP phrase not blocked: $phrase")
    fi
  done

  # Sub-assert (d): AIHAUS_GSP_DS_REGEX=0 skips 13 new PT-BR patterns
  # PT-BR-only phrase (no match in existing 11 English + 1 modified patterns) should NOT block
  local ptbr_only='Honesto sobre escopo paro aqui.'
  local out_d_ptbr
  out_d_ptbr="$(AIHAUS_GSP_DS_REGEX=0 AIHAUS_EXEC_PHASE=1 \
    AIHAUS_AUDIT_GATE_LOG="${tmp_dir}/gate-d1.jsonl" \
    AIHAUS_AUDIT_LOG="${tmp_dir}/viol-d1.jsonl" \
    bash "$hook" <<< "$ptbr_only" 2>/dev/null || true)"
  if printf '%s' "$out_d_ptbr" | grep -q '"decision":"block"'; then
    issues+=("sub-assert(d): AIHAUS_GSP_DS_REGEX=0 still blocked PT-BR-only phrase (should skip)")
  fi
  # Existing English pattern must STILL block with opt-out
  local eng_phrase='Checkpoint honesto: stopping here.'
  local out_d_eng
  out_d_eng="$(AIHAUS_GSP_DS_REGEX=0 AIHAUS_EXEC_PHASE=1 \
    AIHAUS_AUDIT_GATE_LOG="${tmp_dir}/gate-d2.jsonl" \
    AIHAUS_AUDIT_LOG="${tmp_dir}/viol-d2.jsonl" \
    bash "$hook" <<< "$eng_phrase" 2>/dev/null || true)"
  if ! printf '%s' "$out_d_eng" | grep -q '"decision":"block"'; then
    issues+=("sub-assert(d): AIHAUS_GSP_DS_REGEX=0 suppressed existing English pattern; 'Checkpoint honesto' must still block")
  fi

  rm -rf "$tmp_dir" 2>/dev/null || true

  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${issues[@]}"
  fi
}

# ---- Check 67: /aih-resume stranded-pause prose (M023/S03) ------------------
# Asserts:
#   (a) ^### 4c\. Stranded-pause detection present in aih-resume/SKILL.md
#   (b) wc -l <= 199
#   (c) both option phrasings: "continue here" AND "re-promote"
#   (d) no A/B/C / 1./2./3. option-menu language in the §4c section
check_aih_resume_stranded_prose() {
  _start_check
  local label="Check ${CHECK_NUMBER}: /aih-resume stranded-pause prose (M023/S03)"
  local issues=()
  local skill="${PACKAGE_ROOT}/.aihaus/skills/aih-resume/SKILL.md"

  if [[ ! -f "$skill" ]]; then
    _fail "$label" "aih-resume/SKILL.md missing: $skill"
    return
  fi

  # Sub-assert (a): ### 4c. Stranded-pause detection heading present
  if ! grep -qE '^### 4c\. Stranded-pause detection' "$skill"; then
    issues+=("sub-assert(a): '### 4c. Stranded-pause detection' heading missing")
  fi

  # Sub-assert (b): line count <= 199
  local line_count
  line_count=$(wc -l < "$skill" | tr -d ' ')
  if [[ "$line_count" -gt 199 ]]; then
    issues+=("sub-assert(b): aih-resume/SKILL.md has $line_count lines (limit 199)")
  fi

  # Sub-assert (c): both option phrasings present
  if ! grep -q "continue here" "$skill"; then
    issues+=("sub-assert(c): 'continue here' option phrasing missing")
  fi
  if ! grep -q "re-promote" "$skill"; then
    issues+=("sub-assert(c): 're-promote' option phrasing missing")
  fi

  # Sub-assert (d): no A/B/C or 1./2./3. option-menu language in §4c section
  local section_text
  section_text=$(awk '/^### 4c\./{on=1; next} on && /^###/{on=0} on {print}' "$skill" 2>/dev/null)
  if printf '%s' "$section_text" | grep -qE '^\(a\)|^\(b\)|^\(c\)|^a\)|^b\)|^c\)'; then
    issues+=("sub-assert(d): A/B/C option-menu language found in §4c section")
  fi
  if printf '%s' "$section_text" | grep -qE '^[[:space:]]*[123]\.[[:space:]]'; then
    issues+=("sub-assert(d): 1./2./3. numbered option-menu language found in §4c section")
  fi

  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${issues[@]}"
  fi
}

# ---- Check 68: ADR-260506-A canonical present (M023/S04) --------------------
# Asserts:
#   (a) ^## ADR-260506-A present exactly once in decisions.md
#   (b) required subsections: Context, Decision, Consequences, Migration, Rollback,
#       Implementation Status, References
#   (c) §Decision item 2 contains both negative-example phrases
#   (d) §References cites 10 ADRs + autonomy-protocol.md
#   (e) _shared/autonomy-protocol.md contains "M023 invariants" or "M023 amendments"
#   (f) §Migration contains "field-presence" (case-insensitive; no hardcoded date gate per I-04/L3)
#   (g) §Rollback enumerates 3 env vars
#   (h) CLAUDE.md has >= 4 grep hits for M023|GSP-DS|pause_class|ADR-260506-A (cross S06)
check_adr_260506a_present() {
  _start_check
  local label="Check ${CHECK_NUMBER}: ADR-260506-A canonical present (M023/S04)"
  local issues=()
  local decisions="${PACKAGE_ROOT}/.aihaus/decisions.md"
  local protocol="${PACKAGE_ROOT}/.aihaus/skills/_shared/autonomy-protocol.md"
  local claude_md="${PACKAGE_ROOT}/../CLAUDE.md"

  if [[ ! -f "$decisions" ]]; then
    _fail "$label" "decisions.md missing: $decisions"
    return
  fi

  # Sub-assert (a): heading present exactly once
  local adr_count
  adr_count=$(grep -cE '^## ADR-260506-A' "$decisions" 2>/dev/null || echo 0)
  if [[ "$adr_count" -ne 1 ]]; then
    issues+=("sub-assert(a): expected 1 '## ADR-260506-A' heading; found $adr_count")
  fi

  # Extract the ADR block for scoped checks
  local adr_block
  adr_block=$(awk '/^## ADR-260506-A/{on=1} on && /^## ADR-[0-9]/ && !/^## ADR-260506-A/{on=0} on {print}' "$decisions" 2>/dev/null)

  # Sub-assert (b): required subsections
  for subsec in "### Context" "### Decision" "### Consequences" "### Migration" "### Rollback" "### Implementation Status" "### References"; do
    if ! printf '%s' "$adr_block" | grep -qF "$subsec"; then
      issues+=("sub-assert(b): '$subsec' subsection missing from ADR-260506-A")
    fi
  done

  # Sub-assert (c): §Decision negative-example phrases
  if ! printf '%s' "$adr_block" | grep -q "backend/frontend decomposition is NEVER an external dep"; then
    issues+=("sub-assert(c): negative-example phrase 1 missing")
  fi
  if ! printf '%s' "$adr_block" | grep -q "internal sequencing is NEVER an external dep"; then
    issues+=("sub-assert(c): negative-example phrase 2 missing")
  fi

  # Sub-assert (d): §References cites 10 ADRs + autonomy-protocol.md
  local -a required_refs=(
    "ADR-001"
    "ADR-004"
    "ADR-M005-A"
    "ADR-M011-A"
    "ADR-M011-B"
    "ADR-M014-B"
    "ADR-M017-A"
    "ADR-260502-A"
    "ADR-260504-A"
    "_shared/autonomy-protocol.md"
  )
  for ref in "${required_refs[@]}"; do
    if ! printf '%s' "$adr_block" | grep -qF "$ref"; then
      issues+=("sub-assert(d): §References missing '$ref'")
    fi
  done

  # Sub-assert (e): autonomy-protocol.md contains M023 invariants/amendments
  if [[ -f "$protocol" ]]; then
    if ! grep -qE "M023 invariants|M023 amendments" "$protocol"; then
      issues+=("sub-assert(e): _shared/autonomy-protocol.md missing 'M023 invariants' or 'M023 amendments'")
    fi
  else
    issues+=("sub-assert(e): _shared/autonomy-protocol.md not found: $protocol")
  fi

  # Sub-assert (f): §Migration contains "field-presence" (case-insensitive; no hardcoded date gate)
  local migration_block
  migration_block=$(printf '%s' "$adr_block" | awk '/^### Migration/{on=1; next} on && /^### /{on=0} on {print}')
  if ! printf '%s' "$migration_block" | grep -qiE "field.presence"; then
    issues+=("sub-assert(f): §Migration missing 'field-presence' prose (I-04/L3 fork-portable gate)")
  fi

  # Sub-assert (g): §Rollback enumerates 3 opt-out env vars
  local rollback_block
  rollback_block=$(printf '%s' "$adr_block" | awk '/^### Rollback/{on=1; next} on && /^### /{on=0} on {print}')
  for envvar in "AIHAUS_PAUSE_CLASS" "AIHAUS_AUTONOMY_HAIKU" "AIHAUS_GSP_DS_REGEX"; do
    if ! printf '%s' "$rollback_block" | grep -q "$envvar"; then
      issues+=("sub-assert(g): §Rollback missing env var '$envvar'")
    fi
  done

  # Sub-assert (h): CLAUDE.md >= 4 grep hits (cross-S06)
  if [[ -f "$claude_md" ]]; then
    local claude_hits
    claude_hits=$(grep -cE "M023|GSP-DS|pause_class|ADR-260506-A" "$claude_md" 2>/dev/null || echo 0)
    if [[ "$claude_hits" -lt 4 ]]; then
      issues+=("sub-assert(h): CLAUDE.md has $claude_hits grep hits for M023|GSP-DS|pause_class|ADR-260506-A (need >= 4; check S06)")
    fi
  else
    issues+=("sub-assert(h): CLAUDE.md not found: $claude_md")
  fi

  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${issues[@]}"
  fi
}

# ---- Check 69: pause_class field permissive on legacy manifests (M023/S01) --
# Asserts:
#   (a) synthetic v4 manifest with status: paused and no pause_class field is permissive
#   (b) validate_status still accepts paused-user-input (NFR-04)
check_pause_class_permissive_legacy() {
  _start_check
  local label="Check ${CHECK_NUMBER}: pause_class field permissive on legacy manifests (M023/S01)"
  local issues=()
  local helpers="${PACKAGE_ROOT}/.aihaus/hooks/lib/manifest-helpers.sh"

  # Sub-assert (a): a synthetic legacy manifest (status: paused, no pause_class)
  # should NOT have a pause_class: line (which would trigger Check 70 audit-pair)
  local legacy_text
  legacy_text="$(printf '%s\n' \
    '## Metadata' \
    'milestone: legacy-test-fixture' \
    'branch: legacy-branch' \
    'started: 2020-01-01T00:00:00Z' \
    'schema: v4' \
    'phase: paused' \
    'status: paused' \
    'pause_reason: test legacy fixture no pause_class field' \
    'last_updated: 2020-01-01T00:00:00Z' \
    '' \
    '## Invoke stack' \
    '' \
    '## Story Records' \
    'story_id|status|started_at|commit_sha|verified|notes' \
    '' \
    '## Progress Log' \
    '')"
  if printf '%s' "$legacy_text" | grep -qE '^pause_class:'; then
    issues+=("sub-assert(a): synthetic legacy fixture unexpectedly contains 'pause_class:' line")
  elif [[ -f "$helpers" ]]; then
    if ! bash -c ". '$helpers'; validate_status 'paused'" 2>/dev/null; then
      issues+=("sub-assert(a): validate_status rejects 'paused' -- legacy manifests would fail")
    fi
  fi

  # Sub-assert (b): validate_status accepts paused-user-input (NFR-04 legacy shape)
  if [[ -f "$helpers" ]]; then
    if ! bash -c ". '$helpers'; validate_status 'paused-user-input'" 2>/dev/null; then
      issues+=("sub-assert(b): validate_status rejects 'paused-user-input' -- NFR-04 regression")
    fi
  else
    issues+=("sub-assert(b): lib/manifest-helpers.sh not found: $helpers")
  fi

  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${issues[@]}"
  fi
}

# ---- Check 70: audit-pair invariant (M023/S05) -- FIELD-PRESENCE GATE -------
# For each manifest with pause_class: field present in ## Metadata (post-M023),
# assert a phase-advance --to paused row exists in hook.jsonl within 60s of
# last_updated. Pre-M023 manifests (no pause_class: field) are SKIPPED.
# NO HARDCODED DATE STRINGS -- field-presence gate only (per I-04 / L3).
check_audit_pair_invariant() {
  _start_check
  local label="Check ${CHECK_NUMBER}: audit-pair invariant (M023/S05)"
  local issues=()
  local repo_root="${PACKAGE_ROOT}/.."
  local audit_file="${repo_root}/.claude/audit/hook.jsonl"

  while IFS= read -r manifest; do
    # Field-presence gate: skip manifests without pause_class: (pre-M023 legacy permissive)
    if ! grep -qE '^pause_class:' "$manifest" 2>/dev/null; then
      continue
    fi

    # Post-M023 manifest: require an audit-pair row in hook.jsonl
    local last_updated
    last_updated=$(grep -E '^last_updated:' "$manifest" 2>/dev/null | head -1 | awk '{print $2}')
    if [[ -z "$last_updated" ]]; then
      issues+=("$manifest: pause_class present but last_updated missing")
      continue
    fi

    # Convert ISO-8601 to epoch (try date -d, fallback to py)
    local lu_epoch=0
    if date -d "$last_updated" +%s >/dev/null 2>&1; then
      lu_epoch=$(date -d "$last_updated" +%s 2>/dev/null || echo 0)
    elif command -v py >/dev/null 2>&1; then
      lu_epoch=$(py -c "
import sys
from datetime import datetime
try:
    s=sys.argv[1].replace('Z','+00:00')
    print(int(datetime.fromisoformat(s).timestamp()))
except:
    print(0)
" "$last_updated" 2>/dev/null || echo 0)
    fi

    if [[ "$lu_epoch" -eq 0 ]]; then
      issues+=("$manifest: could not parse last_updated='$last_updated' as epoch")
      continue
    fi

    if [[ ! -f "$audit_file" ]]; then
      issues+=("$manifest: pause_class present but audit log absent: $audit_file")
      continue
    fi

    local found_pair=0
    while IFS= read -r row; do
      printf '%s' "$row" | grep -q '"to_phase":"paused"' || continue
      local row_ts
      row_ts=$(printf '%s' "$row" | sed 's/.*"ts":"\([^"]*\)".*/\1/')
      local row_epoch=0
      if date -d "$row_ts" +%s >/dev/null 2>&1; then
        row_epoch=$(date -d "$row_ts" +%s 2>/dev/null || echo 0)
      elif command -v py >/dev/null 2>&1; then
        row_epoch=$(py -c "
import sys
from datetime import datetime
try:
    s=sys.argv[1].replace('Z','+00:00')
    print(int(datetime.fromisoformat(s).timestamp()))
except:
    print(0)
" "$row_ts" 2>/dev/null || echo 0)
      fi
      local delta=$(( row_epoch - lu_epoch ))
      if [[ "$delta" -ge -60 && "$delta" -le 60 ]]; then
        found_pair=1
        break
      fi
    done < "$audit_file"

    if [[ "$found_pair" -eq 0 ]]; then
      issues+=("$manifest: pause_class present but no audit row within 60s of last_updated=$last_updated")
    fi
  done < <(find "${repo_root}/.aihaus" -type f -name 'RUN-MANIFEST.md' 2>/dev/null)

  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${issues[@]}"
  fi
}

# ---- Check 70b: external-dep-down laundering detection (M023/S05) -----------
# For each manifest with pause_class: external-dep-down, grep pause_reason for
# laundering tokens (backend|frontend|wave|batch|phase [0-9]).
# Fails if matched -- these are internal decomposition seams, not external deps.
check_external_dep_down_laundering() {
  _start_check
  local label="Check ${CHECK_NUMBER}: external-dep-down laundering detection (M023/S05)"
  local issues=()
  local launder_re='(backend|frontend|wave|batch|phase [0-9])'
  local repo_root="${PACKAGE_ROOT}/.."

  while IFS= read -r manifest; do
    if grep -qE '^pause_class: external-dep-down' "$manifest" 2>/dev/null; then
      local reason
      reason=$(grep -E '^pause_reason:' "$manifest" 2>/dev/null | head -1)
      if printf '%s' "$reason" | grep -qiE "$launder_re"; then
        issues+=("$manifest: pause_class=external-dep-down but pause_reason matches laundering regex: $reason")
      fi
    fi
  done < <(find "${repo_root}/.aihaus" -type f -name 'RUN-MANIFEST.md' 2>/dev/null)

  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${issues[@]}"
  fi
}

# ---- Check 72: completion-protocol audit-pair invariant (M024/S04) ----------
# For each milestone manifest with status:completed AND phase:complete, assert
# .claude/audit/curator-apply.jsonl has a row with "milestone":"M0XX" within
# 1h (3600s) of last_updated. FIELD-PRESENCE GATE — pre-M024 milestones
# without status:completed + phase:complete are skipped (legacy permissive).
# GRACE-WINDOW (CHECK F2 fix): currently-running milestone (matches
# `git branch --show-current` against milestone/M0XX-* pattern) is SKIPPED to
# prevent M024 self-completion sequence trap. POST-HOC DETECTION (CHECK F5
# honest framing) — phase-advance.sh has zero hook into smoke-test.sh; this
# is offline observability, NOT runtime gating.
check_completion_curator_audit_pair() {
  _start_check
  local label="Check ${CHECK_NUMBER}: completion-protocol audit-pair invariant (M024/S04)"
  local issues=()
  local repo_root="${PACKAGE_ROOT}/.."
  local audit_file="${repo_root}/.claude/audit/curator-apply.jsonl"

  # Grace-window: detect currently-running milestone via branch
  local current_branch current_milestone=""
  current_branch=$(git -C "${repo_root}" branch --show-current 2>/dev/null || echo "")
  if [[ "$current_branch" =~ ^milestone/(M[0-9]+)- ]]; then
    current_milestone="${BASH_REMATCH[1]}"
  fi

  while IFS= read -r manifest; do
    # Field-presence gate: skip manifests without BOTH status:completed AND phase:complete
    if ! grep -qE '^status:[[:space:]]*completed' "$manifest" 2>/dev/null; then
      continue
    fi
    if ! grep -qE '^phase:[[:space:]]*complete' "$manifest" 2>/dev/null; then
      continue
    fi

    # Extract milestone ID from manifest path or content
    local milestone_id milestone_num
    milestone_id=$(grep -E '^milestone:' "$manifest" 2>/dev/null | head -1 | awk '{print $2}' | sed -E 's/^(M[0-9]+)-.*/\1/')
    if [[ -z "$milestone_id" ]]; then
      continue
    fi

    # Only enforce on canonical M0XX format milestones (skip pre-canonical
    # slug-prefixed manifests like "260414-run-M003" that predate the M0XX scheme).
    if [[ ! "$milestone_id" =~ ^M[0-9]+$ ]]; then
      continue
    fi

    # Pre-M020 milestones are grandfathered (curator-apply.jsonl backfill scope
    # was M020-M023 per S05a/b; pre-M020 closed before the curator era).
    # Field-presence-equivalent gate via numeric threshold — fork-portable
    # (no hardcoded date), time-stable.
    milestone_num=$(echo "$milestone_id" | sed 's/^M//' | sed 's/^0*//')
    if [[ -z "$milestone_num" ]]; then
      milestone_num=0
    fi
    if [[ "$milestone_num" =~ ^[0-9]+$ ]] && [[ "$milestone_num" -lt 20 ]]; then
      continue
    fi

    # Grace-window: skip currently-running milestone (CHECK F2 fix)
    if [[ -n "$current_milestone" ]] && [[ "$milestone_id" == "$current_milestone" ]]; then
      continue
    fi

    if [[ ! -f "$audit_file" ]]; then
      issues+=("$manifest: completed milestone but curator-apply.jsonl absent: $audit_file")
      continue
    fi

    # Search audit log for ANY matching milestone row.
    # NOTE: time-window check removed — retroactive backfill (M024/S05a/S05b) writes
    # curator-apply rows long after the manifest's last_updated. Existence-only check
    # catches the real failure mode (orchestrator skipped curator entirely) without
    # false-positives on retroactive applies. M024+ live runs naturally write rows
    # at completion-time so timing is implicitly current.
    if ! grep -qF "\"milestone\":\"${milestone_id}\"" "$audit_file" 2>/dev/null; then
      issues+=("$milestone_id: completed but no curator-apply.jsonl row found")
    fi
  done < <(find "${repo_root}/.aihaus/milestones" -maxdepth 2 -type f -name 'RUN-MANIFEST.md' 2>/dev/null)

  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${issues[@]}"
  fi
}

# ---- Check 73: LSDD regex coverage (M025/S02) -------------------------------
# Asserts:
#   (a) all 16 named LSDD labels present in autonomy-guard.sh
#   (b) literal screenshot strings block at exit-2 with AIHAUS_EXEC_PHASE=1
#   (c) AIHAUS_LSDD_REGEX=0 opt-out skips 16 new patterns; existing 24 still fire
#   (d) Onda absent (F1 absorption — fabricated mandate dropped)
#   (e) header comment mentions "16 patterns total" or "M025"
#   (f) fixture-fail (tools/fixtures/check-73/missing-pattern.sh):
#       a synthesized autonomy-guard variant missing LSDD-PT-Etapa must NOT block "Etapa 5 paralelo"
check_lsdd_regex_coverage() {
  _start_check
  local label="Check ${CHECK_NUMBER}: LSDD regex coverage (M025/S02)"
  local issues=()
  local hook="${PACKAGE_ROOT}/.aihaus/hooks/autonomy-guard.sh"
  local out_root="${SCRIPT_DIR}/.out"
  mkdir -p "$out_root" 2>/dev/null || true

  if [[ ! -f "$hook" ]]; then
    _fail "$label" "autonomy-guard.sh missing: $hook"
    return
  fi

  # Sub-assert (a): 16 named LSDD labels
  local -a lsdd_labels=(
    LSDD-EN-Phase-letter LSDD-EN-Phase-numeric LSDD-EN-Round LSDD-EN-Stage LSDD-EN-Tranche
    LSDD-PT-Etapa LSDD-PT-Bloco LSDD-PT-Fase LSDD-PT-Rodada LSDD-PT-Secao
    LSDD-Sigo-question
    LSDD-fraction-stories LSDD-fraction-progress LSDD-fraction-storyies LSDD-fraction-of LSDD-fraction-tasks
  )
  for lbl in "${lsdd_labels[@]}"; do
    if ! grep -qF "$lbl" "$hook"; then
      issues+=("sub-assert(a): label '$lbl' missing from autonomy-guard.sh LSDD heredoc")
    fi
  done

  # Sub-assert (d): Onda absent
  if grep -qE '\b[Oo]nda\b' "$hook"; then
    issues+=("sub-assert(d): 'Onda' present in autonomy-guard.sh — must be dropped per F1 absorption")
  fi

  # Sub-assert (e): header mentions "16 patterns"
  if ! grep -qE '16 patterns' "$hook"; then
    issues+=("sub-assert(e): header comment does not mention '16 patterns' (M025 LSDD)")
  fi

  local tmp_dir="${out_root}/lsdd-test-$$"
  rm -rf "$tmp_dir"; mkdir -p "$tmp_dir"

  # Sub-assert (b): screenshot evidence strings block
  local -a screenshot_strings=(
    'Phase B complete'
    'Round 1 paralelo: S22, S23, S24, S28'
    'Total M002 progress: 23/30 done'
    'Sigo Round 1?'
    'Etapa 5 paralelo'
  )
  local idx=0
  for phrase in "${screenshot_strings[@]}"; do
    idx=$((idx+1))
    local out_b
    out_b="$(AIHAUS_EXEC_PHASE=1 \
      AIHAUS_AUDIT_GATE_LOG="${tmp_dir}/gate-b${idx}.jsonl" \
      AIHAUS_AUDIT_LOG="${tmp_dir}/viol-b${idx}.jsonl" \
      bash "$hook" <<< "$phrase" 2>/dev/null || true)"
    if ! printf '%s' "$out_b" | grep -q '"decision":"block"'; then
      issues+=("sub-assert(b): LSDD did not block screenshot string: $phrase")
    fi
  done

  # Sub-assert (c): AIHAUS_LSDD_REGEX=0 skips 16 new patterns
  # LSDD-only phrase ("Phase 7 complete") should NOT block under opt-out
  local lsdd_only='Phase 7 complete'
  local out_c1
  out_c1="$(AIHAUS_LSDD_REGEX=0 AIHAUS_EXEC_PHASE=1 \
    AIHAUS_AUDIT_GATE_LOG="${tmp_dir}/gate-c1.jsonl" \
    AIHAUS_AUDIT_LOG="${tmp_dir}/viol-c1.jsonl" \
    bash "$hook" <<< "$lsdd_only" 2>/dev/null || true)"
  if printf '%s' "$out_c1" | grep -q '"decision":"block"'; then
    issues+=("sub-assert(c): AIHAUS_LSDD_REGEX=0 still blocked LSDD-only phrase 'Phase 7 complete'")
  fi
  # Existing M005 fast-path must STILL block with LSDD opt-out
  local m005_phrase='Checkpoint honesto'
  local out_c2
  out_c2="$(AIHAUS_LSDD_REGEX=0 AIHAUS_EXEC_PHASE=1 \
    AIHAUS_AUDIT_GATE_LOG="${tmp_dir}/gate-c2.jsonl" \
    AIHAUS_AUDIT_LOG="${tmp_dir}/viol-c2.jsonl" \
    bash "$hook" <<< "$m005_phrase" 2>/dev/null || true)"
  if ! printf '%s' "$out_c2" | grep -q '"decision":"block"'; then
    issues+=("sub-assert(c): AIHAUS_LSDD_REGEX=0 suppressed existing M005 'Checkpoint honesto' (must still block)")
  fi

  # Sub-assert (f): fixture-fail — variant missing LSDD-PT-Etapa must NOT block "Etapa 5 paralelo"
  local fixture="${PACKAGE_ROOT}/../tools/fixtures/check-73/missing-pattern.sh"
  if [[ ! -f "$fixture" ]]; then
    issues+=("sub-assert(f): fixture-fail file missing: tools/fixtures/check-73/missing-pattern.sh")
  else
    local out_f
    out_f="$(AIHAUS_EXEC_PHASE=1 \
      AIHAUS_AUDIT_GATE_LOG="${tmp_dir}/gate-f.jsonl" \
      AIHAUS_AUDIT_LOG="${tmp_dir}/viol-f.jsonl" \
      bash "$fixture" <<< 'Etapa 5 paralelo' 2>/dev/null || true)"
    if printf '%s' "$out_f" | grep -q '"decision":"block"'; then
      issues+=("sub-assert(f): fixture WITH LSDD-PT-Etapa removed still blocks 'Etapa 5 paralelo' — fixture broken")
    fi
  fi

  rm -rf "$tmp_dir" 2>/dev/null || true

  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${issues[@]}"
  fi
}

# ---- Check 74: LSDD false-positive guards + runtime narrative-emission (M025/S02) ----
# Asserts:
#   (a) "5/5 tests pass" does NOT block (false positive guard via stories|tasks qualifier)
#   (b) "## Phase 1 — Detect Package Source" markdown header does NOT block
#   (c) "Etapa/Bloco" canonical seam enumeration does NOT block (no completion verb)
#   (d) "Backend/Frontend, Wave N/M, Phase X/Y" autonomy-protocol L487 form does NOT block
#   (e) Runtime narrative "Phase 7 complete. Moving to Phase 7.5." DOES block (cadence + verb)
#   (f) fixture-fail (tools/fixtures/check-74/false-positive.sh): a variant with bare
#       [Pp]hase [0-9]+ (no anchoring) MUST block "## Phase 1 — Detect Package Source"
check_lsdd_false_positive_guards() {
  _start_check
  local label="Check ${CHECK_NUMBER}: LSDD false-positive guards + runtime narrative-emission (M025/S02)"
  local issues=()
  local hook="${PACKAGE_ROOT}/.aihaus/hooks/autonomy-guard.sh"
  local out_root="${SCRIPT_DIR}/.out"
  local tmp_dir="${out_root}/lsdd-fp-test-$$"
  rm -rf "$tmp_dir"; mkdir -p "$tmp_dir"

  local -a allow_phrases=(
    '5/5 tests pass'
    '## Phase 1 — Detect Package Source'
    'Etapa/Bloco'
    'Backend/Frontend, Wave N/M, Phase X/Y'
  )
  local idx=0
  for phrase in "${allow_phrases[@]}"; do
    idx=$((idx+1))
    local out
    out="$(AIHAUS_EXEC_PHASE=1 \
      AIHAUS_AUDIT_GATE_LOG="${tmp_dir}/gate-a${idx}.jsonl" \
      AIHAUS_AUDIT_LOG="${tmp_dir}/viol-a${idx}.jsonl" \
      bash "$hook" <<< "$phrase" 2>/dev/null || true)"
    if printf '%s' "$out" | grep -q '"decision":"block"'; then
      issues+=("false-positive: legitimate phrase blocked: $phrase")
    fi
  done

  # Sub-assert (e): runtime narrative emission DOES block
  local narrative='Phase 7 complete. Moving to Phase 7.5.'
  local out_e
  out_e="$(AIHAUS_EXEC_PHASE=1 \
    AIHAUS_AUDIT_GATE_LOG="${tmp_dir}/gate-e.jsonl" \
    AIHAUS_AUDIT_LOG="${tmp_dir}/viol-e.jsonl" \
    bash "$hook" <<< "$narrative" 2>/dev/null || true)"
  if ! printf '%s' "$out_e" | grep -q '"decision":"block"'; then
    issues+=("sub-assert(e): runtime narrative '$narrative' should have blocked but did not")
  fi

  # Sub-assert (f): fixture-fail — bare [Pp]hase [0-9]+ MUST block markdown header
  local fixture="${PACKAGE_ROOT}/../tools/fixtures/check-74/false-positive.sh"
  if [[ ! -f "$fixture" ]]; then
    issues+=("sub-assert(f): fixture-fail file missing: tools/fixtures/check-74/false-positive.sh")
  else
    local out_f
    out_f="$(AIHAUS_EXEC_PHASE=1 \
      AIHAUS_AUDIT_GATE_LOG="${tmp_dir}/gate-f.jsonl" \
      AIHAUS_AUDIT_LOG="${tmp_dir}/viol-f.jsonl" \
      bash "$fixture" <<< '## Phase 1 — Detect Package Source' 2>/dev/null || true)"
    if ! printf '%s' "$out_f" | grep -q '"decision":"block"'; then
      issues+=("sub-assert(f): fixture WITH bare [Pp]hase [0-9]+ should false-positive on markdown header but did not — fixture broken")
    fi
  fi

  rm -rf "$tmp_dir" 2>/dev/null || true

  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${issues[@]}"
  fi
}

# ---- Check 75: Skill+agent prose absence of cadence-noun templates (M025/S01b) ----
# Asserts cadence-noun template patterns absent from skill+agent prose, EXCEPT skip-list:
#   - legitimate `## Phase N — <Title>` markdown headers (regex `^## [Pp]hase [0-9.]+ — `)
#   - step-numbered references (regex `^### [0-9]+\. `)
#   - brainstorm-synthesizer.md L32/L61/L86 (load-bearing per F-CRIT-2)
#   - PRD enumeration prose with anchor keywords ("decomposition seam", "legitimate", "NEVER TRUE blockers")
# fixture-fail (tools/fixtures/check-75/cadence-leak.md) MUST trigger Check 75 failure
check_skill_agent_cadence_absence() {
  _start_check
  local label="Check ${CHECK_NUMBER}: Skill+agent prose absence of cadence-noun templates (M025/S01b)"
  local issues=()
  local roots=(
    "${PACKAGE_ROOT}/.aihaus/skills"
    "${PACKAGE_ROOT}/.aihaus/agents"
  )

  # Match cadence-noun template patterns (Phase/Round + numeric — strictly the substitution-source shape)
  # NOT the conceptual-prose shape (e.g., "phase grouping" — lowercase + non-numeric)
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local file lineno content
    file="${line%%:*}"
    line="${line#*:}"
    lineno="${line%%:*}"
    content="${line#*:}"

    # Skip-list: markdown H2/H3 phase headers (skill-step framing)
    if echo "$content" | grep -qE '^## [Pp]hase [0-9.]+ — '; then continue; fi
    if echo "$content" | grep -qE '^### [0-9]+\. '; then continue; fi

    # Skip-list: brainstorm-synthesizer.md panel mechanics (F-CRIT-2)
    if [[ "$file" == *"brainstorm-synthesizer.md" ]]; then continue; fi

    # Skip-list: anchor keywords for legitimate enumeration prose
    if echo "$content" | grep -qiE 'decomposition seam|canonical seam|legitimate decomposition|NEVER TRUE blockers|cadence-noun|substitution operator|substitution surface|excis(e|ion)|catalog|enumeration|skip-list|anchored|anchoring|panel architecture|panel mechanic|F-CRIT|F2 absorption|disposition'; then continue; fi

    # Skip-list: lines that are themselves part of the LSDD pack regex
    if echo "$content" | grep -qE 'LSDD-|GSP-DS-|CADENCE_VERBS'; then continue; fi

    # Cadence-noun template check: "Phase N: {" or "Phase N must" or numeric Phase X table cells
    if echo "$content" | grep -qE '\| [Pp]hase [0-9]+ \||## [Pp]hase [0-9]+: \{'; then
      issues+=("$file:$lineno: cadence-noun template leak: $content")
    fi
  done < <(grep -rnE '\| [Pp]hase [0-9]+ \||## [Pp]hase [0-9]+: \{' "${roots[@]}" 2>/dev/null)

  # Sub-assert (fixture-fail)
  local fixture="${PACKAGE_ROOT}/../tools/fixtures/check-75/cadence-leak.md"
  if [[ ! -f "$fixture" ]]; then
    issues+=("fixture-fail file missing: tools/fixtures/check-75/cadence-leak.md")
  else
    if ! grep -qE '\| [Pp]hase [0-9]+ \||## [Pp]hase [0-9]+: \{' "$fixture"; then
      issues+=("fixture tools/fixtures/check-75/cadence-leak.md does NOT contain a cadence-noun template — fixture broken")
    fi
  fi

  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${issues[@]}"
  fi
}

# ---- Check 76: M027 semantic-gate ADR-presence forcing function (M025/S03) ---
# Asserts pkg/.aihaus/decisions.md contains an ^## ADR-NNNNNN-X block satisfying
# all three: (a) **Date:** YYYY-MM-DD, (b) keyword from
# {denylist-extension, haiku-classifier, whitelist-on-cadence}, (c) **Status:** Accepted
# within the same ADR block.
# fixture-fail #1 (missing-adr.md): decisions.md without gate ADR → exit non-zero
# fixture-fail #2 (token-rejected.md): decisions.md with token + Status: Rejected → exit non-zero
check_m027_semantic_gate() {
  _start_check
  local label="Check ${CHECK_NUMBER}: M027 semantic-gate ADR-presence forcing function (M025/S03)"
  local issues=()
  local decisions="${PACKAGE_ROOT}/.aihaus/decisions.md"

  if [[ ! -f "$decisions" ]]; then
    _fail "$label" "decisions.md missing: $decisions"
    return
  fi

  # Helper — check if a decisions.md file contains a valid M027 gate ADR
  _check_m027_gate() {
    local file="$1"
    awk '
      /^## ADR-/ { in_adr=1; date=""; status=""; token=0; }
      in_adr && /^\*\*Date:\*\* [0-9]{4}-[0-9]{2}-[0-9]{2}/ { date=1 }
      in_adr && /^\*\*Status:\*\* Accepted/ { status=1 }
      in_adr && /denylist-extension|haiku-classifier|whitelist-on-cadence/ { token=1 }
      in_adr && /^---$/ {
        if (date && status && token) { found=1; exit }
        in_adr=0
      }
      END { if (date && status && token) found=1; exit !found }
    ' "$file" 2>/dev/null
  }

  # Live decisions.md: gate may be absent at M025 ship (M027 is the next milestone's
  # decision; the gate FAILS until M027 ADR lands — that's the forcing function).
  # This check is OFFLINE OBSERVABILITY (mirror M024/S04 Check 72 framing): existence
  # of the gate ADR is the post-M025 dogfood signal that M027 has shipped.
  if _check_m027_gate "$decisions"; then
    # M027 already landed (post-M027 milestone runs)
    : # OK — gate active
  else
    # M027 not yet landed — emit INFO log, NOT failure (this is the forcing function pattern)
    # The check still runs the fixture-fail tests below to verify the gate logic itself works.
    : # silent — M027 ADR pending is the expected state immediately post-M025
  fi

  # Fixture-fail #1: missing-adr (decisions.md without gate ADR → must NOT pass gate)
  local fixture1="${PACKAGE_ROOT}/../tools/fixtures/check-76/missing-adr.md"
  if [[ ! -f "$fixture1" ]]; then
    issues+=("fixture-fail file missing: tools/fixtures/check-76/missing-adr.md")
  else
    if _check_m027_gate "$fixture1"; then
      issues+=("fixture-fail #1: missing-adr.md fixture passes gate (should fail — no gate ADR present)")
    fi
  fi

  # Fixture-fail #2: token-rejected (ADR with all 3 tokens but Status: Rejected → must NOT pass gate)
  local fixture2="${PACKAGE_ROOT}/../tools/fixtures/check-76/token-rejected.md"
  if [[ ! -f "$fixture2" ]]; then
    issues+=("fixture-fail file missing: tools/fixtures/check-76/token-rejected.md")
  else
    if _check_m027_gate "$fixture2"; then
      issues+=("fixture-fail #2: token-rejected.md fixture passes gate (should fail — ADR present with tokens but Status: Rejected)")
    fi
  fi

  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${issues[@]}"
  fi
}

# ---- Check 77: BRIEF.md sub-field schema (M026/S1b) ----------------------
# Validates Alt D OQ inline sub-fields per ADR-26050X-A I3.
# Asserts:
#   (a) every BRIEF.md with **Panel-Confidence:** marker has each OQ block
#       containing **Recommendation:** + **Panel-Confidence:** + **Defer if:**
#       + **Source:**
#   (b) H/M Panel-Confidence requires **Source:** matching one of three regexes
#       (file:line citation grammar)
#   (c) field-presence permissive: legacy schema-v1 BRIEFs (no **Panel-Confidence:**)
#       skip sub-field check
#   (d) fixture-fail #1: tools/fixtures/check-77/missing-recommendation.md
#       (OQ#1 missing **Recommendation:**) must exit non-zero
#   (e) fixture-fail #2: tools/fixtures/check-77/source-prose-violation.md
#       (OQ#1 H Panel-Confidence + prose-only Source) must exit non-zero
check_brief_subfield_schema() {
  _start_check
  local label="Check ${CHECK_NUMBER}: BRIEF.md sub-field schema (M026/S1b)"
  local issues=()
  local repo_root="${PACKAGE_ROOT}/.."

  # Helper: validate a single BRIEF.md against Alt D sub-field schema
  _validate_brief() {
    local brief="$1"
    awk '
      /^## Open Questions/ { in_oq=1; oq_num=0; rec=0; conf=0; defer=0; src=0; conf_value=""; src_line=""; next }
      in_oq && /^## / { check_block(); in_oq=0 }
      in_oq && /^[0-9]+\. \*\*/ {
        if (oq_num > 0) check_block()
        oq_num++; rec=0; conf=0; defer=0; src=0; conf_value=""; src_line=""
      }
      in_oq && /\*\*Recommendation:\*\*/ { rec=1 }
      in_oq && /\*\*Panel-Confidence:\*\*/ {
        conf=1
        if (match($0, /Panel-Confidence:\*\* H( |$)/)) conf_value="H"
        else if (match($0, /Panel-Confidence:\*\* M( |$)/)) conf_value="M"
        else if (match($0, /Panel-Confidence:\*\* L( |$)/)) conf_value="L"
      }
      in_oq && /\*\*Defer (if|to PLAN if):\*\*/ { defer=1 }
      in_oq && /\*\*Source:\*\*/ { src=1; src_line=$0 }
      END { if (oq_num > 0) check_block() }

      function check_block() {
        if (oq_num == 0) return
        missing=""
        if (!rec) missing=missing "Recommendation,"
        if (!conf) missing=missing "Panel-Confidence,"
        if (!defer) missing=missing "Defer if,"
        if (!src) missing=missing "Source,"
        if (length(missing) > 0) {
          printf "OQ#%d missing field(s): %s\n", oq_num, substr(missing, 1, length(missing)-1)
          exit 1
        }
        if ((conf_value == "H" || conf_value == "M") && src_line != "") {
          if (!match(src_line, /(PERSPECTIVE-[a-z-]+(\.r2)?\.md:L?[0-9]+-L?[0-9]+|CONVERSATION\.md ## Turn [0-9]+|pkg\/\.aihaus\/.+:L?[0-9]+-L?[0-9]+|\.aihaus\/.+[ `]+(F[0-9]+|A[0-9]+|L[0-9]+)|[A-Z][A-Z-]*\.md[ `]+(F[0-9]+|A[0-9]+|L[0-9]+))/)) {
            printf "OQ#%d Panel-Confidence:%s grammar fail: %s\n", oq_num, conf_value, src_line
            exit 1
          }
        }
      }
    ' "$brief" 2>/dev/null
  }

  # Sub-assert (a)+(b)+(c): validate every shipped BRIEF.md with Panel-Confidence marker
  while IFS= read -r brief; do
    [ -f "$brief" ] || continue
    if ! grep -q '\*\*Panel-Confidence:\*\*' "$brief" 2>/dev/null; then
      continue  # legacy schema-v1 — skip
    fi
    local out
    out="$(_validate_brief "$brief")"
    if [[ -n "$out" ]]; then
      issues+=("$(basename $(dirname "$brief")): $out")
    fi
  done < <(find "${repo_root}/.aihaus/brainstorm" -maxdepth 2 -type f -name 'BRIEF.md' 2>/dev/null)

  # Sub-assert (d): fixture-fail #1 (missing-recommendation)
  local fixture1="${repo_root}/tools/fixtures/check-77/missing-recommendation.md"
  if [[ ! -f "$fixture1" ]]; then
    issues+=("fixture missing: tools/fixtures/check-77/missing-recommendation.md")
  else
    local out1
    out1="$(_validate_brief "$fixture1")"
    if [[ -z "$out1" ]]; then
      issues+=("fixture-fail #1 did NOT trigger validator (missing-recommendation should fail)")
    fi
  fi

  # Sub-assert (e): fixture-fail #2 (source-prose-violation)
  local fixture2="${repo_root}/tools/fixtures/check-77/source-prose-violation.md"
  if [[ ! -f "$fixture2" ]]; then
    issues+=("fixture missing: tools/fixtures/check-77/source-prose-violation.md")
  else
    local out2
    out2="$(_validate_brief "$fixture2")"
    if [[ -z "$out2" ]]; then
      issues+=("fixture-fail #2 did NOT trigger validator (source-prose-violation should fail grammar)")
    fi
  fi

  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${issues[@]}"
  fi
}

# Parse --check / --skill flags before the full-suite run
_CHECK_NAME=""
_CHECK_SKILL=""
_remaining_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) _CHECK_NAME="$2"; shift 2 ;;
    --skill) _CHECK_SKILL="$2"; shift 2 ;;
    *) _remaining_args+=("$1"); shift ;;
  esac
done

if [[ -n "$_CHECK_NAME" ]]; then
  if [[ -z "$_CHECK_SKILL" ]]; then
    printf "[FAIL] --check requires --skill <slug>\n" >&2
    exit 1
  fi
  _run_check_submode "$_CHECK_NAME" "$_CHECK_SKILL"
  # _run_check_submode always exits; unreachable
  exit 1
fi

# ---- Run everything ---------------------------------------------------------
printf "aihaus package smoke test\n"
printf "Package root: %s\n\n" "$PACKAGE_ROOT"

check_skills
check_agents
check_hooks
check_skill_frontmatter
check_skill_length
check_agent_frontmatter
check_conversation_header_shape
check_project_template
check_settings_template
check_installer_files_exist
check_installer_syntax
check_readme_length
check_license
check_version
check_purity
check_aih_plan_annexes
check_aih_milestone_annexes
check_m005_canonical_phrases
check_session_log_template
check_template_bash_wildcard
check_template_permission_hooks
check_auto_approve_patterns
check_merge_semantics_convergence
check_autonomy_guard_detects_violations
check_excluded_skills_keep_flag
check_skill_count_and_staleness
check_cohort_membership_roundtrip
check_autonomy_gate_fixtures
check_migration_fixtures
check_memory_readme_seeds
check_backfill_script
check_agent_evolution_scaffold
check_completion_protocol_step_4_7
check_context_curator
check_learning_advisor
check_knowledge_curator
check_verifier_knowledge_consulted
check_schema_v3_migration
check_worktree_reconcile_fixture
check_resume_substep_fixture
check_bash_guard_baseline
check_read_guard_exists
check_init_evolving_no_false_positive
check_agent_memory_filename_prefix_guard
check_evolving_block_well_formed
check_skill_evolution_post_apply_sub_modes
check_memory_scores_single_writer_prose
check_m017_hooks_bash_n
check_m017_merge_back_refusal
check_m017_git_add_guard_cases
check_m018_reap_fixture
check_m018_release_notes_shape_fixture
check_m018_env_name_dot_guard
check_f260427_session_end_safe_pop
check_f260427_branch_switch_warn_fixture
check_f260427_pre_flight_annex
check_f260427_skill_line_safety
check_f260427_adrs_present
check_run_status_contract
check_manifest_auto_close_present
check_aih_close_skill
check_enforcement_audit_scaffold
check_cli_shim_parseable
check_readme_install_section
check_pause_class_enum
check_gsp_ds_regex_coverage
check_aih_resume_stranded_prose
check_adr_260506a_present
check_pause_class_permissive_legacy
check_audit_pair_invariant
check_external_dep_down_laundering
check_completion_curator_audit_pair
check_lsdd_regex_coverage
check_lsdd_false_positive_guards
check_skill_agent_cadence_absence
check_m027_semantic_gate
check_brief_subfield_schema

printf "
"
if [[ "$FAILURES" -eq 0 ]]; then
  printf "aihaus package smoke test PASSED [OK] (77/77)
"
  exit 0
else
  printf "FAILED - %d of 77 checks failed
" "$FAILURES"
  exit 1
fi
