# prefs-lock fixtures (Smoke Check 98 — M050/S06, ADR-260611-C/E)

Fixture-fail pairs for the `aihaus prefs add` tier-C write chokepoint,
exercised on BOTH shells (bash shim `pkg/scripts/aihaus` + PowerShell shim
`pkg/scripts/aihaus.ps1`) under a TEMP home override — the real
`~/.aihaus/**` is never written during smoke runs (BR-P3, BR-P8).

- `valid-entry.txt` — single-line entry text that MUST append (exit 0,
  `- PREF-1 ...` row + `"result":"ok"` audit row).
- `concurrent-a.txt` / `concurrent-b.txt` — launched in parallel; BOTH
  entries must land intact (mkdir-lock / FileStream-lock + temp + atomic
  rename), with distinct max-scan-allocated PREF ids and no temp-file or
  lock leftovers.
- `malformed-empty.txt` — empty entry text; MUST be refused (non-zero exit
  + `"result":"refused"` audit row). If it appends, the validation gate is
  green-but-vacuous (BR-P8).
- `malformed-multiline.txt` — embedded newline; MUST be refused (entry
  grammar is one line: `- PREF-<n> [YYYY-MM-DD] (<topic>) <text>`).
