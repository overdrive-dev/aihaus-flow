# aih-brainstorm annex: Phase 7.5 Sub-Field Validator (M026+ / ADR-260509-A I3)

Extends the existing 8-H2-header schema check at Phase 7.5 with per-OQ inline sub-field validation. **Composes** with the H2 check — never replaces it (per PATTERNS §2). Annex-split per CHECK F2 (SKILL.md was at 199-line cap; annex carries full validator logic).

## Validator logic (awk-based per-OQ block scoping)

After the H2 header check at Phase 7.5 passes, run the sub-field validator:

```bash
# Sub-field validator (M026+ Alt D OQ schema)
# Skips legacy schema-v1 BRIEFs (where **Panel-Confidence:** absent)
# Reports OQ#<N> + missing field name on first failure

awk '
  /^## Open Questions/ { in_oq=1; oq_num=0; next }
  in_oq && /^## / { in_oq=0 }
  in_oq && /^[0-9]+\. \*\*/ {
    if (oq_num > 0) check_block()
    oq_num++; rec=0; conf=0; defer=0; src=0; conf_value=""
  }
  in_oq && /\*\*Recommendation:\*\*/ { rec=1 }
  in_oq && /\*\*Panel-Confidence:\*\*/ {
    conf=1
    if (/Panel-Confidence:\*\* H( |$)/) conf_value="H"
    else if (/Panel-Confidence:\*\* M( |$)/) conf_value="M"
    else if (/Panel-Confidence:\*\* L( |$)/) conf_value="L"
  }
  in_oq && /\*\*Defer if:\*\*/ { defer=1 }
  in_oq && /\*\*Source:\*\*/ { src=1; src_line=$0 }
  END { if (oq_num > 0) check_block() }

  function check_block() {
    missing=""
    if (!rec) missing=missing "Recommendation,"
    if (!conf) missing=missing "Panel-Confidence,"
    if (!defer) missing=missing "Defer if,"
    if (!src) missing=missing "Source,"
    if (length(missing) > 0) {
      printf "OQ#%d missing field(s): %s\n", oq_num, substr(missing, 1, length(missing)-1)
      exit 1
    }
    # Citation grammar check on H/M Panel-Confidence (per ADR-260509-A I1)
    if ((conf_value == "H" || conf_value == "M") && src_line) {
      if (!match(src_line, /(PERSPECTIVE-[a-z-]+(\.r2)?\.md:L?[0-9]+-L?[0-9]+|CONVERSATION\.md ## Turn [0-9]+|pkg\/\.aihaus\/.+:L?[0-9]+-L?[0-9]+|\.aihaus\/.+ (F[0-9]+|A[0-9]+|L[0-9]+))/)) {
        printf "OQ#%d Panel-Confidence:%s requires file:line citation in **Source:**; got: %s\n", oq_num, conf_value, src_line
        exit 1
      }
    }
  }
' .aihaus/brainstorm/<slug>/BRIEF.md
```

## Legacy permissive gate (pre-M026 schema-v1)

If `## Open Questions` is absent OR has no `**Panel-Confidence:**` markers anywhere → skip sub-field validation entirely (legacy BRIEFs). Field-presence detection:

```bash
if ! grep -q '\*\*Panel-Confidence:\*\*' .aihaus/brainstorm/<slug>/BRIEF.md; then
  # Legacy schema-v1 — skip sub-field validation
  exit 0
fi
```

## Failure mode

On sub-field violation, abort with:

```
BRIEF.md at <slug> failed sub-field validation — OQ#<N> missing field(s): <list>.
Re-run /aih-brainstorm <slug> or patch BRIEF.md manually before promoting.
```

On citation grammar violation:

```
BRIEF.md at <slug> failed Source grammar — OQ#<N> Panel-Confidence:<H|M> requires file:line citation in **Source:**.
```

## Composition rule (binding)

The H2 header check (existing at Phase 7.5 L148-168) runs FIRST. If it fails, abort with the existing schema-validation error. Only on H2 pass does the sub-field validator run. Both gates are required — never replace one with the other.
