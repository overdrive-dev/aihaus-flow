# Brainstorm Escalation Protocol

Co-located helper for `/aih-brainstorm` conversational-default mode. Referenced from `SKILL.md` "Conversational Default Mode" section.

The orchestrating assistant (not a spawned agent) watches the ping-pong conversation for escalation signals. When a signal fires, propose escalation inline with **cost transparency** — state agent count + wall-clock estimate before asking consent. User consents per escalation.

## Escalation Surfaces

### Research Escalation
**Spawns:** one of `phase-researcher`, `advisor-researcher`, `domain-researcher`.

**Trigger signals (any one is sufficient):**
- User asserts a fact-dependent claim the assistant cannot verify from internal knowledge (e.g., "this framework supports feature X").
- A design branch pivots on unverified external detail — API capability, framework behavior, regulatory rule, version/changelog fact.
- The assistant has internal uncertainty flagged as ASSUMED in its own reasoning and the decision is load-bearing.

**Researcher selection:**
- `phase-researcher` — technical / unfamiliar framework / implementation pattern.
- `advisor-researcher` — market / vendor / landscape / competitor comparison.
- `domain-researcher` — regulatory / domain / compliance rules.

**Proposal template (verbatim shape):**
```
signal: <one-sentence description of the unknown>.
Worth ~2 min + 1 agent invocation to have <researcher-name> fetch and tag VERIFIED/CITED/ASSUMED. Spawn?
```

**On consent:** spawn researcher with the focused question. Researcher writes `RESEARCH.md`. Skill appends a research turn block to `CONVERSATION.md`. Resume ping-pong with the researcher's output in scope.

### Panel Escalation
**Spawns:** 2-3 specialists per the Phase 2 selection table (architecture / UX / domain rows).

**Trigger signals (any one):**
- Topic branches into specialist-heavy territory the assistant can't adequately cover — architecture deep-dives, UX/accessibility tradeoffs, security/threat-model questions, domain/regulatory details.
- The user explicitly asks for multiple perspectives ("what would the architect say?", "get me a panel").
- Ping-pong has stalled — two or more consecutive exchanges have produced no new information or framing.

**Proposal template:**
```
signal: <specialist domain> deep-dive warranted.
Worth ~5 min + 3 agents + 1 contrarian to consult <architect + advisor-researcher + phase-researcher>
(or <product-manager + ux-designer + analyst> | <domain-researcher + analyst + advisor-researcher>).
Spawn?
```

**On consent:** run Phase 2 (panel selection) through Phase 6 (contrarian) as defined in `SKILL.md`. Conversational mode resumes after the contrarian's turn appends.

### Synthesis Escalation
**Spawns:** `brainstorm-synthesizer` (in lightweight mode if no `PERSPECTIVE-*.md` exist).

**Trigger signals (any one):**
- User signals "wrap this up" / "write it up" / "let's move to /aih-plan".
- Conversation has matured toward a concrete, plan-worthy direction — a specific approach is identified with known tradeoffs and risks.
- User says any future-looking command-like phrase (`/aih-plan`, `/aih-milestone`) — synthesize first so the handoff has a BRIEF.

**Proposal template:**
```
signal: we have a concrete direction ready for /aih-plan handoff.
Worth ~1 min + 1 agent to write BRIEF.md per the 8-header contract. Write it?
```

**On consent:** spawn `brainstorm-synthesizer`. Phase 7.5 schema validator runs after write. Phase 8 handoff prints BRIEF.md path and Suggested Next Command.

## Cost-Transparency Rules (LOAD-BEARING)

1. Every proposal MUST state approximate agent count AND wall-clock estimate before asking consent. Rule: no silent spawns.
2. If the user declines an escalation proposal, do NOT re-propose the same escalation until new conversation signal justifies it. Repeat-pressuring is a violation.
3. If the user says "abandon" / "not pursuing" / "nevermind" at any turn: stop. Leave `CONVERSATION.md` + any artifacts already produced. Do NOT write `BRIEF.md`. Print: `Brainstorm ended without BRIEF.md — CONVERSATION.md preserved at <path>.`

## Anti-Pattern Guard

The failure mode this protocol prevents: running multi-agent autonomous fan-out *before* the user has indicated the idea deserves that weight. The protocol inverts the default — agents are spawned only after the conversation earns them.

If a user-invoked flag (`--panel`, `--deep`, `--research`) is present, this protocol is BYPASSED and `SKILL.md` Phase 2+ runs directly. Flag invocation is the user's explicit pre-commitment; conversational-default is the safer path when intent is unknown.
