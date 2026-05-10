# Annex: `testing_discipline` Auto-Detection (Step 9.5 of aih-init)

**Purpose:** Detect the appropriate `testing_discipline` value during `/aih-init`
and seed it into the `## Practices` section of `project.md`. Preserves the
zero-prompt invariant — all detection is heuristic; no questions asked.

**Referenced by:** `aih-init/SKILL.md` Step 9.5
**ADR:** ADR-260510-A (testing_discipline schema)

---

## Detection Logic

Run all checks in order. Use the FIRST match that applies. Default to `none`
if no signal is detected.

### Signal: `tdd` (strongest — explicit opt-in evidence)

Detect if ANY of the following are true:

1. **Marker file present:**
   ```bash
   [ -f ".tdd-discipline" ]
   ```

2. **Commit convention in recent history:**
   ```bash
   git log --oneline -30 --format="%s" 2>/dev/null | grep -q "^tdd:"
   ```

### Signal: `test-after` (moderate — test infra exists but no TDD signal)

Detect if ALL of the following are true:
- No `tdd` signal detected above
- Test infrastructure is present (at least one of):

```bash
# Directory-based detection
[ -d "tests" ] || [ -d "__tests__" ] || [ -d "test" ] || [ -d "spec" ]
```

AND at least one framework is declared:

```bash
# package.json test script
node -e "const p=require('./package.json'); process.exit(p.scripts&&p.scripts.test?0:1)" 2>/dev/null

# pyproject.toml — pytest, unittest, or tox
grep -qE '^\[tool\.(pytest|tox)\]|testpaths\s*=' pyproject.toml 2>/dev/null

# Cargo.toml — Rust tests are built-in; presence of [dev-dependencies] signals test culture
grep -q '^\[dev-dependencies\]' Cargo.toml 2>/dev/null

# go.mod — Go test convention: _test.go files present
find . -maxdepth 3 -name "*_test.go" 2>/dev/null | grep -q .
```

### Default: `none`

No signals detected. Current behavior preserved. User may upgrade to `test-after`
or `tdd` manually post-install by editing `## Practices` in `project.md`.

---

## Write Contract

After detection, update the `## Practices` section in `project.md`:

**First-run (Step 10a):** The detected value is written directly into the
`testing_discipline: <value>` line when the template is copied. Replace
`testing_discipline: none` with `testing_discipline: <detected-value>`.

**Re-run (Step 10b):** The `## Practices` section lives outside the
`AIHAUS:AUTO-GENERATED` block; it is NOT overwritten on re-run. Skip Step 9.5
detection entirely on re-run mode — the user's current value is preserved.

**Constraint:** No prompts. If detection is ambiguous (e.g., `tests/` dir exists
but no framework declared), default to `none`. `test-after` requires BOTH a
test directory AND a framework signal.

---

## Examples

| Repo signal | Result |
|-------------|--------|
| `.tdd-discipline` file present | `tdd` |
| Last 30 commits include `tdd: fix login` | `tdd` |
| `__tests__/` dir + `"test": "jest"` in package.json | `test-after` |
| `tests/` dir + `[tool.pytest.ini_options]` in pyproject.toml | `test-after` |
| `test/` dir only, no framework config | `none` (ambiguous) |
| Clean greenfield project | `none` |
