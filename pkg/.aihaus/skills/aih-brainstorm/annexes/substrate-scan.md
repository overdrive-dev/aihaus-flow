# aih-brainstorm annex: Phase 6.5 Substrate Scan (M026+ / ADR-260509-A I2)

Opt-in via `--substrate` flag. Spawned between Phase 6 (research) and Phase 7 (synthesis). Catches 55-64% of substrate-discoverable BLOCKERs per F1-VERIFICATION classification. Complements (not replaces) plan-checker's adversarial-review domain.

## Mechanic

When `--substrate` is present:

1. **Spawn `assumptions-analyzer`** (`subagent_type: "assumptions-analyzer"`) with brainstorm-shape input scope. Use this minimal prompt:

   ```
   You are the substrate-scan analyzer for the brainstorm at `.aihaus/brainstorm/<slug>/`.
   Read every PERSPECTIVE-*.md and identify files referenced in CONVERSATION.md Turn 1.
   Read those files at HEAD. Surface substrate findings (regex catalog conflicts,
   ownership rule violations, sequence traps, missing dependencies) the panel could
   not discover from prose alone.

   Write findings to a string payload in your existing `## Output Format` shape:
   ## Assumptions
   ### <Area>
   **Assumption:** ...
   **Why this way:** ...
   **If wrong:** ...
   **Confidence:** Confident | Likely | Unclear
   ## Needs External Research
   ...

   Return the full string payload — the skill writes it verbatim to SUBSTRATE-FINDINGS.md.
   Read-only on substrate; no writes outside the agent's `Output Format` payload.
   ```

2. **The skill** writes `.aihaus/brainstorm/<slug>/SUBSTRATE-FINDINGS.md` verbatim from agent return (PM Path B Option α — preserves synthesizer's single-file write scope; preserves ADR-001 single-writer).

3. **The skill** appends a substrate turn block to `CONVERSATION.md` summarizing the finding count.

## SUBSTRATE-FINDINGS.md schema (= assumptions-analyzer's existing output, NOT extended)

Per CHECK F3 absorption — drop invented schema; use agent's existing `## Output Format`:

```markdown
# Substrate Findings — <slug>

## Assumptions
### <Area 1>
**Assumption:** ...
**Why this way:** ...
**If wrong:** ...
**Confidence:** Confident | Likely | Unclear

### <Area 2>
...

## Needs External Research
- [ ] <topic>: <why this needs research>
```

**Blocker semantics derived from `**Confidence:** Unclear`** — entries marked Unclear are interpreted by synthesizer as candidate Open Questions or contrarian-input. No invented "Blocker flag" or "VERIFIED/CITED/ASSUMED" tag fields.

## Synthesizer integration

Phase 7 synthesizer reads SUBSTRATE-FINDINGS.md as new conditional input (alongside RESEARCH.md). Synthesizer surfaces substrate findings in `## Synthesis` with `**Stance:**` markers; integrates substrate concerns into Open Questions Recommendations with `**Source:**` citations referencing `pkg/.aihaus/<path>:Lstart-Lend` from substrate findings.

## Failure mode

If `assumptions-analyzer` returns malformed payload (no `## Assumptions` header) or fails:
- Skill logs error to CONVERSATION.md as a substrate turn block
- Skill writes minimal SUBSTRATE-FINDINGS.md with `# Substrate Findings — <slug>\n\n(scan failed; see CONVERSATION.md)` body
- Synthesizer's "if present" guard handles cleanly — BRIEF still ships from R1/R2 inputs
- This is the partial-fail mode worked example in ADR-260509-A
