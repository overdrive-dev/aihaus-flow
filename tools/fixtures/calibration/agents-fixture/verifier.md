---
name: verifier
tools: Read,Grep
model: opus
effort: max
color: green
memory: .claude/agent-memory/verifier
---

# Verifier (fixture)

Stub agent file used by smoke-test Check 28. `model: opus` + `effort: max`
is the pre-restore state; the restore function transforms model/effort
to the values recorded in the fixture `.calibration` file.
