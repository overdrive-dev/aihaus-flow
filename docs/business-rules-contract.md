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
| Decision is **covered** by a rule | Decide alone. **Cite the rule ID when it affects behavior** (BR-F4). Never ask. |
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

Domains (**founding — BR-F1**): `software` · `design` · `infra` · `security` · `data` · `compliance` (6, set upfront). Further domains are each a recorded decision.

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

- **`flow-guard.sh`** (PreToolUse) — enforces dispatch **at the promotion boundary** (BR-F2): a code mutation reaching an **online stage (`homolog`/`prod`) or production code** is rejected unless it arrives through an active flow (sentinel: `aih-plan` writes `.claude/_state/active-slug`; the kanban task sits in an execution stage). It **composes with `role-guard`** at that same boundary. Offline/dev edits stay free — but the only path to production runs through the gated stages, so **nothing lands in prod without the contract**. Emergency opt-out `AIHAUS_FLOW_GUARD=0`, audited.

  > **Reconciling with "deterministicamente obrigado":** the determinism lives at **what lands**, not at every keystroke. Local scratch is the dev's sandbox; the moment work promotes toward prod, `flow-guard` + `role-guard` + `rule-gate` bind it to the contract. Same boundary `role-guard` already owns — so this reuses the existing online frontier rather than inventing a new one.
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
| **S4** | `flow-guard.sh` — promotion-boundary determinism (Q1 / BR-F2) | *Given* a mutation reaching an online stage or production code with no active flow, *When* attempted, *Then* blocked (composes with `role-guard`); *Given* an offline/dev edit, *Then* allowed. |
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

## 8. Founding rules — premises set by the client

*The model in action: designing this, I hit four contract gaps; the client set the premises (2026-05-31). They are now the **founding rules** — `BR-F1..BR-F4`, the seed of the ledger.*

- **BR-F1 (domains)** — the contract covers **6 domains** from day one: `software · design · infra · security · data · compliance`. Further domains are each a recorded decision.
- **BR-F2 (determinism scope)** — `flow-guard` enforces dispatch **at the promotion boundary only**: online stages (`homolog`/`prod`) + production code. Offline/dev editing is free; nothing reaches production without an active flow + the contract. Composes with `role-guard` at the same boundary.
- **BR-F3 (residence)** — the **markdown ledger is the source of truth** (reviewable, git-diffable, like `decisions.md`); the aih-graph `Rule` node is the **queryable index** for code↔rule.
- **BR-F4 (provenance)** — an autonomous decision **cites its rule ID when it affects business behavior**; pure-mechanics decisions need no citation.

Proof of the loop: the contract grew by exactly the four premises the client defined.

---

## 9. Definition of done (the closed loop)

A change to ruled behavior **cannot reach production** without all of: promotion through an active flow (`flow-guard` + `role-guard` at the online boundary) → a linked, testable rule (`rule-gate`) → tests generated from the rule's BDD scenario → a fresh rule↔code binding (no staleness flag). Offline scratch is free; the gates bind it the moment it promotes. And mid-flow, the agent **decides every contract-covered question alone, citing the rule when it affects behavior**, pausing only on a genuine gap — whose answer permanently extends the contract.

That is the theory made enforceable: *the agent decides from the fundamentals; the hooks guarantee nothing escapes them.*
