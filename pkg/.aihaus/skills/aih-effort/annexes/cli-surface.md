# CLI Surface Detail — `--cohort`, `--agent`, Phase-4 v3 sidecar write

Extracted from SKILL.md to stay under the 200-line cap. This annex documents
the M012 CLI surface, the adversarial-bypass layered prompt, and the exact
shape of the `schema=3` sidecar write performed in Phase-4 step 17.

## CLI validation rules (ADR-M012-A)

| Invocation | Verdict |
|------------|---------|
| `--preset <name>` | ALLOWED — iterates cohort tuples from `annexes/presets.md`; skips adversarial cohorts via `is_preset_immune()` |
| `--cohort :<name> --model X --effort Y` | ALLOWED (both axes required) |
| `--cohort :<name>` with single axis | REJECTED — clear error, no commit |
| `--cohort :adversarial-scout --model X --effort Y` | ALLOWED **only after** literal-word `adversarial` confirmation |
| `--cohort :adversarial-review --model X --effort Y` | ALLOWED **only after** literal-word `adversarial` confirmation |
| `--agent <name> --effort Y` | ALLOWED (effort-only preserved) |
| `--agent <name> --model X --effort Y` | ALLOWED — ADR-M008-A amendment, dual-axis escape |
| `--agent <name> --model X` alone | REJECTED |
| bare `--model X` or `--effort Y` | REJECTED |
| `--permission-mode <m>` | REJECTED — exits nonzero; stderr: `--permission-mode flag removed in v0.16.0; use bash .aihaus/auto.sh for DSP launch` |

Argument parser for `--cohort`: leading `:` is literal (matches docs),
but accept `:planner` or `planner` defensively (strip optional leading
`:` during parse; error if name not in the 6-cohort set).

## Adversarial bypass — layered full-word confirmation

When the invocation explicitly targets an adversarial cohort
(`--cohort :adversarial-scout --model X --effort Y`,
`--cohort :adversarial-review --model X --effort Y`, or `--agent <member>
--model X --effort Y` where `<member>` is any of `plan-checker`, `contrarian`,
`reviewer`, `code-reviewer`), Phase-3 inserts a second prompt AFTER the
standard step-10 confirm:

```
!! You are mutating an adversarial cohort (ADR-M012-A / supersedes ADR-M008-C + ADR-M010-A).
!! These agents produce binding findings in the review flow.
!! To confirm, type the literal word `adversarial` (any other response aborts):
```

Any response other than the literal string `adversarial` aborts with no
edits and no commit. Autonomy-protocol compliant: literal-word confirmation
is not an A/B/C menu — it's an explicit high-blast-radius gate.

## Joint-tuple Edit application (Phase-3 step 11)

For each agent file in the diff:

1. Read file (Edit tool precondition — inherited ADR-M008-A discipline).
2. If target `model:` differs from current: `Edit "model: <old>" →
   "model: <target>"`.
3. If target `effort:` differs from current: `Edit "effort: <old>" →
   "effort: <target>"`.
4. If step 2 succeeds and step 3 fails: run `git checkout -- <file>` to
   restore the mid-state file before aborting the sequence. Two Edit
   calls per file when both axes differ; single Edit when only one
   differs; zero if the file is already at target.

Never use sed/awk — Edit's Read precondition is free safety.

## Phase-4 step 17 — v3 sidecar write

After the commit + smoke-test/purity gate pass (step 15 green), write
`.aihaus/.effort` as `schema=3`. Layout follows `annexes/state-file.md` § Schema v3.

```
schema=3
last_preset=<cost|balanced|high|custom>
last_commit=$(git rev-parse --short HEAD)

# Cohort-level — one per cohort TOUCHED by this invocation.
# Preset runs skip adversarial cohorts (is_preset_immune() filter).
cohort.<name>.model=<m>
cohort.<name>.effort=<e>

# Per-agent override lines — for each member whose post-filter state
# differs from its cohort default, or for each --agent invocation.
<agent>=<effort>              # effort-only grammar
<agent>.model=<m>             # model axis grammar
```

### Write-time adversarial filter

Before serializing, filter the diff:

```
if invocation == --preset <name>:
  for each cohort where is_preset_immune(cohort) returns true:
    remove all members of that cohort from per-agent entries
    remove cohort.<name>.* rows
```

On explicit `--cohort :adversarial-*` or `--agent <member>` invocations,
the filter is NOT applied — user intent is recorded verbatim.

### 17-guard / 17-ownership

- **17-guard** — if step 15 self-reverted the commit (`git reset` fired),
  SKIP the sidecar write. A stale sidecar with no matching commit would
  lie about repo state.
- **17-ownership** — NEVER `git add .aihaus/.effort` under any mode.
  User-owned (ADR-M009-A); `.gitignore` covers it.

### v2 → v3 migration (schema-upgrade on first `/aih-effort` invocation)

If a `schema=2` `.effort` (or `.calibration`) sidecar is present at write
time, run the v2→v3 migration documented in `annexes/state-file.md` §
Migration v2→v3 before writing v3. See also `pkg/scripts/lib/restore-effort.sh`
for the authoritative migration implementation.

For permission-mode calibration, use `bash .aihaus/auto.sh` (DSP launch via wrapper).
