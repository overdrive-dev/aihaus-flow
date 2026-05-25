# Review Memory

This directory holds durable reviewer output for this repository: recurring
findings, false positives, anti-pattern logs, and review heuristics confirmed by
project evidence.

Fresh installs intentionally start with no inherited review findings.

## What Goes Here

- `common-findings.md`: recurring findings seen in this project.
- `false-positives.md`: review warnings confirmed as acceptable for this
  project.
- Per-run reviewer summaries when a workflow promotes them as durable context.

## What Does Not Go Here

- Active run notes.
- Backend or frontend implementation patterns.
- Business-rule questions that still need a human answer.

Unanswered questions belong in `.aihaus/init/business-context-questions.md`.
