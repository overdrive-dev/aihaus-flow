# Install aihaus via an LLM agent

If you would rather hand the install off to an LLM with shell access, copy the
prompt below into a fresh agent chat. It is intended for Claude Code CLI, Cursor,
Windsurf, Claude Desktop with filesystem tools, or another local agent runtime
that can run bash or PowerShell commands.

This does not work in chat-only interfaces without local shell access.

---

## Copy-paste prompt

````
You are a DevOps assistant. Your mission is to install aihaus
(https://github.com/overdrive-dev/aihaus-flow) on the machine you have shell
access to. Aihaus is a Claude Code skills toolkit; users invoke `/aih-*` slash
commands inside Claude Code.

This prompt is approval to perform the machine-wide aihaus install in the
standard per-user directory. Do not ask what I want to do unless a prerequisite
install requires admin approval or a command fails.

Critical constraints:
- Do not skip verification steps. Report each checkpoint result back to me.
- Do not improvise alternative install paths. The commands below are canonical.
- Do not bind aihaus to the current repo unless I explicitly provide PROJECT_DIR.
- Do not run `bash .aihaus/auto.sh`.
- On Windows, use PowerShell and `$env:LOCALAPPDATA`, not `$XDG_DATA_HOME`.

### Step 1 - Verify prerequisites

Check that these are installed; install whichever are missing:

- git
- Node.js 18+
- Claude Code CLI: `npm install -g @anthropic-ai/claude-code`, then verify with `claude --version`
- Windows: PowerShell 5.1+
- macOS/Linux: bash 4+

If any prerequisite install requires elevated permissions, ask before using
admin privileges. Otherwise continue.

### Step 2 - Clone and install

Detect the platform first.

macOS / Linux:
```bash
INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/aihaus"
if [ -d "$INSTALL_DIR/.git" ]; then
  git -C "$INSTALL_DIR" pull --ff-only
else
  mkdir -p "$(dirname "$INSTALL_DIR")"
  git clone https://github.com/overdrive-dev/aihaus-flow "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"
bash pkg/scripts/install.sh
```

Windows PowerShell:
```powershell
$InstallDir = Join-Path $env:LOCALAPPDATA 'aihaus'
if (Test-Path (Join-Path $InstallDir '.git')) {
  git -C $InstallDir pull --ff-only
} else {
  New-Item -ItemType Directory -Path (Split-Path $InstallDir) -Force | Out-Null
  git clone https://github.com/overdrive-dev/aihaus-flow $InstallDir
}
Set-Location $InstallDir
.\pkg\scripts\install.ps1
```

### Step 3 - Verify the install

Run each checkpoint and report the output:

1. Global skills linked:
   - macOS/Linux: `ls ~/.claude/skills/ | grep aih-`
   - Windows: `Get-ChildItem ~/.claude/skills/ -Filter aih-* -Name`
   - Expected: 15 entries starting with `aih-`.

2. Install registry:
   - macOS/Linux: `cat ~/.aihaus/.install-source`
   - Windows: `Get-Content "$HOME\.aihaus\.install-source"`
   - Expected: path points at the aihaus clone.

3. aih-graph binary:
   - macOS/Linux: `test -x ~/.aihaus/bin/aih-graph && ~/.aihaus/bin/aih-graph version`
   - Windows: `Test-Path "$HOME\.aihaus\bin\aih-graph.exe"; & "$HOME\.aihaus\bin\aih-graph.exe" version`
   - Expected: file exists and `version` exits 0. If this fails, report it as optional; `/aih-init` can retry.

If checkpoint 1 or 2 fails, stop and report the failure. Checkpoint 3 is optional
at install time.

### Step 4 - Tell the human what to do next

After checkpoints pass, output this:

---
aihaus installed successfully.

Final interactive steps must be done by the human inside Claude Code. In any
project where you want to use aihaus:

  cd <your-project>
  claude

Then inside Claude Code, type:

  /aih-install
  /aih-init

After that, all `/aih-*` commands work in that project.
---

Report final status: platform detected, install location, skill count, registry
path, and aih-graph result.
````

---

## What the LLM cannot do

The final two steps, `/aih-install` and `/aih-init`, are slash commands inside
the interactive Claude Code TUI. A shell-only agent cannot run them from outside
that session. This is intentional: `/aih-init` builds project-local context from
the repository where you run it.
