#!/usr/bin/env bash
# launch-aihaus.sh -- exec claude with DSP for full aihaus autonomy
# Created M014/S03. DSP launcher -- replaces the old permission-mode skill toggle.
#
# CLI-005 idle-stall defense (M019/S02): set env defaults before exec so Claude
# Code 2.1.84+ stream-abort/retry behavior activates. User overrides win because
# := only assigns when the variable is unset or empty. AIHAUS_DSP_TIMEOUT=0 opt-out
# is handled at the caller level (the user simply sets both vars before running).
: "${CLAUDE_STREAM_IDLE_TIMEOUT_MS:=300000}"
: "${CLAUDE_STREAM_RETRY_ON_IDLE:=1}"
export CLAUDE_STREAM_IDLE_TIMEOUT_MS CLAUDE_STREAM_RETRY_ON_IDLE
exec claude --dangerously-skip-permissions "$@"
