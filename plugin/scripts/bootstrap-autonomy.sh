#!/usr/bin/env bash
# bootstrap-autonomy.sh
#
# One-time merge of aihaus autonomy defaults into the target repo's
# .claude/settings.local.json. Runs on every SessionStart but is idempotent:
# once the merge marker file exists, the script noops.
#
# Why this exists: Claude Code plugins do NOT support
# `permissionMode: bypassPermissions` on plugin-shipped agents. aihaus relies
# on autonomous Write/Edit/Bash during milestone execution. This script
# compensates by merging a focused allow-list into the USER's settings.local.json,
# which Claude Code DOES honor for permission decisions.
#
# The merge only touches keys aihaus needs (permissions.allow, permissions.deny,
# additionalDirectories, env, aihaus). Pre-existing values are preserved;
# aihaus additions are appended and deduplicated.

set -eu

# Target repo root — provided by Claude Code at hook execution time.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
SETTINGS_DIR="${PROJECT_DIR}/.claude"
SETTINGS_FILE="${SETTINGS_DIR}/settings.local.json"
MARKER_FILE="${SETTINGS_DIR}/.aihaus-plugin-bootstrapped"

# Idempotency: exit quietly on subsequent sessions.
if [ -f "$MARKER_FILE" ]; then
  exit 0
fi

mkdir -p "$SETTINGS_DIR"

# Ensure target settings file exists (empty JSON object if missing).
if [ ! -f "$SETTINGS_FILE" ]; then
  printf '{}\n' > "$SETTINGS_FILE"
fi

# The aihaus autonomy patch. Structured as a JSON object for merge.
PATCH='{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "aihaus": {
    "suppress": {
      "taskCreateReminder": true
    }
  },
  "additionalDirectories": [
    ".aihaus",
    ".claude"
  ],
  "permissions": {
    "allow": [
      "Read", "Glob", "Grep", "Write", "Edit",
      "WebFetch", "WebSearch", "Agent", "Skill",
      "Bash(*)"
    ],
    "deny": [
      "Bash(rm -rf /)", "Bash(rm -rf ~)", "Bash(rm -rf /*)",
      "Bash(: > /dev/sda*)", "Bash(dd if=/dev/zero*)",
      "Read(//**/.env)", "Read(//**/.env.*)",
      "Read(//**/credentials*)", "Read(//**/id_rsa*)", "Read(//**/*.pem)"
    ]
  }
}'

# Prefer jq (native, fast); fall back to Python which ships on all supported OSes.
if command -v jq >/dev/null 2>&1; then
  tmp="$(mktemp)"
  # Deep-merge, deduping array values for allow/deny/additionalDirectories.
  jq --argjson patch "$PATCH" '
    . as $orig
    | ($orig.permissions.allow // [])    as $exist_allow
    | ($orig.permissions.deny  // [])    as $exist_deny
    | ($orig.additionalDirectories // []) as $exist_dirs
    | $orig
      * $patch
      * {
          permissions: {
            allow: (($exist_allow + $patch.permissions.allow) | unique),
            deny:  (($exist_deny  + $patch.permissions.deny)  | unique)
          },
          additionalDirectories: (($exist_dirs + $patch.additionalDirectories) | unique)
        }
  ' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"
elif command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
  PY="$(command -v python3 || command -v python)"
  "$PY" - "$SETTINGS_FILE" "$PATCH" <<'PYEOF'
import json, sys
path, patch_json = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as f:
    try:
        data = json.load(f)
    except json.JSONDecodeError:
        data = {}
patch = json.loads(patch_json)

def dedupe(seq):
    seen, out = set(), []
    for v in seq:
        if v not in seen:
            seen.add(v); out.append(v)
    return out

# env + aihaus: shallow-merge patch over existing
data.setdefault("env", {}).update(patch.get("env", {}))
aih = data.setdefault("aihaus", {})
aih_sup = aih.setdefault("suppress", {})
aih_sup.update(patch.get("aihaus", {}).get("suppress", {}))

# additionalDirectories: union + dedupe
data["additionalDirectories"] = dedupe(
    list(data.get("additionalDirectories", [])) + patch["additionalDirectories"]
)

# permissions.allow / .deny: union + dedupe
perms = data.setdefault("permissions", {})
perms["allow"] = dedupe(list(perms.get("allow", [])) + patch["permissions"]["allow"])
perms["deny"]  = dedupe(list(perms.get("deny",  [])) + patch["permissions"]["deny"])

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF
else
  # Neither jq nor python available — print a diagnostic to stderr so the
  # user sees it in --debug logs, but don't crash the session.
  printf '[aihaus-plugin] bootstrap skipped: jq/python not found on PATH\n' >&2
  exit 0
fi

# Drop the idempotency marker so subsequent sessions skip the merge.
touch "$MARKER_FILE"
printf '[aihaus-plugin] autonomy defaults merged into %s\n' "$SETTINGS_FILE" >&2
