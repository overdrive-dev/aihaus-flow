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
  update --all  Update all registered installs (requires Z9 registry)
  self-update   Update the central aihaus clone from origin (requires Z9)
  --help, -h    Show this message
'@ | Write-Host }

function Invoke-Sh([string]$sh,[string]$ps1,[string[]]$xa) {
    if (Get-Command bash -ErrorAction SilentlyContinue) { & bash $sh @xa; exit $LASTEXITCODE }
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $ps1 @xa; exit $LASTEXITCODE }

function Invoke-Memory([string]$HomePath,[string[]]$GraphArgs) {
    $GraphArgs = Repair-GraphArgs $GraphArgs
    $candidates=@()
    if ($env:AIH_GRAPH_BIN) { $candidates += $env:AIH_GRAPH_BIN }
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
            & $candidate @Args
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

if ($Verb -in @("--help","-h","")) { Show-Help; exit 0 }
$h=Resolve-Home
if (-not $h) { Write-Host "aihaus: package not found. Set AIHAUS_HOME or reinstall." -ForegroundColor Red; exit 1 }

switch ($Verb) {
  "install"     { Invoke-Sh (Join-Path $h "pkg\scripts\install.sh") (Join-Path $h "pkg\scripts\install.ps1") (@("--target",(Get-Location).Path)+$Rest) }
  "update" {
      if ($Rest -and $Rest[0] -eq "--all") {
          $reg=Join-Path $env:USERPROFILE ".aihaus\.targets"
          if (!(Test-Path $reg)) { Write-Host "aihaus update --all: registry not yet populated (Z9 writes on next install)." -ForegroundColor Yellow; exit 1 }
          $rc=0; $extra=if($Rest.Count -gt 1){$Rest[1..($Rest.Count-1)]}else{@()}
          foreach ($t in (Get-Content -LiteralPath $reg)) { if(!$t.Trim()){continue}
              Write-Host "aihaus update: $t"
              & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $h "pkg\scripts\update.ps1") -Target $t @extra
              if ($LASTEXITCODE -ne 0){$rc=$LASTEXITCODE} }; exit $rc }
      Invoke-Sh (Join-Path $h "pkg\scripts\update.sh") (Join-Path $h "pkg\scripts\update.ps1") (@("--target",(Get-Location).Path)+$Rest) }
  "memory"      { Invoke-Memory $h $Rest }
  "self-update" { Test-DogfoodDirty; Invoke-Sh (Join-Path $h "pkg\scripts\update.sh") (Join-Path $h "pkg\scripts\update.ps1") (@("--self")+$Rest) }
  default       { Write-Host "aihaus: unknown verb '$Verb'" -ForegroundColor Red; Write-Host "Run 'aihaus --help' for usage." -ForegroundColor Red; exit 2 }
}
