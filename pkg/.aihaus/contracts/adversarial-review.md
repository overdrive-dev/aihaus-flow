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
reversibility and data loss, integration existence-versus-wiring, complexity,
and goal-backward verification.

Output confirmed findings by severity, criterion results, commands actually run,
and one verdict: `ship`, `ship-with-changes`, or `blocked`.
