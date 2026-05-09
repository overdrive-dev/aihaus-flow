# Autonomy Protocol (shared annex)

Binding rules for execution autonomy across all aihaus skills. Referenced by every SKILL.md. Overrides contradictory prose in individual skills.

## The 3-phase rule

Every aihaus workflow has three discrete phases with one boundary between them:

1. **Planning phase** — interactive. Questions are permitted *and expected* when they are evidence-driven (informed by what the codebase, memory, or prior agent output actually revealed). Hypothetical questions ("what should this be called?" when the user already said) are not permitted. Iteration continues until every decision that materially changes the output is locked.
2. **Threshold gate** — exactly **one** question, in natural language, asking for permission to proceed. Acceptable forms: *"Planejamento completo. Posso executar?"*, *"Pode seguir?"*, *"Vai?"*. Never printed as a command to type. On affirmative (y/yes/sim/vai/go/enter), the skill dispatches the next step via the Skill tool itself.
3. **Execution phase** — zero questions. The skill auto-chains through every sub-step, every spawned agent, every commit, every validation, every skill-to-skill handoff until completion or a TRUE blocker (see definition below). Progress updates are permitted as one-line status messages; they are not checkpoints.

The boundary is unidirectional. Once in execution, the skill does not return to planning-interactive mode. User interrupt (ESC/Ctrl+C) halts execution and triggers paused-state recovery via auto-detect — never a planning-retry loop.

## TRUE blocker definition

Pausing during execution is permitted **only** when one of the following is true:

- **Missing credential or auth**: the next step requires a secret/token/key that is not present and cannot be acquired without user action.
- **Destructive git state**: pre-existing merge conflict, detached HEAD with uncommitted work, or a force-push situation that cannot be safely resolved automatically.
- **Inaccessible external dependency**: database offline, required API endpoint returning 5xx, expected file path does not exist and cannot be synthesized.
- **Internal plan contradiction**: the plan specifies two mutually exclusive outcomes and there is no safe default to pick from.

That is the exhaustive list. The following are **not** blockers:

- "The estimate was wrong and this is taking longer than expected" — keep going, log it.
- "There is an ambiguity in the approach" — pick the safer default, note it in RUN-MANIFEST.md, keep going.
- "The user might want to re-scope" — the user already approved at the threshold gate. Do not re-prompt for scope during execution.
- "A smoke-test or lint warning appeared" — attempt to fix inline; only surface if the fix is not within current scope.
- "A dependency between stories is unclear" — read the artifacts that define the dependency (PRD, architecture.md, prior story's commit); the information is in the milestone dir.

## No option menus

Do not emit lettered or numbered option menus mid-execution. The anti-pattern looks like:

```
How should I proceed?
(a) do the thing safely
(b) do the thing quickly
(c) pause and ask the user to decide
(d) something else
```

This is strictly forbidden during execution phase. When there is a choice to make:

1. Pick the option most consistent with (i) the plan, (ii) prior decisions in `.aihaus/decisions.md`, (iii) the autonomy-protocol defaults.
2. Log the choice in RUN-MANIFEST.md's progress log as a one-liner: *"Chose approach X over Y — reason: Z."*
3. Proceed.

During planning phase, lettered options in a table (Alternatives Considered, Risk Assessment) are part of the plan document — those are fine. What is forbidden is using them as a user-facing decision menu that stops the flow.

## No honest checkpoints / reality renegotiation

Do not emit spontaneous "honest checkpoint", "reality check", "surface honest scope", "let me pause to reconsider" prose mid-execution. These are disguised checkpoints — they stop the flow without the user having asked for a stop. The M005 regex fast-path + M011 haiku backstop (ADR-M011-A) detect the common phrasings and block them; novel phrasings are caught by the conservative haiku judge, which then surfaces a block via `autonomy-guard.sh`.

When a TRUE blocker IS hit (per the TRUE blocker definition above), emit the **state-gate block** via:

    bash .aihaus/hooks/phase-advance.sh --to paused --reason "<reason>" --dir <milestone-dir>

That single call writes `status: paused` + `pause_reason: <text>` into RUN-MANIFEST Metadata, which `autonomy-guard.sh` recognizes as a legitimate stop (short-circuits allow before the regex or haiku branches). This works from worktree-isolated agents — the `--to paused` path bypasses the worktree refusal (F-02). Checkpoint-style prose remains forbidden; `phase-advance --to paused` is the canonical escape. If the haiku backstop blocks you with a spurious checkpoint-like pattern, pick the safer default per §3-phase rule and proceed silently.

Observed anti-patterns to avoid verbatim:
- "Pausing to surface honest scope before continuing."
- "Wave 1 completa. Stop aqui pra alinhar escopo de Wave 2."
- "Honest reality check — ..."
- "Three realistic forks: (1) ... (2) ... (3) ..."
- "Suggested next steps: Option A ... Option B ... Option C ..."

If the execution-phase estimate was wrong, continue executing and let the user decide when to stop via ESC. If the execution phase hits an unexpected condition, apply the TRUE blocker test above — only pause if it matches (and when pausing, use the canonical `phase-advance --to paused` call above).

## No delegated typing

When the logical next step is inferable and part of the approved execution path, never print something like *"Next: run `/aih-xxx [slug]`"* as an instruction for the user to type. That delegates keyboard work the skill can do itself.

Acceptable alternatives:
1. **Execution phase**: dispatch the next skill via the Skill tool immediately. No ask.
2. **At the threshold gate**: ask one natural-language permission question, then dispatch on affirmative.
3. **Opt-out only**: if the user ran with `--no-chain` or the explicit policy of the standalone skill requires it, print the suggestion. Default is to dispatch.

## Progress updates vs checkpoints

Progress updates are a one-line status message that does not stop the flow. A checkpoint is anything that implicitly or explicitly waits for user input.

| Progress update (OK) | Checkpoint (forbidden during execution) |
|----------------------|------------------------------------------|
| `Story 3 complete, starting Story 4.` | `Story 3 done. Should I continue to Story 4, or pause first?` |
| `Chose approach X — logged in RUN-MANIFEST.` | `Between X and Y, which should I pick? (a) X (b) Y` |
| `Smoke-test green.` | `Smoke-test green. Ready to merge? [Y/n]` |
| `Pivoting to inline edits per K-002 allowance.` | `Realized inline would be faster — should I switch approach?` |

If a line you are about to emit would invite a response, it is a checkpoint. Rewrite it as a statement.

## Natural skill-to-skill chaining

When a skill finishes its primary work and the next skill is implied by the plan or the autonomy-protocol defaults:

1. During planning phase end (threshold gate): ask the permission question, then dispatch via Skill tool on affirmative.
2. During execution phase: dispatch via Skill tool without asking. The user's original approval at the threshold gate covers the entire chain.

Chain example for the primary flow:
```
/aih-plan (approves at threshold)
  → /aih-milestone --plan [slug] (runs silently through promotion + execution via annexes)
    → report final status
```

At each arrow, the skill calls the next one via Skill tool inside its own final step. No user prompt between arrows.

## Opt-outs

- `--no-chain` flag on any skill: preserves the legacy "suggest next command, do not dispatch" behavior. For CI / scripting / users who genuinely want manual stepping.
- User interrupt (ESC / Ctrl+C): always works. Halts current tool call, leaves RUN-MANIFEST.md as-is, next session can `/aih-resume`-style auto-detect.

## Authority

This annex overrides contradictory prose in individual SKILL.md files. When a skill's own prose says "ask the user to confirm X" and this annex says "do not ask during execution", the annex wins.

## CLI-005 idle-stall defense (M019)

Long-running milestone executions on Opus 4.7 at `xhigh` effort may appear to
stall for 10-22 minutes with no progress output. Two stall classes exist:

1. **Model self-stop** -- outside the autonomy-guard substrate. `RUN-STATUS.md`
   (M019) provides a filesystem-visible heartbeat: if `manifest-append.sh` has
   not regenerated `RUN-STATUS.md` for >20 minutes during an active story, the
   stall is likely model self-stop, not an aihaus pause.
2. **CLI-005 stream-idle regression** -- a known Claude Code stream-idle
   regression. Mitigated at install time: `CLAUDE_STREAM_IDLE_TIMEOUT_MS`
   defaults to `300000` (5 min) in `auto.sh` / `auto.ps1`. Opt-out via
   `AIHAUS_DSP_TIMEOUT=0` in environment (set before launching auto.sh).

Skills must NOT paper over stalls with option menus or "honest checkpoints."
Per the TRUE blocker test (above), a stream stall is not a TRUE blocker.
Apply the safer default: `/aih-resume` after confirming `RUN-STATUS.md`
shows no new progress for >20 minutes.

**Propagation:** existing installs receive the env defaults via `pkg/scripts/update.sh`
and `pkg/scripts/update.ps1`, which now refresh `auto.sh` / `auto.ps1` from
`launch-aihaus.sh` / `launch-aihaus.ps1` on hash-change (M019/S02 F-C3 fix;
previously update.sh only touched skills/agents/hooks/templates).

## §M023 invariants (post-2026-05-06; ADR-260506-A)

> **M023 amendments to the TRUE-blocker definition:**
>
> - **Conversation length is NEVER a TRUE blocker.** Long context, "conversa muito longa," "preservar qualidade" framings are GSP-DS anti-patterns.
> - **Decomposition seams are NEVER TRUE blockers.** Backend/Frontend, Wave N/M, Batch A/B, Phase X/Y boundaries are stylistic decompositions, not blockers.
> - **`pause_class` enum is REQUIRED on every `phase-advance --to paused` write.** 4 values: `{credential-missing, destructive-git-state, external-dep-down, user-invoked}`. See ADR-260506-A §Decision item 2 for operational definitions.
> - **GSP-DS prose triggers Stop block.** `autonomy-guard.sh` PATTERNS heredoc covers 13 PT-BR regexes (M023 pack) — see ADR-260506-A.

## §M024 invariants (post-2026-05-06; ADR-260507-A)

> **M024 amendments to the composition rule + auto-improve substrate framing:**
>
> - **Composition rule (M023 + M024).** M023 + M024 compose at runtime. Skill prose excises Wave/Group structural nouns from `pkg/.aihaus/skills/aih-milestone/annexes/execution.md` (S01 — 5 substitution sites at L50, L61, L70, L198, L271, L295); `pkg/.aihaus/hooks/autonomy-guard.sh:73` regex (`[Ww]ave [0-9]+ complet[ao].*([Ss]top|[Pp]ause|[Aa]linha)`) still blocks them at Stop hook. The runtime detector and the skill prose are **independent enforcement layers** — never assume regex deletion follows skill-prose excision.
>
> - **`--plan <slug>` short-circuit (consumer-self-validating).** When `/aih-milestone --plan <slug>` is invoked at Step E3 and the 3-way gate passes ((a) OQ-resolved + (b) architecture-coverage + (d) story-table, all H-level permissive) AND the on-disk CHECK.md SHA proves plan-checker ran (consumer reads `git log -1 --format=%H -- .aihaus/plans/<slug>/CHECK.md`), milestone execution skips analyst/PM/architect/plan-checker spawns. Three stub files (`analysis-brief.md`, `PRD.md`, `architecture.md`) with skip-markers preserve the 6 production-path consumer contracts. Fail-closed default: CHECK.md absent or untracked → gate refused, fall back to full E3.
>
> - **Auto-improve post-hoc detection (per CHECK F5 — NOT runtime gating).** Smoke Check 72 detects post-hoc that `phase-advance.sh --to complete` was called for a milestone without a corresponding `.claude/audit/curator-apply.jsonl` row. Detection is **offline**; enforcement requires CI/dogfood smoke runs to fail. M024 acknowledges this as **primary=A model-driven gate** per ADR-260502-A enforcement-audit classification — `phase-advance.sh` has zero hook into `tools/smoke-test.sh`; the smoke check is offline observability, NOT a runtime block. Grace-window for currently-running milestone (`git branch --show-current` match `milestone/M0XX-*`) prevents self-completion sequence trap.
>
> - **F3 task-fraction laundering — prose-only mitigation.** `pkg/.aihaus/skills/aih-milestone/annexes/execution.md` Step E6 advises orchestrator to TaskCreate only the next 1-3 active rows ahead. This is **prose-only**; `autonomy-guard.sh` does NOT include a regex for `[0-9]+/[0-9]+ (stories|tasks) (complete|done)` task-fraction laundering. M025+ may add the regex if dogfood detects. Honest about the prose vs runtime composition gap.

## §M025 invariants (post-2026-05-07; ADR-260508-A)

> **M025 amendments to the LSDD pack + canonical-vocabulary protection rule:**
>
> - **Composition rule (M023 + M024 + M025).** All three packs compose at runtime byte-identical. M005 fast-path (L65-76, 11 patterns) + M023 GSP-DS PT-BR pack (L84-97, 13 patterns under `AIHAUS_GSP_DS_REGEX=0` env opt-out) + M025 LSDD anchored pack (16 patterns under `AIHAUS_LSDD_REGEX=0` env opt-out) = 40 active patterns. Each pack has a distinct heredoc terminator (`PATTERNS_EOF`, `GSP_DS_EOF`, `LSDD_EOF`) and a distinct env opt-out — never assume one pack's deletion follows from another's.
>
> - **LSDD 16-pattern reservation (5 EN + 5 PT-BR cadence + 1 Sigo + 5 task-fraction).** All cadence-noun patterns anchor to completion-prose verb-set on the same line via `.*(complete|completa|completo|done|paralelo|seguir|working|remaining|shipped|finalizada|finalizado|pronta|in progress)`. **Onda DROPPED** per F1 absorption. Known-uncovered slots (Tier/Cycle/Iteration/Sprint/Slice/Pass/Bucket/Cohort/Greek-letters) have a mechanical M026 trigger via `.claude/audit/autonomy-gate.jsonl` haiku-backstop frequency monitoring (30-day window post-release).
>
> - **Canonical-vocabulary protection (NEW — F-CRIT-1 resolution).** LSDD patterns anchor specifically to preserve §M023 catalog at L147+L487 ("Etapa/Bloco/Fase/Phase X/Y" enumeration) AND legitimate `## Phase N` H2 headers in skill prose at runtime emission. These labels remain legitimate decomposition seams; the regex fires ONLY when paired with completion-prose verbs on the same line. **Composition rule binding — never delete the anchoring without ADR amendment.**
>
> - **Agent-template excision (orchestrator-read templates targeted).** `roadmapper.md` L64-83 cadence-noun template excised → "Delivery 1/Delivery 2/N" substitution (per ADR-260508-A I3). `brainstorm-synthesizer.md` Round 1/Round 2 panel mechanics + `*-r2.md` filename convention preserved (load-bearing). `eval-auditor.md`/`eval-planner.md` step-headers untouched (skill-step framing surface).
>
> - **M027 mechanical forcing function via Smoke Check 76.** Calendar-anchored ADR-presence gate with `Status: Accepted` semantic requirement (NOT declarative deadline theater). Fixture-fail tests (missing-ADR + token-rejected) prove gate is not green-but-vacuous. Replaces R2 declarative theater per CHECK F4.

## §M027 invariants (post-2026-05-08; ADR-260509-X)

> **M027 amendments to the two-tier dispatch + pattern freeze:**
>
> - **Composition rule (M005 + M023 + M024 + M025 + M027).** All packs compose at runtime. M005 fast-path (11 patterns) + M023 GSP-DS (13 patterns) + M025 LSDD (16 patterns) = **40 active patterns total — FROZEN**. Adding any new pattern requires a new ADR explicitly amending ADR-260509-X. Per-pack env-gates (`AIHAUS_GSP_DS_REGEX=0`, `AIHAUS_LSDD_REGEX=0`) preserved — per-pack disable still permitted, but total cannot grow.
>
> - **Two-tier dispatch (NEW — ADR-260509-X).** `autonomy-guard.sh` routes by `manifest_status` + `exec_phase` binary field. `exec_phase="1"` AND `manifest_status ∈ {running, in-progress}` → **haiku-primary** (milestone-execution turns); all other statuses + `exec_phase="0"` → **regex-primary** (40-pattern fast-path). On haiku-primary timeout/error: falls back to regex-primary with `tier_used=two-tier-fallback` in JSONL row. Default when `AIHAUS_AUTONOMY_TIER` unset: context-route (two-tier).
>
> - **`exec_phase` wire-contract preserved.** The JSONL field `exec_phase` continues to emit binary string `"0"` (idle) or `"1"` (in execution) per existing `autonomy-guard.sh` printf. The string `"milestone-execution"` is documentation prose (ADR-260509-X §Dispatch fields), NOT a wire value. NO parent-skill `AIHAUS_EXEC_PHASE=milestone-execution` env mandate. Existing 4185+ JSONL rows continue to parse identically.
>
> - **New env opt-out: `AIHAUS_AUTONOMY_TIER=regex|haiku|two-tier`.** Default unset → context-route. `AIHAUS_AUTONOMY_TIER=regex` forces regex-primary on every invocation. `AIHAUS_AUTONOMY_HAIKU=0` (M011) preserved — disables haiku on all paths regardless of tier setting. The two controls are orthogonal: `AIHAUS_AUTONOMY_HAIKU=0` is always the stronger kill-switch.
>
> - **`rephrase_suggestion` JSONL field (S3 OPAQUE verdict obligation).** Static lookup keyed on `$GATE_SECTION`; emitted only on `regex-match` decision rows. Maps 6 section namespaces (`L65-72:no-delegated-typing`, `L52-63:no-honest-checkpoints`, `L32-50:no-option-menus`, `L52-63:no-reality-renegotiation`, `GSP-DS-*`, `LSDD-*`) to canonical human-readable rephrase strings. `<1ms` overhead (no LLM call). `null` for all non-regex-match decisions. Backward-compatible: prior rows simply lack the field.
>
> - **`tier_used` JSONL field (additive).** Values: `regex` | `haiku` | `two-tier-fallback`. Present on every decision row from M027 forward. Prior rows lack the field — schema is field-presence-permissive.
>
> - **Pattern-arms-race halted.** Total=40 frozen per ADR-260509-X. The M025 30-day window (known-uncovered slots: Tier/Cycle/Iteration/Sprint/Slice/Pass/Bucket/Cohort/Greek-letters) is now resolved via `haiku-primary` tier (classifier accuracy on novel phrasing) rather than pattern extension. Any new pattern is a policy decision requiring an explicit ADR amendment — not a mechanical addition.
