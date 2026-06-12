# aihaus Fan-out Workflows (native dynamic workflows)

Native dynamic workflows (JS orchestration scripts) are reserved for **autonomous
fan-out only** — never the interactive spine.

## When (and when not)

- **Use a native workflow** for fan-out at scale: a qa sweep (parallel
  test/lint/security across the repo), parallel env/deploy ops, a
  cross-checked audit. Many agents, context-isolated, rerunnable.
- **Do NOT** use one for the interactive spine (planning/bugfix/feature). Native
  workflows take **no mid-run input** — interactive flows stay skills (see
  [default.md](default.md) § Composition). Rule: interactive → skill sub-flow;
  fully autonomous → native workflow.

## How they are created (not shipped)

aihaus does **not** ship hand-written `.js` workflows — they are **runtime-authored**
and in research preview. Per project:

1. Ask Claude to "run a workflow to <fan-out task>" (or `/effort ultracode`).
2. Once a run does what you want, save it via `/workflows` → `s` to
   `.claude/workflows/<name>.js` (project, shared) or `~/.claude/workflows/`
   (personal). It then runs as `/<name>`.

## Online boundary

The online boundary still holds inside fan-out: a workflow's subagents inherit
the tool allowlist, and `flow-guard.sh` blocks online actions outside an active
tracked flow **even inside a workflow**. Defense in depth — the guard is not
bypassed by the workflow layer.

## Sequencing

Simplicity-first: fan-out comes **after** the spine + eval are proven (S3 + S6,
done). It is the optional accelerator, not the foundation.
