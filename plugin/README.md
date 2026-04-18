# aihaus — Claude Code plugin (preview)

> [!IMPORTANT]
> This plugin preview is no longer maintained.
>
> aihaus-flow is archived in place as historical reference. We are not maintaining this plugin packaging further, and we are not recommending it for new installs.
>
> **Use [`gsd2`](https://github.com/gsd-build/gsd-2) or [`gsd1`](https://github.com/gsd-build/get-shit-done) instead.**

Native Claude Code plugin packaging of the [aihaus](../pkg/) agent harness. This is a **separate, parallel preview**: the existing `install.sh` flow still ships from `pkg/.aihaus/` and is unchanged. Content here is a duplicate copy, free to diverge as the plugin format requires.

## What this plugin ships

- **11 skills** (`/aih-init`, `/aih-plan`, `/aih-bugfix`, `/aih-feature`, `/aih-milestone`, `/aih-resume`, `/aih-brainstorm`, `/aih-help`, `/aih-quick`, `/aih-update`, `/aih-sync-notion`) — full aihaus command surface as Claude Code slash commands.
- **43 agents** — analyst, architect, product-manager, planner, implementer, frontend-dev, reviewer, code-reviewer, code-fixer, plan-checker, verifier, security-auditor, and the rest of the role catalogue.
- **19 lifecycle hook scripts** registered via `hooks/hooks.json` — session bootstrap, bash-guard, file-guard, auto-approve-bash, auto-approve-writes, backup-file, audit-log, audit-agent, task-created, task-completed, teammate-idle, permission-debug, autonomy-guard (Stop), session-end, plus the M003 protocol scripts (invoke-guard, manifest-append, manifest-migrate, phase-advance).
- **Project templates** — `project.md`, `settings.local.json`, `STATUS.md`, `RUN-MANIFEST-schema-v2.md`, `knowledge.md`, `SESSION-LOG.md`, Notion card templates. Used by `/aih-init` to scaffold a new target repo.

## Quick test — local plugin dir

From any repo where you want to try aihaus:

```bash
claude --plugin-dir /absolute/path/to/aihaus-flow/plugin
```

Multiple `--plugin-dir` flags are fine if you want to stack plugins.

Inside the session:

```
/plugin           # confirms aihaus loaded
/aih-help         # lists the 11 aihaus skills
/aih-init         # scaffolds .aihaus/ in the target repo
```

## Known divergence from the `pkg/.aihaus/` install

| Concern | `pkg/` install | Plugin |
|---|---|---|
| `permissionMode: bypassPermissions` on `implementer` / `frontend-dev` / `code-fixer` / `executor` / `nyquist-auditor` | honored per-agent | stripped (plugins can't set it) — compensated via allow-list merge (see below) |
| `isolation: worktree` | honored | honored (plugins support it) |
| Hook registration | via `.claude/settings.local.json` at install time | via `hooks/hooks.json` inside the plugin |
| Settings merge | shell installer uses `jq` / Python | `scripts/bootstrap-autonomy.sh` runs on first `SessionStart` and merges the autonomy allow-list into `.claude/settings.local.json` |

### How autonomy is preserved without `bypassPermissions`

On the first session with the plugin active, `bootstrap-autonomy.sh` merges this patch into the target repo's `.claude/settings.local.json`:

```json
{
  "permissions": {
    "allow": ["Read", "Glob", "Grep", "Write", "Edit",
              "WebFetch", "WebSearch", "Agent", "Skill", "Bash(*)"],
    "deny":  ["Bash(rm -rf /)", "Bash(rm -rf ~)", "Bash(rm -rf /*)",
              "Read(//**/.env)", "Read(//**/.env.*)",
              "Read(//**/credentials*)", "Read(//**/id_rsa*)", "Read(//**/*.pem)"]
  },
  "additionalDirectories": [".aihaus", ".claude"],
  "env":   {"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"},
  "aihaus": {"suppress": {"taskCreateReminder": true}}
}
```

The merge is idempotent — subsequent sessions skip it once `.claude/.aihaus-plugin-bootstrapped` exists. Pre-existing `allow` / `deny` / `additionalDirectories` entries are preserved and deduplicated against the aihaus additions.

If you never want the bootstrap to run, delete `scripts/bootstrap-autonomy.sh` from your clone or comment the entry out of `hooks/hooks.json`.

## Directory layout

```
plugin/
├── .claude-plugin/
│   └── plugin.json          # manifest
├── skills/                  # 11 aih-* skills + _shared/autonomy-protocol.md
├── agents/                  # 43 agent .md files (plugin-safe frontmatter)
├── hooks/
│   └── hooks.json           # lifecycle hook registration
├── scripts/                 # 19 hook/bootstrap shell scripts
├── templates/               # project.md, settings.local.json, STATUS.md, etc.
└── README.md                # this file
```

## Maintenance

- Content is a **duplicate copy** of `pkg/.aihaus/`. There is no automatic sync. When a skill, agent, or hook changes in `pkg/`, update it here manually if the fix applies to the plugin too.
- Run `bash tools/smoke-test.sh` against `pkg/` as usual; plugin validation is a separate concern (future: `tools/smoke-test-plugin.sh`).
- Plugin-specific agent frontmatter: `executor`, `implementer`, `frontend-dev`, `code-fixer`, `nyquist-auditor` ship **without** `permissionMode: bypassPermissions` in the plugin (unsupported). The `isolation: worktree` field is retained where present.

## Status

Preview quality. Known untested:
- Install into a fresh repo via `claude --plugin-dir`
- Hooks firing end-to-end against `hooks.json` path-substitution (`${CLAUDE_PLUGIN_ROOT}`)
- `/aih-init` scaffolding when templates live at `${CLAUDE_PLUGIN_ROOT}/templates/`
- Permission flow on `implementer` / `frontend-dev` / `code-fixer` without the frontmatter override

Report issues against the parent repo until this graduates to its own package.
