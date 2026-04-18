# aih-plan annex: guardrails

## Must-nots

- MUST NOT create git branches.
- MUST NOT modify any source code, tests, configs, or migrations.
- MUST NOT write files outside `.aihaus/plans/` (except attachments dir during Phase 2 slug finalization).
- MUST NOT fabricate ADR content when the plan-checker emits an `INVOKE_OK` for `aih-quick draft-adr` — dispatch it or prompt the user to decline.

## Must-dos

- Create `.aihaus/plans/` if it does not exist.
- If the topic is too vague to plan after clarification, say so and ask what info is needed.
- Obey intake discipline (see `annexes/intake-discipline.md`).
- Obey attachment rules (see `annexes/attachments.md`).

## Output shape

PLAN.md must include: Problem Statement, Affected Files, Proposed Approach, Alternatives Considered, Risk Assessment, Estimated Scope, Suggested Next Command. Adversarial plan-checker gate (capped at 2 iterations) with Disposition-based verdict when CHECK.md has the column.
