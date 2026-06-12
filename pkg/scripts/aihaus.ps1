# aihaus.ps1 — PowerShell CLI shim  M022/Z5  FR-10; ADR-260504-A §6.1
# 8-tier AIHAUS_HOME chain inlined (D-Z5-A; sourcing install.ps1 unsafe).
# self-update → update.ps1 -Self / update.sh --self  (Z9 implements flag; fails until then)
# update --all → $env:USERPROFILE\.aihaus\.targets registry  (Z9 writes on install)
param([Parameter(Position=0)][string]$Verb="",[Parameter(Position=1,ValueFromRemainingArguments=$true)][string[]]$Rest)
$ErrorActionPreference='Stop'

function Resolve-Home {
    if ($env:AIHAUS_HOME -and (Test-Path (Join-Path $env:AIHAUS_HOME "pkg\.aihaus\skills"))) { return $env:AIHAUS_HOME }
    $reg=Join-Path $env:USERPROFILE ".aihaus\.install-source"
    if (Test-Path $reg) { $r=(Get-Content -LiteralPath $reg -Raw).Trim()
        if ($r -and (Test-Path (Join-Path $r "pkg\.aihaus\skills"))) { return $r } }
    $lad=if($env:LOCALAPPDATA){$env:LOCALAPPDATA}else{Join-Path $env:USERPROFILE "AppData\Local"}
    $best=$null;$bestTs=0
    foreach ($c in @((Join-Path $lad "aihaus"),(Join-Path $env:USERPROFILE "tools\aihaus"),
        (Join-Path $env:USERPROFILE "Documents\GitHub\aihaus-flow"),
        (Join-Path $env:USERPROFILE "Documents\GitHub\aihaus"),(Join-Path $env:USERPROFILE "code\aihaus"))) {
        if ((Test-Path (Join-Path $c "pkg\.aihaus\skills")) -and (Test-Path (Join-Path $c ".git"))) {
            try { $ts=[long](& git -C $c log -1 --format=%ct 2>$null)
                  if ($ts -gt $bestTs){$best=$c;$bestTs=$ts} } catch {} } }
    if ($best) { $rd=Join-Path $env:USERPROFILE ".aihaus"; if(!(Test-Path $rd)){New-Item -ItemType Directory $rd -Force|Out-Null}
        Set-Content -LiteralPath $reg -Value $best -Encoding UTF8 -NoNewline; return $best }
    return $null
}

function Test-DogfoodDirty {  # FR-12/R8
    $cwd=(Get-Location).Path
    if ((Test-Path (Join-Path $cwd "pkg\scripts\install.sh")) -and (Test-Path (Join-Path $cwd "pkg\.aihaus\skills"))) {
        $dirty=& git -C $cwd status --porcelain 2>$null
        if ($dirty) { Write-Host "aihaus self-update: dogfood cwd has uncommitted changes -- aborting (commit or stash manually first)" -ForegroundColor Red; exit 3 } } }

function Show-Help { @'
Usage: aihaus <verb> [options]
Verbs:
  install       Install aihaus into the current directory
  update        Update aihaus in the current directory
  memory        Query repository memory (delegates to aih-graph)
                memory packet --task "<text>" --json -- batched context packet
                (status + Rule/Decision slice + top matches in ONE call; M050/S05)
  prefs add "<text>" [--topic <slug>]
                Append a global user preference (tier C, M050/S06) to
                ~\.aihaus\memory\user\preferences.md -- the SOLE write path
                (ADR-260611-C). Topics: workflow|style|tooling|communication|other
  kanban gate|question|answer
                Sanctioned write path for .aihaus/state/kanban.db (M050/S07,
                ADR-260611-C): gate_events / planning_questions /
                planning_answers rows. Gate validation is WARN-ONLY this cycle
                (ADR-260611-D). Grammar: .aihaus/protocols/kanban/db-schema.md
  feedback export
                Produce .aihaus/runtime/evolution-export.md (M050/S08): gate-churn
                stats (kanban.db gate_events) + recurring warnings
                (warning-recurrence.jsonl) + evolution proposals
                (milestones/*/execution/{AGENT,SKILL}-EVOLUTION.md). Sections
                always present; empty sources carry explicit "(none)" markers.
  update --all  Update all registered installs (~\.aihaus\.targets registry)
  self-update   Update the central aihaus clone from origin (requires Z9)
  --help, -h    Show this message
'@ | Write-Host }

function Invoke-Sh([string]$sh,[string]$ps1,[string[]]$xa) {
    if (Get-Command bash -ErrorAction SilentlyContinue) { & bash $sh @xa; exit $LASTEXITCODE }
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $ps1 @xa; exit $LASTEXITCODE }

function Resolve-GraphRun([string]$HomePath) {
    # Mirrors the Invoke-Memory discovery chain, returning the runner as an
    # array (exe [+ prefix args]) instead of exec-ing — needed by the M050/S05
    # packet verb, which composes three aih-graph calls in one process.
    $candidates=@()
    if ($env:AIH_GRAPH_BIN) { $candidates += $env:AIH_GRAPH_BIN }
    $candidates += (Join-Path (Get-Location).Path ".aihaus\bin\aih-graph.exe")
    $candidates += (Join-Path (Get-Location).Path ".aihaus\bin\aih-graph")
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return ,@($candidate) }
    }
    $sourceDir=Join-Path $HomePath "aih-graph"
    if ((Test-Path (Join-Path $sourceDir "go.mod")) -and (Get-Command go -ErrorAction SilentlyContinue)) {
        $goTmpRoot = if ($env:AIH_GRAPH_GO_TMP) { $env:AIH_GRAPH_GO_TMP } else { Join-Path $HomePath "tmp\aih-graph-go" }
        New-Item -ItemType Directory -Force -Path (Join-Path $goTmpRoot "tmp") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $goTmpRoot "cache") | Out-Null
        $env:AIH_GRAPH_CALLER_CWD=(Get-Location).Path
        $env:GOTMPDIR=(Join-Path $goTmpRoot "tmp")
        $env:GOCACHE=(Join-Path $goTmpRoot "cache")
        return ,@("go","-C",$sourceDir,"run","./cmd/aih-graph")
    }
    foreach ($candidate in @((Join-Path $HomePath "aih-graph\bin\aih-graph.exe"),
                             (Join-Path $HomePath "aih-graph\bin\aih-graph"),
                             (Join-Path $env:USERPROFILE ".aihaus\bin\aih-graph.exe"),
                             (Join-Path $env:USERPROFILE ".aihaus\bin\aih-graph"))) {
        if (Test-Path -LiteralPath $candidate) { return ,@($candidate) }
    }
    $cmd=Get-Command aih-graph -ErrorAction SilentlyContinue
    if ($cmd) { return ,@($cmd.Source) }
    return $null
}

function Invoke-MemoryPacket([string]$HomePath,[string[]]$PacketArgs) {
    # M050/S05 (ADR-260611-F): single batched packet — status + Rule/Decision
    # slice (--types Rule,Decision --top 5) + top-3 hybrid matches, ONE shim
    # call. Output shape per architecture.md §4.4. BR-P3 parity with bash shim.
    $task=""; $db=""; $repo=""
    for ($i = 0; $i -lt $PacketArgs.Count; $i++) {
        $a=$PacketArgs[$i]
        if ($a -eq "--task" -and ($i+1) -lt $PacketArgs.Count) { $task=$PacketArgs[$i+1]; $i++ }
        elseif ($a -like "--task=*") { $task=$a.Substring(7) }
        elseif (($a -eq "--db" -or $a -eq "-db") -and ($i+1) -lt $PacketArgs.Count) { $db=$PacketArgs[$i+1]; $i++ }
        elseif ($a -like "--db=*") { $db=$a.Substring(5) }
        elseif ($a -like "-db=*") { $db=$a.Substring(4) }
        elseif ($a -eq "--repo" -and ($i+1) -lt $PacketArgs.Count) { $repo=$PacketArgs[$i+1]; $i++ }
        elseif ($a -like "--repo=*") { $repo=$a.Substring(7) }
        # --json accepted and ignored: packet output is always JSON
    }
    if (-not $task) { Write-Host 'aihaus memory packet: --task "<text>" required' -ForegroundColor Red; exit 2 }
    if (-not $repo) {
        $repo = if ($env:AIH_GRAPH_REPO) { $env:AIH_GRAPH_REPO }
                elseif ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR }
                else { (Get-Location).Path }
    }
    $run = Resolve-GraphRun $HomePath
    if (-not $run) { Write-Host "aihaus memory: aih-graph not found. Install it with: bash pkg/scripts/install-aih-graph-binary.sh" -ForegroundColor Red; exit 1 }
    $exe = $run[0]
    $baseArgs = if ($run.Count -gt 1) { $run[1..($run.Count-1)] } else { @() }
    $dbArgs = if ($db) { @("--db",$db) } else { @() }
    $degraded = $false
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    # try/catch per call: with $ErrorActionPreference='Stop', stderr redirect of
    # a native command can throw on Windows PowerShell 5.1 — packet is fail-open.
    $statusJson=""; $rulesJson=""; $matchesJson=""
    try { $statusJson  = (& $exe @baseArgs status --repo $repo @dbArgs --json 2>$null | Out-String).Trim() } catch { $statusJson = "" }
    try { $rulesJson   = (& $exe @baseArgs query --repo $repo @dbArgs --types "Rule,Decision" --top 5 --json $task 2>$null | Out-String).Trim() } catch { $rulesJson = "" }
    try { $matchesJson = (& $exe @baseArgs query --repo $repo @dbArgs --top 3 --json $task 2>$null | Out-String).Trim() } catch { $matchesJson = "" }
    $sw.Stop()
    # Defensive: any sub-payload that is empty or non-JSON degrades to {}.
    if (-not $statusJson  -or -not $statusJson.StartsWith("{"))  { $statusJson="{}";  $degraded=$true }
    if (-not $rulesJson   -or -not $rulesJson.StartsWith("{"))   { $rulesJson="{}";   $degraded=$true }
    if (-not $matchesJson -or -not $matchesJson.StartsWith("{")) { $matchesJson="{}"; $degraded=$true }
    $deg = if ($degraded) { "true" } else { "false" }
    Write-Output ('{"status":' + $statusJson + ',"rules":' + $rulesJson + ',"matches":' + $matchesJson + ',"degraded":' + $deg + ',"elapsed_ms":' + $sw.ElapsedMilliseconds + '}')
    exit 0
}

function Invoke-Memory([string]$HomePath,[string[]]$GraphArgs) {
    $GraphArgs = Repair-GraphArgs $GraphArgs
    $GraphArgs = Add-DefaultGraphDbArgs $GraphArgs
    # M050/S05: `packet` is composed by the shim (ONE shim call -> three
    # aih-graph invocations), never forwarded to the binary.
    if ($GraphArgs -and $GraphArgs.Count -ge 1 -and $GraphArgs[0] -eq "packet") {
        $rest = if ($GraphArgs.Count -gt 1) { $GraphArgs[1..($GraphArgs.Count-1)] } else { @() }
        Invoke-MemoryPacket $HomePath $rest
    }
    $candidates=@()
    if ($env:AIH_GRAPH_BIN) { $candidates += $env:AIH_GRAPH_BIN }
    $candidates += (Join-Path (Get-Location).Path ".aihaus\bin\aih-graph.exe")
    $candidates += (Join-Path (Get-Location).Path ".aihaus\bin\aih-graph")
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            & $candidate @GraphArgs
            exit $LASTEXITCODE
        }
    }
    $sourceDir=Join-Path $HomePath "aih-graph"
    if ((Test-Path (Join-Path $sourceDir "go.mod")) -and (Get-Command go -ErrorAction SilentlyContinue)) {
        $goTmpRoot = if ($env:AIH_GRAPH_GO_TMP) { $env:AIH_GRAPH_GO_TMP } else { Join-Path $HomePath "tmp\aih-graph-go" }
        New-Item -ItemType Directory -Force -Path (Join-Path $goTmpRoot "tmp") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $goTmpRoot "cache") | Out-Null
        $env:AIH_GRAPH_CALLER_CWD=(Get-Location).Path
        $env:GOTMPDIR=(Join-Path $goTmpRoot "tmp")
        $env:GOCACHE=(Join-Path $goTmpRoot "cache")
        & go -C $sourceDir run ./cmd/aih-graph @GraphArgs
        exit $LASTEXITCODE
    }
    foreach ($candidate in @((Join-Path $HomePath "aih-graph\bin\aih-graph.exe"), (Join-Path $HomePath "aih-graph\bin\aih-graph"))) {
        if (Test-Path -LiteralPath $candidate) {
            & $candidate @GraphArgs
            exit $LASTEXITCODE
        }
    }
    foreach ($candidate in @((Join-Path $env:USERPROFILE ".aihaus\bin\aih-graph.exe"), (Join-Path $env:USERPROFILE ".aihaus\bin\aih-graph"))) {
        if (Test-Path -LiteralPath $candidate) {
            & $candidate @GraphArgs
            exit $LASTEXITCODE
        }
    }
    $cmd=Get-Command aih-graph -ErrorAction SilentlyContinue
    if ($cmd) {
        & $cmd.Source @GraphArgs
        exit $LASTEXITCODE
    }
    Write-Host "aihaus memory: aih-graph not found. Install it with: bash pkg/scripts/install-aih-graph-binary.sh" -ForegroundColor Red
    exit 1
}

function Repair-GraphArgs([string[]]$GraphArgs) {
    if (-not $GraphArgs -or $GraphArgs.Count -lt 2) { return $GraphArgs }
    $cmd=$GraphArgs[0]
    if ($cmd -notin @("build","refresh","status","mark-stale")) { return $GraphArgs }
    $flags=@()
    $positional=@()
    foreach ($arg in $GraphArgs[1..($GraphArgs.Count-1)]) {
        if ($arg -match '\.db$') {
            $flags += @("-db", $arg)
        } else {
            $positional += $arg
        }
    }
    return @($cmd) + $flags + $positional
}

function Add-DefaultGraphDbArgs([string[]]$GraphArgs) {
    if (-not $GraphArgs -or $GraphArgs.Count -lt 1) { return $GraphArgs }
    $cmd=$GraphArgs[0]
    # db-pin allowlist (BR-P3): every query verb pins --db to the repo DB unless
    # the caller passed one. --user scope is exempt -- the user-scope graph lives
    # at ~/.aihaus/state/user-graph.db (ADR-260611-E), never the per-repo DB.
    # `packet` (M050/S05) joins the allowlist to inherit --db defaulting, then
    # is intercepted in Invoke-Memory (shim-composed verb).
    if ($cmd -notin @("build","refresh","status","query","context","callers","impact","gotchas","milestone","rule","why","rule-drift","obsidian-export","export-obsidian","packet")) { return $GraphArgs }
    foreach ($arg in $GraphArgs) {
        if ($arg -eq "--db" -or $arg -eq "-db" -or $arg -like "--db=*" -or $arg -like "-db=*") { return $GraphArgs }
        if ($arg -eq "--user") { return $GraphArgs }
    }
    $repoRoot = if ($env:AIH_GRAPH_REPO) { $env:AIH_GRAPH_REPO } elseif ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { (Get-Location).Path }
    for ($i = 0; $i -lt $GraphArgs.Count; $i++) {
        if ($GraphArgs[$i] -eq "--repo" -and ($i + 1) -lt $GraphArgs.Count) {
            $repoRoot = $GraphArgs[$i + 1]
        } elseif ($GraphArgs[$i] -like "--repo=*") {
            $repoRoot = $GraphArgs[$i].Substring(7)
        }
    }
    $dbPath = Join-Path $repoRoot ".aihaus\state\aih-graph.db"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dbPath) | Out-Null
    if ($GraphArgs.Count -eq 1) { return @($cmd, "--db", $dbPath) }
    return @($cmd, "--db", $dbPath) + $GraphArgs[1..($GraphArgs.Count-1)]
}

# ---------------------------------------------------------------------------
# prefs (M050/S06, ADR-260611-C/E) -- tier-C global user preferences.
# `aihaus prefs add "<text>" [--topic <slug>]` is the SOLE write path to
# ~\.aihaus\memory\user\preferences.md (BR-P7 -- no file-guard carve-outs).
# Atomicity: [System.IO.File]::Open exclusive lock file + temp + Move-Item.
# Own audit JSONL (~\.aihaus\state\prefs-audit.jsonl, sole writer -- BR-P5).
# BR-P3 parity with the bash shim _prefs()/_prefs_add().
# ---------------------------------------------------------------------------
function Write-PrefsAudit([string]$Result,[string]$Id,[string]$Topic,[string]$Reason) {
    try {
        $auditDir = Join-Path $env:USERPROFILE ".aihaus\state"
        if (-not (Test-Path $auditDir)) { New-Item -ItemType Directory -Path $auditDir -Force | Out-Null }
        $auditFile = Join-Path $auditDir "prefs-audit.jsonl"
        $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        $escReason = $Reason -replace '\\','\\\\' -replace '"','\"'
        $row = '{"ts":"' + $ts + '","event":"prefs-add","result":"' + $Result + '","id":"' + $Id + '","topic":"' + $Topic + '","reason":"' + $escReason + '","shell":"pwsh"}'
        [System.IO.File]::AppendAllText($auditFile, $row + "`n")
    } catch { }
}

function Invoke-Prefs([string]$HomePath,[string[]]$PrefArgs) {
    $sub = if ($PrefArgs -and $PrefArgs.Count -ge 1) { $PrefArgs[0] } else { "" }
    if ($sub -ne "add") {
        Write-Host 'aihaus prefs: unknown sub-verb. Usage: aihaus prefs add "<text>" [--topic <slug>]' -ForegroundColor Red
        exit 2
    }
    $text = ""; $topic = "other"
    for ($i = 1; $i -lt $PrefArgs.Count; $i++) {
        $a = $PrefArgs[$i]
        if ($a -eq "--topic" -and ($i+1) -lt $PrefArgs.Count) { $topic = $PrefArgs[$i+1]; $i++ }
        elseif ($a -like "--topic=*") { $topic = $a.Substring(8) }
        else { if ($text) { $text = "$text $a" } else { $text = $a } }
    }

    # --- Format validation (refusal = non-zero exit + audit row) ---
    $text = if ($text) { $text.Trim() } else { "" }
    if (-not $text) {
        Write-PrefsAudit "refused" "" $topic "empty entry text"
        Write-Host 'aihaus prefs add: entry text is empty. Usage: aihaus prefs add "<text>" [--topic <slug>]' -ForegroundColor Red
        exit 2
    }
    if ($text -match "[`r`n]") {
        Write-PrefsAudit "refused" "" $topic "multi-line entry text"
        Write-Host "aihaus prefs add: entry must be a single line (no embedded newlines)." -ForegroundColor Red
        exit 2
    }
    if ($text.Length -gt 500) {
        Write-PrefsAudit "refused" "" $topic "entry text exceeds 500 chars ($($text.Length))"
        Write-Host "aihaus prefs add: entry text exceeds 500 characters ($($text.Length))." -ForegroundColor Red
        exit 2
    }
    if ($topic -notin @("workflow","style","tooling","communication","other")) {
        Write-PrefsAudit "refused" "" $topic "invalid topic (allowed: workflow|style|tooling|communication|other)"
        Write-Host "aihaus prefs add: invalid --topic '$topic' (allowed: workflow|style|tooling|communication|other)." -ForegroundColor Red
        exit 2
    }

    $prefsFile = Join-Path $env:USERPROFILE ".aihaus\memory\user\preferences.md"
    $prefsDir = Split-Path -Parent $prefsFile
    if (-not (Test-Path $prefsDir)) { New-Item -ItemType Directory -Path $prefsDir -Force | Out-Null }

    # --- Exclusive lock file ([System.IO.File]::Open, FileShare None; ~10s) ---
    $lockPath = "$prefsFile.lock"
    $lockStream = $null
    for ($try = 0; $try -lt 100; $try++) {
        try {
            $lockStream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            break
        } catch {
            Start-Sleep -Milliseconds 100
        }
    }
    if (-not $lockStream) {
        Write-PrefsAudit "refused" "" $topic "lock timeout at $lockPath"
        Write-Host "aihaus prefs add: could not acquire lock at $lockPath (stale lock? remove it manually and retry)." -ForegroundColor Red
        exit 3
    }

    try {
        # Seed create-if-absent INSIDE the lock (concurrent first-adds race-safe).
        if (-not (Test-Path $prefsFile)) {
            $seedSrc = Join-Path $HomePath "pkg\.aihaus\templates\user-preferences-global.md"
            if (Test-Path $seedSrc) {
                Copy-Item -LiteralPath $seedSrc -Destination $prefsFile
            } else {
                [System.IO.File]::WriteAllText($prefsFile, "# User Preferences (aihaus tier C)`n`n<!-- AIHAUS:PREFS-START -->`n## Preferences`n<!-- AIHAUS:PREFS-END -->`n")
            }
        }

        # PREF-<n> max-scan allocation (business-rules-migrate.sh shape).
        $maxId = 0
        foreach ($line in [System.IO.File]::ReadAllLines($prefsFile)) {
            if ($line -match '^- PREF-([0-9]+)') {
                $n = [int]$Matches[1]
                if ($n -gt $maxId) { $maxId = $n }
            }
        }
        $nextId = $maxId + 1
        $entryDate = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
        $entryLine = "- PREF-$nextId [$entryDate] ($topic) $text"

        # Temp file in the same directory + atomic Move-Item. Insert before the
        # END marker when present; append at EOF otherwise.
        $lines = [System.IO.File]::ReadAllLines($prefsFile)
        $out = New-Object System.Collections.Generic.List[string]
        $inserted = $false
        foreach ($line in $lines) {
            if (-not $inserted -and $line.Contains('<!-- AIHAUS:PREFS-END -->')) {
                $out.Add($entryLine)
                $inserted = $true
            }
            $out.Add($line)
        }
        if (-not $inserted) { $out.Add($entryLine) }
        $tmpFile = "$prefsFile.tmp.$PID"
        [System.IO.File]::WriteAllLines($tmpFile, $out)
        Move-Item -LiteralPath $tmpFile -Destination $prefsFile -Force

        Write-PrefsAudit "ok" "PREF-$nextId" $topic ""
        Write-Host "prefs: appended PREF-$nextId ($topic) to ~\.aihaus\memory\user\preferences.md"
    } catch {
        Write-PrefsAudit "refused" "" $topic "write failed: $($_.Exception.Message)"
        Write-Host "aihaus prefs add: failed to write ${prefsFile}: $($_.Exception.Message)" -ForegroundColor Red
        try { $lockStream.Close() } catch { }
        try { Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue } catch { }
        exit 1
    }
    try { $lockStream.Close() } catch { }
    try { Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue } catch { }
    exit 0
}

# ---------------------------------------------------------------------------
# kanban (M050/S07, ADR-260611-C) -- the sanctioned write path for
# .aihaus/state/kanban.db (gate_events / planning_questions / planning_answers).
# Verdict 4-enum + rules_cited grammar are NORMATIVE in
# .aihaus/protocols/kanban/db-schema.md; the citation obligation itself is the
# harness gate law (protocols/harness.md, Gates) -- cited, not restated.
# Gate validation is WARN-ONLY this cycle (ADR-260611-D): malformed shape =>
# warn + "warn-allow" audit row + exit 0 -- never a block. Every decision path
# (allow / warn-allow / bypass) emits its row BEFORE exiting.
# .claude/audit/rule-cite.jsonl -- this wrapper is its SOLE writer (BR-P5),
# keyed (task_id, stage, created_at). gate_events schema UNTOUCHED (BR-P10).
# Audited validation bypass: AIHAUS_KANBAN_GATE_VALIDATE=0 (BR-P4).
# BR-P3 parity with the bash shim _kanban().
# ---------------------------------------------------------------------------
function Get-KanbanTs { (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") }

function ConvertTo-KanbanJson([string]$s) {
    if ($null -eq $s) { return "" }
    return (($s -replace '\\','\\') -replace '"','\"')
}

function ConvertTo-KanbanSql([string]$s) {
    if ($null -eq $s) { return "" }
    return ($s -replace "'","''")
}

function Get-KanbanNextId([string]$Sqlite,[string]$Db,[string]$Table,[string]$Prefix) {
    $n = 0
    try {
        $sub = $Prefix.Length + 1
        $raw = (& $Sqlite $Db "SELECT COALESCE(MAX(CAST(substr(id, $sub) AS INTEGER)), 0) FROM $Table WHERE id GLOB '$Prefix[0-9]*';" 2>$null | Out-String).Trim()
        if ($raw -match '^[0-9]+$') { $n = [int]$raw }
    } catch { $n = 0 }
    return ($n + 1)
}

function Invoke-Kanban([string]$HomePath,[string[]]$KanArgs) {
    $sub = if ($KanArgs -and $KanArgs.Count -ge 1) { $KanArgs[0] } else { "" }
    if ($sub -notin @("gate","question","answer")) {
        Write-Host 'aihaus kanban: unknown sub-verb. Usage: aihaus kanban gate|question|answer (grammar: .aihaus/protocols/kanban/db-schema.md, ADR-260611-C)' -ForegroundColor Red
        exit 2
    }
    # Generic --flag <value> / --flag=<value> parse into a map.
    $opt = @{}
    for ($i = 1; $i -lt $KanArgs.Count; $i++) {
        $a = $KanArgs[$i]
        if ($a -like "--*=*") {
            $pair = $a.Substring(2).Split("=", 2)
            $opt[$pair[0]] = $pair[1]
        } elseif ($a -like "--*" -and ($i+1) -lt $KanArgs.Count) {
            $opt[$a.Substring(2)] = $KanArgs[$i+1]; $i++
        }
    }
    $repo = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { (Get-Location).Path }
    $db = if ($opt["db"]) { $opt["db"] } else { Join-Path $repo ".aihaus\state\kanban.db" }

    if ($sub -eq "gate") {
        $task = $opt["task"]; $stage = $opt["stage"]; $verdict = $opt["verdict"]; $rules = $opt["rules"]
        if (-not $task -or -not $stage -or -not $verdict) {
            Write-Host 'aihaus kanban gate: --task <id> --stage <stage> --verdict "<verdict>" required ([--rules <csv>] [--reason <text>] [--evidence <path>] [--db <path>])' -ForegroundColor Red
            exit 2
        }
        # --- Shape validation (WARN-ONLY; grammar normative in db-schema.md) --
        $validation = "ok"; $warnReason = ""; $decision = "allow"; $optOut = "false"
        $ruleEls = @()
        if ($rules) { $ruleEls = @($rules.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
        if ($env:AIHAUS_KANBAN_GATE_VALIDATE -eq "0") {
            $decision = "bypass"; $optOut = "true"
        } else {
            if ($verdict -notmatch '^(PASS|SKIPPED|BLOCKED-TO-PLANNING|BLOCKED)(:.*)?$') {
                $validation = "warn"
                $warnReason = "verdict '$verdict' not in 4-enum PASS|SKIPPED|BLOCKED-TO-PLANNING|BLOCKED"
            }
            if (-not $rules) {
                $validation = "warn"
                if ($warnReason) { $warnReason += "; " }
                $warnReason += "rules_cited missing -- cite per the harness gate law (protocols/harness.md)"
            } else {
                $bad = @($ruleEls | Where-Object { $_ -notmatch '^(BR-F?[0-9]+|GAP:pq-[A-Za-z0-9][A-Za-z0-9_-]*|MECHANICS)$' })
                if ($bad.Count -gt 0) {
                    $validation = "warn"
                    if ($warnReason) { $warnReason += "; " }
                    $warnReason += "rules_cited element(s) '$($bad -join "' '")' not in grammar BR-F?[0-9]+ | GAP:pq-<id> | MECHANICS"
                }
            }
            if ($validation -eq "warn") { $decision = "warn-allow" }
        }
        if ($decision -eq "warn-allow") {
            Write-Host "aihaus kanban gate: WARN -- $warnReason. Recorded warn-allow; the write proceeds (warn-only this cycle, ADR-260611-D). Grammar: .aihaus/protocols/kanban/db-schema.md. Audited bypass: AIHAUS_KANBAN_GATE_VALIDATE=0." -ForegroundColor Yellow
        }
        # --- Persist the kanban row (gate_events schema UNTOUCHED -- BR-P10) --
        $sqlite = Get-Command sqlite3 -ErrorAction SilentlyContinue
        if (-not $sqlite) { Write-Host "aihaus kanban: sqlite3 not found -- the kanban DB requires it (same prerequisite as init-kanban-db.sh). Install sqlite3 and retry." -ForegroundColor Red; exit 127 }
        $dbDir = Split-Path -Parent $db
        if (-not (Test-Path $dbDir)) { New-Item -ItemType Directory -Path $dbDir -Force | Out-Null }
        if (-not (Test-Path $db)) {
            foreach ($schema in @((Join-Path $repo ".aihaus\protocols\kanban\schema.sql"), (Join-Path $HomePath "pkg\.aihaus\protocols\kanban\schema.sql"))) {
                if (Test-Path $schema) { try { Get-Content -Raw -LiteralPath $schema | & $sqlite.Source $db 2>$null } catch { }; break }
            }
        }
        $createdAt = Get-KanbanTs
        $gid = "GATE-{0:d3}" -f (Get-KanbanNextId $sqlite.Source $db "gate_events" "GATE-")
        $reasonSql = if ($opt["reason"]) { "'" + (ConvertTo-KanbanSql $opt["reason"]) + "'" } else { "NULL" }
        $evidenceSql = if ($opt["evidence"]) { "'" + (ConvertTo-KanbanSql $opt["evidence"]) + "'" } else { "NULL" }
        $ok = $true
        try {
            & $sqlite.Source $db "INSERT INTO gate_events (id, task_id, stage, verdict, reason, evidence_path, created_at) VALUES ('$(ConvertTo-KanbanSql $gid)', '$(ConvertTo-KanbanSql $task)', '$(ConvertTo-KanbanSql $stage)', '$(ConvertTo-KanbanSql $verdict)', $reasonSql, $evidenceSql, '$createdAt');" 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) { $ok = $false }
        } catch { $ok = $false }
        if (-not $ok) { Write-Host "aihaus kanban gate: failed to write gate_events row to $db." -ForegroundColor Red; exit 1 }
        # --- Citation row -> rule-cite.jsonl (SOLE writer -- BR-P5) -----------
        try {
            $auditDir = Join-Path $repo ".claude\audit"
            if (-not (Test-Path $auditDir)) { New-Item -ItemType Directory -Path $auditDir -Force | Out-Null }
            $rulesJson = ($ruleEls | ForEach-Object { '"' + (ConvertTo-KanbanJson $_) + '"' }) -join ","
            $warnJson = if ($warnReason) { '"' + (ConvertTo-KanbanJson $warnReason) + '"' } else { "null" }
            $row = '{"ts":"' + $createdAt + '","event":"kanban-gate","task_id":"' + (ConvertTo-KanbanJson $task) + '","stage":"' + (ConvertTo-KanbanJson $stage) + '","created_at":"' + $createdAt + '","verdict":"' + (ConvertTo-KanbanJson $verdict) + '","rules_cited":[' + $rulesJson + '],"validation":"' + $validation + '","warn_reason":' + $warnJson + ',"decision":"' + $decision + '","opt_out":' + $optOut + ',"shell":"pwsh"}'
            [System.IO.File]::AppendAllText((Join-Path $auditDir "rule-cite.jsonl"), $row + "`n")
        } catch { }
        Write-Host "kanban: gate $(($verdict -split ':')[0]) recorded for $task@$stage ($gid; decision $decision)"
        exit 0
    }

    # --- question / answer (thin validated wrappers) --------------------------
    $sqlite = Get-Command sqlite3 -ErrorAction SilentlyContinue
    if (-not $sqlite) { Write-Host "aihaus kanban: sqlite3 not found -- the kanban DB requires it (same prerequisite as init-kanban-db.sh). Install sqlite3 and retry." -ForegroundColor Red; exit 127 }
    $dbDir = Split-Path -Parent $db
    if (-not (Test-Path $dbDir)) { New-Item -ItemType Directory -Path $dbDir -Force | Out-Null }
    if (-not (Test-Path $db)) {
        foreach ($schema in @((Join-Path $repo ".aihaus\protocols\kanban\schema.sql"), (Join-Path $HomePath "pkg\.aihaus\protocols\kanban\schema.sql"))) {
            if (Test-Path $schema) { try { Get-Content -Raw -LiteralPath $schema | & $sqlite.Source $db 2>$null } catch { }; break }
        }
    }
    $srcKind = if ($opt["source-kind"]) { $opt["source-kind"] } else { "local" }
    $srcRefSql = if ($opt["source-ref"]) { "'" + (ConvertTo-KanbanSql $opt["source-ref"]) + "'" } else { "NULL" }

    if ($sub -eq "question") {
        $task = $opt["task"]; $question = $opt["question"]
        if (-not $task -or -not $question) {
            Write-Host 'aihaus kanban question: --task <id> --question "<one task-specific business-rule gap>" required ([--reason <text>] [--id pq-<n>] [--source-kind <kind>] [--source-ref <ref>] [--db <path>])' -ForegroundColor Red
            exit 2
        }
        $qid = $opt["id"]
        if ($qid -and $qid -notmatch '^pq-[A-Za-z0-9][A-Za-z0-9_-]*$') {
            Write-Host "aihaus kanban question: --id '$qid' must match pq-<id> (grammar: .aihaus/protocols/kanban/db-schema.md)." -ForegroundColor Red
            exit 2
        }
        if (-not $qid) { $qid = "pq-{0:d3}" -f (Get-KanbanNextId $sqlite.Source $db "planning_questions" "pq-") }
        $askedAt = Get-KanbanTs
        $reasonSql = if ($opt["reason"]) { "'" + (ConvertTo-KanbanSql $opt["reason"]) + "'" } else { "NULL" }
        $ok = $true
        try {
            & $sqlite.Source $db "INSERT INTO planning_questions (id, task_id, question, reason, status, source_kind, source_ref, asked_at) VALUES ('$(ConvertTo-KanbanSql $qid)', '$(ConvertTo-KanbanSql $task)', '$(ConvertTo-KanbanSql $question)', $reasonSql, 'open', '$(ConvertTo-KanbanSql $srcKind)', $srcRefSql, '$askedAt');" 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) { $ok = $false }
        } catch { $ok = $false }
        if (-not $ok) { Write-Host "aihaus kanban question: failed to write planning_questions row to $db (duplicate id $qid?)." -ForegroundColor Red; exit 1 }
        Write-Host "kanban: planning question $qid recorded for $task (status open)"
        exit 0
    }

    # answer
    $qid = $opt["question"]; $answer = $opt["answer"]
    if (-not $qid -or -not $answer) {
        Write-Host 'aihaus kanban answer: --question <pq-id> --answer "<text>" required ([--source-kind <kind>] [--source-ref <ref>] [--db <path>]). A "no-rule:<reason>" answer records an explicit promotion waiver.' -ForegroundColor Red
        exit 2
    }
    $exists = "0"
    try { $exists = (& $sqlite.Source $db "SELECT count(*) FROM planning_questions WHERE id = '$(ConvertTo-KanbanSql $qid)';" 2>$null | Out-String).Trim() } catch { $exists = "0" }
    if ($exists -eq "0") {
        Write-Host "aihaus kanban answer: question $qid not found in $db -- record it first via: aihaus kanban question" -ForegroundColor Red
        exit 4
    }
    $qstatus = if ($answer -like "no-rule:*") { "waived" } else { "answered" }
    $aid = "pa-{0:d3}" -f (Get-KanbanNextId $sqlite.Source $db "planning_answers" "pa-")
    $answeredAt = Get-KanbanTs
    $ok = $true
    try {
        & $sqlite.Source $db "INSERT INTO planning_answers (id, question_id, answer, source_kind, source_ref, answered_at) VALUES ('$(ConvertTo-KanbanSql $aid)', '$(ConvertTo-KanbanSql $qid)', '$(ConvertTo-KanbanSql $answer)', '$(ConvertTo-KanbanSql $srcKind)', $srcRefSql, '$answeredAt'); UPDATE planning_questions SET status = '$qstatus', answered_at = '$answeredAt' WHERE id = '$(ConvertTo-KanbanSql $qid)';" 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { $ok = $false }
    } catch { $ok = $false }
    if (-not $ok) { Write-Host "aihaus kanban answer: failed to write planning_answers row to $db." -ForegroundColor Red; exit 1 }
    Write-Host "kanban: answer $aid recorded for $qid (question status $qstatus)"
    if ($qstatus -eq "answered") {
        Write-Host "kanban: promote it to a DRAFT business rule carrying 'Source: $qid' per .aihaus/protocols/kanban/memory-promotion.md (the eval planning-answer-promotion join checks this)"
    }
    exit 0
}

# ---------------------------------------------------------------------------
# feedback (M050/S08) -- evolution-feedback export. Produces
# .aihaus/runtime/evolution-export.md with THREE sections, each ALWAYS present
# (never silently absent): empty sources carry an explicit "(none -- <reason>)"
# marker. Read-only over every source (BR-P5). BR-P3 parity with the bash shim
# _feedback()/_feedback_export().
# ---------------------------------------------------------------------------
function Invoke-Feedback([string]$HomePath,[string[]]$FbArgs) {
    $sub = if ($FbArgs -and $FbArgs.Count -ge 1) { $FbArgs[0] } else { "" }
    if ($sub -ne "export") {
        Write-Host 'aihaus feedback: unknown sub-verb. Usage: aihaus feedback export' -ForegroundColor Red
        exit 2
    }
    $repo = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { (Get-Location).Path }
    $outDir = Join-Path $repo '.aihaus\runtime'
    $out = Join-Path $outDir 'evolution-export.md'
    try {
        if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    } catch {
        Write-Host "aihaus feedback export: cannot create $outDir" -ForegroundColor Red
        exit 1
    }
    $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    # --- Section 1: gate-churn stats (kanban.db gate_events) ------------------
    $gateSection = "(none -- no kanban.db at .aihaus/state/kanban.db)"
    $db = Join-Path $repo '.aihaus\state\kanban.db'
    if (Test-Path -LiteralPath $db) {
        $sqlite = Get-Command sqlite3 -ErrorAction SilentlyContinue
        if ($sqlite) {
            $gateRows = @()
            try {
                $gateRows = @(& $sqlite.Source -separator ' | ' $db "SELECT stage, verdict, COUNT(*) FROM gate_events GROUP BY stage, verdict ORDER BY stage, verdict;" 2>$null | Where-Object { $_ })
            } catch { $gateRows = @() }
            if ($gateRows.Count -gt 0) {
                $totals = ""
                try { $totals = (& $sqlite.Source -separator ' ' $db "SELECT COUNT(*), COUNT(DISTINCT task_id) FROM gate_events;" 2>$null | Out-String).Trim() } catch { $totals = "" }
                $tableLines = @('| stage | verdict | count |', '|-------|---------|-------|')
                foreach ($row in $gateRows) {
                    $parts = $row -split ' \| '
                    if ($parts.Count -ge 3) { $tableLines += ('| ' + $parts[0] + ' | ' + $parts[1] + ' | ' + $parts[2] + ' |') }
                }
                $totalEvents = ($totals -split ' ')[0]
                $totalTasks = ($totals -split ' ')[-1]
                $gateSection = ($tableLines -join "`n") + "`n`nTotals: $totalEvents gate event(s) across $totalTasks distinct task(s)."
            } else {
                $gateSection = "(none -- kanban.db present but gate_events is empty)"
            }
        } else {
            $gateSection = "(none -- kanban.db present but sqlite3 unavailable)"
        }
    }

    # --- Section 2: recurring warnings (warning-recurrence.jsonl) -------------
    $warnSection = "(none -- no .claude/audit/warning-recurrence.jsonl)"
    $recurrenceLog = Join-Path $repo '.claude\audit\warning-recurrence.jsonl'
    if (Test-Path -LiteralPath $recurrenceLog) {
        $warnLines = @()
        foreach ($line in (Get-Content -LiteralPath $recurrenceLog -ErrorAction SilentlyContinue)) {
            if (-not $line.Trim()) { continue }
            try {
                $rowObj = $line | ConvertFrom-Json
                $cat = if ($rowObj.category) { $rowObj.category } else { "unknown" }
                $agent = if ($rowObj.source_agent) { $rowObj.source_agent } else { "unknown" }
                $cnt = if ($rowObj.recurrence_count) { $rowObj.recurrence_count } else { 0 }
                $first = if ($rowObj.first_seen_milestone) { $rowObj.first_seen_milestone } else { "?" }
                $last = if ($rowObj.last_seen_milestone) { $rowObj.last_seen_milestone } else { "?" }
                $summary = if ($rowObj.summary_representative) { $rowObj.summary_representative } else { "" }
                if ($summary.Length -gt 200) { $summary = $summary.Substring(0, 200) }
                $warnLines += ("- [$cat] $agent (x$cnt, $first -> $last): $summary")
            } catch { }
        }
        if ($warnLines.Count -gt 0) {
            $warnSection = $warnLines -join "`n"
        } else {
            $warnSection = "(none -- warning-recurrence.jsonl present but empty)"
        }
    }

    # --- Section 3: evolution proposals (milestone EVOLUTION ledgers) ---------
    $evoLines = @()
    $msRoot = Join-Path $repo '.aihaus\milestones'
    if (Test-Path -LiteralPath $msRoot) {
        foreach ($evoName in @('AGENT-EVOLUTION.md','SKILL-EVOLUTION.md')) {
            # NOTE: wildcard goes in -Path (not -Filter) -- PS 5.1 returns 0 results
            # when -Filter is combined with a wildcarded directory path.
            foreach ($evoFile in (Get-ChildItem -Path (Join-Path $msRoot "*\execution\$evoName") -File -ErrorAction SilentlyContinue)) {
                $rel = $evoFile.FullName.Substring($repo.Length).TrimStart('\','/') -replace '\\','/'
                $lineCount = 0
                try { $lineCount = @(Get-Content -LiteralPath $evoFile.FullName -ErrorAction SilentlyContinue).Count } catch { $lineCount = 0 }
                $evoLines += ('- `' + $rel + '` (' + $lineCount + ' lines)')
            }
        }
    }
    $evoSection = if ($evoLines.Count -gt 0) { ($evoLines | Sort-Object) -join "`n" } else { "(none -- no .aihaus/milestones/*/execution/{AGENT,SKILL}-EVOLUTION.md found)" }

    $doc = @"
# Evolution export (aihaus feedback export, M050/S08)

Generated: $ts
Repo: $repo
Sources are read-only; this file is regenerated on every run.

## Gate-churn stats

$gateSection

## Recurring warnings

$warnSection

## Evolution proposals

$evoSection
"@
    $utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllText($out, ($doc -replace "`r`n", "`n") + "`n", $utf8NoBom)
    Write-Host "feedback: wrote $out"
    exit 0
}

if ($Verb -in @("--help","-h","")) { Show-Help; exit 0 }
$h=Resolve-Home
if (-not $h) { Write-Host "aihaus: package not found. Set AIHAUS_HOME or reinstall." -ForegroundColor Red; exit 1 }

switch ($Verb) {
  "install"     { Invoke-Sh (Join-Path $h "pkg\scripts\install.sh") (Join-Path $h "pkg\scripts\install.ps1") (@("--target",(Get-Location).Path)+$Rest) }
  "update" {
      if ($Rest -and $Rest[0] -eq "--all") {
          $reg=Join-Path $env:USERPROFILE ".aihaus\.targets"
          if (!(Test-Path $reg)) { Write-Host "aihaus update --all: registry not yet populated (~\.aihaus\.targets; written by install/update since M050/S08 -- run an install or update on a repo first)." -ForegroundColor Yellow; exit 1 }
          $rc=0; $extra=if($Rest.Count -gt 1){$Rest[1..($Rest.Count-1)]}else{@()}
          foreach ($t in (Get-Content -LiteralPath $reg)) { if(!$t.Trim()){continue}
              Write-Host "aihaus update: $t"
              & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $h "pkg\scripts\update.ps1") -Target $t @extra
              if ($LASTEXITCODE -ne 0){$rc=$LASTEXITCODE} }; exit $rc }
      Invoke-Sh (Join-Path $h "pkg\scripts\update.sh") (Join-Path $h "pkg\scripts\update.ps1") (@("--target",(Get-Location).Path)+$Rest) }
  "memory"      { Invoke-Memory $h $Rest }
  "prefs"       { Invoke-Prefs $h $Rest }
  "kanban"      { Invoke-Kanban $h $Rest }
  "feedback"    { Invoke-Feedback $h $Rest }
  "self-update" { Test-DogfoodDirty; Invoke-Sh (Join-Path $h "pkg\scripts\update.sh") (Join-Path $h "pkg\scripts\update.ps1") (@("--self")+$Rest) }
  default       { Write-Host "aihaus: unknown verb '$Verb'" -ForegroundColor Red; Write-Host "Run 'aihaus --help' for usage." -ForegroundColor Red; exit 2 }
}
