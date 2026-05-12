# CHECK.md — fixture for Check 81 (drift-bypassed-by-no-calibrate)
#
# This file simulates a post-merge CHECK.md artifact that should PASS Check 81.
# Conditions: ASSUMPTIONS.md has ambiguity markers, no BUSINESS-RULES.md,
# but a calibration-skip audit row IS present (dated within 24h).
#
# Expected result: Check 81 MUST allow (audit-skip row present).

status: checked
slug: test-drift-bypassed
