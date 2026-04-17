# v0.17.0 — Cohorts, Effort Skill, and Auto-Mode (M012)

## BREAKING CHANGES (v0.17.0)

Three breaking changes ship in this release. Read before upgrading.

**1. `/aih-calibrate` removed — use `/aih-effort` or `/aih-automode`**

The `/aih-calibrate` skill is gone. Typing `/aih-calibrate` returns
skill-not-found. Effort + model tuning moves to `/aih-effort`; permission-mode
enable/disable moves to the new `/aih-automode` skill. The two surfaces are now
fully independent — no cross-skill dispatch.

**2. Four preset names dropped**

`cost-optimized`, `quality-first`, `performatic`, and `auto-mode-safe` no
longer exist as preset names. They are replaced by three simpler names:

| Old | New |
|-----|-----|
| `cost-optimized` | `cost` |
| `balanced` | `balanced` (unchanged) |
| `quality-first` | `high` |
| `auto-mode-safe` | `/aih-automode --enable` (separate skill) |
| `performatic` | removed (was an alias; use `high`) |

**3. `.aihaus/.calibration` sidecar renamed to `.aihaus/.effort`**

The effort-state sidecar moves from `.aihaus/.calibration` (schema v2) to
`.aihaus/.effort` (schema v3). `/aih-update` automatically migrates v2 → v3
on the next run — no manual action required unless you have custom scripts
reading `.calibration` directly.

### Migration recipe

```bash
# 1. Rename any /aih-calibrate references in your personal scripts or docs:
rg -l '/aih-calibrate' . | xargs sed -i 's|/aih-calibrate|/aih-effort|g'
# Then review per-user muscle-memory docs, personal scripts, agent memory.

# 2. Permission-mode flags (--permission-mode, --preset auto-mode-safe)
#    moved to /aih-automode:
#    /aih-calibrate --preset auto-mode-safe  →  /aih-automode --enable

# 3. Run /aih-update — sidecar migrates to v3 automatically.

# 4. If you were on auto-mode-safe, re-run /aih-automode --enable to
#    replay side effects (hook/worktree changes are not auto-replayed).
```

---

## What changed

- **New skill: `/aih-automode`** — Dedicated permission-mode skill. Enable
  Claude Code auto-mode (`permissionMode: default`) via `/aih-automode --enable`;
  disable with `/aih-automode --disable`; check status with
  `/aih-automode --status`. Full caveat matrix printed before any change.
  Sidecar: `.aihaus/.automode` (2 fields: `enabled`, `last_enabled_at`).

- **Renamed skill: `/aih-calibrate` → `/aih-effort`** — Effort + model tuning
  only. Preset surface simplified to 3 names (`cost`, `balanced`, `high`).
  Permission-mode flags fully removed from this skill.

- **6-cohort taxonomy (replaces 5 cohorts)** — Uniform one-model-per-cohort
  design. Old cohort `:investigator` (3 agents) absorbed into `:doer`
  (byte-identical default tier). Old `:adversarial` (4 agents) split into
  `:adversarial-scout` (2, preset-immune, `(opus, max)`) and
  `:adversarial-review` (2, preset-immune, `(opus, high)`). Old `:planner`
  (17 agents) split into `:planner-binding` (4, xhigh) and `:planner`
  (13, high). The `verifier-rich` subset label is gone — agents reassigned
  individually.

- **Sidecar schema v2 → v3** — `.aihaus/.calibration` renamed to
  `.aihaus/.effort`. Automatic migration on `/aih-update`. Four named lossy
  migration cases emit `!!` stderr warnings (see `state-file.md`).

- **Restore scripts** — `pkg/scripts/lib/restore-effort.sh` (bash) and
  updated `install.ps1` / `update.ps1` (PowerShell) handle v2→v3 migration
  and preset-immunity enforcement via a shared `is_preset_immune` / `Test-PresetImmune`
  helper. All 4 install paths (bash + PowerShell, install + update) now
  apply cohort-level writes first, per-agent overrides second.

- **COMPAT-MATRIX updated** — `/aih-effort` and `/aih-automode` rows added
  with Cursor support verdicts. Smoke test suite extended to 30 checks
  (Check 27: skill count 13, Check 28: 6-cohort parse contract, Check 30:
  migration fixture round-trips).

---

## Cursor

**Cursor users:** The `/aih-calibrate` command has been renamed to `/aih-effort`
(and permission-mode work moves to `/aih-automode`). We cannot confirm whether
Cursor's fuzzy-match suggestion will automatically offer `/aih-effort` when
you type `/aih-calibrate` — the empirical test was deferred (no Cursor
environment was available at release time). Since `aih-calibrate` and `aih-effort`
share only the `aih-` prefix, fuzzy match on the old name is unlikely to surface
the new name automatically.

**Action required for Cursor users:** Please re-type `/aih-effort` (or
`/aih-automode`) manually if auto-suggest does not appear. If you can run
the 5-minute Cursor fuzzy-match test (type `/aih-calibrate`, observe whether
a suggestion appears), share the result at GitHub Discussions — it will inform
the M013 release notes.

Both `/aih-effort` and `/aih-automode` are Claude-Code-first. `/aih-automode`
requires hook-level side effects (`settings.local.json` merge) that Cursor
does not offer — see COMPAT-MATRIX for the full verdict.

---

## M013 follow-up

The following items are queued for M013 and are **out of M012 scope**:

- **Memory consumption + selective capture via hooks** — agent-memory files
  have grown organically across milestones. M013 will add structured pruning
  and selective capture heuristics (hook-based, not shipped to users).
- **Cursor fuzzy-match empirical confirmation** — once a team member with a
  Cursor install validates the `/aih-calibrate` → `/aih-effort` suggestion
  behavior, update `cursor-fuzzy-match-test.md` and the M013 release notes.

---

*Generated from milestone M012-260417-cohorts-effort-automode. Hand-edited
for BREAKING banner, migration recipe, Cursor section, and M013 note.*
