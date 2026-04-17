#!/usr/bin/env bash
# A5 fixture stub: simulates a haiku CLI that exceeds the 3s timeout.
# Used by smoke Check 29 A5 — autonomy-guard wraps the call in `timeout 3s`,
# so this stub's sleep exceeds the budget and the hook falls through to
# `timeout-fallback-allow`.
sleep 5
echo '{"decision":"continue","reason":"should not get here"}'
