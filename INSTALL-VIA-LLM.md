# Install aihaus via an LLM agent

If you'd rather hand the install off to an LLM with shell access (Claude Code CLI, Cursor, Windsurf, Claude Desktop with filesystem MCP, etc.), copy the prompt below into a fresh chat. The agent will:

1. Detect your platform (macOS/Linux/Windows).
2. Verify prerequisites (`git`, Node 18+, Claude Code CLI, bash on Unix or PowerShell 5.1+ on Windows) and install whichever are missing.
3. Clone aihaus-flow and run the canonical install script.
4. Verify three checkpoints (global skills linked, aih-graph binary downloaded + executable, settings template merged).
5. Hand back to you for the final two slash commands inside Claude Code (those steps require an interactive TUI — no agent can run them headlessly).

The prompt assumes the LLM has shell execution. It does **not** work in chat-only LLM interfaces (Claude.ai web, ChatGPT web without local code interpreter). Use it inside Claude Code CLI, Cursor, Windsurf, Claude Desktop with filesystem MCP, or any agent runtime with bash/PowerShell tool access.

---

## Copy-paste prompt

````
You are a DevOps assistant. Your mission: install aihaus (https://github.com/overdrive-dev/aihaus-flow) on the machine you have shell access to. Aihaus is a Claude Code skills toolkit; users invoke `/aih-*` slash commands inside Claude Code.

CRITICAL CONSTRAINT: do NOT skip verification steps. Report each checkpoint result back to me. Do NOT improvise alternative install paths — the discovery chain is deterministic; the commands below are the canonical path.

### Step 1 — Verify prerequisites

Check that these are installed; install whichever are missing:

- git (any recent version)
- Node.js 18+ AND Claude Code CLI: `npm install -g @anthropic-ai/claude-code` then verify with `claude --version`
- On Windows: PowerShell 5.1+ (built-in on Windows 10+) — no Git Bash needed
- On macOS/Linux: bash 4+

If any are missing, install them first using the platform's standard package manager (apt/brew/winget/choco), then continue.

### Step 2 — Clone + install (detect platform first)

macOS / Linux:
```
INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/aihaus"
mkdir -p "$(dirname "$INSTALL_DIR")"
git clone https://github.com/overdrive-dev/aihaus-flow "$INSTALL_DIR"
bash "$INSTALL_DIR/pkg/scripts/install.sh"
```

Windows PowerShell:
```
$InstallDir = "$env:LOCALAPPDATA\aihaus"
New-Item -ItemType Directory -Path (Split-Path $InstallDir) -Force | Out-Null
git clone https://github.com/overdrive-dev/aihaus-flow $InstallDir
& "$InstallDir\pkg\scripts\install.ps1"
```

If git clone fails with "directory already exists", the user already has a clone. Run `git -C "$INSTALL_DIR" pull` instead, then re-run the install script.

### Step 3 — Verify the install (3 checkpoints, all MUST pass)

Run each and report the output:

1. Global skills linked:
   - macOS/Linux: `ls ~/.claude/skills/ | grep aih-`
   - Windows: `Get-ChildItem ~/.claude/skills/ -Filter aih-* -Name`
   - Expected: 14 entries starting with `aih-` (init, install, plan, feature, milestone, brainstorm, bugfix, close, effort, help, quick, resume, sync-notion, update).

2. aih-graph binary downloaded:
   - macOS/Linux: `ls -la ~/.aihaus/bin/aih-graph && ~/.aihaus/bin/aih-graph version`
   - Windows: `Test-Path ~/.aihaus/bin/aih-graph.exe; & "$HOME/.aihaus/bin/aih-graph.exe" version`
   - Expected: file exists; `version` command prints something like `0.1.3` or higher, exit 0.

3. Settings template merged:
   - Both platforms: confirm `~/.aihaus/.install-source` contains `https://github.com/overdrive-dev/aihaus-flow`.

4. Memory engine queryable (run AFTER the user has executed `/aih-init` inside Claude Code on at least one project — skip this checkpoint until then):
   - Both platforms: `~/.aihaus/bin/aih-graph query --hybrid "decision"` (Windows: `& "$HOME/.aihaus/bin/aih-graph.exe" query --hybrid "decision"`)
   - Expected: at least one line prefixed with `[s=N.NN]` showing scored result (e.g., `[s=5.42] Decision   ADR-260515-E-amend-02   ...`).
   - If the output is `no node matches identifier` you used the wrong mode — only `--hybrid`, `--semantic`, or `--bfs` with an exact identifier return results.
   - If the output is `consent gate: missing .aih-graph-consent` the user hasn't run `/aih-init` yet — that's expected at install time; tell the user to run `/aih-init` and skip this checkpoint.

If ANY checkpoint (1-3) fails, do NOT proceed — report which one and stop. Checkpoint 4 is post-install validation; skip it cleanly if the user hasn't run `/aih-init` yet.

### Step 4 — Tell the human user what to do next

After all 3 checkpoints pass, output EXACTLY this message to the user:

---
aihaus installed successfully.

Two final steps must be done by YOU (the human) inside Claude Code — these are slash commands inside the interactive TUI, not shell commands. An LLM/agent cannot run them from outside.

In any project you want to use aihaus on:

  cd <your-project>
  claude

Then inside Claude Code, type:

  /aih-install     # links aihaus into this repo
  /aih-init        # bootstraps .aihaus/project.md + indexes memory engine

After that, all `/aih-*` commands work in that project.
---

### Recovery paths if something goes wrong

- aih-graph binary did not download (Step 3 checkpoint 2 fails): run `bash "$INSTALL_DIR/pkg/scripts/install-aih-graph-binary.sh"` manually. If it still fails, check `https://github.com/overdrive-dev/aihaus-flow/releases` for the `aih-graph-v*` release matching your platform (linux-amd64, darwin-amd64, darwin-arm64, windows-amd64); download manually and place at `~/.aihaus/bin/aih-graph[.exe]`, chmod +x on Unix.
- `/aih-install` not recognized in Claude Code: the user did not restart Claude Code after install. Have them `exit` and re-launch `claude`.
- AIHAUS_HOME ambiguity: if user has multiple legacy installs, the 8-tier discovery chain picks the newest. Force a specific one with: `AIHAUS_HOME="$INSTALL_DIR" claude`.

Report final status: install location, aih-graph version, and which platform you detected.
````

---

## What the LLM cannot do

The final two steps — `/aih-install` and `/aih-init` — are slash commands inside the interactive Claude Code TUI. No LLM/agent can drive these from outside the session. You (human) must run them yourself. This is by design: `/aih-init` writes `.aihaus/project.md` based on your codebase, and the slash command lives in a different runtime than shell automation.
