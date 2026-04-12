# Architectural Decisions

## ADR-001 — Skill-to-Agent Delegation Mandate
**Date:** 2026-04-12
**Status:** Accepted

**Context:** Skills historically did specialist work inline (triage, review, verify). 27 of 41 specialist agents had no invocation path, which defeated their purpose and made the system rely on the parent Claude's general capabilities instead of specialist protocols.

**Decision:** All skills MUST delegate to specialist agents where one exists. Inline implementation of agent responsibilities is forbidden. Skills become thin orchestrators.

**Consequences:** Agents remain single-sourced. Adversarial contracts apply uniformly. Iteration caps (2-3 rounds) prevent cost explosion. Slight latency increase on fast commands is acceptable — caps and model-tier selection (sonnet for light agents) keep cost bounded.

## ADR-002 — Adversarial Review Contract
**Date:** 2026-04-12
**Status:** Accepted

**Context:** Confirmation bias produces rubber-stamp reviews. The `plan-checker` agent already implemented a mandatory problem-finding contract ("zero findings triggers halt"), but code-level, verification-level, integration-level, and security-level reviews had no such gate.

**Decision:** All review-role agents operate under the Adversarial Contract: "Your review fails if you return zero findings without written justification. Operate with cynical stance. If after thorough analysis you find nothing, you MUST explicitly list what you checked and why each is clean, plus flag what you could not verify."

**Affected agents:** code-reviewer, verifier, integration-checker, security-auditor (plan-checker already conformed).

**Consequences:** Slightly noisier review output; dramatically fewer missed defects. Reviewers must produce evidence even in the "no issues found" case. The human still filters for false positives — BMAD's acceptance criterion.

## ADR-003 — Multimodal Attachment Persistence
**Date:** 2026-04-12
**Status:** Accepted

**Context:** Users paste images (screenshots, mockups, error screens) during gathering and planning. Claude Code caches them at `~/.claude/image-cache/[uuid]/[n].png`. The parent Claude can Read them in-session, but subagents receive only a string prompt — images don't embed. Artifacts had no record of attachments. Future sessions and `/aih-resume` lost them entirely.

**Decision:** All scoping and execution skills persist pasted attachments under `.aihaus/[artifact-type]/[slug]/attachments/` and reference them in an `## Attachments` section of the corresponding artifact file (CONTEXT.md, PLAN.md, TRIAGE.md). When a skill spawns an agent, the prompt includes an Attachments block with paths — agents Read them via the Read tool. Selected agents (analyst, product-manager, architect, debugger, code-reviewer, ux-designer) get a Multimodal Context protocol line making attachment reading mandatory when present.

**Consequences:** Visual context survives across sessions and agent boundaries. Adds ~10 lines per skill for detection + copy + description. Attachments are git-tracked under `.aihaus/` — redaction responsibility is on the user (reminder surfaced at copy time).
