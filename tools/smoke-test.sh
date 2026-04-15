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
  local label="Check ${CHECK_NUMBER}: .aihaus/skills/ has 11 expected SKILL.md files"
  local expected=(aih-init aih-plan aih-bugfix aih-feature aih-milestone aih-help aih-quick aih-sync-notion aih-update aih-resume aih-brainstorm)
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

# ---- Check 2: .aihaus/agents/ has 43 .md files ------------------------------
check_agents() {
  _start_check
  local label="Check ${CHECK_NUMBER}: .aihaus/agents/ has 43 .md files"
  local agents_root="${PACKAGE_ROOT}/.aihaus/agents"
  if [[ ! -d "$agents_root" ]]; then
    _fail "$label" "directory not found: $agents_root"
    return
  fi
  local count
  count=$(find "$agents_root" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')
  if [[ "$count" -eq 43 ]]; then
    _pass "$label"
  else
    _fail "$label" "expected 43 .md files, found $count"
  fi
}

# ---- Check 3: .aihaus/hooks/ has 17 .sh files (post-M003 + autonomy-guard) --
check_hooks() {
  _start_check
  local label="Check ${CHECK_NUMBER}: .aihaus/hooks/ has 17 .sh files"
  local hooks_root="${PACKAGE_ROOT}/.aihaus/hooks"
  if [[ ! -d "$hooks_root" ]]; then
    _fail "$label" "directory not found: $hooks_root"
    return
  fi
  local count
  count=$(find "$hooks_root" -maxdepth 1 -type f -name '*.sh' | wc -l | tr -d ' ')
  if [[ "$count" -eq 17 ]]; then
    _pass "$label"
  else
    _fail "$label" "expected 17 .sh files, found $count"
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
check_agent_frontmatter() {
  _start_check
  local label="Check ${CHECK_NUMBER}: every agent declares name/tools/model/effort/color/memory"
  local agents_root="${PACKAGE_ROOT}/.aihaus/agents"
  local offenders=()
  while IFS= read -r -d '' file; do
    local front
    front=$(awk '/^---$/{c++; next} c==1' "$file")
    for field in name tools model effort color memory; do
      if ! printf '%s\n' "$front" | grep -q "^${field}:"; then
        offenders+=("${file#${PACKAGE_ROOT}/} missing '$field'")
      fi
    done
  done < <(find "$agents_root" -maxdepth 1 -type f -name '*.md' -print0)
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

printf "\n"
if [[ "$FAILURES" -eq 0 ]]; then
  printf "aihaus package smoke test PASSED [OK]\n"
  exit 0
else
  printf "FAILED - %d checks failed\n" "$FAILURES"
  exit 1
fi
