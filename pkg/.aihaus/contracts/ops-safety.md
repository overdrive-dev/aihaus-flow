# Contract: ops safety

Classify every operational action as read-only observation, local, CI,
staging/homolog, production, destructive, or secret-touching. Higher risk wins.

Before execution, record exact prechecks, commands, expected evidence, smoke
checks, rollback, stop conditions, credential scope, and containment boundary.
Read-only/local work may proceed when the repository contract covers it.
Staging, production, destructive, or secret-touching actions require explicit
human approval and the appropriate external containment.

`tools/online-action-gate.mjs` blocks recognized promotion commands outside an
active flow when a host adapter invokes it. This tool, hooks, and instruction
files are not a sandbox or privilege boundary. Least-privilege credentials,
environment isolation, and provider controls remain mandatory.
