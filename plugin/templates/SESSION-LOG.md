# Session Log: <milestone-slug>

**Generated:** <ISO date>
**Milestone:** <M0XX>-<slug>
**Generator:** `/aih-update --session-log <slug>`

Post-hoc retrospective. Opt-in — this log exists because a user invoked the subcommand, not because a milestone completed. Sections below are filled by `aih-update` from existing on-disk artifacts (RUN-MANIFEST.md, CHECK.md, VERIFICATION.md, reviewer reports, `.claude/audit/*.jsonl`).

---

## Timeline

_Derived from RUN-MANIFEST.md Progress Log + Story Records. One bullet per notable event: phase transitions, story completes, sub-agent spawns, plan-checker verdicts._

- <ISO ts> — <event>

---

## Friction

_From CHECK.md findings + reviewer reports. Pain points the milestone encountered, what the fix was._

- **F1 — <short label>**: <what happened, how resolved>

---

## Wins

_From VERIFICATION.md, INTEGRATION.md, reviewer PASS verdicts. Things that worked well and are worth repeating._

- **W1 — <short label>**: <what worked>

---

## Ideas for package

_Self-evolution suggestions pulled from plan-checker / reviewer `common-findings.md` additions during this milestone. Numbered suggestions for future improvement._

1. <idea>

---

## Artifacts

- PLAN.md: `<path>`
- PRD.md: `<path>`
- architecture.md: `<path>`
- CHECK.md: `<path>`
- VERIFICATION.md: `<path>`
- stories/: `<path>`
- attachments/: `<path>`

---

## Hand-off

_Next command the user is likely to run._

```bash
<next-command>
```
