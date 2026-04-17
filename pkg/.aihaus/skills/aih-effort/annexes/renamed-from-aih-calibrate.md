# Rename Note: aih-calibrate → aih-effort

This skill was previously named `aih-calibrate` (shipped in v0.13.0–v0.15.0).
It was hard-renamed to `aih-effort` in **v0.16.0** (milestone M012).

There is no backwards-compat shim. Typing `/aih-calibrate` returns
skill-not-found. Use `/aih-effort` for effort/model calibration and
`/aih-automode` for permission-mode calibration.

## Why

The name `aih-calibrate` conflated two distinct concerns — effort/model tuning
and permission-mode selection (the `--preset` auto-mode variant). M012 separates them:
`/aih-effort` owns effort calibration; `/aih-automode` owns permission-mode
calibration (extracted from this skill's `permission-modes.md` annex).

## References

- ADR-M012-A in `.aihaus/decisions.md` — supersedes ADR-M008-C + ADR-M010-A
- Release notes M012 — BREAKING banner + migration recipe
- Migration recipe: `rg -l '/aih-calibrate' . | xargs sed -i 's|/aih-calibrate|/aih-effort|g'`
