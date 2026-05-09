# Open Questions — Alt D Schema (M026+ / ADR-260508-B)

**Canonical definition.** Consumed by `brainstorm-synthesizer`, validated by
`aih-brainstorm/annexes/sub-field-validator.md` (Smoke Check 77). Any skill or
agent that emits `## Open Questions` in a BRIEF.md MUST conform to this schema.

---

## OQ Block Schema

Each numbered Open Question MUST ship inline sub-fields:

```markdown
1. **<Question text>**
   - **Recommendation:** <single-classification path-forward; NOT A/B/C menu — autonomy-protocol §TRUE-blocker scoping>
   - **Panel-Confidence:** H | M | L
   - **Defer if:** <criterion under which OQ defers to PLAN-time decision>
   - **Source:** <PERSPECTIVE-<role>.md:Lstart-Lend | CONVERSATION.md ## Turn N | pkg/.aihaus/<path>:Lstart-Lend>
```

---

## Sub-field Semantics

| Field | Required | Description |
|-------|----------|-------------|
| `**Recommendation:**` | Always | Single-classification path-forward. NOT an A/B/C menu. Autonomy-protocol §TRUE-blocker scoping applies. |
| `**Panel-Confidence:**` | Always | Synthesizer's confidence about the PANEL's commit: `H` (high), `M` (medium), or `L` (low). Use `L` when uncertain — synthesizer cannot read substrate. |
| `**Defer if:**` | Always | Criterion under which the OQ defers to PLAN-time decision rather than being resolved in the BRIEF. |
| `**Source:**` | Always (citation grammar required for H/M) | File + line citation proving provenance. `L` Panel-Confidence may use prose-only attribution. |

---

## Citation Grammar (binding for `Panel-Confidence: H` or `M`)

`**Source:**` value MUST match one of these patterns (Smoke Check 77 enforces):

```
PERSPECTIVE-<role>(\.r2)?\.md:Lstart-Lend
CONVERSATION.md ## Turn N
pkg/.aihaus/<path>:Lstart-Lend
.aihaus/<path> `(F<N>|A<N>|L<N>)`
[A-Z][A-Z-]*\.md `(F<N>|A<N>|L<N>)`
```

As regex (used by sub-field-validator.md and Smoke Check 77):
```
PERSPECTIVE-[a-z-]+(\.r2)?\.md:L?[0-9]+-L?[0-9]+
CONVERSATION\.md ## Turn [0-9]+
pkg/\.aihaus\/.+:L?[0-9]+-L?[0-9]+
\.aihaus\/.+[ `]+(F[0-9]+|A[0-9]+|L[0-9]+)
[A-Z][A-Z-]*\.md[ `]+(F[0-9]+|A[0-9]+|L[0-9]+)
```

`L` Panel-Confidence may use prose-only attribution (no regex enforcement).

---

## Synthesis Stance-Marker (companion discipline)

Every Synthesis bullet in BRIEF.md ships with a mandatory `**Stance:**` bold-prefix marker indicating panel commit:

```markdown
- **Stance:** ratified by 3/3 R2
- **Stance:** dissented by analyst R2
- **Stance:** uncertain — defer to PLAN
```

Eliminates two-surface scanning (synthesizer + panelist files).

---

## Legacy Permissive Gate (schema-v1)

BRIEFs without `**Panel-Confidence:**` anywhere skip sub-field validation entirely. Detection:

```bash
if ! grep -q '\*\*Panel-Confidence:\*\*' BRIEF.md; then
  # Legacy schema-v1 — skip sub-field validation
  exit 0
fi
```

---

## Consumers

| Consumer | Role |
|----------|------|
| `pkg/.aihaus/agents/brainstorm-synthesizer.md` | Writes OQs per this schema |
| `pkg/.aihaus/skills/aih-brainstorm/annexes/sub-field-validator.md` | Validates per-OQ sub-field presence + citation grammar |
| `tools/smoke-test.sh` Check 77 | Enforces citation grammar on shipped `BRIEF.md` fixtures |
| `pkg/.aihaus/skills/aih-brainstorm/annexes/panelist-template.md` | R2 panelist `## Recommendations` section uses compatible grammar (synthesizer aggregates into OQ sub-fields) |

---

## Minimum OQ count

If fewer than 3 OQs are present in BRIEF.md, downstream `/aih-plan --from-brainstorm`
skips its clarifying-questions step. Precision in Recommendation + Panel-Confidence
matters proportionally more for small-OQ briefs.
