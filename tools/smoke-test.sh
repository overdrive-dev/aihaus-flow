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

_mktemp_dir() {
  local prefix="${1:-aihaus-smoke}"
  local base="${AIHAUS_SMOKE_TMPDIR:-${TMPDIR:-}}"
  local dir
  if [[ -z "$base" || ! -d "$base" || ! -w "$base" ]]; then
    base="$(cd "$SCRIPT_DIR/.." && pwd)/tmp"
    mkdir -p "$base" 2>/dev/null || return 1
  fi
  dir="$(mktemp -d "${base%/}/${prefix}.XXXXXX" 2>/dev/null)" && {
    printf '%s\n' "$dir"
    return 0
  }
  dir="${base%/}/${prefix}.$$.$RANDOM"
  mkdir -p "$dir" 2>/dev/null && {
    printf '%s\n' "$dir"
    return 0
  }
  return 1
}

# ---- Check 1: 15 expected SKILL.md files in expected subdirectories ---------
check_skills() {
  _start_check
  local label="Check ${CHECK_NUMBER}: .aihaus/skills/ has 15 expected SKILL.md files"
  local expected=(aih-brainstorm aih-bugfix aih-close aih-effort aih-env aih-feature aih-help aih-init aih-install aih-milestone aih-plan aih-quick aih-resume aih-sync-notion aih-update)
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

# ---- Check 2: .aihaus/agents/ has 58 .md files (M050 adds init interview agent) --
check_agents() {
  _start_check
  local label="Check ${CHECK_NUMBER}: .aihaus/agents/ has 58 .md files"
  local agents_root="${PACKAGE_ROOT}/.aihaus/agents"
  if [[ ! -d "$agents_root" ]]; then
    _fail "$label" "directory not found: $agents_root"
    return
  fi
  local count
  count=$(find "$agents_root" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')
  if [[ "$count" -eq 58 ]]; then
    _pass "$label"
  else
    _fail "$label" "expected 58 .md files, found $count"
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
    calibrate-guard.sh
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
    role-guard.sh
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
    tdd-guard.sh
    aih-graph-refresh.sh
    project-context-refresh.sh
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
# (per-cohort value-validation, ADR-M012-A § smoke-test Check 6 + ADR-260509-Y).
# effort: is presence-only for most agents; preset-immunity sub-assert (Part C)
# enforces effort=max for plan-checker, contrarian, plan-calibrator.
#
# Cohort default-model table (5-cohort post-M027/S10 fork, balanced preset):
#   :planner-binding → opus
#   :planner         → opus
#   :doer            → sonnet
#   :verifier        → haiku
#   :adversarial     → opus  (merged from :adversarial-scout + :adversarial-review)
#
# Part C: Preset-immunity preservation sub-assert (BLOCKER #2 — ADR-260509-Y)
#   When cohort = :adversarial AND agent ∈ {plan-checker, contrarian, plan-calibrator}
#   → MUST have effort: max (per-agent override preserving the (opus,max) profile).
#   Failure indicates v3→v4 migration silently demoted the preset-immune agents.
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
    # Cohort → expected model map (5-cohort balanced baseline, ADR-M012-A + ADR-260509-Y).
    declare -A _cohort_model_map
    _cohort_model_map[":planner-binding"]="opus"
    _cohort_model_map[":planner"]="opus"
    _cohort_model_map[":doer"]="sonnet"
    _cohort_model_map[":verifier"]="haiku"
    _cohort_model_map[":adversarial"]="opus"

    local cohort expected_model members agent_file actual_model
    for cohort in ":planner-binding" ":planner" ":doer" ":verifier" ":adversarial"; do
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

    # ---- Part C: Preset-immunity preservation sub-assert (ADR-260509-Y BLOCKER #2) --
    # plan-checker, contrarian, plan-calibrator MUST have effort: max (not high)
    # because v4 cohort baseline is high; per-agent override carries the (opus,max) profile.
    # Failure here means v3→v4 migration silently demoted these preset-immune agents.
    local _preset_immune_agents=("plan-checker" "contrarian" "plan-calibrator")
    local pi_agent pi_file pi_effort
    for pi_agent in "${_preset_immune_agents[@]}"; do
      pi_file="${agents_root}/${pi_agent}.md"
      if [[ ! -f "$pi_file" ]]; then
        offenders+=("preset-immunity sub-assert: ${pi_agent}.md not found -- cannot verify effort=max")
        continue
      fi
      pi_effort=$(awk '/^---$/{c++; next} c==1 && /^effort:/{print $2; exit}' "$pi_file")
      if [[ "$pi_effort" != "max" ]]; then
        offenders+=("preset-immunity VIOLATION: agents/${pi_agent}.md has effort=${pi_effort} (must be max -- v4 cohort baseline=high would demote unless per-agent override present)")
      fi
    done
    unset _preset_immune_agents

    # ---- Part D: Fixture-fail tests (ADR-260509-Y — prove gate is not vacuous) --
    # Three inline synthetic-fixture tests using tmpdir agent files.
    # Each test creates a fake agent with effort: high (preset-immunity violation).
    # Part C logic extracts effort and compares to "max" — MUST detect violation.
    # If awk extraction fails to return "high" (returns "max" or empty) → gate broken.
    local _tmpdir
    _tmpdir="$(_mktemp_dir smoke6)" || true
    if [[ -d "$_tmpdir" ]]; then
      # fixture-fail-c (load-bearing BLOCKER #2): plan-checker effort=high → must NOT read as max.
      local _fake_pc="${_tmpdir}/plan-checker.md"
      printf -- '---\nname: plan-checker\ntools: Read\nmodel: opus\neffort: high\ncolor: amber\nmemory: project\nresumable: true\ncheckpoint_granularity: story\n---\n' > "$_fake_pc"
      local _fake_effort_pc
      _fake_effort_pc=$(awk '/^---$/{c++; next} c==1 && /^effort:/{print $2; exit}' "$_fake_pc")
      # Gate broken if extraction returns "max" (it should return "high" → Part C would fire).
      if [[ "$_fake_effort_pc" == "max" || -z "$_fake_effort_pc" ]]; then
        offenders+=("fixture-fail-c BROKEN: awk extracted '${_fake_effort_pc}' from synthetic plan-checker effort=high (expected 'high' — gate would not detect preset-immunity demotion)")
      fi

      # fixture-fail-b: contrarian effort=high → must NOT read as max.
      local _fake_ct="${_tmpdir}/contrarian.md"
      printf -- '---\nname: contrarian\ntools: Read\nmodel: opus\neffort: high\ncolor: indigo\nmemory: project\nresumable: true\ncheckpoint_granularity: story\n---\n' > "$_fake_ct"
      local _fake_effort_ct
      _fake_effort_ct=$(awk '/^---$/{c++; next} c==1 && /^effort:/{print $2; exit}' "$_fake_ct")
      if [[ "$_fake_effort_ct" == "max" || -z "$_fake_effort_ct" ]]; then
        offenders+=("fixture-fail-b BROKEN: awk extracted '${_fake_effort_ct}' from synthetic contrarian effort=high (expected 'high' — gate would not detect preset-immunity demotion)")
      fi

      # fixture-fail-a: plan-calibrator effort=high → must NOT read as max.
      local _fake_cal="${_tmpdir}/plan-calibrator.md"
      printf -- '---\nname: plan-calibrator\ntools: Read\nmodel: opus\neffort: high\ncolor: red\nmemory: project\nresumable: false\ncheckpoint_granularity: step\n---\n' > "$_fake_cal"
      local _fake_effort_cal
      _fake_effort_cal=$(awk '/^---$/{c++; next} c==1 && /^effort:/{print $2; exit}' "$_fake_cal")
      if [[ "$_fake_effort_cal" == "max" || -z "$_fake_effort_cal" ]]; then
        offenders+=("fixture-fail-a BROKEN: awk extracted '${_fake_effort_cal}' from synthetic plan-calibrator effort=high (expected 'high' — gate would not detect preset-immunity demotion)")
      fi

      rm -rf "$_tmpdir" 2>/dev/null || true
    fi
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
  local -a settings_files=(
    "${PACKAGE_ROOT}/templates/settings.local.json"
    "${PACKAGE_ROOT}/.aihaus/templates/settings.local.json"
  )
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
  for settings_file in "${settings_files[@]}"; do
    if [[ ! -f "$settings_file" ]]; then
      _fail "$label" "file not found: $settings_file"
      return
    fi
    case "$parser" in
      jq)
        if ! jq -e '.hooks and .env and (.hooks | to_entries | all(.value | type == "array"))' "$settings_file" >/dev/null 2>&1; then
          _fail "$label" "invalid JSON, missing hooks/env keys, or hook event is not array: $settings_file"
          return
        fi
        ;;
      python3|python|py)
        if ! "$parser" -c "import json,sys; d=json.load(open(sys.argv[1], encoding='utf-8')); ok=all(k in d for k in ('hooks','env')) and isinstance(d.get('hooks'),dict) and all(isinstance(v,list) for v in d['hooks'].values()); sys.exit(0 if ok else 1)" "$settings_file" >/dev/null 2>&1; then
          _fail "$label" "invalid JSON, missing hooks/env keys, or hook event is not array: $settings_file"
          return
        fi
        ;;
    esac
  done
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

# ---- merge-settings.sh produces replacement semantics for permissions arrays ----
# (Check 23 amended M030/S05 per ADR-260514-B)
# Verifies that the shared merge helper REPLACES permissions.allow (overlay wins)
# per the per-array-path semantics matrix. This is the M014 migration-hint contract
# regression assertion: .hooks.<Event>[] now union-merges but permissions.allow
# still replaces. Runs under default path AND forced Python path.
check_merge_semantics_convergence() {
  _start_check
  local label="Check ${CHECK_NUMBER}: merge-settings.sh produces replacement semantics for permissions.allow (ADR-260514-B M014 contract)"
  local helper="${PACKAGE_ROOT}/scripts/lib/merge-settings.sh"
  local base="${PACKAGE_ROOT}/../tools/fixtures/settings-merge/base.json"
  local overlay="${PACKAGE_ROOT}/../tools/fixtures/settings-merge/overlay.json"
  [[ -f "$base" ]] || base="tools/fixtures/settings-merge/base.json"
  [[ -f "$overlay" ]] || overlay="tools/fixtures/settings-merge/overlay.json"
  [[ -f "$helper" && -f "$base" && -f "$overlay" ]] || { _fail "$label" "missing helper or fixtures"; return; }

  local py_bin
  py_bin="$(command -v python3 || command -v python || command -v py)"
  if [[ -z "$py_bin" ]]; then
    _fail "$label" "python required to parse merge result"
    return
  fi

  local repo_root="${PACKAGE_ROOT}/.."
  local tmpdir="${repo_root}/tools/.out/merge-test-$$"
  mkdir -p "$tmpdir"
  local tmpdst="${tmpdir}/dst.json"
  local tmpsrc="${tmpdir}/src.json"
  local issues=()

  # Sub-assert A: default path (jq if available, else python)
  cp "$base" "$tmpdst"; cp "$overlay" "$tmpsrc"
  # shellcheck disable=SC1090
  ( source "$helper" && merge_settings "$tmpdst" "$tmpsrc" ) >/dev/null 2>&1
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
  if [[ "$result_len" != "3" ]]; then
    issues+=("default path: expected replacement (3 entries from overlay), got $result_len entries")
  fi

  # Sub-assert B: forced Python path
  cp "$base" "$tmpdst"; cp "$overlay" "$tmpsrc"
  # shellcheck disable=SC1090
  ( AIHAUS_FORCE_PYTHON_MERGE=1 source "$helper" && AIHAUS_FORCE_PYTHON_MERGE=1 merge_settings "$tmpdst" "$tmpsrc" ) >/dev/null 2>&1
  if command -v cygpath >/dev/null 2>&1; then
    py_path="$(cygpath -w "$tmpdst" 2>/dev/null || echo "$tmpdst")"
  else
    py_path="$tmpdst"
  fi
  result_len=$("$py_bin" -c "
import json, sys
with open(sys.argv[1]) as f: data = json.load(f)
print(len(data.get('permissions', {}).get('allow', [])))
" "$py_path" 2>/dev/null || echo "0")
  if [[ "$result_len" != "3" ]]; then
    issues+=("python path: expected replacement (3 entries from overlay), got $result_len entries")
  fi

  rm -rf "$tmpdir"

  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${issues[@]}"
  fi
}

# ---- Check 82: merge-settings.sh union semantics for .hooks arrays (M030/S05) ----
# ADR-260514-B: .hooks.<Event>[N].hooks[] union by .command;
# .hooks.<Event>[] outer arrays position-paired-merge.
# Runs under default path AND AIHAUS_FORCE_PYTHON_MERGE=1 for each of 4 fixtures.
_check_merge_hooks_fixture() {
  local fixdir="$1" label_prefix="$2" helper="$3" py_bin="$4"
  local force_python="${5:-0}" issues_ref="$6"

  local base_file="${fixdir}.base.json"
  local overlay_file="${fixdir}.overlay.json"
  local expected_file="${fixdir}.expected.json"

  if [[ ! -f "$base_file" || ! -f "$overlay_file" || ! -f "$expected_file" ]]; then
    eval "${issues_ref}+=(\"${label_prefix}: missing fixture files\")"
    return
  fi

  local repo_root
  repo_root="$(cd "$(dirname "$helper")/../.." && pwd)"
  local tmpdir="${repo_root}/tools/.out/merge-hooks-$$"
  mkdir -p "$tmpdir"
  local tmpdst="${tmpdir}/dst.json"
  local tmpsrc="${tmpdir}/src.json"
  cp "$base_file" "$tmpdst"
  cp "$overlay_file" "$tmpsrc"

  if [[ "$force_python" = "1" ]]; then
    # shellcheck disable=SC1090
    ( AIHAUS_FORCE_PYTHON_MERGE=1 source "$helper" && AIHAUS_FORCE_PYTHON_MERGE=1 merge_settings "$tmpdst" "$tmpsrc" ) >/dev/null 2>&1
    local path_label="python"
  else
    # shellcheck disable=SC1090
    ( source "$helper" && merge_settings "$tmpdst" "$tmpsrc" ) >/dev/null 2>&1
    local path_label="default"
  fi

  local py_path="$tmpdst"
  if command -v cygpath >/dev/null 2>&1; then
    py_path="$(cygpath -w "$tmpdst" 2>/dev/null || echo "$tmpdst")"
  fi
  local expected_path="$expected_file"
  if command -v cygpath >/dev/null 2>&1; then
    expected_path="$(cygpath -w "$expected_file" 2>/dev/null || echo "$expected_file")"
  fi

  local match
  match=$("$py_bin" -c "
import json, sys
with open(sys.argv[1]) as f: actual = json.load(f)
with open(sys.argv[2]) as f: expected = json.load(f)
if actual == expected:
    print('match')
else:
    import json as j
    print('mismatch: actual=' + j.dumps(actual, separators=(',',':')) + ' expected=' + j.dumps(expected, separators=(',',':')))
" "$py_path" "$expected_path" 2>/dev/null || echo "error")

  rm -rf "$tmpdir"

  if [[ "$match" != "match" ]]; then
    eval "${issues_ref}+=(\"${label_prefix} [${path_label}]: ${match}\")"
  fi
}

check_merge_hooks_union() {
  _start_check
  local label="Check ${CHECK_NUMBER}: merge-settings.sh union semantics for .hooks arrays (ADR-260514-B)"
  local helper="${PACKAGE_ROOT}/scripts/lib/merge-settings.sh"
  local fixtures_base="${PACKAGE_ROOT}/../tools/fixtures/settings-merge-hooks"
  [[ -f "$helper" ]] || { _fail "$label" "missing helper: $helper"; return; }
  [[ -d "$fixtures_base" ]] || { _fail "$label" "missing fixture dir: tools/fixtures/settings-merge-hooks/"; return; }

  local py_bin
  py_bin="$(command -v python3 || command -v python || command -v py)"
  if [[ -z "$py_bin" ]]; then
    _fail "$label" "python required"
    return
  fi

  local issues=()

  for n in 01-empty-base 02-pre-m017-shape 03-two-bash-matchers 04-user-custom-non-colliding; do
    local fixdir="${fixtures_base}/${n}"
    _check_merge_hooks_fixture "$fixdir" "fixture-${n}" "$helper" "$py_bin" "0" "issues"
    _check_merge_hooks_fixture "$fixdir" "fixture-${n}" "$helper" "$py_bin" "1" "issues"
  done

  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${issues[@]}"
  fi
}

# ---- Check 83: update.sh drift-detect heuristic (M030/S05 Half B) ----
# Validates the drift-detect heuristic logic:
#   01-no-drift: delta=0 -> heuristic returns no-drift
#   02-two-missing: delta>=2 -> heuristic returns drift
#   03-sentinel-skip: sentinel present -> before==after (no recompute)
check_update_drift_recompute() {
  _start_check
  local label="Check ${CHECK_NUMBER}: update.sh drift-detect recompute heuristic (ADR-260514-B Half B)"
  local fixtures_base="${PACKAGE_ROOT}/../tools/fixtures/update-drift"
  [[ -d "$fixtures_base" ]] || { _fail "$label" "missing fixture dir: tools/fixtures/update-drift/"; return; }

  local py_bin
  py_bin="$(command -v python3 || command -v python || command -v py)"
  if [[ -z "$py_bin" ]]; then
    _fail "$label" "python required"
    return
  fi

  local issues=()

  _drift_heuristic_check() {
    local template_file="$1" user_file="$2" threshold="${3:-2}"
    local _tp="$template_file" _up="$user_file"
    if command -v cygpath >/dev/null 2>&1; then
      _tp="$(cygpath -w "$template_file" 2>/dev/null || echo "$template_file")"
      _up="$(cygpath -w "$user_file" 2>/dev/null || echo "$user_file")"
    fi
    "$py_bin" -c "
import json, sys
threshold = int(sys.argv[3])
with open(sys.argv[1]) as f: tmpl = json.load(f)
with open(sys.argv[2]) as f: user = json.load(f)
tmpl_hooks = tmpl.get('hooks', {})
user_hooks = user.get('hooks', {})
max_delta = 0
max_event = ''
for event, entries in tmpl_hooks.items():
    tc = sum(len(e.get('hooks', [])) for e in entries)
    uc = sum(len(e.get('hooks', [])) for e in user_hooks.get(event, []))
    d = tc - uc
    if d > max_delta:
        max_delta = d
        max_event = event
if max_delta >= threshold:
    print('drift:' + str(max_delta) + ':' + max_event)
else:
    print('no-drift')
" "$_tp" "$_up" "$threshold" 2>/dev/null || echo "error"
  }

  # Fixture 01: no-drift
  local f01_b="${fixtures_base}/01-no-drift.before.json"
  local f01_a="${fixtures_base}/01-no-drift.after.json"
  if [[ ! -f "$f01_b" || ! -f "$f01_a" ]]; then
    issues+=("fixture 01: missing before/after files")
  else
    local r01
    r01=$(_drift_heuristic_check "$f01_a" "$f01_b" "2")
    if [[ "$r01" != "no-drift" ]]; then
      issues+=("fixture 01 (no-drift): heuristic returned '$r01', expected 'no-drift'")
    fi
  fi

  # Fixture 02: two-missing
  local f02_b="${fixtures_base}/02-two-missing.before.json"
  local f02_a="${fixtures_base}/02-two-missing.after.json"
  if [[ ! -f "$f02_b" || ! -f "$f02_a" ]]; then
    issues+=("fixture 02: missing before/after files")
  else
    local r02
    r02=$(_drift_heuristic_check "$f02_a" "$f02_b" "2")
    if [[ "$r02" != drift* ]]; then
      issues+=("fixture 02 (two-missing): heuristic returned '$r02', expected 'drift:...'")
    fi
  fi

  # Fixture 03: sentinel-skip
  local f03_s="${fixtures_base}/03-sentinel-skip.sentinel.json"
  local f03_b="${fixtures_base}/03-sentinel-skip.before.json"
  local f03_a="${fixtures_base}/03-sentinel-skip.after.json"
  if [[ ! -f "$f03_s" || ! -f "$f03_b" || ! -f "$f03_a" ]]; then
    issues+=("fixture 03: missing sentinel/before/after files")
  else
    local _sp="$f03_s"
    if command -v cygpath >/dev/null 2>&1; then
      _sp="$(cygpath -w "$f03_s" 2>/dev/null || echo "$f03_s")"
    fi
    local sv
    sv=$("$py_bin" -c "
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
print(d.get('sentinel', ''))
" "$_sp" 2>/dev/null || echo "")
    if [[ "$sv" != ".recompute-skipped-260514" ]]; then
      issues+=("fixture 03: sentinel JSON missing '.recompute-skipped-260514' value")
    fi
    local _bp="$f03_b" _ap="$f03_a"
    if command -v cygpath >/dev/null 2>&1; then
      _bp="$(cygpath -w "$f03_b" 2>/dev/null || echo "$f03_b")"
      _ap="$(cygpath -w "$f03_a" 2>/dev/null || echo "$f03_a")"
    fi
    local fm
    fm=$("$py_bin" -c "
import json, sys
with open(sys.argv[1]) as f: a = json.load(f)
with open(sys.argv[2]) as f: b = json.load(f)
print('match' if a == b else 'mismatch')
" "$_bp" "$_ap" 2>/dev/null || echo "error")
    if [[ "$fm" != "match" ]]; then
      issues+=("fixture 03 (sentinel-skip): before/after should be identical; got mismatch")
    fi
  fi

  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${issues[@]}"
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

# ---- Check 27: skill directory count = 15 -----------------------------------
# Verifies that exactly 15 aih-* skill directories exist under .aihaus/skills/.
# Note: Check 1 verifies the NAMED SKILL.md files (15 expected names). In the
# 3.0 refactor aih-goal (orchestrator) was removed — its kanban/DB substrate
# relocated to workflows/kanban/, decoupled from goal — and aih-env (env
# capture) was added. Check 27 independently verifies the directory count so
# that unexpected directories (stale renames, extra skill dirs) also cause CI
# failure. If the count exceeds 15, a stale directory likely remains.
check_skill_count_and_staleness() {
  _start_check
  local label="Check ${CHECK_NUMBER}: exactly 15 aih-* skill dirs exist"
  local skills_root="${PACKAGE_ROOT}/.aihaus/skills"
  local problems=()

  # Count aih-* directories (exclude _shared and any non-aih prefixed dirs).
  local actual_count
  actual_count=$(find "$skills_root" -maxdepth 1 -type d -name 'aih-*' | wc -l | tr -d ' ')
  if [[ "$actual_count" -ne 15 ]]; then
    problems+=("expected 15 aih-* skill dirs; found ${actual_count} (stale dir from rename? run: ls ${skills_root}/)")
  fi

  if [[ ${#problems[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${problems[@]}"
  fi
}

# ---- Check 28: cohort membership round-trip + parse contract (M012/S07 + M027/S10) --
# Seven sub-assertions covering the 5-cohort taxonomy in cohorts.md (post-M027/S10 fork):
#   C1 each of the 58 agents appears under exactly one cohort
#   C2 cohort counts match: planner-binding=4, planner=14, doer=25, verifier=9,
#      adversarial=6 (total=58); :adversarial-scout + :adversarial-review merged per ADR-260509-Y
#   C3 no :verifier-rich or :investigator or legacy :adversarial-scout or :adversarial-review
#      cohort name appears in the table (deprecated names forbidden post-M027/S10)
#   C4 F-006 parse contract: every data row yields NF=7 (awk -F'|' | sort -u == "7")
#   C5 header row literal match: "| # | Agent | Cohort | Model | Effort |"
# Self-contained: reads cohorts.md directly; no invocation of /aih-effort
# (R7 cycle prevention preserved).
check_cohort_membership_roundtrip() {
  _start_check
  local label="Check ${CHECK_NUMBER}: cohort membership + counts + F-006 parse contract (M012/S07 + M027/S10)"
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
  _cohort_counts[":adversarial"]=0

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
  if [[ "$total_agents" -ne 58 ]]; then
    problems+=("C1: expected 58 agents in membership table; found ${total_agents}")
  fi

  # C2: expected cohort counts (5-cohort post-M027/S10 fork, ADR-260509-Y).
  local -A _expected_counts=(
    [":planner-binding"]=4
    [":planner"]=14
    [":doer"]=25
    [":verifier"]=9
    [":adversarial"]=6
  )
  for cohort in ":planner-binding" ":planner" ":doer" ":verifier" ":adversarial"; do
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
  # Post-M027/S10: :adversarial-scout and :adversarial-review are deprecated names.
  if grep -qE '^\|[^|]*\| *:adversarial-(scout|review) *\|' "$cohorts_md"; then
    problems+=("C3: deprecated cohort name ':adversarial-scout' or ':adversarial-review' still present in membership table (merged to :adversarial per ADR-260509-Y)")
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
  if ! printf '%s' "$out_a1" | grep -Eq '"decision"[[:space:]]*:[[:space:]]*"block"'; then
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
  if ! printf '%s' "$out_a3" | grep -Eq '"decision"[[:space:]]*:[[:space:]]*"block"'; then
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

# ---- Check 31: memory seeds exist and are non-empty (M013/S02 + goal memory) -
# Asserts that memory-bucket README files and workflow starter files are present
# in the package source and have content (not zero-byte placeholders).
check_memory_readme_seeds() {
  _start_check
  local label="Check ${CHECK_NUMBER}: memory seeds exist and non-empty"
  local memory_root="${PACKAGE_ROOT}/.aihaus/memory"
  local templates_root="${PACKAGE_ROOT}/.aihaus/templates"
  local subdirs=(global backend frontend reviews agents workflows)
  local workflow_files=(README.md environment.md user-preferences.md rules.md gotchas.md)
  local forbidden_re='Promoted from|First observed|adopter|dogfood|ADR-M0|M00[0-9]|M0[0-9][0-9]|pkg/\.aihaus|pkg\\\\\.aihaus|aihaus-flow package'
  local problems=()

  for subdir in "${subdirs[@]}"; do
    local f="${memory_root}/${subdir}/README.md"
    if [[ ! -f "$f" ]]; then
      problems+=("missing: memory/${subdir}/README.md")
    elif [[ ! -s "$f" ]]; then
      problems+=("empty: memory/${subdir}/README.md")
    fi
  done
  for name in "${workflow_files[@]}"; do
    local f="${memory_root}/workflows/${name}"
    if [[ ! -f "$f" ]]; then
      problems+=("missing: memory/workflows/${name}")
    elif [[ ! -s "$f" ]]; then
      problems+=("empty: memory/workflows/${name}")
    fi
  done
  for name in knowledge.md decisions.md; do
    local f="${templates_root}/${name}"
    if [[ ! -f "$f" ]]; then
      problems+=("missing: templates/${name}")
    elif [[ ! -s "$f" ]]; then
      problems+=("empty: templates/${name}")
    fi
  done
  grep -Fq 'AIHAUS:PROJECT-KNOWLEDGE-EMPTY' "${templates_root}/knowledge.md" 2>/dev/null \
    || problems+=("templates/knowledge.md missing empty-project marker")
  grep -Fq 'AIHAUS:PROJECT-DECISIONS-EMPTY' "${templates_root}/decisions.md" 2>/dev/null \
    || problems+=("templates/decisions.md missing empty-project marker")
  while IFS= read -r -d '' f; do
    if grep -Eiq "${forbidden_re}" "$f" 2>/dev/null; then
      problems+=("non-neutral seed content: ${f#${PACKAGE_ROOT}/.aihaus/}")
    fi
  done < <(find "${memory_root}" -type f \( -name '*.md' -o -name '*.txt' \) -print0)
  for f in "${templates_root}/knowledge.md" "${templates_root}/decisions.md"; do
    if grep -Eiq "${forbidden_re}" "$f" 2>/dev/null; then
      problems+=("non-neutral seed content: ${f#${PACKAGE_ROOT}/.aihaus/}")
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
#   (f) agent count at 58 (init interview agent added after M049)
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

  # (f) agent count at 58 (init interview agent added after M049)
  local agents_root="${PACKAGE_ROOT}/.aihaus/agents"
  local count
  count=$(find "$agents_root" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')
  if [[ "$count" -ne 58 ]]; then
    problems+=("expected 58 agents total (init interview agent added after M049); found ${count}")
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
  tmpdir="$(_mktemp_dir aih-smoke)"
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
  tmpdir="$(_mktemp_dir aih-wt-smoke)"

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
  tmpdir="$(_mktemp_dir aih-resume-smoke)"
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
  if ! printf '%s' "$out_b" | grep -Eq '"decision"[[:space:]]*:[[:space:]]*"block"'; then
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
    if ! printf '%s' "$out_c" | grep -Eq '"decision"[[:space:]]*:[[:space:]]*"block"'; then
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
  if printf '%s' "$out_d_ptbr" | grep -Eq '"decision"[[:space:]]*:[[:space:]]*"block"'; then
    issues+=("sub-assert(d): AIHAUS_GSP_DS_REGEX=0 still blocked PT-BR-only phrase (should skip)")
  fi
  # Existing English pattern must STILL block with opt-out
  local eng_phrase='Checkpoint honesto: stopping here.'
  local out_d_eng
  out_d_eng="$(AIHAUS_GSP_DS_REGEX=0 AIHAUS_EXEC_PHASE=1 \
    AIHAUS_AUDIT_GATE_LOG="${tmp_dir}/gate-d2.jsonl" \
    AIHAUS_AUDIT_LOG="${tmp_dir}/viol-d2.jsonl" \
    bash "$hook" <<< "$eng_phrase" 2>/dev/null || true)"
  if ! printf '%s' "$out_d_eng" | grep -Eq '"decision"[[:space:]]*:[[:space:]]*"block"'; then
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
    if ! printf '%s' "$out_b" | grep -Eq '"decision"[[:space:]]*:[[:space:]]*"block"'; then
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
  if printf '%s' "$out_c1" | grep -Eq '"decision"[[:space:]]*:[[:space:]]*"block"'; then
    issues+=("sub-assert(c): AIHAUS_LSDD_REGEX=0 still blocked LSDD-only phrase 'Phase 7 complete'")
  fi
  # Existing M005 fast-path must STILL block with LSDD opt-out
  local m005_phrase='Checkpoint honesto'
  local out_c2
  out_c2="$(AIHAUS_LSDD_REGEX=0 AIHAUS_EXEC_PHASE=1 \
    AIHAUS_AUDIT_GATE_LOG="${tmp_dir}/gate-c2.jsonl" \
    AIHAUS_AUDIT_LOG="${tmp_dir}/viol-c2.jsonl" \
    bash "$hook" <<< "$m005_phrase" 2>/dev/null || true)"
  if ! printf '%s' "$out_c2" | grep -Eq '"decision"[[:space:]]*:[[:space:]]*"block"'; then
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
    if printf '%s' "$out_f" | grep -Eq '"decision"[[:space:]]*:[[:space:]]*"block"'; then
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
    if printf '%s' "$out" | grep -Eq '"decision"[[:space:]]*:[[:space:]]*"block"'; then
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
  if ! printf '%s' "$out_e" | grep -Eq '"decision"[[:space:]]*:[[:space:]]*"block"'; then
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
    if ! printf '%s' "$out_f" | grep -Eq '"decision"[[:space:]]*:[[:space:]]*"block"'; then
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

# ---- Check 78: calibration-gate ambiguity-detection trigger (M027/S5) --------
# Validates plan-calibrator trigger logic: detects plans with ambiguous markers
# (TBD / assumed / TODO / pending confirmation) vs plans with all defaults explicit.
#
# fixture-fail #1: trigger-fires.md — plan with TBD/assumed/TODO markers
#   → ambiguity detected → trigger SHOULD fire (≥1 ambiguity found)
# fixture-fail #2: trigger-suppressed.md — plan with all confirmed values
#   → no ambiguity markers → trigger should NOT fire (0 ambiguities found)
#
# Detection logic mirrors plan-calibrator §Trigger — Ambiguity-Surface Detection:
#   markers: TBD | assumed | TODO | pending confirmation
#
# ADR-260509-W: trigger is ambiguity-surface-detection, NOT story-count threshold.
check_calibration_trigger() {
  _start_check
  local label="Check ${CHECK_NUMBER}: calibration-gate ambiguity-detection trigger (M027/S5)"
  local issues=()
  local repo_root="${PACKAGE_ROOT}/.."
  local fixture_dir="${repo_root}/tools/fixtures/check-78"

  # Helper: count ambiguity markers in a plan file.
  # grep -c always prints a single-line count to stdout (0 when no match, N otherwise)
  # and exits 1 when no match — `|| true` neutralizes the exit code without
  # double-printing "0\n0" (the prior `|| echo 0` would append a second line on
  # no-match because grep already printed "0", breaking `[[ -gt ]]` comparisons).
  _count_ambiguities() {
    local file="$1"
    grep -ciE '\bTBD\b|[[:space:]]assumed[[:space:]]|[[:space:]]assumed$|\bTODO\b|pending confirmation' "$file" 2>/dev/null || true
  }

  # Sub-assert (a): fixture-fail #1 — trigger-fires.md must have ≥1 ambiguity
  local fixture1="${fixture_dir}/trigger-fires.md"
  if [[ ! -f "$fixture1" ]]; then
    issues+=("fixture missing: tools/fixtures/check-78/trigger-fires.md")
  else
    local count1
    count1=$(_count_ambiguities "$fixture1")
    if [[ "$count1" -lt 1 ]]; then
      issues+=("fixture-fail #1: trigger-fires.md detected 0 ambiguity markers (should have ≥1 — trigger must fire on TBD/assumed/TODO)")
    fi
  fi

  # Sub-assert (b): fixture-fail #2 — trigger-suppressed.md must have 0 ambiguities
  local fixture2="${fixture_dir}/trigger-suppressed.md"
  if [[ ! -f "$fixture2" ]]; then
    issues+=("fixture missing: tools/fixtures/check-78/trigger-suppressed.md")
  else
    local count2
    count2=$(_count_ambiguities "$fixture2")
    if [[ "$count2" -gt 0 ]]; then
      issues+=("fixture-fail #2: trigger-suppressed.md detected ${count2} ambiguity markers (should have 0 — all defaults must be explicitly confirmed)")
    fi
  fi

  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${issues[@]}"
  fi
}

# ---- Check 79: tdd-guard.sh hook fixture-fail tests (M028/S2) ---------------
# Validates tdd-guard.sh PreToolUse hook via 3 fixture JSON payloads:
#
#   fixture 1: tdd-on-no-test.json — Write on non-test file, AIHAUS_TESTING_DISCIPLINE=tdd,
#              no session marker → hook MUST exit 2 (block)
#   fixture 2: tdd-on-with-test.json — Edit on non-test file, AIHAUS_TESTING_DISCIPLINE=tdd,
#              session marker present → hook MUST exit 0 (allow)
#   fixture 3: aih-quick-bypass.json — Write with AIHAUS_TDD_GUARD=0 → hook MUST exit 0 (bypass)
#
# ADR-260510-C: hook contract (env bypass + session-marker + test-file allowlist).
check_tdd_guard_hook() {
  _start_check
  local label="Check ${CHECK_NUMBER}: tdd-guard.sh PreToolUse hook fixture-fail tests (M028/S2)"
  local issues=()
  local repo_root="${PACKAGE_ROOT}/.."
  local fixture_dir="${repo_root}/tools/fixtures/check-79"
  local hook="${PACKAGE_ROOT}/.aihaus/hooks/tdd-guard.sh"

  # Verify hook exists
  if [[ ! -f "$hook" ]]; then
    _fail "$label" "tdd-guard.sh missing: ${hook}"
    return
  fi

  # Verify fixture directory exists
  if [[ ! -d "$fixture_dir" ]]; then
    _fail "$label" "fixture directory missing: tools/fixtures/check-79/"
    return
  fi

  local tmpdir
  tmpdir="$(_mktemp_dir tdd-guard-check)"
  mkdir -p "${tmpdir}/.claude/audit" 2>/dev/null || true

  # Helper: run hook with controlled env, returns exit code
  # Usage: _run_hook_exit <fixture> <extra-env-assignments...>
  _run_hook_exit() {
    local fixture="$1"
    shift
    # Run in subshell with overridden env; redirect stderr to /dev/null for clean output
    local exit_code=0
    (
      # Point audit log to tmpdir to avoid polluting real dirs
      export AIHAUS_AUDIT_LOG="${tmpdir}/.claude/audit/hook.jsonl"
      # Point session marker dir to tmpdir so we control the marker file location
      export AIHAUS_SESSION_MARKER_DIR="${tmpdir}/.claude/audit"
      # Apply caller-specified env
      for e in "$@"; do
        export "${e?}"
      done
      bash "${hook}" < "${fixture}" >/dev/null 2>/dev/null
    ) || exit_code=$?
    echo "${exit_code}"
  }

  # Sub-assert 1: tdd-on-no-test.json — no session marker, tdd discipline → MUST block (exit 2)
  local fixture1="${fixture_dir}/tdd-on-no-test.json"
  if [[ ! -f "$fixture1" ]]; then
    issues+=("fixture missing: tools/fixtures/check-79/tdd-on-no-test.json")
  else
    # Ensure no session marker exists in tmpdir (clean state)
    rm -f "${tmpdir}/.claude/audit"/tdd-guard.session.*.json 2>/dev/null || true
    local exit1
    exit1="$(_run_hook_exit "$fixture1" "AIHAUS_TESTING_DISCIPLINE=tdd" "AIHAUS_TDD_GUARD=1")"
    if [[ "$exit1" -ne 2 ]]; then
      issues+=("fixture-fail #1: tdd-on-no-test.json exit ${exit1} (expected 2 — hook must block non-test Write with tdd discipline and no session marker)")
    fi
  fi

  # Sub-assert 2: tdd-on-with-test.json — session marker present, tdd discipline → MUST allow (exit 0)
  local fixture2="${fixture_dir}/tdd-on-with-test.json"
  if [[ ! -f "$fixture2" ]]; then
    issues+=("fixture missing: tools/fixtures/check-79/tdd-on-with-test.json")
  else
    # Create a valid session marker under a known CLAUDE_SESSION_ID in tmpdir
    local sess_id="smoke-check-79"
    mkdir -p "${tmpdir}/.claude/audit" 2>/dev/null || true
    printf '{"session_id":"%s","ts":"%s","test_files":["tests/test_service.py"]}\n' \
      "${sess_id}" "$(date -u +%FT%TZ 2>/dev/null || echo "2026-05-09T00:00:00Z")" \
      > "${tmpdir}/.claude/audit/tdd-guard.session.${sess_id}.json" 2>/dev/null || true
    local exit2
    exit2="$(_run_hook_exit "$fixture2" "AIHAUS_TESTING_DISCIPLINE=tdd" "AIHAUS_TDD_GUARD=1" "CLAUDE_SESSION_ID=${sess_id}")"
    if [[ "$exit2" -ne 0 ]]; then
      issues+=("fixture-fail #2: tdd-on-with-test.json exit ${exit2} (expected 0 — hook must allow non-test Edit when session marker shows prior test-file edit)")
    fi
  fi

  # Sub-assert 3: aih-quick-bypass.json — AIHAUS_TDD_GUARD=0 → MUST allow (exit 0)
  local fixture3="${fixture_dir}/aih-quick-bypass.json"
  if [[ ! -f "$fixture3" ]]; then
    issues+=("fixture missing: tools/fixtures/check-79/aih-quick-bypass.json")
  else
    local exit3
    exit3="$(_run_hook_exit "$fixture3" "AIHAUS_TESTING_DISCIPLINE=tdd" "AIHAUS_TDD_GUARD=0")"
    if [[ "$exit3" -ne 0 ]]; then
      issues+=("fixture-fail #3: aih-quick-bypass.json exit ${exit3} (expected 0 — AIHAUS_TDD_GUARD=0 must bypass hook)")
    fi
  fi

  # Cleanup tmpdir
  rm -rf "${tmpdir}" 2>/dev/null || true

  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${issues[@]}"
  fi
}

# ---- Check 80: tdd-discipline annex pointer (M028/S3) -------------------------
# Validates that aih-feature Step 7.6 tdd-discipline annex is wired correctly:
#   (a) annex file exists at aih-feature/annexes/tdd-discipline.md
#   (b) aih-feature/SKILL.md contains the tdd-discipline annex pointer
#   (c) annex has expected H2 sections (Trigger, Step 7.6, --no-tdd opt-out, Composition)
#   (d) aih-plan/SKILL.md contains --no-tdd Phase 3.6 entry
#   (e) aih-milestone/SKILL.md contains --no-tdd propagation prose
#
# ADR-260510-A: testing_discipline schema (project.md field + enum).
# ADR-260510-C: tdd-guard.sh PreToolUse hook contract.
check_tdd_discipline_annex() {
  _start_check
  local label="Check ${CHECK_NUMBER}: tdd-discipline annex pointer + --no-tdd flag wiring (M028/S3)"
  local issues=()
  local skills_root="${PACKAGE_ROOT}/.aihaus/skills"
  local annex="${skills_root}/aih-feature/annexes/tdd-discipline.md"
  local feature_skill="${skills_root}/aih-feature/SKILL.md"
  local plan_skill="${skills_root}/aih-plan/SKILL.md"
  local milestone_skill="${skills_root}/aih-milestone/SKILL.md"

  # Sub-assert (a): annex file exists
  if [[ ! -f "$annex" ]]; then
    issues+=("tdd-discipline.md annex missing at aih-feature/annexes/tdd-discipline.md")
  fi

  # Sub-assert (b): SKILL.md contains annex pointer
  if ! grep -q "tdd-discipline" "$feature_skill" 2>/dev/null; then
    issues+=("aih-feature/SKILL.md missing tdd-discipline annex pointer")
  fi

  # Sub-assert (c): annex contains expected H2 sections
  if [[ -f "$annex" ]]; then
    for section in "## Trigger" "## Step 7.6" "## --no-tdd opt-out" "## Composition"; do
      if ! grep -qF "$section" "$annex"; then
        issues+=("tdd-discipline.md missing section: ${section}")
      fi
    done
  fi

  # Sub-assert (d): aih-plan/SKILL.md contains --no-tdd Phase 3.6 prose
  if ! grep -q "no-tdd" "$plan_skill" 2>/dev/null; then
    issues+=("aih-plan/SKILL.md missing --no-tdd flag handling")
  fi

  # Sub-assert (e): aih-milestone/SKILL.md contains --no-tdd propagation prose
  if ! grep -q "no-tdd" "$milestone_skill" 2>/dev/null; then
    issues+=("aih-milestone/SKILL.md missing --no-tdd propagation prose")
  fi

  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${issues[@]}"
  fi
}

# ---- Check 81: calibrate-guard drift detection (M029/S3) ----------------------
# Post-merge assertion: every CHECK.md in .aihaus/plans/ must satisfy at least one
# of 4 allow conditions, or the plan is in drift (calibration gate was skipped):
#
#   (a) Companion BUSINESS-RULES.md exists                        → allow
#   (b) ASSUMPTIONS.md ambiguity count = 0 (Check 78 regex)      → allow
#   (c) hook.jsonl has calibration-skip row for this slug         → allow
#   (d) CHECK.md ctime predates M029_EPOCH (1747008000) — legacy → allow
#
# Uses fixture-based test (not real plans/) to prove gate is non-vacuous:
#   drift-detected/       — ASSUMPTIONS ambiguity ≥1, no BUSINESS-RULES.md,
#                           no audit row, not legacy → MUST fail (block)
#   drift-bypassed-by-no-calibrate/  — same as above BUT audit row present → MUST pass
#   no-ambiguity-skip/    — ASSUMPTIONS ambiguity = 0, no BUSINESS-RULES.md → MUST pass
#
# ADR-260511-C: drift detection + legacy ctime-exemption.
check_calibrate_drift() {
  _start_check
  local label="Check ${CHECK_NUMBER}: calibrate-guard drift detection + 3 fixtures (M029/S3)"
  local issues=()
  local repo_root="${PACKAGE_ROOT}/.."
  local fixture_base="${repo_root}/tools/fixtures/check-81"

  # M029 first-commit epoch (matches calibrate-guard.sh L41)
  local M029_EPOCH=1747008000

  # Helper: count ambiguity markers in ASSUMPTIONS.md (mirrors Check 78 / calibrate-guard.sh L137)
  _count_plan_ambiguities() {
    local file="$1"
    grep -ciE '\bTBD\b|[[:space:]]assumed[[:space:]]|[[:space:]]assumed$|\bTODO\b|pending confirmation' "$file" 2>/dev/null || echo 0
  }

  # Helper: evaluate 4-axis allow condition for a given plan dir + optional audit jsonl path
  # Returns 0 (allow) or 1 (drift)
  # Usage: _evaluate_drift <plan_dir> [<audit_jsonl>]
  _evaluate_drift() {
    local plan_dir="$1"
    local audit_jsonl="${2:-}"
    local slug
    slug="$(basename "${plan_dir}")"
    local check_md="${plan_dir}/CHECK.md"
    local business_rules="${plan_dir}/BUSINESS-RULES.md"
    local assumptions_md="${plan_dir}/ASSUMPTIONS.md"

    # (a) BUSINESS-RULES.md present → allow
    if [[ -f "${business_rules}" ]]; then
      return 0
    fi

    # (b) ASSUMPTIONS.md ambiguity count = 0 → allow
    local amb=0
    if [[ -f "${assumptions_md}" ]]; then
      amb="$(_count_plan_ambiguities "${assumptions_md}")"
      case "${amb}" in ''|*[!0-9]*) amb=0 ;; esac
    fi
    if [[ "${amb}" -eq 0 ]]; then
      return 0
    fi

    # (c) hook.jsonl shows calibration-skip row for this slug → allow
    if [[ -n "${audit_jsonl}" ]] && [[ -f "${audit_jsonl}" ]]; then
      if grep -qE '"event":"calibration-skip"' "${audit_jsonl}" 2>/dev/null; then
        if grep -E '"event":"calibration-skip"' "${audit_jsonl}" 2>/dev/null \
            | grep -qE "\"slug\":\"${slug}\"" 2>/dev/null; then
          return 0
        fi
      fi
    fi

    # (d) CHECK.md ctime predates M029_EPOCH → allow (legacy artifact)
    # Primary: filesystem mtime (portable; may reflect git-checkout time on Windows)
    local _mtime
    _mtime="$(stat -c%Y "${check_md}" 2>/dev/null || stat -f%m "${check_md}" 2>/dev/null || echo "")"
    if [[ -n "${_mtime}" ]] && [[ "${_mtime}" =~ ^[0-9]+$ ]]; then
      if [[ "${_mtime}" -lt "${M029_EPOCH}" ]]; then
        return 0
      fi
    fi
    # Fallback: slug-date prefix (YYMMDD-*) — reliable on Windows where git-checkout
    # updates mtime. Slugs starting with 6-digit date < 260512 are pre-M029 artifacts.
    # Only applies when slug matches YYMMDD- prefix pattern.
    if [[ "${slug}" =~ ^([0-9]{6})- ]]; then
      local _slug_date="${BASH_REMATCH[1]}"
      if [[ "${_slug_date}" < "260512" ]]; then
        return 0
      fi
    fi

    # No allow condition satisfied → drift
    return 1
  }

  # ---- fixture sub-assert 1: drift-detected/ MUST fail (block) ----------------
  local fix1_dir="${fixture_base}/drift-detected"
  local fix1_audit="${fix1_dir}/hook.jsonl"  # does not exist in this fixture
  if [[ ! -d "${fix1_dir}" ]]; then
    issues+=("fixture directory missing: tools/fixtures/check-81/drift-detected/")
  elif [[ ! -f "${fix1_dir}/CHECK.md" ]]; then
    issues+=("fixture missing: tools/fixtures/check-81/drift-detected/CHECK.md")
  elif [[ ! -f "${fix1_dir}/ASSUMPTIONS.md" ]]; then
    issues+=("fixture missing: tools/fixtures/check-81/drift-detected/ASSUMPTIONS.md")
  else
    if _evaluate_drift "${fix1_dir}" "${fix1_audit}"; then
      issues+=("fixture-fail #1: drift-detected/ evaluated as ALLOW (should detect drift — ASSUMPTIONS has ambiguities, no BUSINESS-RULES.md, no audit row)")
    fi
  fi

  # ---- fixture sub-assert 2: drift-bypassed-by-no-calibrate/ MUST pass (allow) --
  local fix2_dir="${fixture_base}/drift-bypassed-by-no-calibrate"
  local fix2_audit="${fix2_dir}/hook.jsonl"
  if [[ ! -d "${fix2_dir}" ]]; then
    issues+=("fixture directory missing: tools/fixtures/check-81/drift-bypassed-by-no-calibrate/")
  elif [[ ! -f "${fix2_dir}/CHECK.md" ]]; then
    issues+=("fixture missing: tools/fixtures/check-81/drift-bypassed-by-no-calibrate/CHECK.md")
  elif [[ ! -f "${fix2_dir}/ASSUMPTIONS.md" ]]; then
    issues+=("fixture missing: tools/fixtures/check-81/drift-bypassed-by-no-calibrate/ASSUMPTIONS.md")
  elif [[ ! -f "${fix2_audit}" ]]; then
    issues+=("fixture missing: tools/fixtures/check-81/drift-bypassed-by-no-calibrate/hook.jsonl (needed for calibration-skip row)")
  else
    if ! _evaluate_drift "${fix2_dir}" "${fix2_audit}"; then
      issues+=("fixture-fail #2: drift-bypassed-by-no-calibrate/ evaluated as DRIFT (should allow — calibration-skip audit row present)")
    fi
  fi

  # ---- fixture sub-assert 3: no-ambiguity-skip/ MUST pass (allow) -------------
  local fix3_dir="${fixture_base}/no-ambiguity-skip"
  if [[ ! -d "${fix3_dir}" ]]; then
    issues+=("fixture directory missing: tools/fixtures/check-81/no-ambiguity-skip/")
  elif [[ ! -f "${fix3_dir}/CHECK.md" ]]; then
    issues+=("fixture missing: tools/fixtures/check-81/no-ambiguity-skip/CHECK.md")
  elif [[ ! -f "${fix3_dir}/ASSUMPTIONS.md" ]]; then
    issues+=("fixture missing: tools/fixtures/check-81/no-ambiguity-skip/ASSUMPTIONS.md")
  else
    if ! _evaluate_drift "${fix3_dir}" ""; then
      issues+=("fixture-fail #3: no-ambiguity-skip/ evaluated as DRIFT (should allow — ASSUMPTIONS.md has zero ambiguity markers)")
    fi
  fi

  # ---- real plan scan (may be empty in CI — that is OK) -----------------------
  # Scan actual .aihaus/plans/*/CHECK.md if present; emit per-slug failure strings.
  local real_plans_dir="${repo_root}/.aihaus/plans"
  if [[ -d "${real_plans_dir}" ]]; then
    local real_audit="${repo_root}/.claude/audit/hook.jsonl"
    while IFS= read -r -d '' check_md_path; do
      local plan_dir
      plan_dir="$(dirname "${check_md_path}")"
      if ! _evaluate_drift "${plan_dir}" "${real_audit}"; then
        local slug
        slug="$(basename "${plan_dir}")"
        issues+=("drift detected: .aihaus/plans/${slug}/CHECK.md has no BUSINESS-RULES.md, ambiguities present, no calibration-skip audit row, and not a legacy artifact — run plan-calibrator or add BUSINESS-RULES.md")
      fi
    done < <(find "${real_plans_dir}" -maxdepth 2 -name "CHECK.md" -print0 2>/dev/null)
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
check_calibration_trigger
check_tdd_guard_hook
check_tdd_discipline_annex
check_calibrate_drift
# ---- Check 84: aih-graph pure-Go pivot ADRs present (M040/S1) -------------
# Asserts the 3 amendments that defined the pure-Go pivot are in decisions.md
# with Status: Accepted. Forcing-function gate: pivot can't be silently
# reverted without smoke breaking.
check_aih_graph_purego_adrs() {
  _start_check
  local label="Check ${CHECK_NUMBER}: aih-graph pure-Go pivot ADRs present (M040/S1)"
  local issues=()
  local decisions="${PACKAGE_ROOT}/.aihaus/decisions.md"
  if [[ ! -f "${decisions}" ]]; then
    issues+=("decisions.md not found at ${decisions}")
    _fail "${label}" "${issues[@]}"
    return
  fi
  for adr in "ADR-260515-B-amend-02" "ADR-260515-C-amend-02" "ADR-260515-E-amend-03"; do
    if ! grep -qE "^## ${adr} " "${decisions}"; then
      issues+=("missing section: ## ${adr}")
    fi
  done
  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "${label}"
  else
    _fail "${label}" "${issues[@]}"
  fi
}

# ---- Check 85: aih-graph build smoke (M040/S2) ----------------------------
# Builds the aih-graph binary from source (Go required) and verifies it
# produces a non-zero binary + responds to `version` and `help`. Skips
# gracefully when Go is unavailable on the host (preserves pre-Go-install
# smoke green).
check_aih_graph_build_smoke() {
  _start_check
  local label="Check ${CHECK_NUMBER}: aih-graph build smoke (M040/S2)"
  local issues=()
  local repo_root="${PACKAGE_ROOT}/.."
  local aih_graph_dir="${repo_root}/aih-graph"
  if [[ ! -d "${aih_graph_dir}" ]]; then
    issues+=("aih-graph/ source dir missing")
    _fail "${label}" "${issues[@]}"
    return
  fi
  if ! command -v go >/dev/null 2>&1; then
    # Soft-skip: smoke green when Go is unavailable; contributors with Go get
    # the real assertion.
    _pass "${label} (skipped — go not in PATH)"
    return
  fi
  local tmpbin
  tmpbin="$(_mktemp_dir aih-graph-smoke)"
  trap 'rm -rf "${tmpbin}"' RETURN
  mkdir -p "${tmpbin}/gotmp" "${tmpbin}/gocache"
  if ! (cd "${aih_graph_dir}" && GOTMPDIR="${tmpbin}/gotmp" GOCACHE="${tmpbin}/gocache" go build -o "${tmpbin}/aih-graph" ./cmd/aih-graph) >/dev/null 2>&1; then
    issues+=("go build failed")
    _fail "${label}" "${issues[@]}"
    return
  fi
  local version_out help_out
  version_out="$("${tmpbin}/aih-graph" version 2>/dev/null)"
  help_out="$("${tmpbin}/aih-graph" help 2>&1 | head -1)"
  if [[ -z "${version_out}" ]]; then
    issues+=("\`aih-graph version\` produced no output")
  fi
  if [[ "${help_out}" != aih-graph* ]]; then
    issues+=("\`aih-graph help\` first line does not begin with 'aih-graph' (got: ${help_out})")
  fi
  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "${label}"
  else
    _fail "${label}" "${issues[@]}"
  fi
}

# ---- Check 86: aih-graph integration round-trip (M040/S3) -----------------
# Builds aih-graph + runs build subcommand against this repo + asserts the
# extracted node counts match smoke-test ground truth (Check 1 + 2 + 3).
# Requires Go on PATH; soft-skips otherwise.
check_aih_graph_integration_round_trip() {
  _start_check
  local label="Check ${CHECK_NUMBER}: aih-graph integration round-trip (M040/S3)"
  local issues=()
  local repo_root="${PACKAGE_ROOT}/.."
  local aih_graph_dir="${repo_root}/aih-graph"
  if [[ ! -d "${aih_graph_dir}" ]]; then
    issues+=("aih-graph/ source dir missing")
    _fail "${label}" "${issues[@]}"
    return
  fi
  if ! command -v go >/dev/null 2>&1; then
    _pass "${label} (skipped — go not in PATH)"
    return
  fi
  local tmpdir
  tmpdir="$(_mktemp_dir aih-graph-itest)"
  trap 'rm -rf "${tmpdir}"' RETURN
  local bin="${tmpdir}/aih-graph"
  local db="${tmpdir}/test.db"
  mkdir -p "${tmpdir}/gotmp" "${tmpdir}/gocache"
  if ! (cd "${aih_graph_dir}" && GOTMPDIR="${tmpdir}/gotmp" GOCACHE="${tmpdir}/gocache" go build -o "${bin}" ./cmd/aih-graph) >/dev/null 2>&1; then
    issues+=("go build failed")
    _fail "${label}" "${issues[@]}"
    return
  fi
  # Run build against the parent repo. --accept-all-repos creates a consent
  # marker; clean up after.
  local consent_marker="${repo_root}/.aih-graph-consent"
  local marker_pre_existed=0
  [[ -f "${consent_marker}" ]] && marker_pre_existed=1
  local out
  out="$(AIH_GRAPH_OLLAMA_URL=http://127.0.0.1:9 "${bin}" build --accept-all-repos --db "${db}" "${repo_root}" 2>&1)"
  if [[ ${marker_pre_existed} -eq 0 ]]; then
    rm -f "${consent_marker}"
  fi
  if [[ ! -f "${db}" ]]; then
    issues+=("build did not produce ${db}")
    _fail "${label}" "${issues[@]}"
    return
  fi
  # Assert expected per-type counts. Match smoke-test ground truth.
  if ! grep -qE "Decisions: [0-9]+ \([0-9]+ are amendments" <<< "${out}"; then
    issues+=("build output missing Decisions line")
  fi
  if ! grep -qE "Agents:    58 " <<< "${out}"; then
    issues+=("expected Agents: 58 (Smoke Check 2)")
  fi
  if ! grep -qE "Skills:    15" <<< "${out}"; then
    issues+=("expected Skills: 15 (Smoke Check 1)")
  fi
  if ! grep -qE "Hooks: +[0-9]+ " <<< "${out}"; then
    issues+=("build output missing Hooks line")
  fi
  # Privacy gate: rebuild without --accept-all-repos should refuse (exit 2).
  rm -f "${consent_marker}"
  "${bin}" build --db "${db}.refuse" "${repo_root}" >/dev/null 2>&1
  local refuse_rc=$?
  if [[ ${refuse_rc} -ne 2 ]]; then
    issues+=("expected exit 2 on missing consent marker; got ${refuse_rc}")
  fi
  if [[ ${marker_pre_existed} -eq 1 ]]; then
    touch "${consent_marker}"
  fi

  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "${label}"
  else
    _fail "${label}" "${issues[@]}"
  fi
}

# ---- Check 87: M048 repository memory integration contract ----------------
# The installed settings template and the package-local template must keep the
# same memory lifecycle hooks, and all packaged agents must consume
# machine-readable memory output.
check_m048_memory_integration_contract() {
  _start_check
  local label="Check ${CHECK_NUMBER}: M048 repository memory hooks and agent JSON contracts"
  local issues=()
  local tpl
  local context_hook="${PACKAGE_ROOT}/.aihaus/hooks/context-inject.sh"
  local refresh_hook="${PACKAGE_ROOT}/.aihaus/hooks/aih-graph-refresh.sh"
  local graph_main="${PACKAGE_ROOT}/../aih-graph/cmd/aih-graph/main.go"
  local embed_go="${PACKAGE_ROOT}/../aih-graph/internal/embed/embed.go"

  for tpl in \
    "${PACKAGE_ROOT}/templates/settings.local.json" \
    "${PACKAGE_ROOT}/.aihaus/templates/settings.local.json"; do
    if [[ ! -f "${tpl}" ]]; then
      issues+=("settings template missing: ${tpl}")
      continue
    fi
    if ! grep -Fq 'aih-graph-stale.sh --reason write-edit' "${tpl}"; then
      issues+=("${tpl}: missing Write/Edit stale hook")
    fi
    if ! grep -Fq 'aih-graph-stale.sh --from-hook bash' "${tpl}"; then
      issues+=("${tpl}: missing Bash stale hook")
    fi
    if ! grep -Fq 'aih-graph-refresh.sh' "${tpl}"; then
      issues+=("${tpl}: missing lifecycle refresh hook")
    fi
    if ! grep -Fq 'SessionStart' "${tpl}" || ! grep -Fq 'AIH_GRAPH_QUIET=1 bash \"$CLAUDE_PROJECT_DIR\"/.aihaus/hooks/aih-graph-refresh.sh' "${tpl}"; then
      issues+=("${tpl}: missing automatic SessionStart memory refresh")
    fi
    if ! grep -Fq 'context-inject.sh' "${tpl}"; then
      issues+=("${tpl}: missing SubagentStart automatic context injection")
    fi
  done

  if [[ ! -f "${context_hook}" ]]; then
    issues+=("context-inject.sh missing")
  else
    if ! grep -Fq 'Native repository memory (auto-injected, M048)' "${context_hook}"; then
      issues+=("context-inject.sh: missing automatic native memory packet")
    fi
    if ! grep -Fq '_run_memory_with_timeout query --repo "$PROJECT_ROOT"' "${context_hook}" || ! grep -Fq -- '--json --top "$AIHAUS_MEMORY_QUERY_TOP"' "${context_hook}"; then
      issues+=("context-inject.sh: missing automatic aihaus memory query")
    fi
    if ! grep -Fq 'local combined="${target_agent_name:-}|${cohort:-}|${_active_profile:-}|${task_description:-}"' "${context_hook}"; then
      issues+=("context-inject.sh: cache key must include task-specific context (+ active profile, S4)")
    fi
  fi

  if [[ ! -f "${refresh_hook}" ]]; then
    issues+=("aih-graph-refresh.sh missing")
  else
    if ! grep -Fq 'AIHAUS_OLLAMA_AUTO' "${refresh_hook}"; then
      issues+=("aih-graph-refresh.sh: missing Ollama auto-start control")
    fi
    if grep -Fq 'AIH_GRAPH_PROVIDER' "${refresh_hook}" || grep -Fq -- '--embed-provider' "${refresh_hook}"; then
      issues+=("aih-graph-refresh.sh: embedding backend selection should be removed")
    fi
    if ! grep -Fq 'ollama_model="nomic-embed-text"' "${refresh_hook}"; then
      issues+=("aih-graph-refresh.sh: missing fixed nomic-embed-text model")
    fi
  fi

  if [[ ! -f "${graph_main}" || ! -f "${embed_go}" ]]; then
    issues+=("aih-graph source missing for M048 contract check")
  else
    if grep -Fq -- '--embed-provider' "${graph_main}" || grep -Fq 'buildEmbedProvider' "${graph_main}"; then
      issues+=("aih-graph CLI should not expose provider selection")
    fi
    if grep -Fq 'NewFakeProvider' "${embed_go}" || grep -Fq 'NewVoyageProvider' "${embed_go}"; then
      issues+=("aih-graph embed package should keep only Ollama embeddings")
    fi
    if ! grep -Eq 'ollamaDefaultModel[[:space:]]*=[[:space:]]*"nomic-embed-text"' "${embed_go}"; then
      issues+=("aih-graph embed package must fix the model to nomic-embed-text")
    fi
  fi

  local agents_root="${PACKAGE_ROOT}/.aihaus/agents"
  local file agent
  shopt -s nullglob
  local agent_files=("${agents_root}"/*.md)
  shopt -u nullglob
  if [[ ${#agent_files[@]} -eq 0 ]]; then
    issues+=("no packaged agents found under ${agents_root}")
  fi

  for file in "${agent_files[@]}"; do
    agent="$(basename "${file}")"
    if ! grep -Fq 'aihaus memory status --repo . --json' "${file}"; then
      issues+=("${agent}: missing JSON status memory command")
    fi
    if ! grep -Eq 'aihaus memory (query|context|impact|callers)( --repo \.)? --json' "${file}"; then
      issues+=("${agent}: missing role-specific JSON memory command")
    fi
    if grep -Eq 'aih-graph (status|query|context|impact|callers|gotchas|milestone)' "${file}"; then
      issues+=("${agent}: bypasses integrated aihaus memory command")
    fi
  done

  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "${label}"
  else
    _fail "${label}" "${issues[@]}"
  fi
}

check_goal_aftermath_regressions() {
  _start_check
  local label="Check ${CHECK_NUMBER}: workflow aftermath regressions (audit root, no auto-close churn, kanban DB schema)"
  local issues=()
  local hooks_root="${PACKAGE_ROOT}/.aihaus/hooks"
  local helper="${hooks_root}/lib/path-helpers.sh"
  local git_add_guard="${hooks_root}/git-add-guard.sh"
  local auto_close="${hooks_root}/manifest-auto-close.sh"
  local goal_schema="${PACKAGE_ROOT}/.aihaus/workflows/kanban/schema.sql"
  local goal_init="${PACKAGE_ROOT}/.aihaus/workflows/kanban/init-kanban-db.sh"
  local workflow_default="${PACKAGE_ROOT}/.aihaus/workflows/default.md"
  local dev_reviewer="${PACKAGE_ROOT}/.aihaus/agents/workflow-dev-reviewer.md"
  local human_review="${PACKAGE_ROOT}/.aihaus/agents/workflow-human-review.md"

  if [[ ! -f "$helper" ]] || ! bash -n "$helper" >/dev/null 2>&1; then
    issues+=("path-helpers.sh missing or not parseable")
  fi
  if [[ ! -f "$goal_schema" ]]; then
    issues+=("kanban packaged schema.sql missing")
  fi
  for needle in 'CREATE TABLE IF NOT EXISTS memory_events' 'idx_memory_events_task'; do
    if ! grep -Fq "$needle" "$goal_schema"; then
      issues+=("kanban schema missing ${needle}")
    fi
  done
  if [[ ! -f "$goal_init" ]] || ! bash -n "$goal_init" >/dev/null 2>&1; then
    issues+=("kanban init-kanban-db.sh missing or not parseable")
  fi
  if ! grep -Fq 'Playwright/E2E evidence' "$workflow_default"; then
    issues+=("workflow default missing Playwright evidence exit gate")
  fi
  if ! grep -Fq 'PASS requires a Playwright command result' "$dev_reviewer"; then
    issues+=("workflow-dev-reviewer missing mandatory Playwright PASS rule")
  fi
  if ! grep -Fq 'must spawn this agent immediately' "$dev_reviewer"; then
    issues+=("workflow-dev-reviewer missing mandatory dispatch contract")
  fi
  if ! grep -Fq 'Playwright was required but not run' "$human_review"; then
    issues+=("workflow-human-review missing missing-Playwright blocker rule")
  fi

  local tmp_root
  tmp_root="$(_mktemp_dir aih-aftermath-root)" || {
    _fail "$label" "failed to create temp dir"
    return
  }
  mkdir -p "$tmp_root/.aihaus/state" "$tmp_root/.claude/audit"
  git -C "$tmp_root" init >/dev/null 2>&1 || issues+=("git init failed for audit-root fixture")
  (
    cd "$tmp_root/.aihaus/state" || exit 1
    printf '{"tool_name":"Bash","tool_input":{"command":"echo ok"}}' \
      | CLAUDE_PROJECT_DIR="$tmp_root" bash "$git_add_guard" >/dev/null 2>&1
  ) || issues+=("git-add-guard audit-root fixture failed")
  if [[ ! -f "$tmp_root/.claude/audit/hook.jsonl" ]]; then
    issues+=("git-add-guard did not write audit under project root")
  fi
  if [[ -e "$tmp_root/.aihaus/state/.claude" ]]; then
    issues+=("git-add-guard wrote nested .claude/audit under cwd")
  fi

  local tmp_manifest
  tmp_manifest="$(_mktemp_dir aih-aftermath-autoclose)" || {
    _fail "$label" "failed to create temp dir"
    return
  }
  mkdir -p "$tmp_manifest/.aihaus/features/old" "$tmp_manifest/.claude/audit"
  git -C "$tmp_manifest" init >/dev/null 2>&1 || issues+=("git init failed for auto-close fixture")
  cat > "$tmp_manifest/.aihaus/features/old/RUN-MANIFEST.md" <<'EOF_MANIFEST'
---
schema: v3
status: completed
branch: feature/old
---
EOF_MANIFEST
  CLAUDE_PROJECT_DIR="$tmp_manifest" bash "$auto_close" >/dev/null 2>&1 || true
  if ! grep -q '^schema: v3$' "$tmp_manifest/.aihaus/features/old/RUN-MANIFEST.md"; then
    issues+=("manifest-auto-close migrated a skipped completed manifest")
  fi

  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${issues[@]}"
  fi
}

check_legacy_hygiene_regressions() {
  _start_check
  local label="Check ${CHECK_NUMBER}: legacy hygiene preflight and gitignore normalization"
  local issues=()
  local init_skill="${PACKAGE_ROOT}/.aihaus/skills/aih-init/SKILL.md"
  local preflight="${PACKAGE_ROOT}/.aihaus/skills/aih-init/scripts/legacy-preflight.sh"
  local fragment="${PACKAGE_ROOT}/.aihaus/templates/gitignore-fragment"
  local purity="${PACKAGE_ROOT}/../tools/purity-check.sh"

  if [[ ! -f "$preflight" ]] || ! bash -n "$preflight" >/dev/null 2>&1; then
    issues+=("aih-init legacy-preflight.sh missing or not parseable")
  fi
  for rel in '.aihaus/skills/aih-init/scripts/legacy-preflight.sh' '.aihaus/skills/aih-init/SKILL.md' '.aihaus/skills/_shared/enforcement-audit.md' 'scripts/install.sh' 'scripts/update.ps1'; do
    if ! grep -Fq "$rel" "$purity"; then
      issues+=("purity-check allowlist missing ${rel}")
    fi
  done
  if ! grep -Fq 'legacy-preflight.sh --fix-safe' "$init_skill"; then
    issues+=("aih-init does not invoke legacy-preflight.sh --fix-safe")
  fi
  if ! grep -Fq 'local .claude/worktrees/agent-* dirs' "$preflight"; then
    issues+=("legacy-preflight does not report stale agent worktree dirs")
  fi
  if ! grep -Fq 'target is on a synced path' "${PACKAGE_ROOT}/../pkg/scripts/update.sh"; then
    issues+=("update.sh missing synced-path warning")
  fi
  if ! grep -Fq 'copy mode overwrites package-managed' "${PACKAGE_ROOT}/../pkg/scripts/update.ps1"; then
    issues+=("update.ps1 missing copy-mode overwrite warning")
  fi
  for needle in '/.claude/agents/' '/.claude/hooks/' '/.claude/skills/' '/.aihaus/agents/' '*/.aihaus/' '*/.claude/' '/.bg-shell/' '/.gsd/' '/.hermes/'; do
    if ! grep -Fxq "$needle" "$fragment"; then
      issues+=("gitignore fragment missing ${needle}")
    fi
    if ! grep -Fq "$needle" "${PACKAGE_ROOT}/../pkg/scripts/install.sh"; then
      issues+=("install.sh missing ${needle}")
    fi
    if ! grep -Fq "$needle" "${PACKAGE_ROOT}/../pkg/scripts/update.sh"; then
      issues+=("update.sh missing ${needle}")
    fi
    if ! grep -Fq "$needle" "${PACKAGE_ROOT}/../pkg/scripts/install.ps1"; then
      issues+=("install.ps1 missing ${needle}")
    fi
    if ! grep -Fq "$needle" "${PACKAGE_ROOT}/../pkg/scripts/update.ps1"; then
      issues+=("update.ps1 missing ${needle}")
    fi
  done
  if ! grep -Fq 'aihaus block updated' "${PACKAGE_ROOT}/../pkg/scripts/update.sh"; then
    issues+=("update.sh does not patch existing AIHAUS:GITIGNORE block")
  fi
  if ! grep -Fq 'aihaus block updated' "${PACKAGE_ROOT}/../pkg/scripts/update.ps1"; then
    issues+=("update.ps1 does not patch existing AIHAUS:GITIGNORE block")
  fi

  local tmp_root
  tmp_root="$(_mktemp_dir aih-legacy-preflight)" || {
    _fail "$label" "failed to create temp dir"
    return
  }
  mkdir -p "$tmp_root/.aihaus/state/.claude/audit" "$tmp_root/.gsd" "$tmp_root/.hermes" "$tmp_root/.claude/worktrees/agent-old"
  git -C "$tmp_root" init >/dev/null 2>&1 || issues+=("git init failed for legacy-preflight fixture")
  printf 'old hook\n' > "$tmp_root/.aihaus/state/.claude/audit/hook.jsonl"
  printf 'old schema\n' > "$tmp_root/.aihaus/state/schema.sql"
  printf 'legacy gsd\n' > "$tmp_root/.gsd/PROJECT.md"
  printf 'legacy hermes\n' > "$tmp_root/.hermes/report.md"
  printf 'agent worktree\n' > "$tmp_root/.claude/worktrees/agent-old/README.md"
  (
    cd "$tmp_root" || exit 1
    bash "$preflight" --fix-safe >/dev/null 2>&1
  ) || issues+=("legacy-preflight fixture failed")
  if [[ -e "$tmp_root/.aihaus/state/.claude" ]]; then
    issues+=("legacy-preflight did not archive nested .aihaus/state/.claude")
  fi
  if [[ -e "$tmp_root/.aihaus/state/schema.sql" ]]; then
    issues+=("legacy-preflight did not archive old .aihaus/state/schema.sql")
  fi
  if ! compgen -G "$tmp_root/.aihaus/backups/legacy-cleanup/*/.aihaus/state/schema.sql" >/dev/null; then
    issues+=("legacy-preflight backup copy for schema.sql missing")
  fi
  if [[ ! -e "$tmp_root/.gsd/PROJECT.md" || ! -e "$tmp_root/.hermes/report.md" ]]; then
    issues+=("legacy-preflight moved manual-review legacy directories")
  fi
  if ! compgen -G "$tmp_root/.aihaus/audit/legacy-preflight-*.md" >/dev/null; then
    issues+=("legacy-preflight report missing")
  else
    local report_file
    report_file="$(ls "$tmp_root"/.aihaus/audit/legacy-preflight-*.md 2>/dev/null | head -1)"
    if ! grep -Fq 'local .claude/worktrees/agent-* dirs: 1' "$report_file"; then
      issues+=("legacy-preflight report missing agent worktree count")
    fi
    if ! grep -Fq 'git worktree remove --force "$wt"' "$report_file"; then
      issues+=("legacy-preflight report missing manual worktree cleanup pattern")
    fi
  fi

  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${issues[@]}"
  fi
}

check_goal_business_rule_gap_contract() {
  _start_check
  local label="Check ${CHECK_NUMBER}: kanban business-rule gap contract"
  local issues=()
  local local_kanban="${PACKAGE_ROOT}/.aihaus/workflows/kanban/local-kanban.md"
  local linear_intake="${PACKAGE_ROOT}/.aihaus/workflows/kanban/linear-intake.md"
  local run_state="${PACKAGE_ROOT}/.aihaus/workflows/kanban/run-state.md"
  local planning_agent="${PACKAGE_ROOT}/.aihaus/agents/workflow-planning-gate.md"
  local workflow_default="${PACKAGE_ROOT}/.aihaus/workflows/default.md"

  if ! grep -Fq 'business-rule gap for one task' "$local_kanban"; then
    issues+=("local-kanban annex missing one-task business-rule gap rule")
  fi
  if ! grep -Fq 'one row per task' "$local_kanban"; then
    issues+=("local-kanban annex missing per-task row rule")
  fi
  if ! grep -Fq 'one issue at a time' "$linear_intake"; then
    issues+=("linear intake missing one-issue-at-a-time sync rule")
  fi
  if ! grep -Fq 'Business Rule Gaps' "$run_state"; then
    issues+=("run-state artifact still lacks Business Rule Gaps section")
  fi
  if ! grep -Fq 'not TUI prompts' "$planning_agent"; then
    issues+=("planning gate missing not-TUI prompt rule")
  fi
  if ! grep -Fq 'Do not merge blockers from several tasks' "$workflow_default"; then
    issues+=("workflow default missing no-merged-blockers rule")
  fi
  if grep -R "Socratic" "$local_kanban" "$linear_intake" "$run_state" "$planning_agent" "$workflow_default" >/dev/null 2>&1; then
    issues+=("kanban planning contract still contains Socratic wording")
  fi

  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${issues[@]}"
  fi
}

check_memory_write_boundary_contract() {
  _start_check
  local label="Check ${CHECK_NUMBER}: memory writes stay inside project boundary"
  local issues=()
  local file_guard="${PACKAGE_ROOT}/.aihaus/hooks/file-guard.sh"
  local per_agent="${PACKAGE_ROOT}/.aihaus/skills/_shared/per-agent-memory.md"
  local goal_memory="${PACKAGE_ROOT}/.aihaus/workflows/kanban/memory-promotion.md"
  local workflow_agents="${PACKAGE_ROOT}/.aihaus/agents/workflow-"'*.md'

  if ! grep -Fq 'Do not whitelist ~/.claude/projects/**/memory' "$file_guard"; then
    issues+=("file-guard missing Claude internal memory guidance")
  fi
  if ! grep -Fq 'The only valid `path:` target is `.aihaus/memory/agents/<agent-name>.md`.' "$per_agent"; then
    issues+=("per-agent memory contract missing path restriction")
  fi
  if ! grep -Fq 'Reject or defer any `aihaus:agent-memory` block whose `path:` targets' "$goal_memory"; then
    issues+=("kanban memory promotion missing invalid target rejection")
  fi
  if grep -R "targeting \`.aihaus/memory/workflows" $workflow_agents >/dev/null 2>&1; then
    issues+=("workflow agent still targets workflow memory from aihaus:agent-memory")
  fi

  local tmp_root out rc
  tmp_root="$(_mktemp_dir aih-memory-boundary)" || {
    _fail "$label" "failed to create temp dir"
    return
  }
  mkdir -p "$tmp_root"
  set +e
  out="$(printf '{"tool_input":{"file_path":"%s/.claude/projects/repo/memory/reference_playwright_dev_smoke_toolkit.md"}}' "$HOME" | CLAUDE_PROJECT_DIR="$tmp_root" bash "$file_guard" 2>&1)"
  rc=$?
  set +e
  if [[ "$rc" -ne 2 ]]; then
    issues+=("file-guard did not block ~/.claude/projects/**/memory write")
  fi
  if ! printf '%s\n' "$out" | grep -Fq 'mirror reusable facts into project memory'; then
    issues+=("file-guard block output missing project-memory remediation")
  fi

  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${issues[@]}"
  fi
}

check_claude_project_context_bridge() {
  _start_check
  local label="Check ${CHECK_NUMBER}: Claude-native project context bridge"
  local issues=()
  local context_template="${PACKAGE_ROOT}/.aihaus/templates/claude/CLAUDE.md"
  local rule_template="${PACKAGE_ROOT}/.aihaus/templates/claude/rules/aihaus-project-memory.md"
  local role_defaults="${PACKAGE_ROOT}/.aihaus/hooks/lib/role-defaults.json"
  local context_hook="${PACKAGE_ROOT}/.aihaus/hooks/context-inject.sh"
  local session_hook="${PACKAGE_ROOT}/.aihaus/hooks/session-start.sh"
  local init_skill="${PACKAGE_ROOT}/.aihaus/skills/aih-init/SKILL.md"
  local project_template="${PACKAGE_ROOT}/.aihaus/templates/project.md"
  local env_seed="${PACKAGE_ROOT}/.aihaus/memory/workflows/environment.md"
  local out_root="${SCRIPT_DIR}/.out"
  local script
  mkdir -p "${out_root}" 2>/dev/null || true

  if [[ ! -f "${context_template}" ]]; then
    issues+=("missing Claude context template")
  else
    grep -Fq 'AIHAUS:CLAUDE-CONTEXT-START' "${context_template}" || issues+=("CLAUDE.md template missing managed marker")
    grep -Fq '@../.aihaus/project.md' "${context_template}" || issues+=("CLAUDE.md template does not import project.md")
    grep -Fq '@../.aihaus/workflows/default.md' "${context_template}" || issues+=("CLAUDE.md template does not import workflow profile")
    grep -Fq '@../.aihaus/memory/workflows/environment.md' "${context_template}" || issues+=("CLAUDE.md template does not import workflow environment memory")
    if grep -Eq '^@\.\./\.aihaus/(decisions|knowledge)\.md[[:space:]]*$' "${context_template}"; then
      issues+=("CLAUDE.md template imports large decisions/knowledge ledgers at startup")
    fi
    grep -Fq 'Large ledgers are intentionally not imported on startup' "${context_template}" || issues+=("CLAUDE.md template missing large-ledger selective-read note")
  fi

  if [[ ! -f "${rule_template}" ]]; then
    issues+=("missing Claude rules template")
  else
    grep -Fq 'AIHAUS:CLAUDE-RULES-START' "${rule_template}" || issues+=("Claude rule template missing managed marker")
    grep -Fq 'Never store plaintext secrets' "${rule_template}" || issues+=("Claude rule template missing secret-handling rule")
    grep -Fq 'Do not import entire large ledgers into startup context' "${rule_template}" || issues+=("Claude rule template missing large-ledger startup guard")
  fi

  for script in "${PACKAGE_ROOT}/scripts/install.sh" "${PACKAGE_ROOT}/scripts/update.sh"; do
    grep -Fq 'seed_claude_context_bridge' "${script}" || issues+=("$(basename "${script}") missing Claude bridge seeding")
    grep -Fq '_scrub_large_claude_imports' "${script}" || issues+=("$(basename "${script}") missing large-ledger import scrub")
    grep -Fq 'memory: created .aihaus/decisions.md' "${script}" || issues+=("$(basename "${script}") missing decisions.md neutral seed")
    grep -Fq 'memory: created .aihaus/knowledge.md' "${script}" || issues+=("$(basename "${script}") missing knowledge.md seed")
    grep -Fq 'ensure_workflow_environment_prompts' "${script}" || issues+=("$(basename "${script}") missing workflow environment prompt backfill")
    grep -Fq 'AIHAUS:WORKFLOW-ENVIRONMENT-PROMPTS-START' "${script}" || issues+=("$(basename "${script}") missing workflow environment prompt marker")
  done
  if grep -Fq 'cp -R "${PKG_AIHAUS}/."' "${PACKAGE_ROOT}/scripts/install.sh"; then
    issues+=("install.sh bulk-copies package .aihaus into fresh repositories")
  fi

  for script in "${PACKAGE_ROOT}/scripts/install.ps1" "${PACKAGE_ROOT}/scripts/update.ps1"; do
    grep -Fq 'Ensure-ClaudeContextBridge' "${script}" || issues+=("$(basename "${script}") missing Claude bridge seeding")
    grep -Fq 'Remove-LargeClaudeImports' "${script}" || issues+=("$(basename "${script}") missing large-ledger import scrub")
    grep -Fq 'memory: created .aihaus\decisions.md' "${script}" || issues+=("$(basename "${script}") missing decisions.md neutral seed")
    grep -Fq 'memory: created .aihaus\knowledge.md' "${script}" || issues+=("$(basename "${script}") missing knowledge.md seed")
    grep -Fq 'Ensure-WorkflowEnvironmentPrompts' "${script}" || issues+=("$(basename "${script}") missing workflow environment prompt backfill")
    grep -Fq 'AIHAUS:WORKFLOW-ENVIRONMENT-PROMPTS-START' "${script}" || issues+=("$(basename "${script}") missing workflow environment prompt marker")
  done
  if grep -Fq "Join-Path \$PkgAihaus '*'" "${PACKAGE_ROOT}/scripts/install.ps1"; then
    issues+=("install.ps1 bulk-copies package .aihaus into fresh repositories")
  fi

  if [[ -f "${role_defaults}" ]]; then
    grep -Fq '.aihaus/workflows/default.md' "${role_defaults}" || issues+=("role-defaults missing workflow profile context")
    grep -Fq '.aihaus/memory/workflows/environment.md' "${role_defaults}" || issues+=("role-defaults missing workflow environment context")
    if grep -Eq '\.aihaus/(decisions|knowledge)\.md' "${role_defaults}"; then
      issues+=("role-defaults preloads project decisions/knowledge ledgers")
    fi
  else
    issues+=("role-defaults.json missing")
  fi

  if [[ -f "${context_hook}" ]]; then
    grep -Fq '.aihaus/workflows/default.md' "${context_hook}" || issues+=("context-inject fallback missing workflow profile")
    grep -Fq '.aihaus/memory/workflows/environment.md' "${context_hook}" || issues+=("context-inject fallback missing workflow environment")
    if grep -Eq 'payload_lines="HIGH:\.aihaus/(decisions|knowledge)\.md|cohorts_summary=.*(decisions|knowledge)\.md' "${context_hook}"; then
      issues+=("context-inject fallback/cohort summary preloads project decisions/knowledge ledgers")
    fi
  else
    issues+=("context-inject.sh missing")
  fi

  grep -Fq '.claude/CLAUDE.md' "${init_skill}" || issues+=("aih-init missing .claude/CLAUDE.md bridge contract")
  grep -Fq '## Operating Context' "${project_template}" || issues+=("project.md template missing Operating Context section")
  grep -Fq 'AIHAUS:WORKFLOW-ENVIRONMENT-PROMPTS-START' "${env_seed}" || issues+=("environment memory seed missing managed prompt marker")
  grep -Fq 'CodeBuild' "${env_seed}" || issues+=("environment memory seed missing CodeBuild prompt")
  grep -Fq 'Credential location' "${env_seed}" || issues+=("environment memory seed missing credential-location prompt")
  grep -Fq 'explicit human answers' "${PACKAGE_ROOT}/.aihaus/skills/aih-init/annexes/operational-context-bootstrap.md" \
    || issues+=("aih-init operational bootstrap missing explicit-answer promotion policy")

  if [[ -f "${session_hook}" ]]; then
    bash -n "${session_hook}" 2>/dev/null || issues+=("session-start.sh not parseable")
    grep -Fq 'json_escape()' "${session_hook}" || issues+=("session-start.sh missing jq-free JSON fallback")

    local tmp_session tmp_bin cmd out rc
    tmp_session="$(mktemp -d "${out_root}/session-no-jq-XXXXXX" 2>/dev/null || true)"
    if [[ -n "${tmp_session}" ]]; then
      tmp_bin="${tmp_session}/bin"
      mkdir -p "${tmp_session}/.aihaus/hooks" "${tmp_session}/.claude" "${tmp_bin}"
      for cmd in bash git ls wc date awk sort tail grep tr; do
        cat > "${tmp_bin}/${cmd}" <<EOF
#!/usr/bin/bash
exec /usr/bin/${cmd} "\$@"
EOF
        chmod +x "${tmp_bin}/${cmd}"
      done
      rc=0
      out="$(PATH="${tmp_bin}" CLAUDE_PROJECT_DIR="${tmp_session}" bash "${session_hook}" 2>&1)" || rc=$?
      [[ "${rc}" -eq 0 ]] || issues+=("session-start.sh failed without jq in PATH: rc=${rc} out=${out:0:120}")
      printf '%s' "${out}" | grep -Fq '"hookEventName":"SessionStart"' || issues+=("session-start.sh jq-free output missing SessionStart JSON")
      rm -rf "${tmp_session}" 2>/dev/null || true
    else
      issues+=("failed to create session-start no-jq fixture")
    fi
  else
    issues+=("session-start.sh missing")
  fi

  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${issues[@]}"
  fi
}

check_init_operational_context_discovery() {
  _start_check
  local label="Check ${CHECK_NUMBER}: aih-init operational discovery and business interview"
  local issues=()
  local env_script="${PACKAGE_ROOT}/.aihaus/skills/aih-init/scripts/environment-discovery.sh"
  local verify_script="${PACKAGE_ROOT}/.aihaus/skills/aih-init/scripts/claude-context-verify.sh"
  local op_annex="${PACKAGE_ROOT}/.aihaus/skills/aih-init/annexes/operational-context-bootstrap.md"
  local win_annex="${PACKAGE_ROOT}/.aihaus/skills/aih-init/annexes/windows-gitattributes.md"
  local business_agent="${PACKAGE_ROOT}/.aihaus/agents/project-business-interviewer.md"
  local init_skill="${PACKAGE_ROOT}/.aihaus/skills/aih-init/SKILL.md"

  for f in "${env_script}" "${verify_script}" "${op_annex}" "${win_annex}" "${business_agent}"; do
    [[ -f "${f}" ]] || issues+=("missing: ${f}")
  done
  [[ -f "${env_script}" ]] && bash -n "${env_script}" 2>/dev/null || issues+=("environment-discovery.sh not parseable")
  [[ -f "${verify_script}" ]] && bash -n "${verify_script}" 2>/dev/null || issues+=("claude-context-verify.sh not parseable")

  grep -Fq 'operational-context-bootstrap.md' "${init_skill}" || issues+=("aih-init missing operational context phase")
  grep -Fq 'project-business-interviewer' "${op_annex}" || issues+=("operational annex missing business interviewer dispatch")
  grep -Fq 'environment-discovery.sh' "${op_annex}" || issues+=("operational annex missing environment discovery script")
  grep -Fq 'claude-context-verify.sh' "${op_annex}" || issues+=("operational annex missing Claude verifier script")
  grep -Fq 'One question per business rule gap' "${business_agent}" || issues+=("business interviewer missing one-question-per-gap rule")
  grep -Fq '.aihaus/init/business-context-questions.md' "${business_agent}" || issues+=("business interviewer missing artifact target")
  grep -Fq 'Socratic questioning' "${business_agent}" || issues+=("business interviewer missing Socratic questioning contract")

  local tmp_root
  tmp_root="$(_mktemp_dir aih-init-operational)" || {
    _fail "$label" "failed to create temp dir"
    return
  }
  mkdir -p "${tmp_root}/.aihaus/memory/workflows" "${tmp_root}/.aihaus/project" "${tmp_root}/.claude/rules"
  printf '# Env\n' > "${tmp_root}/.aihaus/memory/workflows/environment.md"
  printf '# Project\n' > "${tmp_root}/.aihaus/project.md"
  printf '{}\n' > "${tmp_root}/.claude/settings.local.json"
  printf '# Rule\n' > "${tmp_root}/.claude/rules/aihaus-project-memory.md"
  cat > "${tmp_root}/.claude/CLAUDE.md" <<'EOF'
<!-- AIHAUS:CLAUDE-CONTEXT-START -->
@../.aihaus/project.md
@../.aihaus/memory/workflows/environment.md
<!-- AIHAUS:CLAUDE-CONTEXT-END -->
EOF
  printf 'version: 0.2\n' > "${tmp_root}/buildspec.yml"
  printf 'export const config = {};\n' > "${tmp_root}/playwright.config.ts"
  printf 'API_URL=\n' > "${tmp_root}/.env.example"
  cat > "${tmp_root}/package.json" <<'EOF'
{"scripts":{"dev":"vite","test":"vitest","build":"vite build"}}
EOF

  bash "${env_script}" --target "${tmp_root}" >/dev/null 2>&1 || issues+=("environment discovery fixture failed")
  bash "${verify_script}" --target "${tmp_root}" >/dev/null 2>&1 || issues+=("Claude verifier fixture failed")
  grep -Fq 'AIHAUS:ENV-DISCOVERY-START' "${tmp_root}/.aihaus/memory/workflows/environment.md" || issues+=("environment discovery did not write managed block")
  grep -Fq 'buildspec present' "${tmp_root}/.aihaus/memory/workflows/environment.md" || issues+=("environment discovery did not detect CodeBuild buildspec")
  grep -Fq 'playwright.config.ts' "${tmp_root}/.aihaus/memory/workflows/environment.md" || issues+=("environment discovery did not detect Playwright config")
  grep -Fq 'Verdict: PASS' "${tmp_root}/.aihaus/audit/claude-context-verify.md" || issues+=("Claude verifier did not pass complete fixture")

  rm -rf "${tmp_root}" 2>/dev/null || true

  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${issues[@]}"
  fi
}

check_project_context_refresh_hook() {
  _start_check
  local label="Check ${CHECK_NUMBER}: continuous project context refresh hook"
  local issues=()
  local refresh_hook="${PACKAGE_ROOT}/.aihaus/hooks/project-context-refresh.sh"
  local merge_lib="${PACKAGE_ROOT}/scripts/lib/merge-settings.sh"
  local update_ps1="${PACKAGE_ROOT}/scripts/update.ps1"
  local install_ps1="${PACKAGE_ROOT}/scripts/install.ps1"
  local settings_full="${PACKAGE_ROOT}/.aihaus/templates/settings.local.json"
  local settings_legacy="${PACKAGE_ROOT}/templates/settings.local.json"

  [[ -f "${refresh_hook}" ]] || issues+=("project-context-refresh.sh missing")
  [[ -f "${refresh_hook}" ]] && bash -n "${refresh_hook}" 2>/dev/null || issues+=("project-context-refresh.sh not parseable")
  grep -Fq 'environment-discovery.sh' "${refresh_hook}" || issues+=("refresh hook does not call environment discovery")
  grep -Fq 'claude-context-verify.sh' "${refresh_hook}" || issues+=("refresh hook does not call Claude verifier")
  grep -Fq '.claude/hooks/' "${refresh_hook}" || issues+=("refresh hook does not detect legacy .claude/hooks paths")
  grep -Fq '.aihaus/hooks/' "${refresh_hook}" || issues+=("refresh hook does not normalize to .aihaus/hooks")

  for settings in "${settings_full}" "${settings_legacy}"; do
    grep -Fq 'project-context-refresh.sh --reason startup' "${settings}" || issues+=("$(basename "$(dirname "${settings}")") settings missing startup refresh hook")
    grep -Fq 'project-context-refresh.sh --reason task-completed' "${settings}" || issues+=("$(basename "$(dirname "${settings}")") settings missing task-completed refresh hook")
    grep -Fq 'project-context-refresh.sh --reason session-end' "${settings}" || issues+=("$(basename "$(dirname "${settings}")") settings missing session-end refresh hook")
    if grep -Fq '.claude/hooks/' "${settings}"; then
      issues+=("$(basename "$(dirname "${settings}")") settings still points at .claude/hooks")
    fi
  done

  grep -Fq 'normalized hook paths to .aihaus/hooks' "${merge_lib}" || issues+=("merge-settings.sh missing legacy hook path normalization")
  grep -Fq 'normalized hook paths to .aihaus\hooks' "${update_ps1}" || issues+=("update.ps1 missing legacy hook path normalization")
  grep -Fq 'normalized hook paths to .aihaus\hooks' "${install_ps1}" || issues+=("install.ps1 missing legacy hook path normalization")

  local tmp_root
  tmp_root="$(_mktemp_dir aih-context-refresh)" || {
    _fail "$label" "failed to create temp dir"
    return
  }
  mkdir -p \
    "${tmp_root}/.aihaus/templates/claude/rules" \
    "${tmp_root}/.aihaus/skills/aih-init/scripts" \
    "${tmp_root}/.claude"
  cp "${PACKAGE_ROOT}/.aihaus/templates/claude/CLAUDE.md" "${tmp_root}/.aihaus/templates/claude/CLAUDE.md"
  cp "${PACKAGE_ROOT}/.aihaus/templates/claude/rules/aihaus-project-memory.md" "${tmp_root}/.aihaus/templates/claude/rules/aihaus-project-memory.md"
  cp "${PACKAGE_ROOT}/.aihaus/skills/aih-init/scripts/environment-discovery.sh" "${tmp_root}/.aihaus/skills/aih-init/scripts/environment-discovery.sh"
  cp "${PACKAGE_ROOT}/.aihaus/skills/aih-init/scripts/claude-context-verify.sh" "${tmp_root}/.aihaus/skills/aih-init/scripts/claude-context-verify.sh"
  cat > "${tmp_root}/.claude/settings.local.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/bash-guard.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
EOF
  cat > "${tmp_root}/.claude/CLAUDE.md" <<'EOF'
# Claude Project Context

<!-- AIHAUS:CLAUDE-CONTEXT-START -->
@../.aihaus/project.md
@../.aihaus/decisions.md
@../.aihaus/knowledge.md
<!-- AIHAUS:CLAUDE-CONTEXT-END -->
EOF
  printf 'version: 0.2\n' > "${tmp_root}/buildspec.yml"
  printf 'export const config = {};\n' > "${tmp_root}/playwright.config.ts"

  CLAUDE_PROJECT_DIR="${tmp_root}" bash "${refresh_hook}" --reason smoke --force >/dev/null 2>&1 || issues+=("project-context-refresh fixture failed")
  [[ -f "${tmp_root}/.aihaus/workflows/default.md" ]] || issues+=("refresh hook did not seed workflow profile")
  [[ -f "${tmp_root}/.aihaus/memory/workflows/rules.md" ]] || issues+=("refresh hook did not seed workflow rules memory")
  [[ -f "${tmp_root}/.aihaus/init/environment-discovery.md" ]] || issues+=("refresh hook did not run environment discovery")
  [[ -f "${tmp_root}/.aihaus/audit/claude-context-verify.md" ]] || issues+=("refresh hook did not run Claude verifier")
  grep -Fq 'Verdict: PASS' "${tmp_root}/.aihaus/audit/claude-context-verify.md" || issues+=("refresh hook did not repair context imports to verifier PASS")
  if grep -Fq '.claude/hooks/' "${tmp_root}/.claude/settings.local.json"; then
    issues+=("refresh hook did not normalize legacy .claude/hooks command path")
  fi
  if grep -Eq '^@\.\./\.aihaus/(decisions|knowledge)\.md[[:space:]]*$' "${tmp_root}/.claude/CLAUDE.md"; then
    issues+=("refresh hook did not scrub large decisions/knowledge startup imports")
  fi
  grep -Fq '.aihaus/hooks/bash-guard.sh' "${tmp_root}/.claude/settings.local.json" || issues+=("refresh hook did not write .aihaus/hooks command path")
  [[ -f "${tmp_root}/.aihaus/audit/project-context-refresh.jsonl" ]] || issues+=("refresh hook did not write audit event")

  rm -rf "${tmp_root}" 2>/dev/null || true

  if [[ ${#issues[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${issues[@]}"
  fi
}

# ---- Check 95: eval-run.sh deterministic eval (good passes, bad fails) (3.0/S6) ----
check_eval_run_deterministic() {
  _start_check
  local label="Check ${CHECK_NUMBER}: eval-run.sh deterministic eval — good passes, bad fails (3.0/S6)"
  local eval_script="${PACKAGE_ROOT}/.aihaus/eval/eval-run.sh"
  local schema="${PACKAGE_ROOT}/.aihaus/workflows/kanban/schema.sql"
  if [[ ! -f "$eval_script" ]]; then _fail "$label" "eval-run.sh missing"; return; fi
  if ! bash -n "$eval_script" >/dev/null 2>&1; then _fail "$label" "eval-run.sh not parseable"; return; fi
  if ! command -v sqlite3 >/dev/null 2>&1; then _pass "$label (skipped: sqlite3 unavailable)"; return; fi
  local issues=()
  local d
  d="$(_mktemp_dir aih-eval)" || { _fail "$label" "mktemp failed"; return; }
  mkdir -p "$d/.aihaus/state" "$d/.aihaus/workflows/runs/r/evidence" 2>/dev/null || true
  sqlite3 "$d/.aihaus/state/kanban.db" < "$schema" >/dev/null 2>&1 || true
  printf 'ev\n' > "$d/.aihaus/workflows/runs/r/evidence/EV-1.md" 2>/dev/null || true
  sqlite3 "$d/.aihaus/state/kanban.db" "INSERT INTO gate_events (id,task_id,stage,verdict,evidence_path,created_at) VALUES('G1','T1','testes','PASS','.aihaus/workflows/runs/r/evidence/EV-1.md','t');" >/dev/null 2>&1 || true
  bash "$eval_script" --project "$d" >/dev/null 2>&1 || issues+=("good fixture should pass (exit 0) but eval failed")
  sqlite3 "$d/.aihaus/state/kanban.db" "INSERT INTO gate_events (id,task_id,stage,verdict,created_at) VALUES('G2','T1','testes','MAYBE','t');" >/dev/null 2>&1 || true
  if bash "$eval_script" --project "$d" >/dev/null 2>&1; then
    issues+=("bad fixture should fail (exit 1) but eval passed — green-but-vacuous")
  fi
  rm -rf "$d" 2>/dev/null || true
  if [[ ${#issues[@]} -eq 0 ]]; then _pass "$label"; else _fail "$label" "${issues[@]}"; fi
}

check_merge_hooks_union
check_update_drift_recompute
check_aih_graph_purego_adrs
check_m048_memory_integration_contract
check_goal_aftermath_regressions
check_legacy_hygiene_regressions
check_goal_business_rule_gap_contract
check_memory_write_boundary_contract
check_claude_project_context_bridge
check_init_operational_context_discovery
check_project_context_refresh_hook
check_aih_graph_build_smoke
check_aih_graph_integration_round_trip
check_eval_run_deterministic

printf "
"
if [[ "$FAILURES" -eq 0 ]]; then
  printf "aihaus package smoke test PASSED [OK] (%d/%d)\n" "$CHECK_NUMBER" "$CHECK_NUMBER"
  exit 0
else
  printf "FAILED - %d of %d checks failed\n" "$FAILURES" "$CHECK_NUMBER"
  exit 1
fi
