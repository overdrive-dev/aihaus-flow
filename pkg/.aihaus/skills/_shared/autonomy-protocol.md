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
