# aihaus Harness (fixture: oversized — MUST FAIL the 2048-byte cap)

This fixture deliberately exceeds 2048 bytes while staying at or under 45 lines, isolating the byte-cap comparison (BR-P8 non-vacuity): if the smoke check reports this file as within caps, the wc -c comparison is green-but-vacuous and the check must be treated as broken.

Filler paragraph one: the harness budget exists because the harness is delivered unconditionally on two paths — first-position CLAUDE.md bridge import for the main session and verbatim inline on SubagentStart — and a document that grows past its byte budget eventually gets trimmed, which silently removes the law from the context it was guaranteed to occupy.

Filler paragraph two: every future addition to the harness must displace something; the 2048-byte hard cap forces that editorial discipline, and this oversized fixture is the standing proof that the cap is actually compared against the real byte count instead of being asserted vacuously by a check that never reads the file.

Filler paragraph three: padding text to push this fixture comfortably past the two-kilobyte boundary so byte-count drift in the surrounding prose can never accidentally bring it back under the cap — the margin should remain several hundred bytes wide at all times, which this sentence and the ones around it guarantee by sheer verbosity.

Filler paragraph four: more deliberate padding, because a fixture that sits one byte over the threshold is fragile, and a fragile fixture defeats the purpose of a non-vacuity proof; the fixture-fail convention from M025 onward requires the failing case to fail loudly and unambiguously rather than marginally and accidentally.

Filler paragraph five: penultimate stretch of padding to push the total well past the cap, keeping the oversized state robust against any future whitespace normalization, line-ending conversion, or trailing-newline trimming applied by editors or by git attributes on checkout across platforms and shells alike.

Filler paragraph six: final stretch of deliberate verbosity landing the total comfortably above 2300 bytes — wide enough that no plausible incidental edit to this fixture, short of deleting whole paragraphs outright, could ever bring it back under the 2048-byte threshold and silently turn the non-vacuity proof into a false positive for the smoke suite.
