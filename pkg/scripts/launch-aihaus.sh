#!/usr/bin/env bash
# launch-aihaus.sh -- exec claude with DSP for full aihaus autonomy
# Created M014/S03. Replaces /aih-automode skill toggle.
exec claude --dangerously-skip-permissions "$@"
