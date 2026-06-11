# aihaus-flow: One Harness, Three Memory Tiers — Final Improvement Proposal

Synthesis: minimal-delta architecture (judges' unanimous winner), grafted with autonomy-first's provenance/citation substrate and clean-target's receipts + scratch-harvest, with every contrarian-refuted claim corrected and all four `missing_everywhere` gaps covered.

---

## 1. Where aihaus-flow is today

**Harness — four fragmented surfaces, no shared document:**
- `pkg/.aihaus/templates/claude/CLAUDE.md` — marker-managed block, orchestrator routing rule + 10 `@imports`. Main session only.
- `pkg/.aihaus/templates/claude/rules/aihaus-project-memory.md` — discipline prose. Main session only.
- `pkg/.aihaus/output-styles/aihaus-contract.md` — autonomy law. Opt-in, top-level only, subagent propagation unverified.
- `pkg/.aihaus/hooks/context-inject.sh` — SubagentStart. Injects path *lists* (advisory) + the ≤6KB M048 memory packet (real content). Per ADR-260517-A, this is the **only** verified subagent channel; `skills:` preload is dead under Task spawn.

**Memory — ~10 surfaces:** `decisions.md`, `knowledge.md`, `project.md`, BR ledger at `.aihaus/memory/workflows/business-rules.md`, `memory/{agents,global,backend,frontend,reviews,workflows,local}/`, plus the dual per-agent planes (`.claude/agent-memory/<name>/MEMORY.md` native scratch vs `.aihaus/memory/agents/<name>.md` promoted). User preferences exist **only repo-scoped**.

**Engine:** aih-graph pure-Go (modernc/sqlite), 14 node types, FTS5/BM25 always-on + Ollama `nomic-embed-text` KNN (roll-own Go, **not** sqlite-vec). DB path split: shim pins `.aihaus/state/aih-graph.db` (`pkg/scripts/aihaus:80`) vs XDG root in `aih-graph/internal/privacy/privacy.go`.

**Verified enforcement holes** (all confirmed by adversarial review):
1. `pkg/.aihaus/hooks/lib/role-defaults.json:41-58` still keys pre-M027 `:adversarial-scout/-review`; merged `:adversarial` falls through to `:doer` at `context-inject.sh:478`. (`context-budget.conf` is **already migrated** — its scout/review keys are deliberate back-compat, not drift.)
2. `context-inject.sh:45-50` — worktree early-exit: nested spawns from isolation agents get zero context.
3. Hook timeout 10s (`templates/settings.local.json:216`) vs 19s internal worst case (2×8s memory CLI + 3s haiku) → silent zero-injection.
4. SessionStart matcher is `startup` only — resume/clear/compact never re-fire refresh hooks.
5. `aihaus memory rule <id>` / `why <ref>` promised in `protocols/business-rules.md:27-28`, absent from `main.go` dispatch.
6. Answered `planning_answers` (which ARE business decisions) never reach the BR ledger — only the lossy manual `business-rules-migrate.sh`.
7. `gate_events`/`planning_questions`/`planning_answers` are written by **free-form sqlite3** from orchestrator bash — no chokepoint, no validation at write time.
8. `~/.aihaus/.targets` is read by `aihaus update --all` but nothing writes it.
9. **Global-skills-only installs** (V5 / dogfood mode, `install.sh:310-322`): every `/aih-*` skill works, but no bridge, no hooks, no harness — total enforcement blackout.

---

## 2. The target model

One harness document; exactly three memory tiers. Markdown stays source of truth (BR-F3); SQLite stays the rebuildable index. No path moves of existing ledgers.

| | Tier A — CODE MEMORY & RELATIONS | Tier B — PROJECT MEMORY & BUSINESS DECISIONS | Tier C — USER PREFERENCES |
|---|---|---|---|
| **Scope** | Per-repo, machine-derived | Per-repo, committed, curated. **The apex tier** — the BR ledger is the autonomy substrate | Global, per-user, cross-project |
| **Storage** | `.aihaus/state/aih-graph.db` (canonical; XDG layout demoted to raw non-aihaus invocations, documented) | `project.md`, `decisions.md`, `knowledge.md`, `.aihaus/memory/**` incl. BR ledger at `memory/workflows/business-rules.md` (**unmoved**) | `~/.aihaus/memory/user/preferences.md` (+ topic files) — path precedented by obsidian-export's `--user-memory` default |
| **Owner / writer** | aih-graph build/refresh only (`aih-graph-refresh.sh`, `aih-graph-stale.sh`) | Orchestrator only, via memory-promotion (ADR-001 / M016-S15a contract preserved verbatim) | **`aihaus prefs add` CLI verb only** — atomic append under a lock file. Direct Write/Edit to `~/.aihaus/memory/**` stays file-guard-blocked (see §4) |
| **Reader** | `aihaus memory query/context/callers/impact/rule/why --json` | Main session: CLAUDE.md imports. Subagents: inlined slices via context-inject | Injected excerpt (≤1.5KB) every spawn; main session via gitignored repo mirror `@import` |
| **Index** | File/Chunk/Symbol/Call/Test/Commit nodes (shipped) | Decision/Rule/Memory nodes (shipped) + `Source: pq-<id>` provenance on Rules (new) | Separate `~/.aihaus/state/user-graph.db` via `aih-graph build --user` + own consent marker — per-repo DBs **never** absorb cross-repo data (keeps ADR-260515-A surgical) |

**Precedence rule (new, closes the contrarian's conflict gap):** repo-scoped preferences (`memory/workflows/user-preferences.md`) **override** global tier-C on conflict. Injection order: global first, repo second, with the rule stated in the harness itself. One deterministic sentence kills the two-divergent-sources regression.

---

## 3. The harness file

**`pkg/.aihaus/protocols/harness.md`** — ~80 lines, **hard byte-cap ≤2KB enforced by a smoke check** (fits even the verifier cohort's 1500-token / 6000-char budget). Lands in `protocols/` alongside `default.md`/`routing.md` — *after* the in-flight 3.0 rename commit.

Contents:
1. The 4-row autonomy law verbatim (covered → decide citing BR-id; **gap → the only TRUE blocker**, ask once, answer becomes a rule; conflict → surface; mechanics → decide freely) — lifted from `output-styles/aihaus-contract.md`, which thins to a pointer.
2. The 3-tier memory map with exact query grammar: `aihaus memory rule <BR-id>`, `aihaus memory why <ref>`, `aihaus memory query --types Rule,Decision --top 5 "<task>"`.
3. Gate 4-enum + the `rules_cited` reporting obligation (warn-only initially — see §4).
4. Tier-C precedence rule + no-option-menus + one-question-per-gap.
5. `<!-- MAIN-SESSION-ONLY -->`-fenced section: spawn `workflow-orchestrator` on every fresh intent.

**Delivery — both audiences, ADR-260517-A respected:**
- **Main session:** `@../.aihaus/protocols/harness.md` added as the *first* import inside the existing `AIHAUS:CLAUDE-CONTEXT` marker block in `templates/claude/CLAUDE.md`. Propagation is free: `install.sh seed_claude_context_bridge()`, `update.sh`, and `project-context-refresh.sh ensure_block()` already re-sync the block; `claude-context-verify.sh` gains the import check.
- **Subagents:** `context-inject.sh` **inlines the harness content verbatim** (MAIN-SESSION-ONLY fence stripped) as a trim-exempt section — joining the already truncation-protected header/warnings/memory-packet set (`context-inject.sh:717-738`). Inlining IS reading. The worktree early-exit is relaxed to a harness-only path: inject harness + memory packet, suppress JSONL/cache writes (preserves the ADR-001 audit-writer rationale).
- **Global-skills-only installs (gap #1 fix):** `install.sh`/`install.ps1` seed a compact marker-managed `AIHAUS:GLOBAL-HARNESS` block into `~/.claude/CLAUDE.md` (user-global memory, read in every session): autonomy law digest + "this repo has no aihaus overlay; run `/aih-install` for memory + enforcement" + tier-C pointer. Honest limit documented: subagents in un-overlaid repos still get no injection — the block makes the *main session* harness-aware everywhere and nudges overlay install. Installer-written, idempotent, never agent-written.

---

## 4. Enforcement: hooks that guarantee reading

Philosophy: **inline what matters (read-by-construction), receipt what's injected, gate what gets recorded, observe the rest.** Everything fail-open with opt-out env vars + own JSONL (single-writer audit discipline).

| Event | Hook | Action |
|---|---|---|
| SubagentStart | `context-inject.sh` v2 | Inlines: harness (≤2KB) + tier-C excerpt (≤1.5KB) + per-task Rule/Decision slice + existing M048 packet — all via **one batched CLI call** `aihaus memory packet --task "<text>" --json` (new shim verb returning status + multi-type slice + top-3 in a single invocation; fixes the 19s-vs-10s timeout structurally; timeout also raised to 15s as belt). Writes a **receipt row** per inlined artifact to `.claude/audit/memory-read.jsonl`. Fixes `:adversarial` fall-through in `role-defaults.json`. Adds `memory_packet: present\|skipped` audit field. Worktree harness-only path. |
| SubagentStop | `memory-read-audit.sh` (NEW) | Greps transcript for Read calls on injected HIGH-tier paths; injected content auto-counts via receipts (kills false-"unread" noise). Writes **its own** `.claude/audit/memory-read.jsonl` rows. `warning-recurrence.sh` (sole writer of its file) is extended to *read* this JSONL during its existing aggregation pass — **corrected from the refuted design**: no second writer to `warning-recurrence.jsonl`, and warnings surface on the recurrence loop's cadence, not "next spawn". Observe-only; opt-out `AIHAUS_MEMORY_READ_AUDIT=0`. Receipts pre-pave a future observe→enforce flip without re-instrumentation. |
| SessionStart `startup\|resume\|clear\|compact` (widened) | `session-start.sh`, `project-context-refresh.sh`, `aih-graph-refresh.sh` | `session-start.sh` gains the same bounded `aihaus memory status` packet subagents get (main-session parity). Refresh hooks now re-fire on resumed sessions. |
| Bash (kanban writes) | `aihaus kanban gate\|question\|answer` (NEW shim verbs) — **gap #3 fix** | The sanctioned write path for `gate_events`/`planning_questions`/`planning_answers` rows, replacing free-form sqlite3. Validates verdict against the 4-enum and `rules_cited` shape (`BR-id \| GAP:pq-<id> \| MECHANICS`) **at write time, warn-only** — audit rows to `.claude/audit/rule-cite.jsonl`. Correctly anchored: `phase-advance.sh` never writes gate_events (the refuted design's anchor), so the chokepoint is a new wrapper, mandated by `protocols/kanban/db-schema.md`. `bash-guard.sh` gains a warn pattern for raw `sqlite3 .aihaus/state/kanban.db` writes. |
| UserPromptExpansion | `calibrate-guard.sh` (extended) | Rule-gate additionally reads the **project ledger** (today: per-plan file only), closing the accretion seam. Single-channel design preserved (M029 BLOCKER F4). |
| PreToolUse Write\|Edit | `file-guard.sh` (unchanged posture) — **gap #2 fix** | `~/.claude/**` stays blocked AND direct Write/Edit to `~/.aihaus/memory/**` stays blocked. **No carve-out**: the hook payload carries no agent identity, so "orchestrator-only" is unenforceable at this boundary — tier-C writes go exclusively through `aihaus prefs add` (format-validated, lock-file atomic append, own audit). The chokepoint provides what the carve-out couldn't. |
| Eval (run completion) | `eval-run.sh` (extended) | Deterministic `planning-answer-promotion` check: joins `planning_answers` against ledger entries **via `Source: pq-<id>`** (deterministic join, not ledger-diff heuristic) — implemented in eval over kanban.db + ledger grep, *not* inside aih-graph (cross-DB; corrected from the refuted `rule-coverage` design). Plus a rule-citation coverage *report* from `rule-cite.jsonl` → the **autonomous-decisions-per-human-answer** metric. Explicit `no-rule:<reason>` waiver rows allowed; fixture-fail test proves non-vacuous. |

Kept unchanged: `flow-guard.sh`, `role-guard.sh`, `tdd-guard.sh`, `autonomy-guard.sh`, `aih-graph-stale.sh`, budgets matrix, all existing opt-outs.

---

## 5. Learning loop

**Loop 1 — per-run rule accretion (the autonomy flywheel).** Gap surfaces as one `planning_questions` row → human answers once → `workflow-planning-gate` drafts a **DRAFT BR entry** with Given/When/Then scaffolded from the Q/A text + `Source: pq-<id>` → orchestrator writes it via the promotion path → **confirmed at the human-review stage** (human in the loop exactly once per rule) → `memory_events` journals `rule-promoted`. The eval check (§4) makes skipping deterministic-detectable. `rule-drift` gains **SHA staleness** (last-reviewed SHA vs `git log` of bound files) so confidently-wrong-from-stale-rules is caught — the worst failure mode of decide-from-contract.

**Loop 2 — per-repo memory.** Memory-promotion ritual kept verbatim, plus: (a) **native-scratch harvest** — at promotion (SessionEnd fallback hook), diff `.claude/agent-memory/<name>/MEMORY.md` and promote durable lessons into committed `.aihaus/memory/agents/<name>.md`, giving the dual planes a defined scratch→durable direction; (b) in user repos, agent-evolution findings route to `memory/agents/<name>.md` lessons — **honest**: definition edits are wiped by `update.sh:182-188` `rm -rf + cp -R`, so pretending they survive is a lie. Definition self-evolution stays a dogfood-repo commit path into `pkg/.aihaus/agents/`.

**Loop 3 — global.** (a) Preference candidates (`user-preference` Memory Candidate class) promote via `aihaus prefs add` → tier C → injected into every future spawn in every repo; (b) `install.sh` finally **writes `~/.aihaus/.targets`**, making `aihaus update --all` functional; (c) **`aihaus feedback export`** bundles gate-churn stats, recurring warnings, and evolution proposals from `memory_events` + audit JSONLs into `.aihaus/runtime/evolution-export.md` — the honest upstream channel from non-dogfood repos to the package PR flow.

**Deferred with trigger:** `.aihaus/overrides/agents/<name>.md` append-layer (survives refresh, same contract as `.effort`). Ship only if two releases of dogfood show `memory/agents/` lessons insufficient for per-repo agent adaptation.

---

## 6. Workplan

Each slice = branch → PR → merge. ⚠ = coordinates with in-flight 3.0 (untracked `protocols/`, deleted `workflows/`, uncommitted workflow-* agents).

**S1 — Drift hygiene (no behavior change).** Migrate `role-defaults.json` to `:adversarial` + align the haiku-prompt cohort string (`context-inject.sh:562`); widen SessionStart matcher; canonicalize DB path docs to `.aihaus/state/aih-graph.db`; add `memory_packet` audit field. Files: `pkg/.aihaus/hooks/lib/role-defaults.json`, `pkg/.aihaus/hooks/context-inject.sh`, `pkg/.aihaus/templates/settings.local.json`, `aih-graph/README.md`. Do **not** touch `context-budget.conf` legacy keys (deliberate back-compat until M046+).

**S2 — ⚠ Land the 3.0 spine commit.** `pkg/.aihaus/protocols/` tracked, `workflows/` deletion committed, agent count reconciled (59) in root `CLAUDE.md` + `docs/architecture-3.0.md`. Everything below anchors on `protocols/`.

**S3 — Harness.** New `pkg/.aihaus/protocols/harness.md`; first-position `@import` in `templates/claude/CLAUDE.md`; thin `output-styles/aihaus-contract.md` to a pointer; verify-script + smoke checks (≤2KB cap as a *failing check*; import presence). Files: above + `pkg/.aihaus/skills/aih-init/scripts/claude-context-verify.sh`, `pkg/.aihaus/skills/aih-init/annexes/claude-context-bridge.md`, `tools/smoke-test.sh`.

**S4 — context-inject v2 + batched CLI.** New `aihaus memory packet` shim verb (one invocation: status + `--types Rule,Decision` slice + top-3) — requires the **new `--types` multi-type flag in aih-graph** (named explicitly; today only singular `--type` exists). Inline harness; worktree harness-only path; receipts; timeout 10s→15s. Files: `pkg/.aihaus/hooks/context-inject.sh`, `pkg/scripts/aihaus`, `aih-graph/cmd/aih-graph/main.go`, `pkg/.aihaus/templates/settings.local.json`.

**S5 — Tier C.** Template `pkg/.aihaus/templates/user-preferences-global.md`; install seed of `~/.aihaus/memory/user/preferences.md`; `aihaus prefs add` with lock-file atomic append + audit (PowerShell parity in `install.ps1` — mandatory, BR-003 lesson); mirror into gitignored `.aihaus/memory/local/user-preferences-global.md` on `project-context-refresh.sh`'s 900s cadence (no unverified `@~` import bet); CLAUDE.md mirror import; precedence rule in harness; `user-preference` candidate route in `protocols/kanban/memory-promotion.md`. ADR in same PR.

**S6 — aih-graph v0.2.** `rule <BR-id>`, `why <ref>` verbs; `--types` filter (from S4); SHA staleness in `rule-drift`; `build --user` → `~/.aihaus/state/user-graph.db` + `~/.aihaus/.aih-graph-consent` + purge path. Files: `aih-graph/cmd/aih-graph/main.go`, `aih-graph/internal/extract/rule.go`, `aih-graph/internal/privacy/privacy.go`, `pkg/scripts/aihaus`, `pkg/scripts/install-aih-graph-binary.sh`. Tag pair with the aihaus release.

**S7 — ⚠ Kanban chokepoint + BR flywheel.** `aihaus kanban gate|question|answer` wrapper verbs (4-enum + warn-only `rules_cited` validation, `rule-cite.jsonl`); `bash-guard.sh` warn pattern for raw kanban writes; `planning_answers`→draft-BR route (`Source: pq-<id>`) in `protocols/kanban/memory-promotion.md` + `pkg/.aihaus/agents/workflow-planning-gate.md` + `workflow-human-review.md` confirmation step; eval `planning-answer-promotion` join + citation coverage report in `pkg/.aihaus/eval/`. Mandate the wrapper in `protocols/kanban/db-schema.md`.

**S8 — Read audit + global reach.** `pkg/.aihaus/hooks/memory-read-audit.sh` (SubagentStop, receipts-aware, own JSONL, recurrence-aggregator read extension in `warning-recurrence.sh`); `AIHAUS:GLOBAL-HARNESS` block seeding into `~/.claude/CLAUDE.md` from `install.sh`/`install.ps1`; `.targets` writer; `aihaus feedback export`; native-scratch harvest + SessionEnd fallback; `session-start.sh` memory-packet parity.

**S9 — Closeout.** Smoke checks with fixture-fail pairs (harness cap, inject fixture, eval join, prefs-verb lock); static grep check "no shipped file references stale cohort keys / superseded surfaces"; delete `pkg/.aihaus/memory/MEMORY.md` (cheapest consolidation — `aihaus memory status` is the index); consolidated ADR set (3-tier model, harness, chokepoints, tier-C, observe→enforce standing policy); release notes.

---

## 7. Explicitly NOT doing

- **sqlite-vec or any CGO extension** — ADR-260515-B-amend-02 / M033 pe-bigobj empirical finding; pure-Go + roll-own KNN is settled. "sql vec" = vectors in SQLite, KNN in Go.
- **`skills:` frontmatter preload for subagents** — empirically dead under Task spawn (ADR-260517-A).
- **AgentTeams programmatic spawn** — architecturally unreachable from skills (ADR-260518-A).
- **Blocking citation gate inside `phase-advance.sh`** — refuted anchor: it never writes gate_events. Warn-only via the kanban wrapper; flip considered only after a release of dogfood data.
- **Hard memory-gate on PreToolUse Write|Edit** — false-blocks when agents read via Bash/Grep; taxes every edit forever. Receipts pre-pave a future flip; observability now.
- **file-guard carve-out for direct agent writes to `~/.aihaus/memory/**`** — hook payload has no agent identity; "orchestrator-only" is unenforceable there. CLI chokepoint instead.
- **Tier-B path moves** (relocating the BR ledger / `environment.md`, folding `global/backend/frontend/reviews` into `knowledge.md`) — large consumer blast radius across `rule.go`, `role-defaults.json`, `context-inject.sh:667-673`, and 59 agent bodies for zero runtime gain; the fragmentation is documented, not migrated, this cycle.
- **Re-importing `decisions.md`/`knowledge.md` wholesale at session start** — the scrub rule stays; ADR awareness arrives as top-K Decision slices in the spawn packet.
- **Home-dir `@~` imports** — unverified-behavior class (same as the ADR-260517-A kill); gitignored repo mirror instead.
- **Indexing `~/.aihaus/memory/` into per-repo graph DBs** — violates the ADR-260515-A per-repo privacy framing; separate `user-graph.db`.
- **Python/JS/TS regex symbol extractors + `runtime/runs/` indexing** — genuine gap, but a quality tarpit and scope creep beyond the four pillars; deferred to its own slice with its own plan.
- **Deleting the output-style / rules file this cycle** — thinned to pointers; deletion only after one release proves harness coverage complete.
- **`.aihaus/overrides/agents/` layer** — designed, parked behind a dogfood trigger (two releases of `memory/agents/` lessons proving insufficient).
- **HNSW/IVF indexes and cloud embedding providers** — ADR-260515-E forever-scope + M048 removal stand.