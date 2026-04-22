#!/usr/bin/env bash
# launch-aihaus.sh -- exec claude with DSP for full aihaus autonomy
# Created M014/S03. DSP launcher — replaces the old permission-mode skill toggle.
exec claude --dangerously-skip-permissions "$@"
