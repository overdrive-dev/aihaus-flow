# CLI Surface Detail — `--cohort`, `--agent`, Phase-4 v2 sidecar write

Extracted from SKILL.md to stay under the 200-line cap (plan-check F10
mitigation). This annex documents the M010 CLI surface additions, the
adversarial-bypass layered prompt, and the exact shape of the `schema=2`
sidecar write performed in Phase-4 step 20.

## CLI validation rules (D-2, D-3)

| Invocation | Verdict |
|------------|---------|
| `--preset <name>` | ALLOWED — iterates cohort tuples from `annexes/presets.md`; skips `:adversarial`; applies override rows |
| `--cohort :<name> --model X --effort Y` | ALLOWED (both axes required) |
| `--cohort :<name>` with single axis | REJECTED — clear error, no commit |
| `--cohort :adversarial --model X --effort Y` | ALLOWED **only after** literal-word `adversarial` confirmation |
| `--agent <name> --effort Y` | ALLOWED (v0.13 effort-only preserved) |
| `--agent <name> --model X --effort Y` | ALLOWED — ADR-M008-A amendment, D-3 dual-axis escape |
| `--agent <name> --model X` alone | REJECTED |
| bare `--model X` or `--effort Y` | REJECTED |

Argument parser for `--cohort`: leading `:` is literal (matches docs),
but accept `:planner` or `planner` defensively (strip optional leading
`:` during parse; error if name not in the 4-cohort set).

## Adversarial bypass — layered full-word confirmation

When the invocation explicitly targets the `:adversarial` cohort
(`--cohort :adversarial --model X --effort Y` or `--agent <member>
--model X --effort Y` where `<member>` ∈ {`plan-checker`, `contrarian`,
`reviewer`, `code-reviewer`}), Phase-3 inserts a second prompt AFTER the
standard step-10 confirm:

```
!! Você está alterando a tier adversarial (ADR-M008-C / ADR-M010-A).
!! Estes agentes produzem findings bindings no fluxo de review.
!! Para confirmar, digite a palavra `adversarial` (qualquer outra
!! resposta aborta):
```

Any response other than the literal string `adversarial` aborts with no
edits and no commit. Analogous to the auto-mode-safe full-word pattern
(ADR-M008-B precedent). Autonomy-protocol compliant: literal-word
confirmation is not an A/B/C menu — it's an explicit high-blast-radius
gate.

## Joint-tuple Edit application (Phase-3 step 14)

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

## Phase-4 step 20 — v2 sidecar write

After the commit + smoke-test/purity gate pass (step 18 green), write
`.aihaus/.calibration` as `schema=2`. Layout follows
`annexes/state-file.md` § Schema v2.

```
schema=2
permission_mode=<current>
last_preset=<preset-or-custom>
last_commit=$(git rev-parse --short HEAD)

# Cohort-level — one per cohort TOUCHED by this invocation.
# Preset runs emit :planner, :doer, :verifier rows (skip :adversarial).
# Explicit --cohort :adversarial invocations emit that row.
cohort.<name>.model=<m>
cohort.<name>.effort=<e>

# Per-agent override lines — for each member whose post-filter state
# differs from its cohort default, or for each --agent invocation.
<agent>=<effort>              # v1-compat grammar (effort axis)
<agent>.model=<m>              # v2 grammar (model axis)
```

### Write-time adversarial filter

Before serializing, filter the diff:

```
if invocation == --preset <name>:
  for member in :adversarial cohort lookup (cohorts.md):
    remove member from per-agent entries
    remove cohort.adversarial.* rows
```

On explicit `--cohort :adversarial` or `--agent <member>` invocations,
the filter is NOT applied — user intent is recorded.

### 20-guard / 20-ownership (inherited from v1)

- **20-guard** — if step 18 self-reverted the commit (`git reset` fired),
  SKIP the sidecar write. A stale sidecar with no matching commit would
  lie about repo state.
- **20-ownership** — NEVER `git add .aihaus/.calibration` under any mode.
  User-owned (ADR-M009-A); dogfood `.gitignore:19` covers it.

### v1 → v2 migration (D-4 — first-time write on v0.13.0 sidecar)

If a `schema=1` sidecar is present at the moment of writing:

```
for each cohort in [:planner, :doer, :verifier, :adversarial]:
  members = cohorts.md lookup
  if all members share (model, effort) in current frontmatter:
    write cohort.<name>.model=<m> + cohort.<name>.effort=<e>
  elif cohort == :adversarial:
    # expected non-uniform — no warning
    write cohort.adversarial.model=custom + cohort.adversarial.effort=custom
    preserve per-agent <member>=<effort> + <member>.model=<m>
  else:
    write cohort.<name>.model=custom + cohort.<name>.effort=custom
    preserve per-agent lines
    emit `!!` warning naming the cohort + remedy
```

Migration is write-once at calibrate time. `/aih-update` alone never
upgrades schema (preserves ADR-M009-A user-owned semantic).
