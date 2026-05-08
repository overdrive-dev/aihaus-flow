# aih-brainstorm annex: Panelist-Template Composed Prompt (M026+ / ADR-260509-A I4)

Mandatory sub-rules block for Phase 3 (R1) AND Phase 4 (R2) panelist prompts. R1+R2 binding per contrarian F8 (rules ship as panelist-template not R2-only). Per PATTERNS §4 (Phase 7 synthesizer minimal-prompt analog + team-template.md mandatory-sub-rules pattern).

## Mandatory sub-rules (binding, R1+R2)

Every panelist prompt MUST include these sub-rules verbatim:

### 1. Citation grammar (ground-check rule per PM R1+R2)

Every claim attributing to another panelist or substrate file MUST cite by `<file>:<line>` or `CONVERSATION.md ## Turn N`. Quoted claims without filename + line citation fail the contract.

Example PASS:
> "Per `PERSPECTIVE-architect.md:L42-L48`, the synthesizer's single-file write scope is binding."

Example FAIL:
> "The architect said the synthesizer write scope is binding." (no file:line citation)

### 2. Argue-against discipline (R2 only — UX R1+R2)

In Round 2, panelists MUST argue against their own R1 stance OR emit `NO-R1-DISSENT-JUSTIFIED` with written rationale (NOT silent ratification). The fail-closed token is acceptable when no genuine R1 dissent surfaces.

Example PASS (dissent):
> "Argued against own R1 stance: my R1 §3 recommendation of X is wrong because [substrate evidence]. Walking back to Y."

Example PASS (fail-closed):
> "NO-R1-DISSENT-JUSTIFIED: re-traced R1 reasoning at PERSPECTIVE-<role>.md:L20-L40; substrate evidence corroborates; no scope-axis or premise-axis dissent surfaces. Ratifying R1 with full citation chain."

Example FAIL:
> Silent ratification (extending R1 without challenging any premise).

### 3. Per-OQ Recommendation discipline (Alt D — folds with S1a synthesizer schema)

R2 panelist perspectives MAY end with a `## Recommendations` section using Alt D's grammar at write-time (not mandatory at panelist layer; synthesizer aggregates):

```markdown
## Recommendations

1. **Recommendation:** <single-classification path-forward>
   **Confidence:** H | M | L (panelist-level confidence; synthesizer renames to Panel-Confidence)
   **Source:** <CONVERSATION.md ## Turn N | PERSPECTIVE-<role>.md:Lstart-Lend | pkg/.aihaus/<path>:Lstart-Lend>
```

The synthesizer's Phase 7 aggregates these into BRIEF Open Questions sub-fields (per ADR-260509-A I1).

## Drops (per ADR-260509-A absorption)

- **Analyst's scope-dissent rule** — redundant per analyst R2's own concession (composed PM ground-check + UX argue-against catches both M025 PM-R2 fabrication AND R2-frame-ratification anti-pattern).
- **UX auto-R3 escape hatch** — walked back per UX R2 (M025 R3 was workaround for under-disciplined R2; composed prompt eliminates need; hard cap stays 2 rounds).
