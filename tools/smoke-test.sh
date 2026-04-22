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

# ---- Check 1: 13 expected SKILL.md files in expected subdirectories ---------
check_skills() {
  _start_check
  local label="Check ${CHECK_NUMBER}: .aihaus/skills/ has 13 expected SKILL.md files"
  local expected=(aih-init aih-plan aih-bugfix aih-feature aih-milestone aih-help aih-quick aih-sync-notion aih-update aih-resume aih-brainstorm aih-effort aih-automode)
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

# ---- Check 3: .aihaus/hooks/ has 22 .sh files (M014/S08 adds worktree-reconcile) --
check_hooks() {
  _start_check
  local label="Check ${CHECK_NUMBER}: .aihaus/hooks/ has 22 .sh files"
  local hooks_root="${PACKAGE_ROOT}/.aihaus/hooks"
  if [[ ! -d "$hooks_root" ]]; then
    _fail "$label" "directory not found: $hooks_root"
    return
  fi
  # maxdepth 1 excludes hooks/lib/ (M011/S01 shared helpers library).
  local count
  count=$(find "$hooks_root" -maxdepth 1 -type f -name '*.sh' | wc -l | tr -d ' ')
  if [[ "$count" -eq 22 ]]; then
    _pass "$label"
  else
    _fail "$label" "expected 22 .sh files, found $count"
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

# ---- Check 9: settings.local.json is valid JSON with _aihaus_managed -------
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
      if ! jq -e '.permissions and .hooks and .env' "$settings_file" >/dev/null 2>&1; then
        _fail "$label" "invalid JSON or missing permissions/hooks/env keys"
        return
      fi
      ;;
    python3|python|py)
      if ! "$parser" -c "import json,sys; d=json.load(open(sys.argv[1], encoding='utf-8')); sys.exit(0 if all(k in d for k in ('permissions','hooks','env')) else 1)" "$settings_file" >/dev/null 2>&1; then
        _fail "$label" "invalid JSON or missing permissions/hooks/env keys"
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

# ---- Template permissions.allow has a wildcard Bash entry -------------------
# Locks in the autonomy contract: template must ship with wildcard-capable
# permissions so execution phase doesn't fall through to interactive prompts.
# Regex match (Bash\(.*\)) accepts "Bash(*)", "Bash(.*)", or future
# normalizations — not brittle on the literal string.
check_template_bash_wildcard() {
  _start_check
  local label="Check ${CHECK_NUMBER}: template permissions.allow has a wildcard Bash entry"
  local tpl="${PACKAGE_ROOT}/.aihaus/templates/settings.local.json"
  [[ -f "$tpl" ]] || { _fail "$label" "template missing: $tpl"; return; }
  if grep -Eq '"Bash\(.*\)"' "$tpl"; then
    _pass "$label"
  else
    _fail "$label" "no Bash(<wildcard>) entry found in $tpl permissions.allow"
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

# ---- auto-approve-bash.sh allows expected safe patterns ---------------------
# Feeds each expanded SAFE_PATTERN through the hook with a synthetic JSON
# input and asserts allow-decision JSON comes back. Regression gate against
# accidental SAFE_PATTERNS removal.
check_auto_approve_patterns() {
  _start_check
  local label="Check ${CHECK_NUMBER}: auto-approve-bash allows expected safe patterns"
  local hook="${PACKAGE_ROOT}/.aihaus/hooks/auto-approve-bash.sh"
  [[ -f "$hook" ]] || { _fail "$label" "hook missing: $hook"; return; }
  local patterns=("printf hello" "env" "tree ." "type ls" "tee file" "cut -f1 file" "tr a b" "seq 1 3")
  local failed=()
  for cmd in "${patterns[@]}"; do
    local out
    out=$(printf '{"tool_input":{"command":"%s"}}' "$cmd" | bash "$hook" 2>/dev/null || true)
    if ! echo "$out" | grep -q '"behavior":[[:space:]]*"allow"'; then
      failed+=("$cmd")
    fi
  done
  if [[ ${#failed[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "did not approve: ${failed[*]}"
  fi
}

# ---- Template PermissionRequest hooks reference auto-approve scripts --------
check_template_permission_hooks() {
  _start_check
  local label="Check ${CHECK_NUMBER}: template PermissionRequest hooks reference auto-approve scripts"
  local tpl="${PACKAGE_ROOT}/.aihaus/templates/settings.local.json"
  [[ -f "$tpl" ]] || { _fail "$label" "template missing: $tpl"; return; }
  local missing=()
  grep -q 'auto-approve-bash.sh' "$tpl" || missing+=("auto-approve-bash.sh")
  grep -q 'auto-approve-writes.sh' "$tpl" || missing+=("auto-approve-writes.sh")
  if [[ ${#missing[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "template missing hook references: ${missing[*]}"
  fi
}

# ---- Check 16: Cursor plugin manifest + rules (M006 / ADR-005) --------------
# Validates:
#   (a) pkg/.aihaus/.cursor-plugin/plugin.json — exists, valid JSON, has "name"
#   (b) pkg/.aihaus/rules/aihaus.mdc — exists, has frontmatter, NO "PREVIEW" marker
#   (c) pkg/.aihaus/rules/COMPAT-MATRIX.md — exists (authoritative per-skill verdict)
# Replaces the pre-v0.10.0 cursor-preview linter (cursor-preview/ is gone).
check_cursor_plugin() {
  _start_check
  local label="Check ${CHECK_NUMBER}: Cursor plugin manifest + rules (M006)"
  local manifest="${PACKAGE_ROOT}/.aihaus/.cursor-plugin/plugin.json"
  local mdc="${PACKAGE_ROOT}/.aihaus/rules/aihaus.mdc"
  local matrix="${PACKAGE_ROOT}/.aihaus/rules/COMPAT-MATRIX.md"
  local problems=()
  # (a) manifest exists, is valid JSON, has required "name" field
  if [[ ! -f "$manifest" ]]; then
    problems+=("plugin.json missing at .aihaus/.cursor-plugin/plugin.json")
  else
    local py_bin=""
    if command -v python3 >/dev/null 2>&1; then py_bin="$(command -v python3)"
    elif command -v python  >/dev/null 2>&1; then py_bin="$(command -v python)"
    elif command -v py      >/dev/null 2>&1; then py_bin="$(command -v py)"
    fi
    if [[ -n "$py_bin" ]]; then
      "$py_bin" -c "import json,sys; d=json.load(open(sys.argv[1],encoding='utf-8')); sys.exit(0 if isinstance(d.get('name'),str) and d['name'] else 1)" "$manifest" 2>/dev/null || problems+=("plugin.json invalid JSON or missing 'name'")
    elif command -v jq >/dev/null 2>&1; then
      jq -e 'has("name") and (.name | type == "string") and (.name | length > 0)' "$manifest" >/dev/null 2>&1 || problems+=("plugin.json invalid JSON or missing 'name'")
    else
      problems+=("cannot validate plugin.json — neither python nor jq available")
    fi
  fi
  # (b) rules/aihaus.mdc exists, has frontmatter, NO PREVIEW marker
  if [[ ! -f "$mdc" ]]; then
    problems+=("rules/aihaus.mdc missing")
  else
    local front
    front=$(awk '/^---$/{c++; next} c==1' "$mdc")
    for field in description globs alwaysApply; do
      if ! printf '%s\n' "$front" | grep -q "^${field}:"; then
        problems+=("rules/aihaus.mdc frontmatter missing '$field:'")
      fi
    done
    if head -n20 "$mdc" | grep -Fq 'PREVIEW'; then
      problems+=("rules/aihaus.mdc still contains 'PREVIEW' marker — dropped in M006")
    fi
  fi
  # (c) COMPAT-MATRIX.md exists
  [[ -f "$matrix" ]] || problems+=("rules/COMPAT-MATRIX.md missing")
  if [[ ${#problems[@]} -eq 0 ]]; then
    _pass "$label"
  else
    _fail "$label" "${problems[@]}"
  fi
}

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

# ---- Check 27: skill directory count = 13 (M012/S07) -----------------------
# Verifies that exactly 13 aih-* skill directories exist under .aihaus/skills/.
# Note: Check 1 verifies the NAMED SKILL.md files (13 expected names including
# aih-effort and aih-automode). Check 27 independently verifies the directory
# count so that unexpected directories (stale renames, extra skill dirs) also
# cause CI failure. If the count exceeds 13, a stale directory likely remains
# from the M012/S04 skill rename.
check_skill_count_and_staleness() {
  _start_check
  local label="Check ${CHECK_NUMBER}: exactly 13 aih-* skill dirs exist (M012/S07)"
  local skills_root="${PACKAGE_ROOT}/.aihaus/skills"
  local problems=()

  # Count aih-* directories (exclude _shared and any non-aih prefixed dirs).
  local actual_count
  actual_count=$(find "$skills_root" -maxdepth 1 -type d -name 'aih-*' | wc -l | tr -d ' ')
  if [[ "$actual_count" -ne 13 ]]; then
    problems+=("expected 13 aih-* skill dirs; found ${actual_count} (stale dir from rename? run: ls ${skills_root}/)")
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
#        !! block in stderr pointing at /aih-automode --enable; idempotent
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

  # stderr must contain the !! block pointing at /aih-automode --enable.
  echo "$f2_stderr" | grep -q '!!' \
    || problems+=("F2: !! warning block not emitted in stderr")
  echo "$f2_stderr" | grep -q '/aih-automode --enable' \
    || problems+=("F2: stderr missing /aih-automode --enable reference")

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

# ---- Check 36: learning-advisor agent + hook exist + COMPAT-MATRIX row (M013/S06) --
# Asserts Component B of M013 shipped:
#   (a) pkg/.aihaus/agents/learning-advisor.md exists with required frontmatter
#       (name, tools, model, effort, color, memory) and read-only tools whitelist
#   (b) pkg/.aihaus/hooks/learning-advisor.sh exists and is executable
#   (c) learning-advisor model is haiku (cohort :verifier default)
#   (d) learning-advisor tools are Read, Grep, Glob (no Write/Edit per ADR-001)
#   (e) templates/settings.local.json references learning-advisor.sh under SubagentStop
#   (f) COMPAT-MATRIX.md has a NOT-SUPPORTED row for learning-advisor
#   (g) agent count reached 45 (context-curator=44, learning-advisor=45)
check_learning_advisor() {
  _start_check
  local label="Check ${CHECK_NUMBER}: learning-advisor agent + hook exist + COMPAT-MATRIX row (M013/S06)"
  local agent="${PACKAGE_ROOT}/.aihaus/agents/learning-advisor.md"
  local hook="${PACKAGE_ROOT}/.aihaus/hooks/learning-advisor.sh"
  local tpl="${PACKAGE_ROOT}/.aihaus/templates/settings.local.json"
  local compat="${PACKAGE_ROOT}/.aihaus/rules/COMPAT-MATRIX.md"
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

  # (f) COMPAT-MATRIX has NOT-SUPPORTED row for learning-advisor
  if [[ -f "$compat" ]]; then
    if ! grep -q 'learning-advisor.*NOT-SUPPORTED\|NOT-SUPPORTED.*learning-advisor' "$compat"; then
      problems+=("COMPAT-MATRIX.md missing NOT-SUPPORTED row for learning-advisor")
    fi
  fi

  # (g) agent count at 46 (knowledge-curator added in M013/S07)
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

# ---- Check (M014/S06): schema v2→v3 migration fixture (idempotent + additive) -
# Exercises manifest-migrate.sh v2→v3 path:
#   R1 takes a v2 fixture manifest (schema: v2, no ## Checkpoints)
#   R2 runs manifest-migrate.sh → asserts ## Checkpoints heading present
#   R3 asserts column header present (LD-1 7-column shape)
#   R4 runs manifest-migrate.sh again → asserts no diff (idempotent)
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

  # R2: run migration first time
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

  # R4: capture snapshot before second run
  local snap_before
  snap_before="$(cat "$fixture")"

  # R4: run migration a second time
  local migrate_out2 migrate_rc2
  migrate_out2=$(MANIFEST_PATH="$fixture" bash "$migrate_hook" 2>&1)
  migrate_rc2=$?
  if [[ "$migrate_rc2" -ne 0 ]]; then
    problems+=("R4: manifest-migrate.sh exited ${migrate_rc2} on second run; output: ${migrate_out2:0:200}")
  fi

  # R4: assert idempotent (file unchanged)
  local snap_after
  snap_after="$(cat "$fixture")"
  if [[ "$snap_before" != "$snap_after" ]]; then
    problems+=("R4: idempotence violated — manifest changed on second migration run")
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
check_cursor_plugin
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

printf "\n"
if [[ "$FAILURES" -eq 0 ]]; then
  printf "aihaus package smoke test PASSED [OK]\n"
  exit 0
else
  printf "FAILED - %d checks failed\n" "$FAILURES"
  exit 1
fi
