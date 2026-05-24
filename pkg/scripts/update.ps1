# aihaus update script (Windows PowerShell)
# Re-syncs local .aihaus/ from pkg/ package source.
# Preserves ALL local data: project.md, plans/, milestones/, memory/, etc.
#
# V5 (M022/Z9): user-global skill refresh + R3 dogfood guard + -Self + R9 copy-mode
# FR-23: user-global refresh on every update
# FR-24: R4 marker invariant -- never touch unmarked entries
# FR-25: R3 dogfood guard -- skip git pull on dogfood cwd
# FR-26: R9 copy-mode user-global refresh
# ADR-260504-A §6.4
#
# Flags:
#   -Target <path>   Update in <path> instead of $PWD
#   -Self            Pull from origin before refreshing (used by 'aihaus self-update')
#   -Help            Show usage

[CmdletBinding()]
param(
    [string]$Target = (Get-Location).Path,
    [switch]$Help,
    [switch]$NoGitignore,
    [switch]$Self
)

$ErrorActionPreference = 'Stop'

function Show-Usage {
    @'
Usage: update.ps1 [-Target <path>] [-NoGitignore] [-Self]

Re-syncs package-managed files in .aihaus/ from the aihaus package source.
Local data (project.md, plans/, milestones/, memory/, etc.) is preserved.
Missing memory starter files are seeded without overwriting existing files.

Options:
  -Target <path>   Target directory (default: current working directory)
  -NoGitignore     Skip the .gitignore backfill prompt entirely (non-interactive
                   CI runs, or users who have already declined and don't want
                   to be asked again).
  -Self            Pull from origin before refreshing. Used by 'aihaus self-update'.
                   Aborts with exit 3 if cwd is dogfood and has uncommitted changes.
  -Help            Show this message
'@ | Write-Host
}

if ($Help) { Show-Usage; exit 0 }

# ---------------------------------------------------------------------------
# V5 (M022/Z9): Dogfood detection -- matches Z3's is_dogfood_cwd exactly.
# Returns $true when the current working directory IS the central aihaus clone.
# Predicate: pkg/scripts/install.sh + pkg/.aihaus/skills/ both exist in PWD.
# ---------------------------------------------------------------------------
function Test-DogfoodCwd {
    $cwd = (Get-Location).Path
    return (Test-Path (Join-Path $cwd 'pkg\scripts\install.sh')) -and `
           (Test-Path (Join-Path $cwd 'pkg\.aihaus\skills'))
}

function Write-SyncedTargetWarning {
    param([string]$TargetPath)
    $normalized = $TargetPath -replace '\\', '/'
    if ($normalized -match '(?i)(OneDrive|Dropbox|Google Drive|iCloudDrive|/Box/)') {
        Write-Host "  warn: target is on a synced path; worktree churn may be slow/lock-prone. Pause sync before cleanup if needed." -ForegroundColor Yellow
    }
}

function Write-CopyModeWarning {
    if ($script:Mode -eq 'copy') {
        Write-Host "  warn: copy mode overwrites package-managed .aihaus/.claude files on update; keep custom edits in project memory/workflows, not managed skills/agents/hooks." -ForegroundColor Yellow
    }
}

# Resolve package root (the directory containing this script's parent)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$PkgRoot = (Resolve-Path (Join-Path $ScriptDir '..')).Path
$PkgAihaus = Join-Path $PkgRoot '.aihaus'
$PkgTemplates = Join-Path $PkgAihaus 'templates'

if (-not (Test-Path $Target)) {
    Write-Error "target directory does not exist: $Target"
    exit 1
}
$Target = (Resolve-Path $Target).Path

$Aihaus = Join-Path $Target '.aihaus'
$Claude = Join-Path $Target '.claude'

# ---------------------------------------------------------------------------
# V5 (M022/Z9): R3 dogfood guard + -Self / R8 dirty-dogfood abort
# Must run BEFORE preflight checks that require .aihaus/ to exist.
# ---------------------------------------------------------------------------
if (Test-DogfoodCwd) {
    if ($Self) {
        # R8: -Self on dogfood -- abort if dirty
        $porcelain = & git -C (Get-Location).Path status --porcelain 2>$null
        if (-not [string]::IsNullOrWhiteSpace($porcelain)) {
            Write-Error "aihaus self-update: uncommitted changes -- aborting (commit or stash manually first)"
            exit 3
        }
        Write-Host "  dogfood mode + -Self: pulling from origin..."
        & git -C (Get-Location).Path pull
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        # After git pull, PkgRoot may have shifted; recalculate derived paths.
        $PkgAihaus = Join-Path $PkgRoot '.aihaus'
        $PkgTemplates = Join-Path $PkgAihaus 'templates'
    } else {
        # R3: dogfood cwd without -Self -- skip git pull, continue with skill refresh
        Write-Host "  dogfood mode -- git pull skipped; commit local changes before self-update"
    }
}

# ---- Preflight checks -------------------------------------------------------

if (-not (Test-Path $Aihaus)) {
    Write-Error "No .aihaus/ directory found at $Target. Run install.ps1 first."
    exit 1
}

# Read install mode from marker file
$ModeFile = Join-Path $Aihaus '.install-mode'
if (Test-Path $ModeFile) {
    $Mode = (Get-Content $ModeFile -Raw).Trim()
} else {
    # Default to copy if no marker exists (legacy installs)
    $Mode = 'copy'
    Write-Host "  warn: .install-mode not found; defaulting to copy mode"
}

Write-Host "aihaus updater"
Write-Host "  package: $PkgRoot"
Write-Host "  target:  $Target"
Write-Host "  mode:    $Mode"
Write-SyncedTargetWarning -TargetPath $Target
Write-CopyModeWarning

# ---- Update package directories in .aihaus/ ---------------------------------
# These are the package-owned directories that get refreshed.
# Local data directories (plans/, milestones/, features/, bugfixes/, memory/,
# rules/, notion/, debug/) are NEVER touched.

function Update-AihausDir {
    param([string]$Name)

    $src = Join-Path $PkgAihaus $Name
    $dst = Join-Path $script:Aihaus $Name

    if (-not (Test-Path $src)) {
        Write-Host "  skip: $Name not found in package"
        return
    }

    # Remove old managed contents before copying. This is copy-mode orphan
    # pruning: the shipped package tree is the manifest for managed files.
    if (Test-Path $dst) {
        Remove-Item -Recurse -Force $dst
    }
    Copy-Item -Path $src -Destination $dst -Recurse -Force
    Write-Host "  refreshed: .aihaus\$Name (managed copy pruned)"
}

foreach ($name in @('skills', 'agents', 'hooks', 'templates')) {
    Update-AihausDir -Name $name
}

# Repo-local runtime layout. Do not overwrite workflow profiles on update; only
# seed missing defaults for existing installs.
foreach ($dir in @(
    (Join-Path $Aihaus 'bin'),
    (Join-Path $Aihaus 'state'),
    (Join-Path $Aihaus 'runtime'),
    (Join-Path $Aihaus 'backups'),
    (Join-Path $Aihaus 'workflows'),
    (Join-Path $Aihaus 'workflows\runs'),
    (Join-Path $Aihaus 'memory\workflows'),
    (Join-Path $Aihaus 'memory\agents'),
    (Join-Path $Aihaus 'memory\reviews'),
    (Join-Path $Aihaus 'memory\global'),
    (Join-Path $Aihaus 'memory\backend'),
    (Join-Path $Aihaus 'memory\frontend')
)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}
$workflowDefaultSrc = Join-Path $PkgAihaus 'workflows\default.md'
$workflowDefaultDst = Join-Path $Aihaus 'workflows\default.md'
if (-not (Test-Path $workflowDefaultDst) -and (Test-Path $workflowDefaultSrc)) {
    Copy-Item -LiteralPath $workflowDefaultSrc -Destination $workflowDefaultDst
    Write-Host "  workflow: created .aihaus\workflows\default.md"
}
$workflowAgentsSrc = Join-Path $PkgAihaus 'workflows\agents.md'
$workflowAgentsDst = Join-Path $Aihaus 'workflows\agents.md'
if (-not (Test-Path $workflowAgentsDst) -and (Test-Path $workflowAgentsSrc)) {
    Copy-Item -LiteralPath $workflowAgentsSrc -Destination $workflowAgentsDst
    Write-Host "  workflow: created .aihaus\workflows\agents.md"
}
$memorySeedFiles = @(
    'memory\MEMORY.md',
    'memory\workflows\README.md',
    'memory\workflows\environment.md',
    'memory\workflows\user-preferences.md',
    'memory\workflows\rules.md',
    'memory\workflows\gotchas.md',
    'memory\agents\README.md',
    'memory\reviews\README.md',
    'memory\reviews\common-findings.md',
    'memory\global\README.md',
    'memory\global\gotchas.md',
    'memory\backend\README.md',
    'memory\frontend\README.md'
)
foreach ($rel in $memorySeedFiles) {
    $src = Join-Path $PkgAihaus $rel
    $dst = Join-Path $Aihaus $rel
    if (-not (Test-Path -LiteralPath $dst) -and (Test-Path -LiteralPath $src)) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force | Out-Null
        Copy-Item -LiteralPath $src -Destination $dst
    }
}

# ---- Refresh auto.ps1 from launch-aihaus.ps1 on hash change (M019/S02 F-C3 fix) --
# Closes the same gap as update.sh: existing installs receive CLI-005 env defaults
# and any future launch-aihaus.ps1 edits via update.ps1 automatically.
$LaunchSrc = Join-Path $ScriptDir 'launch-aihaus.ps1'
$AutoDst   = Join-Path $Aihaus 'auto.ps1'
if (Test-Path $LaunchSrc) {
    if (Test-Path $AutoDst) {
        $srcHash = (Get-FileHash -LiteralPath $LaunchSrc -Algorithm SHA256).Hash
        $dstHash = (Get-FileHash -LiteralPath $AutoDst   -Algorithm SHA256).Hash
        if ($srcHash -ne $dstHash) {
            Copy-Item -Path $LaunchSrc -Destination $AutoDst -Force
            Write-Host "  auto.ps1 refreshed from launch-aihaus.ps1"
        }
    } else {
        Copy-Item -Path $LaunchSrc -Destination $AutoDst -Force
        Write-Host "  auto.ps1 created from launch-aihaus.ps1"
    }
} else {
    Write-Host "  warn: launch-aihaus.ps1 not found at $LaunchSrc, skipping auto.ps1 refresh"
}

# ---- Restore per-agent effort from sidecar -----------------------------------
# Dispatch order (binding per architecture.md):
#   1. Restore-Effort   -- migrates v2 .calibration -> v3 .effort (if needed)
#                          or idempotent v3 restore.
# Pinned between refresh loop and re-link so both .aihaus\agents\ (physical)
# and .claude\agents\ (junction or copy) pick up restored frontmatter.
# Schema contract: <aihaus_root>\skills\aih-effort\annexes\state-file.md
# Cohort membership (v3): <aihaus_root>\skills\aih-effort\annexes\cohorts.md

# ---- Test-PresetImmune inlined (mirrors install.ps1 helper; R3 / ADR-M012-A) --
function Test-PresetImmune {
    param([string]$Cohort)
    return $Cohort -match '^:?(adversarial-scout|adversarial-review)$'
}

function Invoke-MigrateV2ToV3 {
    param(
        [string]$AihausRoot,
        [string]$V2File,
        [string]$V3File
    )
    $sidecarLines = Get-Content -LiteralPath $V2File
    $v2LastPreset = ''; $v2LastCommit = ''; $v2PermMode = ''
    $v2PlannerModel = ''; $v2PlannerEffort = ''
    $v2DoerModel = ''; $v2DoerEffort = ''
    $v2VerifierModel = ''; $v2VerifierEffort = ''
    $v2InvestigatorModel = ''; $v2InvestigatorEffort = ''
    $v2AdversarialModel = ''; $v2AdversarialEffort = ''
    $perAgentEffortLines = [System.Collections.Generic.List[string]]::new()
    $perAgentModelLines  = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $sidecarLines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^\s*#') { continue }
        if ($line -notmatch '=') { continue }
        $parts = $line -split '=', 2
        $k = ($parts[0] -replace "`r", '').Trim()
        $v = ($parts[1] -replace "`r", '').Trim()
        switch ($k) {
            'schema' {}
            'last_preset'              { $v2LastPreset = $v }
            'last_commit'              { $v2LastCommit = $v }
            'permission_mode'          { $v2PermMode = $v }
            'cohort.planner.model'     { $v2PlannerModel = $v }
            'cohort.planner.effort'    { $v2PlannerEffort = $v }
            'cohort.doer.model'        { $v2DoerModel = $v }
            'cohort.doer.effort'       { $v2DoerEffort = $v }
            'cohort.verifier.model'    { $v2VerifierModel = $v }
            'cohort.verifier.effort'   { $v2VerifierEffort = $v }
            'cohort.investigator.model'  { $v2InvestigatorModel = $v }
            'cohort.investigator.effort' { $v2InvestigatorEffort = $v }
            'cohort.adversarial.model'   { $v2AdversarialModel = $v }
            'cohort.adversarial.effort'  { $v2AdversarialEffort = $v }
            default {
                if ($k -match '^cohort\.') {}
                elseif ($k -match '\.model$') { $perAgentModelLines.Add("$k=$v") }
                else { $perAgentEffortLines.Add("$k=$v") }
            }
        }
    }
    $v3LastPreset = 'balanced'; $presetDriftNote = ''
    switch ($v2LastPreset) {
        'balanced'       { $v3LastPreset = 'balanced' }
        'cost-optimized' { $v3LastPreset = 'cost'; $presetDriftNote = "cost-optimized renamed to 'cost'; :planner high->medium; :doer high->medium" }
        'quality-first'  { $v3LastPreset = 'high'; $presetDriftNote = "quality-first renamed to 'high'; :planner max->xhigh" }
        'auto-mode-safe' { $v3LastPreset = 'balanced' }
        ''               { $v3LastPreset = 'balanced' }
        default {
            $v3LastPreset = 'balanced'
            Write-Host "  !!  v2 sidecar had unknown last_preset='$v2LastPreset' -- reset to balanced." -ForegroundColor Yellow
        }
    }
    $plannerLossy = ($v2PlannerModel -ne '' -or $v2PlannerEffort -ne '')
    $adversarialLossy = ($v2AdversarialModel -ne '' -or $v2AdversarialEffort -ne '')
    $investigatorLossy = ($v2InvestigatorModel -ne '' -or $v2InvestigatorEffort -ne '')
    $migrationTs = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    $tmpFile = "$V3File.tmp"
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('# aihaus effort state -- managed by /aih-effort, consumed by /aih-update')
    [void]$sb.AppendLine('# Schema: v3 -- 6 uniform cohorts + per-agent overrides')
    [void]$sb.AppendLine('# This file is USER-OWNED and derived state. Safe to delete. Do not commit.')
    [void]$sb.AppendLine("# Migrated from schema v2 (.calibration) on $migrationTs")
    [void]$sb.AppendLine(''); [void]$sb.AppendLine('schema=3')
    [void]$sb.AppendLine("last_preset=$v3LastPreset")
    if ($v2LastCommit) { [void]$sb.AppendLine("last_commit=$v2LastCommit") }
    [void]$sb.AppendLine(''); [void]$sb.AppendLine('# Cohort-level rows (migrated from v2)')
    if ($v2PlannerModel)  { [void]$sb.AppendLine("cohort.planner-binding.model=$v2PlannerModel") }
    if ($v2PlannerEffort) { [void]$sb.AppendLine("cohort.planner-binding.effort=$v2PlannerEffort") }
    if ($v2DoerModel)   { [void]$sb.AppendLine("cohort.doer.model=$v2DoerModel") }
    if ($v2DoerEffort)  { [void]$sb.AppendLine("cohort.doer.effort=$v2DoerEffort") }
    if ($v2VerifierModel)  { [void]$sb.AppendLine("cohort.verifier.model=$v2VerifierModel") }
    if ($v2VerifierEffort) { [void]$sb.AppendLine("cohort.verifier.effort=$v2VerifierEffort") }
    if ($v2AdversarialModel)  { [void]$sb.AppendLine("cohort.adversarial-scout.model=$v2AdversarialModel") }
    if ($v2AdversarialEffort) { [void]$sb.AppendLine("cohort.adversarial-scout.effort=$v2AdversarialEffort") }
    if ($investigatorLossy) {
        [void]$sb.AppendLine(''); [void]$sb.AppendLine('# investigator cohort deleted -- re-emitted as per-agent overrides (FR-M06)')
        if ($v2InvestigatorModel) {
            [void]$sb.AppendLine("debugger.model=$v2InvestigatorModel")
            [void]$sb.AppendLine("debug-session-manager.model=$v2InvestigatorModel")
            [void]$sb.AppendLine("user-profiler.model=$v2InvestigatorModel")
        }
        if ($v2InvestigatorEffort) {
            [void]$sb.AppendLine("debugger=$v2InvestigatorEffort")
            [void]$sb.AppendLine("debug-session-manager=$v2InvestigatorEffort")
            [void]$sb.AppendLine("user-profiler=$v2InvestigatorEffort")
        }
    }
    if ($perAgentEffortLines.Count -gt 0) {
        [void]$sb.AppendLine(''); [void]$sb.AppendLine('# Per-agent effort overrides')
        foreach ($l in $perAgentEffortLines) { [void]$sb.AppendLine($l) }
    }
    if ($perAgentModelLines.Count -gt 0) {
        [void]$sb.AppendLine(''); [void]$sb.AppendLine('# Per-agent model overrides')
        foreach ($l in $perAgentModelLines) { [void]$sb.AppendLine($l) }
    }
    [System.IO.File]::WriteAllText($tmpFile, $sb.ToString(), [System.Text.Encoding]::UTF8)
    if ($v2LastPreset -eq 'auto-mode-safe' -or $v2PermMode -eq 'auto') {
        $automodeFile = Join-Path $AihausRoot '.automode'
        [System.IO.File]::WriteAllText($automodeFile, "enabled=true`nlast_enabled_at=$migrationTs`n", [System.Text.Encoding]::UTF8)
    }
    Move-Item -Path $tmpFile -Destination $V3File -Force
    Move-Item -Path $V2File  -Destination "$V2File.v2.bak" -Force
    Write-Host "  migrated .aihaus\.calibration -> .aihaus\.effort (schema v2 -> v3)"
    if ($plannerLossy) {
        Write-Host "" -ForegroundColor Yellow
        Write-Host "  !!  cohort.planner.* applied to :planner-binding ONLY (FR-M05). :planner stays at v3 default." -ForegroundColor Yellow
        Write-Host "  !!  Run: /aih-effort --cohort :planner --effort <X> to also calibrate :planner." -ForegroundColor Yellow
        Write-Host "" -ForegroundColor Yellow
    }
    if ($adversarialLossy) {
        Write-Host "" -ForegroundColor Yellow
        Write-Host "  !!  cohort.adversarial.* applied to :adversarial-scout ONLY (FR-M05). :adversarial-review stays at v3 default." -ForegroundColor Yellow
        Write-Host "  !!  Run: /aih-effort --cohort :adversarial-review --effort <X> to mirror." -ForegroundColor Yellow
        Write-Host "" -ForegroundColor Yellow
    }
    if ($investigatorLossy) {
        Write-Host "" -ForegroundColor Yellow
        Write-Host "  !!  cohort.investigator.* preserved as per-agent overrides for debugger, debug-session-manager, user-profiler (FR-M06)." -ForegroundColor Yellow
        Write-Host "" -ForegroundColor Yellow
    }
    if ($v2LastPreset -eq 'auto-mode-safe' -or $v2PermMode -eq 'auto') {
        Write-Host "" -ForegroundColor Yellow
        Write-Host "  !!  v2 sidecar had last_preset=auto-mode-safe." -ForegroundColor Yellow
        Write-Host "  !!    State migrated to .aihaus\.automode (enabled=true)." -ForegroundColor Yellow
        Write-Host "  !!    Side effects (defaultMode=auto, worktree frontmatter, SAFE_PATTERNS) are NOT replayed." -ForegroundColor Yellow
        Write-Host "  !!    Permission auto-mode removed in v0.18.0/M014. Use bash .aihaus/auto.sh for DSP launch." -ForegroundColor Yellow
        Write-Host "" -ForegroundColor Yellow
    }
    if ($presetDriftNote) {
        Write-Host "" -ForegroundColor Yellow
        Write-Host "  !!  Preset renamed: $presetDriftNote" -ForegroundColor Yellow
        Write-Host "  !!  Run: /aih-effort --preset $v3LastPreset to apply v3 defaults." -ForegroundColor Yellow
        Write-Host "" -ForegroundColor Yellow
    }
}

function Restore-EffortV3-Update {
    param([string]$AihausRoot, [string]$StateFile)
    $cohortsMd = Join-Path $AihausRoot 'skills\aih-effort\annexes\cohorts.md'
    $agentsDir = Join-Path $AihausRoot 'agents'
    $restored = 0; $skipped = 0
    $sidecarLines = Get-Content -LiteralPath $StateFile
    $cohortMembers = @{
        'planner-binding' = [System.Collections.Generic.List[string]]::new()
        'planner'         = [System.Collections.Generic.List[string]]::new()
        'doer'            = [System.Collections.Generic.List[string]]::new()
        'verifier'        = [System.Collections.Generic.List[string]]::new()
        'adversarial-scout'  = [System.Collections.Generic.List[string]]::new()
        'adversarial-review' = [System.Collections.Generic.List[string]]::new()
    }
    if (Test-Path $cohortsMd) {
        foreach ($cline in (Get-Content -LiteralPath $cohortsMd)) {
            if ($cline -match '^\|\s*\d+\s*\|\s*(?<agent>[a-z][a-z0-9-]+)\s*\|\s*(?<cohort>:[a-z][a-z0-9-]+)') {
                $cname = $Matches.cohort.TrimStart(':')
                if ($cohortMembers.ContainsKey($cname)) { $cohortMembers[$cname].Add($Matches.agent) }
            }
        }
    } else {
        Write-Host "  warn: cohorts.md missing at $cohortsMd -- skipping cohort-level restore; per-agent overrides still applied"
    }
    foreach ($line in $sidecarLines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^\s*#') { continue }
        if ($line -notmatch '=') { continue }
        $parts = $line -split '=', 2
        $key = ($parts[0] -replace "`r", '').Trim(); $value = ($parts[1] -replace "`r", '').Trim()
        if ($key -notmatch '^cohort\.(planner-binding|planner|doer|verifier|adversarial-scout|adversarial-review)\.(model|effort)$') { continue }
        if ([string]::IsNullOrWhiteSpace($value) -or $value -eq 'custom') { continue }
        $cohortName = ($key -split '\.', 3)[1]; $field = ($key -split '\.', 3)[2]
        if (Test-PresetImmune $cohortName) { continue }
        foreach ($member in $cohortMembers[$cohortName]) {
            $af = Join-Path $agentsDir "$member.md"
            if (Test-Path $af) {
                $c = Get-Content -LiteralPath $af
                $nc = if ($field -eq 'model') { $c -replace '^model: .*', "model: $value" } else { $c -replace '^effort: .*', "effort: $value" }
                Set-Content -LiteralPath $af -Value $nc -Encoding UTF8 -NoNewline; $restored++
            } else { $skipped++; Write-Host "  warn: .effort cohort '$cohortName' missing agent '$member' -- skipped" }
        }
    }
    foreach ($line in $sidecarLines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^\s*#') { continue }
        if ($line -notmatch '=') { continue }
        $parts = $line -split '=', 2
        $key = ($parts[0] -replace "`r", '').Trim(); $value = ($parts[1] -replace "`r", '').Trim()
        if ($key -eq 'schema' -or $key -eq 'last_preset' -or $key -eq 'last_commit') { continue }
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        if ($key -match '^cohort\.') {
            if ($key -notmatch '^cohort\.(planner-binding|planner|doer|verifier|adversarial-scout|adversarial-review)\.(model|effort)$') {
                $bad = ($key -replace '^cohort\.', '') -replace '\..*$', ''
                Write-Host "  warn: .effort unknown cohort '$bad' -- skipped"; $skipped++
            }
            continue
        }
        if ($key -match '\.model$') { $agent = $key -replace '\.model$', ''; $field = 'model' }
        else { $agent = $key; $field = 'effort' }
        $af = Join-Path $agentsDir "$agent.md"
        if (Test-Path $af) {
            $c = Get-Content -LiteralPath $af
            $nc = if ($field -eq 'model') { $c -replace '^model: .*', "model: $value" } else { $c -replace '^effort: .*', "effort: $value" }
            Set-Content -LiteralPath $af -Value $nc -Encoding UTF8 -NoNewline; $restored++
        } else { $skipped++; Write-Host "  warn: .effort missing agent '$agent' -- skipped" }
    }
    if ($skipped -gt 0) { Write-Host ("  restored {0} effort entry(ies) from .aihaus\.effort ({1} skipped)" -f $restored, $skipped) }
    else { Write-Host ("  restored {0} effort entry(ies) from .aihaus\.effort" -f $restored) }
}

function Restore-Effort-Update {
    param([string]$AihausRoot)
    $v2File = Join-Path $AihausRoot '.calibration'; $v3File = Join-Path $AihausRoot '.effort'
    $stateFile = $null; $detectedSchema = ''
    if (Test-Path $v3File) {
        $stateFile = $v3File
        $sl = Select-String -Path $v3File -Pattern '^schema=' | Select-Object -First 1
        if ($sl) { $detectedSchema = (($sl.Line -split '=', 2)[1] -replace "`r", '').Trim() }
    } elseif (Test-Path $v2File) {
        $stateFile = $v2File
        $sl = Select-String -Path $v2File -Pattern '^schema=' | Select-Object -First 1
        if ($sl) { $detectedSchema = (($sl.Line -split '=', 2)[1] -replace "`r", '').Trim() }
    } else { return }
    if ([string]::IsNullOrEmpty($detectedSchema)) {
        Write-Host "  !!  Sidecar has no schema= line. Delete it and re-run: /aih-effort --preset balanced" -ForegroundColor Yellow; return
    }
    if ($detectedSchema -eq '3') { Restore-EffortV3-Update -AihausRoot $AihausRoot -StateFile $v3File }
    elseif ($detectedSchema -eq '2') {
        Invoke-MigrateV2ToV3 -AihausRoot $AihausRoot -V2File $v2File -V3File $v3File
        if (Test-Path $v3File) { Restore-EffortV3-Update -AihausRoot $AihausRoot -StateFile $v3File }
    } else {
        Write-Host "  !!  Unknown sidecar schema='$detectedSchema' -- skipping. Delete and re-run: /aih-effort --preset balanced" -ForegroundColor Yellow
    }
}

Restore-Effort-Update  -AihausRoot $Aihaus

# Count what was updated
$countSkills = 0
$countAgents = 0
$countHooks = 0

$skillsDir = Join-Path $Aihaus 'skills'
if (Test-Path $skillsDir) {
    $countSkills = @(Get-ChildItem -Path $skillsDir -Recurse -Filter 'SKILL.md' -File).Count
}
$agentsDir = Join-Path $Aihaus 'agents'
if (Test-Path $agentsDir) {
    $countAgents = @(Get-ChildItem -Path $agentsDir -Filter '*.md' -File).Count
}
$hooksDir = Join-Path $Aihaus 'hooks'
if (Test-Path $hooksDir) {
    $countHooks = @(Get-ChildItem -Path $hooksDir -Filter '*.sh' -File).Count
}

# ---- Re-link / re-copy .claude/{skills,agents,hooks} ------------------------

function Link-Or-Copy {
    param([string]$Name)

    $src = Join-Path $script:Aihaus $Name
    $dst = Join-Path $script:Claude $Name

    if (-not (Test-Path $src)) {
        Write-Host "  skip: $src does not exist"
        return
    }

    if (Test-Path $dst) {
        # Check if junction/symlink first
        $item = Get-Item $dst -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            cmd /c "rmdir `"$dst`"" | Out-Null
            if ($LASTEXITCODE -ne 0) { Remove-Item -Force $dst -ErrorAction SilentlyContinue }
        } else {
            Remove-Item -Recurse -Force $dst
        }
    }

    if ($script:Mode -eq 'link') {
        try {
            $out = cmd /c "mklink /J `"$dst`" `"$src`"" 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  link: .claude\$Name -> .aihaus\$Name"
                return
            }
            Write-Host "  warn: junction failed for $Name ($out), falling back to copy"
            $script:Mode = 'copy'
        } catch {
            Write-Host "  warn: junction failed for $Name ($_), falling back to copy"
            $script:Mode = 'copy'
        }
    }
    Copy-Item -Path $src -Destination $dst -Recurse -Force
    Write-Host "  copy: .claude\$Name (managed copy pruned)"
}

New-Item -ItemType Directory -Path $Claude -Force | Out-Null
foreach ($name in @('skills', 'agents', 'hooks')) {
    Link-Or-Copy -Name $name
}

# ---- Deep-merge settings template -------------------------------------------
$SettingsSrc = Join-Path $PkgTemplates 'settings.local.json'
$SettingsOut = Join-Path $Claude 'settings.local.json'

function Normalize-HooksShape {
    param($Settings)
    if (-not ($Settings -is [psobject])) { return $Settings }
    if (-not ($Settings.PSObject.Properties.Name -contains 'hooks')) { return $Settings }
    if (-not ($Settings.hooks -is [psobject])) { return $Settings }

    foreach ($eventProp in @($Settings.hooks.PSObject.Properties)) {
        $eventValue = $eventProp.Value
        if ($eventValue -is [array]) {
            $Settings.hooks.$($eventProp.Name) = @($eventValue)
        } elseif ($eventValue -is [psobject]) {
            $Settings.hooks.$($eventProp.Name) = @($eventValue)
        }
    }
    return $Settings
}

if (-not (Test-Path $SettingsSrc)) {
    Write-Host "  warn: settings template missing at $SettingsSrc, skipping merge"
} elseif (-not (Test-Path $SettingsOut)) {
    Copy-Item $SettingsSrc $SettingsOut
    Write-Host "  settings: copied template"
} else {
    $srcJson = Get-Content $SettingsSrc -Raw | ConvertFrom-Json
    $dstJson = Get-Content $SettingsOut -Raw | ConvertFrom-Json

    function Merge-Object {
        param($Base, $Overlay)
        if ($Overlay -is [psobject] -and $Base -is [psobject]) {
            foreach ($prop in $Overlay.PSObject.Properties) {
                if ($Base.PSObject.Properties.Name -contains $prop.Name) {
                    $Base.$($prop.Name) = Merge-Object $Base.$($prop.Name) $prop.Value
                } else {
                    Add-Member -InputObject $Base -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
                }
            }
            return $Base
        }
        return $Overlay
    }

    $merged = Merge-Object $dstJson $srcJson
    $merged = Normalize-HooksShape $merged
    $merged | ConvertTo-Json -Depth 20 | Set-Content -Path $SettingsOut -Encoding UTF8
    Write-Host "  settings: merged"
}

# ---- Update install mode marker ----------------------------------------------
Set-Content -Path (Join-Path $Aihaus '.install-mode') -Value $Mode -NoNewline

# ---------------------------------------------------------------------------
# V5 (M022/Z9): User-global skill refresh -- FR-23/FR-24/FR-26; ADR-260504-A §6.3
# Refreshes %USERPROFILE%\.claude\skills\aih-* entries that carry the .aihaus-managed marker.
# R4 invariant: never touch entries without the marker.
# R9 copy-mode: if user-global entries are copies (no junction/symlink), re-copy skill dir.
# Orphan removal: remove entries for skills no longer in pkg\.aihaus\skills\ (marker required).
# ---------------------------------------------------------------------------
function Invoke-RefreshUserGlobalSkills {
    $pkgSkillsDir = Join-Path $PkgRoot '.aihaus\skills'
    $userHome = [System.Environment]::GetFolderPath('UserProfile')
    $userGlobalSkills = Join-Path $userHome '.claude\skills'

    # No user-global skills dir at all -- nothing to refresh.
    if (-not (Test-Path $userGlobalSkills)) {
        return
    }

    $refreshedCount = 0
    $skippedCount = 0
    $orphanCount = 0

    # ---- Pass 1: refresh existing user-global entries that carry the marker ----
    $existingEntries = @(Get-ChildItem -Path $userGlobalSkills -Filter 'aih-*' -Force `
                         -ErrorAction SilentlyContinue)
    foreach ($entry in $existingEntries) {
        $skillName = $entry.Name
        $targetDir = $entry.FullName
        $markerFile = Join-Path $targetDir '.aihaus-managed'

        # R4: only touch marker-owned entries.
        if (-not (Test-Path $markerFile)) {
            $skippedCount++
            continue
        }

        $pkgSkillDir = Join-Path $pkgSkillsDir $skillName

        # Orphan removal: skill no longer in package AND carries marker.
        if (-not (Test-Path $pkgSkillDir)) {
            Remove-Item -Recurse -Force $targetDir -ErrorAction SilentlyContinue
            Write-Host "  user-global orphan removed: $skillName"
            $orphanCount++
            continue
        }

        # Detect copy-mode for this entry:
        # copy-mode = real directory (not a reparse point / junction / symlink)
        # OR .aihaus-copy-mode marker at user-global level.
        $copyModeMarker = Join-Path $userHome '.claude\.aihaus-copy-mode'
        $entryIsCopy = $false
        if (Test-Path $copyModeMarker) {
            $entryIsCopy = $true
        } else {
            $entryItem = Get-Item $targetDir -Force -ErrorAction SilentlyContinue
            if ($entryItem -and ($entryItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                $entryIsCopy = $false  # junction or symlink -- link mode
            } else {
                $entryIsCopy = $true   # real directory -- copy mode
            }
        }

        # Remove stale entry before re-creating.
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            cmd /c "rmdir `"$targetDir`"" | Out-Null
        } else {
            Remove-Item -Recurse -Force $targetDir -ErrorAction SilentlyContinue
        }

        if ($entryIsCopy) {
            # R9 copy-mode: re-copy skill dir from package.
            Copy-Item -Path $pkgSkillDir -Destination $targetDir -Recurse -Force
            # Re-drop .aihaus-managed marker.
            Set-Content -LiteralPath (Join-Path $targetDir '.aihaus-managed') `
                -Value "managed_by=aihaus`nsource=$pkgSkillDir" -NoNewline
            Write-Host "  user-global refreshed (copy): $skillName"
        } else {
            # Link mode: re-create junction to latest pkg path.
            $winTarget = $targetDir
            $winSkill  = $pkgSkillDir
            $jOut = cmd /c "mklink /J `"$winTarget`" `"$winSkill`"" 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "  warn: junction refresh failed for $skillName; falling back to copy" -ForegroundColor Yellow
                Copy-Item -Path $pkgSkillDir -Destination $targetDir -Recurse -Force
            }
            # Re-drop .aihaus-managed marker.
            Set-Content -LiteralPath (Join-Path $targetDir '.aihaus-managed') `
                -Value "managed_by=aihaus`nsource=$pkgSkillDir" -NoNewline
            Write-Host "  user-global refreshed (link): $skillName"
        }
        $refreshedCount++
    }

    # ---- Pass 2: install user-global entries for new skills not yet present ----
    if (Test-Path $pkgSkillsDir) {
        $pkgSkills = @(Get-ChildItem -Path $pkgSkillsDir -Filter 'aih-*' -Directory `
                       -ErrorAction SilentlyContinue)
        foreach ($pkgSkill in $pkgSkills) {
            $skillName   = $pkgSkill.Name
            $pkgSkillDir = $pkgSkill.FullName
            $targetDir   = Join-Path $userGlobalSkills $skillName

            # Already handled in Pass 1 (exists) -- skip.
            if ((Test-Path $targetDir) -or (Test-Path $targetDir -PathType Container)) {
                continue
            }

            # Install new skill entry.
            $copyModeMarker = Join-Path $userHome '.claude\.aihaus-copy-mode'
            if (Test-Path $copyModeMarker) {
                Copy-Item -Path $pkgSkillDir -Destination $targetDir -Recurse -Force
            } else {
                $winTarget = $targetDir
                $winSkill  = $pkgSkillDir
                $jOut = cmd /c "mklink /J `"$winTarget`" `"$winSkill`"" 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "  warn: junction for new skill $skillName failed; falling back to copy" -ForegroundColor Yellow
                    Copy-Item -Path $pkgSkillDir -Destination $targetDir -Recurse -Force
                }
            }

            Set-Content -LiteralPath (Join-Path $targetDir '.aihaus-managed') `
                -Value "managed_by=aihaus`nsource=$pkgSkillDir" -NoNewline
            Write-Host "  user-global new: $skillName"
            $refreshedCount++
        }
    }

    Write-Host ("  user-global skills: {0} refreshed, {1} skipped (unmanaged), {2} orphans removed" `
                -f $refreshedCount, $skippedCount, $orphanCount)
}

Invoke-RefreshUserGlobalSkills

# ---- Gitignore backfill (existing-install gate) ------------------------------
# TODO: Document this carve-out prominently in v0.19.2 release notes --
#       update.ps1 scope expanded to write repo-root .gitignore behind explicit
#       user prompt gate. First time update.ps1 writes to repo root.
#
# Design: prompt fires once when the guard block is absent and -NoGitignore
# is not set. Idempotent: guard present -> skip silently. Non-interactive CI:
# pass -NoGitignore to suppress. Per ADR-M016-B R3 mitigation.
function New-AihUtf8NoBomEncoding {
    return New-Object System.Text.UTF8Encoding -ArgumentList $false
}

function Read-AihUtf8Text {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return ''
    }

    return [System.IO.File]::ReadAllText($Path, (New-AihUtf8NoBomEncoding))
}

function Get-AihNewline {
    param([string]$Text)

    if ($Text.Contains("`r`n")) { return "`r`n" }
    if ($Text.Contains("`n")) { return "`n" }
    if ($Text.Contains("`r")) { return "`r" }
    return [Environment]::NewLine
}

function ConvertTo-AihLines {
    param([string]$Text)

    if ($Text.Length -eq 0) {
        return @()
    }

    $normalized = $Text -replace "`r`n", "`n" -replace "`r", "`n"
    if ($normalized.EndsWith("`n")) {
        $normalized = $normalized.Substring(0, $normalized.Length - 1)
    }
    if ($normalized.Length -eq 0) {
        return @()
    }

    return @($normalized -split "`n")
}

function Test-AihTrailingNewline {
    param([string]$Text)

    return ($Text.EndsWith("`n") -or $Text.EndsWith("`r"))
}

function Write-AihUtf8Lines {
    param(
        [string]$Path,
        [string[]]$Lines,
        [string]$Newline,
        [bool]$TrailingNewline
    )

    $text = [string]::Join($Newline, $Lines)
    if ($TrailingNewline -and $text.Length -gt 0) {
        $text += $Newline
    }

    [System.IO.File]::WriteAllText($Path, $text, (New-AihUtf8NoBomEncoding))
}

function Add-AihUtf8Lines {
    param(
        [string]$Path,
        [string[]]$Lines
    )

    $text = Read-AihUtf8Text -Path $Path
    $newline = Get-AihNewline -Text $text
    if ($text.Length -gt 0 -and -not (Test-AihTrailingNewline -Text $text)) {
        $text += $newline
    }

    $append = [string]::Join($newline, $Lines)
    if ($append.Length -gt 0) {
        $text += $append + $newline
    }

    [System.IO.File]::WriteAllText($Path, $text, (New-AihUtf8NoBomEncoding))
}

function Invoke-BackfillGitignore {
    param([string]$TargetDir)

    $gitignore = Join-Path $TargetDir '.gitignore'
    $entries = @(
        '/.aihaus/audit/',
        '/.claude/audit/',
        '*/.aihaus/',
        '*/.claude/',
        '/.aihaus/agents/',
        '/.aihaus/skills/',
        '/.aihaus/hooks/',
        '/.aihaus/templates/',
        '/.aihaus/bin/',
        '/.aihaus/state/',
        '/.aihaus/runtime/',
        '/.aihaus/backups/',
        '/.claude/agents/',
        '/.claude/hooks/',
        '/.claude/skills/',
        '/.claude/worktrees/',
        '/.claude/settings.local.json',
        '/.claude/backups/',
        '/.claude/agent-memory/',
        '/.claude/agent-memory-local/',
        '/.bg-shell/',
        '/.worktrees/',
        '/.gsd/',
        '/.gsd-id',
        '/.hermes/',
        '/.aihaus/.context-budgets',
        '/.aihaus/.effort',
        '/.aihaus/.calibration',
        '/.aihaus/.install-mode',
        '/.aihaus/.install-source',
        '/.aihaus/.install-platform',
        '/.aihaus/.version',
        '/.aihaus/.enforcement',
        '/.aihaus/.automode'
    )

    # Step 1: idempotency -- guard-comment block already present?
    if (Test-Path -LiteralPath $gitignore) {
        $guardHit = Select-String -LiteralPath $gitignore -Pattern '^# AIHAUS:GITIGNORE-START' -Quiet
        if ($guardHit) {
            $rawContent = Read-AihUtf8Text -Path $gitignore
            $content = @(ConvertTo-AihLines -Text $rawContent)
            $missing = @($entries | Where-Object { $content -notcontains $_ })
            if ($missing.Count -eq 0) {
                # Already present -- no prompt, no write.
                return
            }
            $endIndex = [Array]::IndexOf($content, '# AIHAUS:GITIGNORE-END')
            if ($endIndex -lt 0) {
                Add-AihUtf8Lines -Path $gitignore -Lines $missing
            } else {
                $before = if ($endIndex -gt 0) { $content[0..($endIndex - 1)] } else { @() }
                $after = $content[$endIndex..($content.Count - 1)]
                Write-AihUtf8Lines `
                    -Path $gitignore `
                    -Lines @($before + $missing + $after) `
                    -Newline (Get-AihNewline -Text $rawContent) `
                    -TrailingNewline (Test-AihTrailingNewline -Text $rawContent)
            }
            Write-Host "  .gitignore: aihaus block updated"
            return
        }
        # Secondary idempotency: hand-edited variant without the full guard comment?
        $auditHit = Select-String -LiteralPath $gitignore -Pattern '\.aihaus/audit' -Quiet
        if ($auditHit) {
            # Already has the relevant entries -- skip to avoid duplication.
            return
        }
    }

    # Step 2: -NoGitignore flag bypasses prompt entirely
    if ($script:NoGitignore) {
        return
    }

    # Step 3: prompt user (explicit gate -- existing users may have intentional choices)
    Write-Host ""
    $answer = Read-Host -Prompt 'aihaus v0.19.2+ recommends adding .aihaus/audit/ and .claude/audit/ to your .gitignore. Add now? [y/N] (skip with -NoGitignore)'

    # Step 4: on y/Y -> inject guard block (idempotent write)
    if ($answer -eq 'y' -or $answer -eq 'Y') {
        $block = @(
            '',
            '# AIHAUS:GITIGNORE-START -- managed by install.sh / update.sh; do not edit between markers'
        ) + $entries + @('# AIHAUS:GITIGNORE-END')
        try {
            Add-AihUtf8Lines -Path $gitignore -Lines $block
            Write-Host "  .gitignore: aihaus block injected"
        } catch {
            Write-Host "  !! WARNING: could not write .gitignore at $gitignore" -ForegroundColor Yellow
            Write-Host "  !!          Apply manually from pkg\.aihaus\templates\gitignore-fragment" -ForegroundColor Yellow
        }
        return
    }

    # Step 5: on N / empty -> skip silently with one-line note
    Write-Host "  Skipped -- re-run with -NoGitignore to suppress this prompt next time, or rerun update.ps1 and answer y to add later."
}
Invoke-BackfillGitignore -TargetDir $Target

# ---- aih-graph binary refresh ------------------------------------------------
# Ensure repo-local .aihaus\bin\aih-graph.exe exists. Non-fatal.
if (-not $env:AIHAUS_SKIP_GRAPH_BINARY) {
    $graphBin = Join-Path $Aihaus 'bin\aih-graph.exe'
    if (-not (Test-Path $graphBin)) {
        $graphInstallerPs1 = Join-Path $ScriptDir 'install-aih-graph-binary.ps1'
        $graphInstallerSh = Join-Path $ScriptDir 'install-aih-graph-binary.sh'
        $bashCmd = Get-Command bash -ErrorAction SilentlyContinue
        if (Test-Path $graphInstallerPs1) {
            Write-Host ""
            Write-Host "  installing aih-graph memory engine..."
            & powershell -NoProfile -ExecutionPolicy Bypass -File $graphInstallerPs1 -Bin $graphBin *> $null
            if ($LASTEXITCODE -eq 0 -and (Test-Path $graphBin)) {
                Write-Host "  ok: aih-graph at $graphBin"
            } else {
                Write-Host "  warn: aih-graph download failed (memory engine optional; /aih-init retries)" -ForegroundColor Yellow
            }
        } elseif ((Test-Path $graphInstallerSh) -and $bashCmd) {
            Write-Host ""
            Write-Host "  installing aih-graph memory engine..."
            & bash $graphInstallerSh --bin $graphBin *> $null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  ok: aih-graph at $graphBin"
            } else {
                Write-Host "  warn: aih-graph download failed (memory engine optional; /aih-init retries)" -ForegroundColor Yellow
            }
        }
    }
}

# ---- Summary -----------------------------------------------------------------
Write-Host ""
Write-Host "Updated $countSkills skills, $countAgents agents, $countHooks hooks"
Write-Host "aihaus updated ($Mode mode)."
exit 0
