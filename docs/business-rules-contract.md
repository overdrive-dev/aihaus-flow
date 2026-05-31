# Plan — The Business-Rules Contract

*A living, incremental, code-bound business-rules ledger as the decision-autonomy substrate for aihaus agents.*

> **Status:** proposal for review. Framed in business-rule + BDD terms on purpose — it dogfoods the very model it proposes.

---

## 0. Premise & thesis

The system serves business rules. If we encode **all business-rule premises** into a single living, reviewable contract, then an agent **derives every decision from that contract** instead of re-asking the client. The client front-loads the premises once; the contract converts that one-time input into **permanent agent decision-authority**.

**BDD (Given/When/Then) is the lingua franca** — not decoration. A rule written as scenarios is (a) unambiguous, (b) testable, and (c) *already* the failing tests the `tdd` stage needs. So BDD is simultaneously the interaction language, the rule format, and the test source. One artifact, three jobs.

**The autonomy law (the whole point):**

| Situation | Agent behavior |
|-----------|----------------|
| Decision is **covered** by a rule | Decide alone. **Cite the rule ID** (decision provenance). Never ask. |
| Decision hits a **gap** (no rule, business-visible behavior) | Pause — this is the *only* TRUE blocker. Ask the client. **The answer becomes a new rule.** |
| Decision hits a **conflict** (two rules disagree) | Surface the contradiction. Ask which wins. **Record the resolution as a rule.** |
| Decision is **pure mechanics** (no business-visible behavior) | Decide alone. No rule required (explicit exemption — see §7). |

Autonomy = contract coverage. Every blocker answered grows the contract by exactly the premise that was missing. This is the closed loop Victor's theory describes, made operational.

---

## 1. How it rides on what already exists (this is *not* greenfield)

| Existing primitive | Becomes |
|--------------------|---------|
| `BUSINESS-RULES.md` (per-plan, from `plan-calibrator`, M027) | Promoted to a **project-wide, incremental ledger** (the contract). |
| `BR-1` / `BR-8` / `BR-9` already in `workflows/default.md` | First-class rule records in the ledger (formalized, not hardcoded in prose). |
| `calibrate-guard.sh` (M029) — blocks unanswered ambiguity | Extended into the **rule-gate** (no flow advances without a linked, testable rule). |
| aih-graph 6 node types (Decision/Milestone/Story/Agent/Hook/Skill) | Add a **7th: `Rule`** — with bidirectional code edges. |
| `decisions.md` (fixed, incremental, reviewed ADR ledger) | The *pattern* we mirror for the BR ledger (proven shape). |
| `context-inject.sh` (SubagentStart) | Injects the **relevant rule slice** into every agent. |
| The "no option menus / decide, don't ask" autonomy protocol | Gets its missing half: *what* the agent is allowed to decide alone — the contract. |

The work is an **evolution of the calibration/decision substrate**, not a new stack.

---

## 2. The contract — schema & domains

**One ledger, namespaced by domain** (single source, `domain:` field — *not* three separate files, so cross-domain rules don't orphan; follows the M028 flat-namespace governance rule).

Domains (initial): `software` · `design` · `infra`. Extensible (e.g. `security`, `data`, `compliance`) — but each new domain is itself a recorded decision.

**Rule record schema:**

```
BR-<id>
  domain:        software | design | infra | …
  statement:     <one line, business language — WHAT must hold, never HOW>
  scenarios:     <≥1 Given/When/Then>           # the testable core; feeds tdd
  status:        proposed | accepted | deprecated
  source:        <who defined the premise + when>   # provenance of the premise
  rationale:     <why this rule exists>
  links:
    implements:  [<symbol|file|test ids>]        # ← aih-graph edges (§3)
    relates:     [BR-<id>…]                       # rule↔rule
    decided-by:  [ADR-<id>…]                       # rule↔ADR (cites, never owns)
  last-reviewed: <commit SHA>                      # staleness anchor (§3)
```

**The 3-ledger ownership boundary (must stay crisp or they bleed):**

- **BR ledger** = *what the system must do* (business behavior, invariants, domain rules).
- **ADRs (`decisions.md`)** = *how/why we chose a technical approach*.
- **`knowledge.md`** = *reusable how-to / findings*.

A rule may cite an ADR and vice-versa (that's a link) — but ownership never overlaps. Rule = behavior; ADR = approach; knowledge = technique.

---

## 3. Code ↔ rule traceability (the aih-graph `Rule` node)

The holy grail of maintainability: *"why does this code exist?" → BR-id*, and *"where is BR-id implemented?" → these functions + tests*.

- New `Rule` node + **bidirectional edges**: `Rule —implements→ {symbol, file, test}`.
- Two queries (both directions):
  - `aihaus memory rule BR-42 --json` → the implementing code + tests + status.
  - `aihaus memory why <symbol> --json` → the rule(s) this code serves.
- **Staleness — the load-bearing part.** aih-graph already has SHA change-detection + `impact`/`callers`. We flag a rule **stale** when its linked code changed but the rule wasn't re-reviewed (`last-reviewed` SHA predates the code's). A `rule-drift` report surfaces these.

> **Honest core risk:** creating the links is easy; keeping them true as code moves/renames is the real engineering. A **stale contract is worse than none** — the agent decides *confidently wrong* from outdated premises. So the staleness flag is not polish; it is what makes the autonomy law safe to trust.

---

## 4. Determinism — the gates (this answers "obrigar o agente")

You cannot force the *model* to invoke anything (auto-invoke is model-judgment). In an agent system you never control the brain — only the **hands**, via hooks. So we don't force the call; we **forbid the bypass**:

- **`flow-guard.sh`** (PreToolUse) — blocks any code mutation (Write/Edit/mutating Bash) when **no active dispatch sentinel** exists. Sub-flows write the sentinel on entry (precedent: `aih-plan` writes `.claude/_state/active-slug`; the kanban task sits in an execution stage). No flow → edit rejected: *"route through a sub-flow first."* Escape: `aih-quick` is the **minimal flow** (already sets/clears bypass env at Step 0/6, like `tdd-guard`). Emergency opt-out `AIHAUS_FLOW_GUARD=0`, audited.
- **`rule-gate`** (extends `calibrate-guard.sh`) — blocks a task from crossing `planejamento → tdd` without **≥1 linked rule carrying testable BDD criteria**. Reuses the existing ambiguity regex; adds the rule-link check.
- **BDD-as-tests** — the `tdd` stage consumes each rule's `Given/When/Then` directly as the failing tests it already must write. No new test authoring concept.

Every guarantee is a hook (the aihaus deterministic layer), with an opt-out env + a JSONL audit row — same family as `tdd-guard`, `role-guard`, `git-add-guard`, `autonomy-guard`.

---

## 5. BDD as the interaction discipline (every conversation, by default)

The framing must hold across the whole spine, not just at planning:

- **entendimento** — restate the ask as rules + scenarios, in business language (never implementation).
- **planejamento** — resolve rule gaps; record rules + BDD criteria; `rule-gate` enforces.
- **tdd** — scenarios → failing tests.
- **review-execucao / testes / homolog** — every piece of evidence maps back to a scenario.

Enforcing the *framing* (vs the artifact) is model-judgment, so we reinforce it two ways: (a) a **top-level Output Style** that bakes "speak in business-rule/BDD terms; cite rule IDs; decide-from-contract" into the session system prompt (this is the A1 finding from the optimization research — the BR contract is its highest-value first use), and (b) `context-inject` puts the relevant rule slice + the autonomy decision-table in front of every agent.

---

## 6. Story breakdown (each with its own acceptance scenario)

| # | Story | Acceptance (Given/When/Then) |
|---|-------|------------------------------|
| **S1** | BR-ledger schema + storage + 3-ledger boundary doc | *Given* a new rule, *When* recorded, *Then* it carries id/domain/statement/scenarios/status/links and passes a schema check; a boundary doc states BR≠ADR≠knowledge. |
| **S2** | `Rule` node in aih-graph + bidirectional code binding | *Given* BR-42 linked to a symbol, *When* `aihaus memory rule BR-42`, *Then* it returns the implementing code + tests; *When* `aihaus memory why <symbol>`, *Then* it returns BR-42. |
| **S3** | Staleness / `rule-drift` detection | *Given* linked code changes without a rule re-review, *When* the drift check runs, *Then* the rule is flagged stale with both SHAs. |
| **S4** | `flow-guard.sh` (determinism / Q1) | *Given* no active flow, *When* a code mutation is attempted, *Then* it is blocked; *Given* `aih-quick` active, *Then* allowed. |
| **S5** | `rule-gate` (extend `calibrate-guard`) | *Given* a task with no linked testable rule, *When* it tries `planejamento → tdd`, *Then* blocked with the missing-rule reason. |
| **S6** | Autonomy decision-table + provenance, wired into agents + a top-level Output Style | *Given* a covered decision, *When* the agent proceeds, *Then* it decides and cites the rule (no client question); *Given* a gap, *Then* it pauses, asks, and writes the answer as a new rule. |
| **S7** | `/aih-init` seeds initial rules from the codebase + migrates `BUSINESS-RULES.md` → ledger | *Given* a repo, *When* `/aih-init` runs, *Then* a seed ledger exists with at least the BR-1/8/9 rules formalized. |

**Sequencing:** S1 → S2 → S3 (the substrate, in order). S4 and S5 (the gates) parallelize after S1. S6 ties the autonomy law to the substrate. S7 bootstraps. Worktree isolation + Owned-Files sharding per ADR-260529-A keeps any parallel stories conflict-free.

---

## 7. Risks & tensions (adversarial — flagged, with mitigations)

1. **Binding rot** (main risk) — keeping rule↔code true as code changes. → S3 staleness flag + `rule-drift` report; the flag is load-bearing.
2. **"Silence = freedom or gap?"** — the subtle epistemic problem: when no rule covers a decision, is it *intentionally unconstrained* or *forgotten*? → The contract can carry **explicit "unconstrained — implementer's discretion" rules** for known-free areas; the default heuristic is *business-visible behavior with no rule → treat as gap (ask); pure mechanics → decide*. This is the same line as the mechanical exemption.
3. **Full-ledger-per-request cost** — reviewing every rule each turn doesn't scale. → Per-request retrieves only the **relevant slice** (aih-graph semantic) + a cheap "does this contradict an existing rule?" check. Full-ledger review is **periodic** (drift audit), not per-request.
4. **Vacuous rules** — forcing BDD on trivia breeds fake rules ("BR: name the var x"), the *green-but-vacuous* anti-pattern the system already fights (M025/M026). → Mechanical/no-behavior-change work is **explicitly exempt**; the rule-gate checks for *testable* criteria (non-vacuous by construction).
5. **3-ledger bleed** — BR/ADR/knowledge overlapping. → Strict ownership boundary (§2), enforced by an S1 doc + review.
6. **Over-rigidity** — hard determinism creating daily friction. → `aih-quick` as the minimal-flow escape; emergency opt-outs; strictness is a tunable default (§8 open premise).
7. **Bootstrapping completeness** — a thin early contract can't ground much. → `/aih-init` seeds from the codebase; the contract accretes one answered gap at a time; autonomy grows with it (that's the design, not a bug).

---

## 8. Genuine contract gaps — premises only the client can set

*Dogfooding the model: these are the gaps **I** hit designing this. They're business premises, so they're yours. Everything else I've defaulted in the plan above; these I left open on purpose.*

1. **Domains** — start with `software · design · infra`? Add `security` / `data` / `compliance` now, or let them accrete?
2. **flow-guard strictness (default)** — hard-block every ad-hoc edit (maximal determinism, friction up front), or warn-first then escalate to block? (You said "deterministicamente obrigado" → I've defaulted to **hard-block with `aih-quick` as the escape**; confirm or soften.)
3. **Ledger residence** — markdown ledger as source-of-truth + aih-graph `Rule` node as the queryable index (my default), or aih-graph-native with markdown projected out?
4. **Provenance depth** — must *every* autonomous decision cite a rule ID in its commit/output (full auditability, more verbosity), or only behavior-affecting ones (my default)?

These four answers become the **founding rules** of the contract.

---

## 9. Definition of done (the closed loop)

A change to ruled behavior **cannot land** without all of: an active flow (`flow-guard`) → a linked, testable rule (`rule-gate`) → tests generated from the rule's BDD scenario → a fresh rule↔code binding (no staleness flag). And mid-flow, the agent **decides every contract-covered question alone, citing the rule**, pausing only on a genuine gap — whose answer permanently extends the contract.

That is the theory made enforceable: *the agent decides from the fundamentals; the hooks guarantee nothing escapes them.*
