#!/usr/bin/env bash
# project-context-refresh.sh - keep repo-local Claude/aihaus context hydrated.
#
# This hook is intentionally best-effort and non-blocking. It repairs missing
# bridge files/import targets, normalizes old hook paths, and refreshes the
# operational discovery/verifier outside the one-time /aih-init flow.

set -u

reason="manual"
force=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --reason)
      reason="${2:-manual}"
      shift 2
      ;;
    --force)
      force=1
      shift
      ;;
    *)
      shift
      ;;
  esac
done

[ "${AIHAUS_PROJECT_CONTEXT_REFRESH:-1}" = "0" ] && exit 0

quiet="${AIHAUS_CONTEXT_REFRESH_QUIET:-0}"
say() {
  [ "$quiet" = "1" ] && return 0
  printf '%s\n' "$*"
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [ -f "${script_dir}/lib/path-helpers.sh" ]; then
  # shellcheck source=lib/path-helpers.sh
  . "${script_dir}/lib/path-helpers.sh"
fi

if command -v aihaus_project_root >/dev/null 2>&1; then
  project_root="$(aihaus_project_root 2>/dev/null || printf '%s\n' "${CLAUDE_PROJECT_DIR:-$PWD}")"
else
  project_root="${CLAUDE_PROJECT_DIR:-$PWD}"
fi
project_root="$(cd "$project_root" 2>/dev/null && pwd)" || exit 0

aihaus_dir="${project_root}/.aihaus"
claude_dir="${project_root}/.claude"
audit_dir="${aihaus_dir}/audit"
state_dir="${aihaus_dir}/state"
roles_dir="${aihaus_dir}/roles"
repair_count=0
discovery_run=0
verify_run=0
freshness_status="unknown"

mkdir -p "$aihaus_dir" "$claude_dir" "$audit_dir" "$state_dir" "$roles_dir" 2>/dev/null || true

write_if_missing() {
  local file="$1"
  local dir
  dir="$(dirname "$file")"
  [ -f "$file" ] && return 0
  mkdir -p "$dir" 2>/dev/null || return 0
  cat > "$file"
  repair_count=$((repair_count + 1))
}

copy_or_seed() {
  local src="$1" dst="$2" label="$3"
  if [ -f "$dst" ]; then
    return 0
  fi
  mkdir -p "$(dirname "$dst")" 2>/dev/null || return 0
  if [ -f "$src" ]; then
    cp "$src" "$dst" 2>/dev/null && {
      repair_count=$((repair_count + 1))
      return 0
    }
  fi
  printf '# %s\n\nSeeded by aihaus project-context-refresh. Replace this placeholder with repository-specific context.\n' "$label" > "$dst" 2>/dev/null && \
    repair_count=$((repair_count + 1))
}

ensure_block() {
  local file="$1" start_marker="$2" end_marker="$3" source_file="$4"
  [ -f "$source_file" ] || return 0
  if [ ! -f "$file" ]; then
    mkdir -p "$(dirname "$file")" 2>/dev/null || return 0
    cp "$source_file" "$file" 2>/dev/null && repair_count=$((repair_count + 1))
    return 0
  fi

  local tmp
  tmp="${file}.tmp.$$"
  if grep -Fq "$start_marker" "$file" 2>/dev/null && grep -Fq "$end_marker" "$file" 2>/dev/null; then
    if awk -v start="$start_marker" -v end="$end_marker" -v source="$source_file" '
      BEGIN {
        while ((getline line < source) > 0) {
          if (index(line, start) > 0) in_source = 1
          if (in_source) block = block line ORS
          if (in_source && index(line, end) > 0) break
        }
        close(source)
      }
      {
        if (index($0, start) > 0) {
          printf "%s", block
          skipping = 1
          next
        }
        if (skipping) {
          if (index($0, end) > 0) skipping = 0
          next
        }
        print
      }
    ' "$file" > "$tmp" 2>/dev/null; then
      if cmp -s "$file" "$tmp" 2>/dev/null; then
        rm -f "$tmp" 2>/dev/null || true
      else
        mv "$tmp" "$file" 2>/dev/null && repair_count=$((repair_count + 1))
      fi
    else
      rm -f "$tmp" 2>/dev/null || true
    fi
    return 0
  fi
  { printf '\n\n'; cat "$source_file"; } >> "$file" 2>/dev/null && repair_count=$((repair_count + 1))
}

scrub_large_claude_imports() {
  local file="$1"
  [ -f "$file" ] || return 0
  if ! grep -Eq '^@\.\./\.aihaus/(decisions|knowledge)\.md[[:space:]]*$' "$file" 2>/dev/null; then
    return 0
  fi

  local tmp
  tmp="${file}.tmp.$$"
  if awk '{
    line=$0
    sub(/\r$/, "", line)
    if (line != "@../.aihaus/decisions.md" && line != "@../.aihaus/knowledge.md") print $0
  }' "$file" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$file" 2>/dev/null && repair_count=$((repair_count + 1))
  else
    rm -f "$tmp" 2>/dev/null || true
  fi
}

ensure_claude_hook_path_normalized() {
  local settings="${claude_dir}/settings.local.json"
  [ -f "$settings" ] || return 0
  if ! grep -Fq '.claude/hooks/' "$settings" 2>/dev/null; then
    return 0
  fi

  local py_bin tmp
  py_bin="$(command -v python3 || command -v python || command -v py || true)"
  if [ -z "$py_bin" ]; then
    say "warn: python not available; could not normalize .claude/hooks settings paths"
    return 0
  fi
  tmp="${settings}.tmp.$$"
  if "$py_bin" - "$settings" "$tmp" <<'PY'
import json
import sys

src, dst = sys.argv[1], sys.argv[2]
with open(src, "r", encoding="utf-8") as fh:
    data = json.load(fh)

changed = False

def normalize(obj):
    global changed
    if isinstance(obj, dict):
        out = {}
        for key, value in obj.items():
            if key == "command" and isinstance(value, str):
                new = value.replace(".claude/hooks/", ".aihaus/hooks/")
                if new != value:
                    changed = True
                out[key] = new
            else:
                out[key] = normalize(value)
        return out
    if isinstance(obj, list):
        normalized = [normalize(item) for item in obj]
        if all(isinstance(item, dict) and "command" in item for item in normalized):
            seen = set()
            deduped = []
            for item in normalized:
                command = item.get("command")
                if command in seen:
                    changed = True
                    continue
                seen.add(command)
                deduped.append(item)
            return deduped
        return normalized
    return obj

data = normalize(data)
if changed:
    with open(dst, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, separators=(",", ": "))
        fh.write("\n")
else:
    open(dst, "w", encoding="utf-8").close()
PY
  then
    if [ -s "$tmp" ]; then
      mv "$tmp" "$settings" 2>/dev/null && repair_count=$((repair_count + 1))
    else
      rm -f "$tmp" 2>/dev/null || true
    fi
  else
    rm -f "$tmp" 2>/dev/null || true
  fi
}

template_dir="${aihaus_dir}/templates"
copy_or_seed "${template_dir}/claude/CLAUDE.md" "${claude_dir}/CLAUDE.md" "Claude Project Context"
copy_or_seed "${template_dir}/claude/rules/aihaus-project-memory.md" "${claude_dir}/rules/aihaus-project-memory.md" "aihaus Project Memory Rule"
ensure_block "${claude_dir}/CLAUDE.md" "AIHAUS:CLAUDE-CONTEXT-START" "AIHAUS:CLAUDE-CONTEXT-END" "${template_dir}/claude/CLAUDE.md"
ensure_block "${claude_dir}/rules/aihaus-project-memory.md" "AIHAUS:CLAUDE-RULES-START" "AIHAUS:CLAUDE-RULES-END" "${template_dir}/claude/rules/aihaus-project-memory.md"
scrub_large_claude_imports "${claude_dir}/CLAUDE.md"

copy_or_seed "${aihaus_dir}/templates/knowledge.md" "${aihaus_dir}/knowledge.md" "Knowledge Base"
copy_or_seed "${aihaus_dir}/templates/decisions.md" "${aihaus_dir}/decisions.md" "Architectural Decision Records"

write_if_missing "${aihaus_dir}/project.md" <<'EOF'
# Project Context

This repository has not yet generated its project context. Run `/aih-init` to
inventory architecture, commands, schemas, components, tests, and conventions.
EOF

write_if_missing "${aihaus_dir}/protocols/default.md" <<'EOF'
# aihaus Workflow Profile

This repository has not yet customized its workflow profile. Run `/aih-init`
or copy the package workflow profile here before relying on stage movement.
EOF

write_if_missing "${aihaus_dir}/protocols/agents.md" <<'EOF'
# Workflow Agents

This repository has not yet customized workflow agent responsibilities. Run
`/aih-init` or copy the package workflow agent profile here.
EOF

write_if_missing "${aihaus_dir}/protocols/routing.md" <<'EOF'
# aihaus Routing

This repository has not yet customized intent routing. Run `/aih-init` or copy
the package routing profile here before relying on workflow orchestration.
EOF

write_if_missing "${aihaus_dir}/memory/MEMORY.md" <<'EOF'
# aihaus Memory

Repository-local memory index. Durable facts should live under
`.aihaus/memory/workflows/` or the relevant domain folder.
EOF

write_if_missing "${aihaus_dir}/memory/workflows/README.md" <<'EOF'
# Workflow Memory

Durable workflow facts for this repository. Do not store transient logs or
plaintext secrets here.
EOF

write_if_missing "${aihaus_dir}/memory/workflows/rules.md" <<'EOF'
# Workflow Rules

Append repository-specific workflow rules here.
EOF

write_if_missing "${aihaus_dir}/memory/workflows/user-preferences.md" <<'EOF'
# User Preferences

Append durable user preferences for workflow movement and validation here.
EOF

write_if_missing "${aihaus_dir}/memory/workflows/gotchas.md" <<'EOF'
# Workflow Gotchas

Append recurring workflow mistakes and the correct future behavior here.
EOF

write_if_missing "${aihaus_dir}/memory/workflows/environment.md" <<'EOF'
# Workflow Environment Memory

Use this file for repository-specific execution environment notes that should
survive across aihaus runs. Do not store plaintext secrets.

<!-- AIHAUS:WORKFLOW-ENVIRONMENT-PROMPTS-START -->
## Runtime and Deployment

- **Where code runs:** _local dev / container / CodeBuild / ECS / Lambda / other_
- **Default dev URL:** _fill in if browser validation uses a stable URL_
- **Deploy path:** _command, pipeline, CodeBuild project, or human-owned release path_
- **Promotion gates:** _what must pass before dev, staging, or production_

## Credentials and Test Accounts

- **Credential location:** _Secrets Manager, Parameter Store, .env vault, password manager, or other approved source_
- **Test users/roles:** _named roles only; do not store passwords or tokens_
- **Auth protocol:** _how an agent should authenticate for Playwright or API smoke checks_

## Validation Commands

- **Unit/integration:** _repo command or CI job_
- **Playwright/browser:** _repo command, dev URL, required seed data_
- **CodeBuild/CI:** _project names or commands used to check builds_
- **Smoke evidence:** _screenshots, traces, URLs, logs, or release artifacts expected_

## Source System Hints

- **External kanban:** _Linear team/project/view, Jira project, Notion DB, or none_
- **Stage sync:** _which statuses/views mirror local aihaus stages_
- **Question protocol:** _how business-rule gaps are recorded and answered_
<!-- AIHAUS:WORKFLOW-ENVIRONMENT-PROMPTS-END -->
EOF

copy_or_seed "${aihaus_dir}/templates/business-rules.md" "${aihaus_dir}/memory/workflows/business-rules.md" "Business Rules"

write_if_missing "${roles_dir}/online-actions.conf" <<'EOF'
# Project-specific online-action command patterns.
# One extended regular expression per line. Blank lines and # comments ignored.
# Keep local; do not commit credentials or environment-specific secrets here.
EOF

ensure_claude_hook_path_normalized

write_project_freshness_audit() {
  local project_file="${aihaus_dir}/project.md"
  local audit_file="${audit_dir}/project-context-freshness.md"
  local warnings=""
  freshness_status="missing"
  [ -f "$project_file" ] || {
    cat > "$audit_file" <<'EOF' 2>/dev/null || true
# Project Context Freshness

Status: MISSING

`.aihaus/project.md` is missing. Run `/aih-init` before relying on project
architecture, inventory, commands, or milestones.
EOF
    return 0
  }

  freshness_status="fresh"
  if grep -Fq '[PROJECT_NAME]' "$project_file" 2>/dev/null || grep -Fq '_example paths_' "$project_file" 2>/dev/null; then
    warnings="${warnings}- project.md still contains template placeholders.\n"
  fi
  if grep -Fq '_No active milestones yet._' "$project_file" 2>/dev/null; then
    if find "${aihaus_dir}/milestones" -maxdepth 1 -type d -name 'M*' 2>/dev/null | grep -q .; then
      warnings="${warnings}- project.md says no active milestones, but .aihaus/milestones contains M* directories.\n"
    fi
  fi

  _count_files() {
    local dir="$1" pattern="$2"
    [ -d "$dir" ] || { printf '0\n'; return 0; }
    find "$dir" -type f -name "$pattern" 2>/dev/null | wc -l | tr -d ' '
  }

  _inventory_count() {
    local label="$1"
    awk -F'|' -v label="$label" '
      $2 ~ label {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3)
        print $3
        exit
      }
    ' "$project_file" 2>/dev/null
  }

  local current recorded
  current="$(_count_files "${project_root}/backend/alembic/versions" '*.py')"
  recorded="$(_inventory_count 'Alembic migrations')"
  if [ -n "$recorded" ] && [ "$recorded" != "$current" ]; then
    warnings="${warnings}- Alembic migrations inventory is stale: project.md=${recorded}, current=${current}.\n"
  fi
  current="$(_count_files "${project_root}/backend/tests" '*.py')"
  recorded="$(_inventory_count 'Backend tests')"
  if [ -n "$recorded" ] && [ "$recorded" != "$current" ]; then
    warnings="${warnings}- Backend tests inventory is stale: project.md=${recorded}, current=${current}.\n"
  fi
  current="$(_count_files "${project_root}/frontend/src/components" '*.tsx')"
  recorded="$(_inventory_count 'Frontend components')"
  if [ -n "$recorded" ] && [ "$recorded" != "$current" ]; then
    warnings="${warnings}- Frontend components inventory is stale: project.md=${recorded}, current=${current}.\n"
  fi
  current="$(_count_files "${project_root}/frontend/app" '*.tsx')"
  recorded="$(_inventory_count 'Frontend screens')"
  if [ -n "$recorded" ] && [ "$recorded" != "$current" ]; then
    warnings="${warnings}- Frontend screens inventory is stale: project.md=${recorded}, current=${current}.\n"
  fi

  if [ -n "$warnings" ]; then
    freshness_status="stale"
    {
      printf '# Project Context Freshness\n\n'
      printf 'Status: STALE\n\n'
      printf '%b' "$warnings"
      printf '\nRun `/aih-init` to refresh the auto-generated project inventory. '
      printf 'Update manual milestone/decision/knowledge pointers after validating the generated block.\n'
    } > "$audit_file" 2>/dev/null || true
  else
    {
      printf '# Project Context Freshness\n\n'
      printf 'Status: FRESH\n\n'
      printf 'No obvious project.md inventory drift detected by project-context-refresh.\n'
    } > "$audit_file" 2>/dev/null || true
  fi
}

last_file="${state_dir}/project-context-refresh.last"
now_epoch="$(date +%s 2>/dev/null || echo 0)"
last_epoch=0
[ -f "$last_file" ] && last_epoch="$(cat "$last_file" 2>/dev/null || echo 0)"
case "$last_epoch" in *[!0-9]*|'') last_epoch=0 ;; esac
interval="${AIHAUS_CONTEXT_REFRESH_INTERVAL_SEC:-900}"
case "$interval" in *[!0-9]*|'') interval=900 ;; esac

discovery_script="${aihaus_dir}/skills/aih-init/scripts/environment-discovery.sh"
verify_script="${aihaus_dir}/skills/aih-init/scripts/claude-context-verify.sh"

should_run_discovery=0
if [ "$force" = "1" ] || [ "$repair_count" -gt 0 ] || [ ! -f "${aihaus_dir}/init/environment-discovery.md" ]; then
  should_run_discovery=1
elif [ "$now_epoch" -gt 0 ] && [ $((now_epoch - last_epoch)) -ge "$interval" ]; then
  should_run_discovery=1
fi

if [ "${AIHAUS_CONTEXT_REFRESH_DISCOVERY:-1}" != "0" ] && [ "$should_run_discovery" = "1" ] && [ -f "$discovery_script" ]; then
  bash "$discovery_script" --target "$project_root" >/dev/null 2>&1 && discovery_run=1
fi

if [ "${AIHAUS_CONTEXT_REFRESH_VERIFY:-1}" != "0" ] && [ -f "$verify_script" ]; then
  bash "$verify_script" --target "$project_root" >/dev/null 2>&1 && verify_run=1
fi

write_project_freshness_audit

[ "$now_epoch" -gt 0 ] && printf '%s\n' "$now_epoch" > "$last_file" 2>/dev/null || true

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
printf '{"ts":"%s","reason":"%s","repairs":%s,"discovery_run":%s,"verify_run":%s,"project_freshness":"%s"}\n' \
  "$ts" "$reason" "$repair_count" "$discovery_run" "$verify_run" "$freshness_status" \
  >> "${audit_dir}/project-context-refresh.jsonl" 2>/dev/null || true

say "project context refresh: repairs=${repair_count} discovery=${discovery_run} verify=${verify_run} project=${freshness_status}"
exit 0
