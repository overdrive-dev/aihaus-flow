# CHECK.md — fixture for Check 81 (drift-detected)
#
# This file simulates a post-merge CHECK.md artifact that should FAIL Check 81.
# Conditions: ASSUMPTIONS.md has ambiguity markers, no BUSINESS-RULES.md present,
# no calibration-skip audit row, ctime NOT predating M029_EPOCH.
#
# Expected result: Check 81 MUST detect drift and FAIL.

status: checked
slug: test-drift-detected
