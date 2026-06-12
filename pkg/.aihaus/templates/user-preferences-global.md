# User Preferences (aihaus tier C)

Global, cross-project user preferences. This file lives at
`~/.aihaus/memory/user/preferences.md` and follows you into every repository
where aihaus is installed (M050 / ADR-260611-E). Precedence per the aihaus
harness: **repo overrides global** — tier-B project ledgers (business rules,
decisions, repo-scoped preferences) always win on conflict (ADR-260611-A).

This file is written ONLY via `aihaus prefs add "<text>" [--topic <slug>]`
(lock-file-atomic append; ADR-260611-C). Do not hand-edit between the markers
below; direct agent Write/Edit to `~/.aihaus/memory/**` stays file-guard
blocked by design (BR-P7 — no carve-outs).

Entry format (validated before append; one line per preference):

    - PREF-<n> [YYYY-MM-DD] (<workflow|style|tooling|communication|other>) <one-line preference>

<!-- Examples (commented out — add real entries via `aihaus prefs add`):
  - PREF-1 [2026-06-11] (workflow) Prefer branch -> PR -> merge; never direct-to-main.
  - PREF-2 [2026-06-11] (communication) Answer in PT-BR; keep code identifiers in EN.
  - PREF-3 [2026-06-11] (tooling) Use ripgrep over grep for repo-wide searches.
-->

<!-- AIHAUS:PREFS-START -->
## Preferences
<!-- AIHAUS:PREFS-END -->
