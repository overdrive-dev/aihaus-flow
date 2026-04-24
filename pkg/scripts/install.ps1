# aihaus install script (Windows PowerShell)
# Copies .aihaus/ into target repo and links .claude/{skills,agents,hooks}.
# Flags:
#   -Target <path>    Install into <path> instead of $PWD
#   -Copy             Copy files instead of creating junctions
#   -Update           Re-sync package dirs only; preserve local data
#   -Help             Show usage

[CmdletBinding()]
param(
    [string]$Target = (Get-Location).Path,
    [switch]$Copy,
    [switch]$Update,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

# Minimum Claude Code version supporting --dangerously-skip-permissions (DSP).
# TODO: Update this floor if the Claude Code changelog confirms a stricter minimum.
# Conservative default: 2.0.0 (DSP flag was present well before this release).
$DspMinVersion = '2.0.0'

function Show-Usage {
    @'
Usage: install.ps1 [-Target <path>] [-Copy] [-Update]

Installs aihaus into a target git repository (Claude Code only).

Options:
  -Target <path>    Target directory (default: current working directory)
  -Copy             Copy files instead of creating junctions
  -Update           Re-sync package dirs only; preserve local data
  -Help             Show this message
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
$Mode = if ($Copy) { 'copy' } else { 'link' }

# ============================================================================
# Test-PresetImmune -- PowerShell equivalent of is_preset_immune() in
# restore-effort.sh (architecture.md section is_preset_immune). Returns $true iff
# cohort is :adversarial-scout or :adversarial-review.
# All preset-write call sites MUST use this helper (R3 / ADR-M012-A).
# Post-S06 grep: rg 'Test-PresetImmune' pkg/scripts/ returns >= 2 matches.
# ============================================================================
function Test-PresetImmune {
    param([string]$Cohort)
    return $Cohort -match '^:?(adversarial-scout|adversarial-review)$'
}

# ============================================================================
# Restore-Effort -- PowerShell mirror of restore_effort() in
# pkg/scripts/lib/restore-effort.sh. Handles v2->v3 migration and v3 restore.
# ADR references: ADR-M012-A, ADR-M009-A.
# ============================================================================
function Restore-Effort {
    param([string]$AihausRoot)

    $v2File    = Join-Path $AihausRoot '.calibration'
    $v3File    = Join-Path $AihausRoot '.effort'
    $agentsDir = Join-Path $AihausRoot 'agents'

    # Determine which sidecar to read.
    $stateFile      = $null
    $detectedSchema = ''
    if (Test-Path $v3File) {
        $stateFile = $v3File
        $sl = Select-String -Path $v3File -Pattern '^schema=' | Select-Object -First 1
        if ($sl) { $detectedSchema = (($sl.Line -split '=', 2)[1] -replace "`r", '').Trim() }
    } elseif (Test-Path $v2File) {
        $stateFile = $v2File
        $sl = Select-String -Path $v2File -Pattern '^schema=' | Select-Object -First 1
        if ($sl) { $detectedSchema = (($sl.Line -split '=', 2)[1] -replace "`r", '').Trim() }
    } else {
        return  # No sidecar -- silent no-op.
    }

    if ([string]::IsNullOrEmpty($detectedSchema)) {
        Write-Host "  !!" -ForegroundColor Yellow
        Write-Host "  !!  Sidecar has no schema= line (pre-v1 file). Cannot auto-migrate." -ForegroundColor Yellow
        Write-Host "  !!  Delete the sidecar and re-run: /aih-effort --preset balanced" -ForegroundColor Yellow
        Write-Host "  !!" -ForegroundColor Yellow
        return
    }

    if ($detectedSchema -eq '3') {
        Restore-EffortV3 -AihausRoot $AihausRoot -StateFile $v3File
    } elseif ($detectedSchema -eq '2') {
        Invoke-MigrateV2ToV3 -AihausRoot $AihausRoot -V2File $v2File -V3File $v3File
        if (Test-Path $v3File) {
            Restore-EffortV3 -AihausRoot $AihausRoot -StateFile $v3File
        }
    } else {
        Write-Host "  !!" -ForegroundColor Yellow
        Write-Host "  !!  Unknown sidecar schema='$detectedSchema' -- skipping restore." -ForegroundColor Yellow
        Write-Host "  !!  Delete the sidecar and re-run: /aih-effort --preset balanced" -ForegroundColor Yellow
        Write-Host "  !!" -ForegroundColor Yellow
    }
}

# ============================================================================
# Invoke-MigrateV2ToV3 -- v2 .calibration -> v3 .effort migration.
# Writes .effort, emits 4 lossy-case !! warnings, renames .calibration to
# .calibration.v2.bak. Does NOT replay permission-mode side effects (ADR-M009-A).
# ============================================================================
function Invoke-MigrateV2ToV3 {
    param(
        [string]$AihausRoot,
        [string]$V2File,
        [string]$V3File
    )

    $sidecarLines = Get-Content -LiteralPath $V2File

    # ---- Parse v2 fields ---------------------------------------------------
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
            'schema'                   { }  # Skip.
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
                if ($k -match '^cohort\.') { }  # Unknown v2 cohort -- skip.
                elseif ($k -match '\.model$') { $perAgentModelLines.Add("$k=$v") }
                else { $perAgentEffortLines.Add("$k=$v") }
            }
        }
    }

    # ---- Derive v3 last_preset + drift note --------------------------------
    $v3LastPreset = 'balanced'
    $presetDriftNote = ''
    switch ($v2LastPreset) {
        'balanced'       { $v3LastPreset = 'balanced' }
        'cost-optimized' {
            $v3LastPreset = 'cost'
            $presetDriftNote = "cost-optimized renamed to 'cost'; effort defaults shifted: :planner high->medium; :doer high->medium"
        }
        'quality-first'  {
            $v3LastPreset = 'high'
            $presetDriftNote = "quality-first renamed to 'high'; effort defaults shifted: :planner max->xhigh"
        }
        'auto-mode-safe' { $v3LastPreset = 'balanced' }
        ''               { $v3LastPreset = 'balanced' }
        default {
            $v3LastPreset = 'balanced'
            Write-Host "" -ForegroundColor Yellow
            Write-Host "  !!  v2 sidecar had unknown last_preset='$v2LastPreset' -- reset to balanced." -ForegroundColor Yellow
            Write-Host "  !!" -ForegroundColor Yellow
        }
    }

    $plannerLossy      = ($v2PlannerModel -ne '' -or $v2PlannerEffort -ne '')
    $adversarialLossy  = ($v2AdversarialModel -ne '' -or $v2AdversarialEffort -ne '')
    $investigatorLossy = ($v2InvestigatorModel -ne '' -or $v2InvestigatorEffort -ne '')

    # ---- Write v3 .effort.tmp ----------------------------------------------
    $migrationTs = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    $tmpFile = "$V3File.tmp"
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('# aihaus effort state -- managed by /aih-effort, consumed by /aih-update')
    [void]$sb.AppendLine('# Schema: v3 -- 6 uniform cohorts + per-agent overrides')
    [void]$sb.AppendLine('# This file is USER-OWNED and derived state. Safe to delete. Do not commit.')
    [void]$sb.AppendLine("# Migrated from schema v2 (.calibration) on $migrationTs")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('schema=3')
    [void]$sb.AppendLine("last_preset=$v3LastPreset")
    if ($v2LastCommit) { [void]$sb.AppendLine("last_commit=$v2LastCommit") }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('# Cohort-level rows (migrated from v2)')
    # planner -> planner-binding ONLY (lossy split, FR-M05).
    if ($v2PlannerModel)  { [void]$sb.AppendLine("cohort.planner-binding.model=$v2PlannerModel") }
    if ($v2PlannerEffort) { [void]$sb.AppendLine("cohort.planner-binding.effort=$v2PlannerEffort") }
    # doer -- direct passthrough.
    if ($v2DoerModel)   { [void]$sb.AppendLine("cohort.doer.model=$v2DoerModel") }
    if ($v2DoerEffort)  { [void]$sb.AppendLine("cohort.doer.effort=$v2DoerEffort") }
    # verifier -- direct passthrough.
    if ($v2VerifierModel)  { [void]$sb.AppendLine("cohort.verifier.model=$v2VerifierModel") }
    if ($v2VerifierEffort) { [void]$sb.AppendLine("cohort.verifier.effort=$v2VerifierEffort") }
    # adversarial -> adversarial-scout ONLY (lossy split, FR-M05 shape).
    if ($v2AdversarialModel)  { [void]$sb.AppendLine("cohort.adversarial-scout.model=$v2AdversarialModel") }
    if ($v2AdversarialEffort) { [void]$sb.AppendLine("cohort.adversarial-scout.effort=$v2AdversarialEffort") }
    # investigator -> per-agent overrides (lossy deletion, FR-M06).
    if ($investigatorLossy) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('# investigator cohort deleted in v3 -- re-emitted as per-agent overrides (FR-M06)')
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
    # Per-agent passthrough.
    if ($perAgentEffortLines.Count -gt 0) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('# Per-agent effort overrides')
        foreach ($l in $perAgentEffortLines) { [void]$sb.AppendLine($l) }
    }
    if ($perAgentModelLines.Count -gt 0) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('# Per-agent model overrides')
        foreach ($l in $perAgentModelLines) { [void]$sb.AppendLine($l) }
    }
    [System.IO.File]::WriteAllText($tmpFile, $sb.ToString(), [System.Text.Encoding]::UTF8)

    # ---- Write .automode if auto-mode-safe or permission_mode=auto (FR-M07) --
    if ($v2LastPreset -eq 'auto-mode-safe' -or $v2PermMode -eq 'auto') {
        $automodeFile = Join-Path $AihausRoot '.automode'
        [System.IO.File]::WriteAllText($automodeFile,
            "enabled=true`nlast_enabled_at=$migrationTs`n",
            [System.Text.Encoding]::UTF8)
    }

    # ---- Atomic swap -------------------------------------------------------
    Move-Item -Path $tmpFile -Destination $V3File -Force
    Move-Item -Path $V2File  -Destination "$V2File.v2.bak" -Force
    Write-Host "  migrated .aihaus\.calibration -> .aihaus\.effort (schema v2 -> v3)"

    # ---- Emit lossy-case !! warnings (FR-M05, FR-M06, FR-M07, FR-M10) -----
    if ($plannerLossy) {
        Write-Host "" -ForegroundColor Yellow
        Write-Host "  !!  v2 sidecar had cohort.planner.* settings (planner cohort split -- FR-M05)." -ForegroundColor Yellow
        Write-Host "  !!  Applied to :planner-binding ONLY (architect, planner, product-manager, roadmapper)." -ForegroundColor Yellow
        Write-Host "  !!  :planner (13 agents) remains at v3 balanced default." -ForegroundColor Yellow
        Write-Host "  !!  To also calibrate :planner: /aih-effort --cohort :planner --effort <X>" -ForegroundColor Yellow
        Write-Host "" -ForegroundColor Yellow
    }
    if ($adversarialLossy) {
        Write-Host "" -ForegroundColor Yellow
        Write-Host "  !!  v2 sidecar had cohort.adversarial.* settings (adversarial split -- FR-M05)." -ForegroundColor Yellow
        Write-Host "  !!  Applied to :adversarial-scout ONLY (contrarian, plan-checker)." -ForegroundColor Yellow
        Write-Host "  !!  :adversarial-review (reviewer, code-reviewer) stays at v3 balanced default." -ForegroundColor Yellow
        Write-Host "  !!  To mirror to review tier: /aih-effort --cohort :adversarial-review --effort <X>" -ForegroundColor Yellow
        Write-Host "" -ForegroundColor Yellow
    }
    if ($investigatorLossy) {
        Write-Host "" -ForegroundColor Yellow
        Write-Host "  !!  v2 sidecar had cohort.investigator.* settings (cohort deleted -- FR-M06)." -ForegroundColor Yellow
        Write-Host "  !!  :investigator removed in v3; settings preserved as per-agent overrides for:" -ForegroundColor Yellow
        Write-Host "  !!    debugger, debug-session-manager, user-profiler" -ForegroundColor Yellow
        Write-Host "  !!  Review .aihaus\.effort to confirm these overrides are still intended." -ForegroundColor Yellow
        Write-Host "" -ForegroundColor Yellow
    }
    if ($v2LastPreset -eq 'auto-mode-safe' -or $v2PermMode -eq 'auto') {
        Write-Host "" -ForegroundColor Yellow
        Write-Host "  !!  v2 sidecar had last_preset=auto-mode-safe." -ForegroundColor Yellow
        Write-Host "  !!    State migrated to .aihaus\.automode (enabled=true)." -ForegroundColor Yellow
        Write-Host "  !!    Side effects (defaultMode=auto, worktree frontmatter, SAFE_PATTERNS) are NOT replayed." -ForegroundColor Yellow
        Write-Host "  !!    Permission auto-mode was removed in v0.18.0/M014. Use bash .aihaus/auto.sh for DSP launch." -ForegroundColor Yellow
        Write-Host "" -ForegroundColor Yellow
        $script:AutoModeSafeWarningEmitted = $true
    }
    if ($presetDriftNote) {
        Write-Host "" -ForegroundColor Yellow
        Write-Host "  !!  Preset renamed during migration -- effort distribution may differ:" -ForegroundColor Yellow
        Write-Host "  !!    $presetDriftNote" -ForegroundColor Yellow
        Write-Host "  !!  Absolute per-cohort values from v2 were preserved verbatim (ADR-M009-A)." -ForegroundColor Yellow
        Write-Host "  !!  To apply v3 preset defaults: /aih-effort --preset $v3LastPreset" -ForegroundColor Yellow
        Write-Host "" -ForegroundColor Yellow
    }
}

# ============================================================================
# Restore-EffortV3 -- idempotent v3 restore loop.
# Pass 1: cohort-level apply (skipping preset-immune via Test-PresetImmune).
# Pass 2: per-agent overrides -- always win over cohort-level (apply-order ADR-M012-A).
# 6-cohort regex: planner-binding|planner|doer|verifier|adversarial-scout|adversarial-review
# ============================================================================
function Restore-EffortV3 {
    param(
        [string]$AihausRoot,
        [string]$StateFile
    )

    $cohortsMd = Join-Path $AihausRoot 'skills\aih-effort\annexes\cohorts.md'
    $agentsDir = Join-Path $AihausRoot 'agents'
    $restored = 0
    $skipped  = 0
    $sidecarLines = Get-Content -LiteralPath $StateFile

    # Build cohort membership map from cohorts.md (6 cohorts).
    $cohortMembers = @{
        'planner-binding'    = [System.Collections.Generic.List[string]]::new()
        'planner'            = [System.Collections.Generic.List[string]]::new()
        'doer'               = [System.Collections.Generic.List[string]]::new()
        'verifier'           = [System.Collections.Generic.List[string]]::new()
        'adversarial-scout'  = [System.Collections.Generic.List[string]]::new()
        'adversarial-review' = [System.Collections.Generic.List[string]]::new()
    }

    if (Test-Path $cohortsMd) {
        foreach ($cline in (Get-Content -LiteralPath $cohortsMd)) {
            # 5-col pipe-table: | # | Agent | Cohort | Model | Effort |
            # Match row lines and extract agent (col 2) + cohort (col 3).
            if ($cline -match '^\|\s*\d+\s*\|\s*(?<agent>[a-z][a-z0-9-]+)\s*\|\s*(?<cohort>:[a-z][a-z0-9-]+)') {
                $cname = $Matches.cohort.TrimStart(':')
                if ($cohortMembers.ContainsKey($cname)) {
                    $cohortMembers[$cname].Add($Matches.agent)
                }
            }
        }
    } else {
        Write-Host "  warn: cohorts.md missing at $cohortsMd -- skipping cohort-level restore; per-agent overrides still applied"
    }

    # Pass 1 -- cohort-level apply. 6-cohort regex (F-002 AC).
    foreach ($line in $sidecarLines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^\s*#') { continue }
        if ($line -notmatch '=') { continue }
        $parts = $line -split '=', 2
        $key   = ($parts[0] -replace "`r", '').Trim()
        $value = ($parts[1] -replace "`r", '').Trim()
        # 6-cohort regex: replaces the old 4-cohort pattern (planner|doer|verifier|adversarial).
        if ($key -notmatch '^cohort\.(planner-binding|planner|doer|verifier|adversarial-scout|adversarial-review)\.(model|effort)$') { continue }
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        if ($value -eq 'custom') { continue }

        $cohortName = ($key -split '\.', 3)[1]
        $field      = ($key -split '\.', 3)[2]

        # Skip preset-immune cohorts via Test-PresetImmune (R3 / ADR-M012-A).
        if (Test-PresetImmune $cohortName) { continue }

        $members = $cohortMembers[$cohortName]
        foreach ($member in $members) {
            $agentFile = Join-Path $agentsDir "$member.md"
            if (Test-Path $agentFile) {
                $content = Get-Content -LiteralPath $agentFile
                if ($field -eq 'model') {
                    $newContent = $content -replace '^model: .*', "model: $value"
                } else {
                    $newContent = $content -replace '^effort: .*', "effort: $value"
                }
                Set-Content -LiteralPath $agentFile -Value $newContent -Encoding UTF8 -NoNewline
                $restored++
            } else {
                $skipped++
                Write-Host "  warn: .effort cohort '$cohortName' references missing agent '$member' -- skipped"
            }
        }
    }

    # Pass 2 -- per-agent overrides (win over cohort via apply order).
    foreach ($line in $sidecarLines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^\s*#') { continue }
        if ($line -notmatch '=') { continue }
        $parts = $line -split '=', 2
        $key   = ($parts[0] -replace "`r", '').Trim()
        $value = ($parts[1] -replace "`r", '').Trim()
        if ($key -eq 'schema') { continue }
        if ($key -eq 'last_preset') { continue }
        if ($key -eq 'last_commit') { continue }
        if ([string]::IsNullOrWhiteSpace($value)) { continue }

        # Cohort keys handled in Pass 1; warn on unknown v3 cohort names.
        if ($key -match '^cohort\.') {
            if ($key -notmatch '^cohort\.(planner-binding|planner|doer|verifier|adversarial-scout|adversarial-review)\.(model|effort)$') {
                $bad = ($key -replace '^cohort\.', '') -replace '\..*$', ''
                Write-Host "  warn: .effort references unknown cohort '$bad' -- skipped"
                $skipped++
            }
            continue
        }

        # Dotted per-agent model vs. effort.
        if ($key -match '\.model$') {
            $agent = $key -replace '\.model$', ''
            $field = 'model'
        } else {
            $agent = $key
            $field = 'effort'
        }

        $agentFile = Join-Path $agentsDir "$agent.md"
        if (Test-Path $agentFile) {
            $content = Get-Content -LiteralPath $agentFile
            if ($field -eq 'model') {
                $newContent = $content -replace '^model: .*', "model: $value"
            } else {
                $newContent = $content -replace '^effort: .*', "effort: $value"
            }
            Set-Content -LiteralPath $agentFile -Value $newContent -Encoding UTF8 -NoNewline
            $restored++
        } else {
            $skipped++
            Write-Host "  warn: .effort references missing agent '$agent' -- skipped"
        }
    }

    if ($skipped -gt 0) {
        Write-Host ("  restored {0} effort entry(ies) from .aihaus\.effort ({1} skipped -- missing agents/cohorts)" -f $restored, $skipped)
    } else {
        Write-Host ("  restored {0} effort entry(ies) from .aihaus\.effort" -f $restored)
    }
}

# Dedupe flag for auto-mode-safe warning across both blocks.
$script:AutoModeSafeWarningEmitted = $false

if ($Update) {
    Write-Host "aihaus updater (via -Update)"
} else {
    Write-Host "aihaus installer"
}
Write-Host "  package:  $PkgRoot"
Write-Host "  target:   $Target"
Write-Host "  mode:     $Mode"

# Step 2: require a git repo
$gitDir = Join-Path $Target '.git'
$isGit = Test-Path $gitDir
if (-not $isGit) {
    try {
        Push-Location $Target
        git rev-parse --is-inside-work-tree 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $isGit = $true }
    } catch {}
    finally { Pop-Location }
}
if (-not $isGit) {
    Write-Error "Target must be a git repository. Run git init first."
    exit 1
}

$TargetAihaus = Join-Path $Target '.aihaus'

if ($Update) {
    # Update mode: require existing installation, refresh package dirs only
    if (-not (Test-Path $TargetAihaus)) {
        Write-Error "No .aihaus/ directory found. Run install.ps1 first (without -Update)."
        exit 1
    }
    # Read install mode from marker if not explicitly overridden
    $ModeFile = Join-Path $TargetAihaus '.install-mode'
    if ((Test-Path $ModeFile) -and (-not $Copy)) {
        $SavedMode = (Get-Content $ModeFile -Raw).Trim()
        if ($SavedMode) { $Mode = $SavedMode }
    }
    # Refresh only package-owned directories inside .aihaus/
    foreach ($name in @('skills', 'agents', 'hooks', 'templates')) {
        $src = Join-Path $PkgAihaus $name
        $dst = Join-Path $TargetAihaus $name
        if (-not (Test-Path $src)) {
            Write-Host "  skip: $name not found in package"
            continue
        }
        if (Test-Path $dst) {
            Remove-Item -Recurse -Force $dst
        }
        Copy-Item -Path $src -Destination $dst -Recurse -Force
        Write-Host "  refreshed: .aihaus\$name"
    }

    # Restore per-agent effort from sidecar.
    # Dispatch order (binding per architecture.md):
    #   1. Restore-Effort -- migrates v2 .calibration -> v3 .effort (if needed)
    #                        or idempotent v3 restore. May write .automode.
    # Note: Restore-Automode removed in M014/S03 (DSP pivot; automode skill deleted).
    # Pinned between agents refresh and .claude\ re-link so both layers pick up
    # restored frontmatter.
    # Schema contract: <aihaus_root>\skills\aih-effort\annexes\state-file.md
    # Cohort membership (v3): <aihaus_root>\skills\aih-effort\annexes\cohorts.md
    Restore-Effort -AihausRoot $TargetAihaus
} else {
    # Step 3: existing .aihaus prompt
    if (Test-Path $TargetAihaus) {
        $reply = Read-Host "Existing .aihaus/ found. Overwrite? [y/N]"
        if ($reply -notmatch '^(y|Y|yes|YES)$') {
            Write-Host "Aborted."
            exit 0
        }
        Remove-Item -Recurse -Force $TargetAihaus
    }

    # Step 4: copy package .aihaus into target
    New-Item -ItemType Directory -Path $TargetAihaus -Force | Out-Null
    Copy-Item -Path (Join-Path $PkgAihaus '*') -Destination $TargetAihaus -Recurse -Force
}

# Step 5+6: create .claude/{skills,agents,hooks} as junctions or copies
$TargetClaude = Join-Path $Target '.claude'
New-Item -ItemType Directory -Path $TargetClaude -Force | Out-Null

function Link-Or-Copy {
    param([string]$Name)

    $src = Join-Path $TargetAihaus $Name
    $dst = Join-Path $TargetClaude $Name

    if (-not (Test-Path $src)) {
        Write-Host "  skip: $src does not exist in package"
        return
    }

    if (Test-Path $dst) {
        Remove-Item -Recurse -Force $dst
    }

    if ($script:Mode -eq 'link') {
        try {
            # mklink /J is available via cmd on every modern Windows -- no admin required
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

foreach ($name in @('skills','agents','hooks')) {
    Link-Or-Copy -Name $name
}

# Step 6.5: create auto.ps1 wrapper symlink / junction / copy (M014/S05)
$WrapperSrc = Join-Path $ScriptDir 'launch-aihaus.ps1'
$WrapperLink = Join-Path $TargetAihaus 'auto.ps1'
if (Test-Path $WrapperSrc) {
    if ($script:Mode -eq 'link') {
        try {
            # Try symbolic link first (requires Developer Mode or admin on Windows)
            New-Item -ItemType SymbolicLink -Path $WrapperLink -Target $WrapperSrc -Force | Out-Null
            Write-Host "  link: .aihaus\auto.ps1 -> $WrapperSrc"
        } catch {
            # Fall back to copy
            Copy-Item -Path $WrapperSrc -Destination $WrapperLink -Force
            Write-Host "  copy: .aihaus\auto.ps1"
        }
    } else {
        Copy-Item -Path $WrapperSrc -Destination $WrapperLink -Force
        Write-Host "  copy: .aihaus\auto.ps1"
    }
} else {
    Write-Host "  warn: launch-aihaus.ps1 not found at $WrapperSrc, skipping auto.ps1 creation"
}

# Step 7: merge settings template into .claude/settings.local.json
$SettingsSrc = Join-Path $PkgTemplates 'settings.local.json'
$SettingsOut = Join-Path $TargetClaude 'settings.local.json'

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

    # Post-merge defaultMode preserve -- user intent wins on this single scalar.
    # Mirror of merge-settings.sh post-merge block. Reads .aihaus\.effort (v3)
    # or .aihaus\.calibration (v2 during first migration run) for permission_mode
    # and overwrites .permissions.defaultMode so /aih-effort choices survive
    # install.ps1 -Update. Only touches .permissions.defaultMode; allow/deny/hook
    # paths still follow template-wins. Missing sidecar or empty value = no-op.
    # Schema contract: pkg\.aihaus\skills\aih-effort\annexes\state-file.md.
    $pmV3File = Join-Path $TargetAihaus '.effort'
    $pmV2File = Join-Path $TargetAihaus '.calibration'
    # Prefer v3; fall back to v2 during first-time migration run.
    $pmStateFile = if (Test-Path $pmV3File) { $pmV3File } elseif (Test-Path $pmV2File) { $pmV2File } else { $null }

    if ($pmStateFile) {
        $pmSchema = ''; $pmUserMode = ''; $pmLastPreset = ''
        foreach ($line in (Get-Content -LiteralPath $pmStateFile)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line -match '^\s*#') { continue }
            if ($line -notmatch '=') { continue }
            $pmParts = $line -split '=', 2
            $pmKey = ($pmParts[0] -replace "`r", '').Trim()
            $pmVal = ($pmParts[1] -replace "`r", '').Trim()
            if ($pmKey -eq 'schema' -and -not $pmSchema)          { $pmSchema = $pmVal }
            elseif ($pmKey -eq 'permission_mode' -and -not $pmUserMode) { $pmUserMode = $pmVal }
            elseif ($pmKey -eq 'last_preset' -and -not $pmLastPreset)   { $pmLastPreset = $pmVal }
        }
        # v3 drops permission_mode; only v2 schema=1/2 sidecars carry it.
        if (($pmSchema -eq '1' -or $pmSchema -eq '2') -and -not [string]::IsNullOrWhiteSpace($pmUserMode)) {
            try {
                $pmJson = Get-Content -LiteralPath $SettingsOut -Raw | ConvertFrom-Json
                if (-not ($pmJson.PSObject.Properties.Name -contains 'permissions')) {
                    Add-Member -InputObject $pmJson -NotePropertyName 'permissions' -NotePropertyValue ([pscustomobject]@{}) -Force
                }
                if ($pmJson.permissions.PSObject.Properties.Name -contains 'defaultMode') {
                    $pmJson.permissions.defaultMode = $pmUserMode
                } else {
                    Add-Member -InputObject $pmJson.permissions -NotePropertyName 'defaultMode' -NotePropertyValue $pmUserMode -Force
                }
                $pmJson | ConvertTo-Json -Depth 20 | Set-Content -Path $SettingsOut -Encoding UTF8
                Write-Host "  settings: defaultMode preserved from .aihaus\.calibration ($pmUserMode)"
            } catch {
                Write-Host "  warn: defaultMode preserve step failed; leaving merged template value"
            }
            if ($pmLastPreset -eq 'auto-mode-safe' -and -not $script:AutoModeSafeWarningEmitted) {
                Write-Host "" -ForegroundColor Yellow
                Write-Host "  !!  v2 sidecar had last_preset=auto-mode-safe." -ForegroundColor Yellow
                Write-Host "  !!    State migrated to .aihaus\.automode (enabled=true)." -ForegroundColor Yellow
                Write-Host "  !!    Side effects (defaultMode=auto, worktree frontmatter, SAFE_PATTERNS) are NOT replayed." -ForegroundColor Yellow
                Write-Host "  !!    Permission auto-mode was removed in v0.18.0/M014. Use bash .aihaus/auto.sh for DSP launch." -ForegroundColor Yellow
                Write-Host "" -ForegroundColor Yellow
                $script:AutoModeSafeWarningEmitted = $true
            }
        }
    }
}

# Step 8: write install mode marker
Set-Content -Path (Join-Path $TargetAihaus '.install-mode') -Value $Mode -NoNewline

# Step 9: DSP version-gate soft warning (LD-3: soft only, never exit non-zero)
$claudeCmd = Get-Command 'claude' -ErrorAction SilentlyContinue
if ($claudeCmd) {
    try {
        $claudeVerRaw = & claude --version 2>$null
        # Extract version number (e.g. "2.1.117 (Claude Code)" -> "2.1.117")
        if ($claudeVerRaw -match '(\d+\.\d+(?:\.\d+)?)') {
            $claudeVer = $Matches[1]
            # Compare using System.Version for reliable semver comparison
            $currentVer = [System.Version]$claudeVer
            $minVer = [System.Version]$DspMinVersion
            if ($currentVer -lt $minVer) {
                Write-Host ""
                Write-Host "  !! WARNING: claude --version reports $claudeVer." -ForegroundColor Yellow
                Write-Host "  !! aihaus requires Claude Code >= $DspMinVersion for --dangerously-skip-permissions." -ForegroundColor Yellow
                Write-Host "  !! Update Claude Code if you encounter permission errors when launching via auto.ps1." -ForegroundColor Yellow
                Write-Host "  !! (This is a soft warning -- install continues regardless.)" -ForegroundColor Yellow
            }
        }
    } catch {
        # Version check failed -- silent no-op per LD-3.
    }
}

# Step 11: idempotent .gitignore injection (soft-fail per LD-3)
# Manual fallback: pkg\.aihaus\templates\gitignore-fragment
function Invoke-InjectGitignore {
    param([string]$TargetDir)

    $gitignore = Join-Path $TargetDir '.gitignore'

    # Primary idempotency check -- guard-comment anchor already present?
    if (Test-Path $gitignore) {
        $guardHit = Select-String -LiteralPath $gitignore -Pattern '^# AIHAUS:GITIGNORE-START' -Quiet
        if ($guardHit) {
            Write-Host "  .gitignore: aihaus block already present (no-op)"
            return
        }
        # Secondary idempotency check -- hand-edited variant without full guard comment?
        $auditHit = Select-String -LiteralPath $gitignore -Pattern '\.aihaus/audit' -Quiet
        if ($auditHit) {
            Write-Host "  .gitignore: .aihaus/audit entry detected (skipping injection to avoid duplication)"
            return
        }
    }

    # Build the guard block (LF line endings -- universal .gitignore convention)
    $block = @(
        '',
        '# AIHAUS:GITIGNORE-START -- managed by install.sh / update.sh; do not edit between markers',
        '/.aihaus/audit/',
        '/.claude/audit/',
        '/.aihaus/.context-budgets',
        '/.aihaus/.effort',
        '/.aihaus/.calibration',
        '/.aihaus/.install-mode',
        '/.aihaus/.install-source',
        '/.aihaus/.install-platform',
        '/.aihaus/.version',
        '/.aihaus/.enforcement',
        '/.aihaus/.automode',
        '# AIHAUS:GITIGNORE-END'
    )

    try {
        # Add-Content appends; creates file if absent. -Encoding UTF8 = UTF-8 with BOM (K-004).
        Add-Content -LiteralPath $gitignore -Value $block -Encoding UTF8
        Write-Host "  .gitignore: aihaus block injected"
    } catch {
        Write-Host "  !! WARNING: could not write .gitignore at $gitignore" -ForegroundColor Yellow
        Write-Host "  !!          Apply manually from pkg\.aihaus\templates\gitignore-fragment" -ForegroundColor Yellow
    }
}
Invoke-InjectGitignore -TargetDir $Target

# Step 10: success message
Write-Host ""
if ($Update) {
    Write-Host "aihaus updated ($Mode mode)."
    Write-Host "Launch with: .\aihaus\auto.ps1"
} else {
    Write-Host "aihaus installed ($Mode mode)."
    Write-Host "Launch with: .\aihaus\auto.ps1"
    Write-Host "Run /aih-init inside the launched session to bootstrap project.md"
}
