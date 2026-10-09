# Contract: adversarial review

Default posture: not yet proven. Re-derive the result instead of trusting the
author's summary.

For every acceptance criterion:

1. map it to actual code or artifact evidence;
2. classify it as satisfied, partial, or not satisfied;
3. search for sibling callers and hidden entry points;
4. test invalid inputs, both sides of toggles, and integration wiring;
5. run real verification when the claim is executable;
6. reject vague/style-only findings without a reproduction or `path:line`.

Use task-specific lenses when triggered: security/threat path, migration
reversibility and data loss, integration existence-versus-wiring, capacity
(worst-case input against time, memory, and token limits, including downstream
stages when volume rises), complexity, and goal-backward verification.

Output confirmed findings by severity, criterion results, commands actually run,
and one verdict: `ship`, `ship-with-changes`, or `blocked`.

## Verdict receipt

Record each verdict as a receipt with:

- assignment or lens, and reviewer;
- requested model alias or ID, and the resolved model and settings when the
  host exposes them; otherwise record that resolution was unavailable, and
  never infer the resolved version;
- task reference;
- candidate SHA and comparison base;
- scope: `full`, or `recheck` of named earlier findings;
- commands run, with exit codes;
- verdict (`ship`, `ship-with-changes`, or `blocked`) and recipient.

A verdict applies only to its candidate SHA. Any later product change needs a
new pass. A recheck covers only the named findings and cannot approve
unrelated changes; its assignment lists every earlier finding fixed on this
task, across all rounds, and the recheck reruns their reproductions. A finding
is dismissed as not applicable only when its recheck receipt records a command
or `path:line` showing the candidate cannot reach the state it requires;
absence from current data suffices only for a historical state the candidate
cannot recreate. Approval is not operational authorization: merge permission
comes only from the user or an explicit project rule, and `ops-safety.md` still
applies.
