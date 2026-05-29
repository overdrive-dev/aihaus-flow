# aihaus Eval & Drift Control

Turns goal-run **traces** (`gate_events` + audit JSONL) into **repeatable pass/fail
checks** — the OpenAI harness-engineering pattern. This is the reliability spine for
the "autonomy without introducing problems" goal: it makes that property
*measurable* rather than aspirational, especially under many concurrent builders.

## `eval-run.sh`

```bash
bash .aihaus/eval/eval-run.sh [--db <aih-goal.db>] [--project <root>]
```

Exit: `0` = all deterministic checks pass · `1` = ≥1 failed · `2` = cannot run
(no `sqlite3` / no DB). Emits one JSONL row per check to stdout.

### Deterministic checks (the part this script owns)

| Check | Dimension | Fails when |
|---|---|---|
| `verdict-validity` | outcome | a `gate_events` verdict is not one of PASS / SKIPPED / BLOCKED-TO-PLANNING / BLOCKED |
| `evidence-exists` | process | a recorded `evidence_path` points to a file that does not exist (violates write-then-reference, rule 5) |
| `planning-gate` | process | a task advanced past `planejamento` with an `open` planning question (BR-1) |
| `no-gate-churn` | efficiency | a task has >30 `gate_events` (likely a re-eval loop) |
| `role-guard-online-blocks` | policy (info) | — (reports count of online-action blocks from `role-guard.jsonl`) |

### Rubric (NOT in this script — needs judgment)

**Business-rule coverage** — whether the delivered work actually satisfies the
confirmed `BUSINESS-RULES` for each task — is non-deterministic and needs a
judgment/LLM pass over the rules + the evidence package. Run it separately; do not
fake it as a deterministic check (avoids the green-but-vacuous trap).

## Eval gate

At goal finish (`/aih-goal` Phase 7), run `eval-run.sh` over the run's
`aih-goal.db`. A deterministic FAIL blocks marking the run complete — see
`.aihaus/workflows/artifacts.md` § Eval gate.
