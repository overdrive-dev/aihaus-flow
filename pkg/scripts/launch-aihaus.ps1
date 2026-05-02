# launch-aihaus.ps1 -- exec claude with DSP for full aihaus autonomy
# Created M014/S03. DSP launcher -- replaces the old permission-mode skill toggle.
#
# CLI-005 idle-stall defense (M019/S02): set env defaults before launch so Claude
# Code 2.1.84+ stream-abort/retry behavior activates. User overrides win because
# the if (-not ...) block only assigns when the variable is absent or empty.
if (-not $env:CLAUDE_STREAM_IDLE_TIMEOUT_MS) { $env:CLAUDE_STREAM_IDLE_TIMEOUT_MS = '300000' }
if (-not $env:CLAUDE_STREAM_RETRY_ON_IDLE) { $env:CLAUDE_STREAM_RETRY_ON_IDLE = '1' }
& claude --dangerously-skip-permissions @args
