# aihaus update script (Windows PowerShell)
# Re-syncs local .aihaus/ from pkg/ package source.
# Preserves ALL local data: project.md, plans/, milestones/, memory/, etc.
# Flags:
#   -Target <path>   Update in <path> instead of $PWD
#   -Help            Show usage

[CmdletBinding()]
param(
    [string]$Target = (Get-Location).Path,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

function Show-Usage {
    @'
Usage: update.ps1 [-Target <path>]

Re-syncs package-managed files in .aihaus/ from the aihaus package source.
Local data (project.md, plans/, milestones/, memory/, etc.) is preserved.

Options:
  -Target <path>   Target directory (default: current working directory)
  -Help            Show this message
'@ | Write-Host
}

if ($Help) { Show-Usage; exit 0 }

# Resolve package root (the directory containing this script's parent)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$PkgRoot = (Resolve-Path (Join-Path $ScriptDir '..')).Path
$PkgAihaus = Join-Path $PkgRoot '.aihaus'
$PkgTemplates = Join-Path $PkgRoot 'templates'

if (-not (Test-Path $Target)) {
    Write-Error "target directory does not exist: $Target"
    exit 1
}
$Target = (Resolve-Path $Target).Path

$Aihaus = Join-Path $Target '.aihaus'
$Claude = Join-Path $Target '.claude'

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

    # Remove old directory contents and replace with fresh copy from package
    if (Test-Path $dst) {
        Remove-Item -Recurse -Force $dst
    }
    Copy-Item -Path $src -Destination $dst -Recurse -Force
    Write-Host "  refreshed: .aihaus\$Name"
}

foreach ($name in @('skills', 'agents', 'hooks', 'templates')) {
    Update-AihausDir -Name $name
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
    Write-Host "  copy: .claude\$Name"
}

New-Item -ItemType Directory -Path $Claude -Force | Out-Null
foreach ($name in @('skills', 'agents', 'hooks')) {
    Link-Or-Copy -Name $name
}

# ---- Deep-merge settings template -------------------------------------------
$SettingsSrc = Join-Path $PkgTemplates 'settings.local.json'
$SettingsOut = Join-Path $Claude 'settings.local.json'

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
    $merged | ConvertTo-Json -Depth 20 | Set-Content -Path $SettingsOut -Encoding UTF8
    Write-Host "  settings: merged"
}

# ---- Update install mode marker ----------------------------------------------
Set-Content -Path (Join-Path $Aihaus '.install-mode') -Value $Mode -NoNewline

# ---- Summary -----------------------------------------------------------------
Write-Host ""
Write-Host "Updated $countSkills skills, $countAgents agents, $countHooks hooks"
Write-Host "aihaus updated ($Mode mode)."
exit 0
