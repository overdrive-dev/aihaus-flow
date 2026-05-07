# Cadence Leak Fixture (M025/S03/Check 75)

This fixture demonstrates a cadence-noun template leak that Check 75 must catch.
Check 75 sub-assert verifies this fixture contains a matching pattern (so the
check itself isn't silently broken).

DO NOT modify the example below — it must permanently include the cadence-noun
template form for Check 75's regex assertion.

## Example Roadmap (synthesized — would trigger Check 75 if shipped to pkg/)

## Phase 1: {Synthesized Name For Fixture}
Goal: demonstrate the cadence-noun template form.

| REQ-001 | Phase 1 | SC-1.1 |
| REQ-002 | Phase 2 | SC-2.1 |

This file lives outside `pkg/.aihaus/skills/` and `pkg/.aihaus/agents/`, so the
production scan does NOT pick it up — the fixture-presence check at Check 75 reads
it directly via grep. Production scope is bounded by `${PACKAGE_ROOT}/.aihaus/{skills,agents}`.
