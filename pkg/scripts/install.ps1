# aihaus install script (Windows PowerShell)
# Installs package-owned aihaus surfaces and seeds neutral repo-local context.
# V5 (M022/Z4): user-global skill bootstrap + 8-tier discovery priority chain
#               + dogfood-mode branch + zero-prompt happy path.
# Flags:
#   -Target <path>    Install into <path> instead of $PWD
#   -Package <path>   Override package source location (tier 1 of discovery chain)
#   -Copy             Copy files instead of creating junctions
#   -Update           Re-sync package dirs only; preserve local data
#   -Force            Overwrite existing .aihaus/ without prompting
#   -Help             Show usage

[CmdletBinding()]
param(
    [string]$Target = (Get-Location).Path,
    [string]$Package = "",
    [switch]$Copy,
    [switch]$Update,
    [switch]$Force,
    [switch]$ForceProjectSkills,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

# Minimum Claude Code version supporting --dangerously-skip-permissions (DSP).
# TODO: Update this floor if the Claude Code changelog confirms a stricter minimum.
# 2.1.126: fixed idle-timeout edge cases (CLI-005 defense-in-depth; M019/S02).
$DspMinVersion = '2.1.126'

function Show-Usage {
    @'
Usage: install.ps1 [-Target <path>] [-Package <path>] [-Copy] [-Update] [-Force] [-ForceProjectSkills]

Installs aihaus into a target git repository (Claude Code only).

Options:
  -Target <path>        Target directory (default: current working directory)
  -Package <path>       Override AIHAUS_HOME discovery; use this path as package root
  -Copy                 Copy files instead of creating junctions
  -Update               Re-sync package dirs only; preserve local data
  -Force                Overwrite existing .aihaus/ without prompting
  -ForceProjectSkills   Always create .claude\skills junction even when
                        user-global skills (~/.claude/skills/aih-init) exist
  -Help                 Show this message
'@ | Write-Host
}

if ($Help) { Show-Usage; exit 0 }

# Resolve package root (the directory containing this script's parent)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$PkgRoot = (Resolve-Path (Join-Path $ScriptDir '..')).Path
$PkgAihaus = Join-Path $PkgRoot '.aihaus'
$PkgTemplates = Join-Path $PkgAihaus 'templates'

# Resolve -Package flag immediately (tier 1 of discovery chain)
$PackageFlag = ""
if (-not [string]::IsNullOrWhiteSpace($Package)) {
    if (Test-Path $Package) {
        $PackageFlag = (Resolve-Path $Package).Path
    } else {
        Write-Error "-Package path does not exist: $Package"
        exit 2
    }
}

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

# ============================================================================
# Resolve-AihausHome -- V5 (M022/Z4): 8-tier discovery priority chain
# ADR-260504-A §6.1 (Windows PowerShell mirror of resolve_aihaus_home() in Z3).
# Returns resolved AIHAUS_HOME path string, or $null if not found.
#
# Tier 1: -Package <path> CLI flag (already resolved into $PackageFlag)
# Tier 2: $env:AIHAUS_HOME env var
# Tier 3: $env:USERPROFILE\.aihaus\.install-source registry
# Tier 4: $env:LOCALAPPDATA\aihaus (Windows XDG-equivalent default)
# Tier 5: $env:USERPROFILE\tools\aihaus (legacy README path)
# Tier 6: $env:USERPROFILE\Documents\GitHub\aihaus-flow (legacy auto-clone path)
# Tier 7: $env:USERPROFILE\Documents\GitHub\aihaus (legacy variant)
# Tier 8: $env:USERPROFILE\code\aihaus (legacy variant)
# Multiple tiers populated -> pick newest by git log -1 --format=%ct HEAD.
# Winning path written to $env:USERPROFILE\.aihaus\.install-source for subsequent runs.
# ============================================================================
function Resolve-AihausHome {
    # Tier 1: explicit -Package flag wins immediately
    if (-not [string]::IsNullOrWhiteSpace($script:PackageFlag)) {
        $pkgSkills = Join-Path $script:PackageFlag "pkg\.aihaus\skills"
        if (Test-Path $pkgSkills) {
            return $script:PackageFlag
        } else {
            Write-Error "-Package path does not contain pkg\.aihaus\skills: $($script:PackageFlag)"
            exit 2
        }
    }

    # Tier 2: env override
    if (-not [string]::IsNullOrWhiteSpace($env:AIHAUS_HOME)) {
        $envSkills = Join-Path $env:AIHAUS_HOME "pkg\.aihaus\skills"
        if (Test-Path $envSkills) {
            return $env:AIHAUS_HOME
        }
    }

    # Tier 3: registry written on first install
    $registry = Join-Path $env:USERPROFILE ".aihaus\.install-source"
    if (Test-Path $registry) {
        $recorded = (Get-Content -LiteralPath $registry -Raw).Trim()
        if (-not [string]::IsNullOrWhiteSpace($recorded)) {
            $recordedSkills = Join-Path $recorded "pkg\.aihaus\skills"
            if (Test-Path $recordedSkills) {
                return $recorded
            }
        }
    }

    # Tiers 4-8: scan candidates, arbitrate by newest HEAD commit timestamp
    $localAppData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $env:USERPROFILE "AppData\Local" }
    $candidates = @(
        (Join-Path $localAppData "aihaus"),
        (Join-Path $env:USERPROFILE "tools\aihaus"),
        (Join-Path $env:USERPROFILE "Documents\GitHub\aihaus-flow"),
        (Join-Path $env:USERPROFILE "Documents\GitHub\aihaus"),
        (Join-Path $env:USERPROFILE "code\aihaus")
    )

    $best = $null
    $bestTs = 0
    foreach ($c in $candidates) {
        $skillsPath = Join-Path $c "pkg\.aihaus\skills"
        $gitPath    = Join-Path $c ".git"
        if ((Test-Path $skillsPath) -and (Test-Path $gitPath)) {
            try {
                $tsRaw = & git -C $c log -1 --format=%ct 2>$null
                $ts = if ($tsRaw -match '^\d+$') { [long]$tsRaw } else { 0 }
                if ($ts -gt $bestTs) {
                    $best   = $c
                    $bestTs = $ts
                }
            } catch {
                # git unavailable or not a real repo -- skip
            }
        }
    }

    if ($null -ne $best) {
        # Record pick to registry for next time (tier 3 on subsequent runs)
        $registryDir = Join-Path $env:USERPROFILE ".aihaus"
        if (-not (Test-Path $registryDir)) {
            New-Item -ItemType Directory -Path $registryDir -Force | Out-Null
        }
        Set-Content -LiteralPath $registry -Value $best -Encoding UTF8 -NoNewline
        return $best
    }

    # Nothing found
    return $null
}

# ============================================================================
# Test-DogfoodCwd -- V5 (M022/Z4): Dogfood detection — I-04
# Returns $true when cwd IS the central aihaus clone.
# Predicate: pkg\scripts\install.sh + pkg\.aihaus\skills\ both exist under cwd.
# ============================================================================
function Test-DogfoodCwd {
    $installSh   = Join-Path $PWD "pkg\scripts\install.sh"
    $skillsDir   = Join-Path $PWD "pkg\.aihaus\skills"
    return ((Test-Path $installSh) -and (Test-Path $skillsDir))
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

# ============================================================================
# Install-UserGlobalSkills -- V5 (M022/Z4): User-global skill install loop
# ADR-260504-A FR-01/FR-06 (Windows mirror of install_user_global_skills() in Z3).
#
# Installs junctions for every pkg\.aihaus\skills\aih-* directory into
# $env:USERPROFILE\.claude\skills\aih-* (user-global Claude Code skill layer).
# Each created dir carries a .aihaus-managed marker (R1 collision defense).
#
# Junction strategy (R7 cross-volume fallback):
#   1. New-Item -ItemType Junction (requires same volume; no elevation needed)
#   2. cmd /c mklink /J (same semantics; fallback if New-Item fails)
#   3. cmd /c mklink /D (directory symlink; requires Developer Mode or admin)
#   4. Copy-Item -Recurse (final fallback; no link; works everywhere)
# Each fallback emits a stderr-level warning line naming the chosen strategy.
# ============================================================================
function Install-UserGlobalSkills {
    param([string]$AihausHome)

    $userGlobalSkills = Join-Path $env:USERPROFILE ".claude\skills"
    if (-not (Test-Path $userGlobalSkills)) {
        New-Item -ItemType Directory -Path $userGlobalSkills -Force | Out-Null
    }

    $skillsSource = Join-Path $AihausHome "pkg\.aihaus\skills"
    $skillDirs    = Get-ChildItem -Path $skillsSource -Directory |
                    Where-Object { $_.Name -like 'aih-*' }

    $installedCount = 0
    $skippedCount   = 0

    foreach ($skillDir in $skillDirs) {
        $skillName = $skillDir.Name
        $src       = $skillDir.FullName
        $dst       = Join-Path $userGlobalSkills $skillName

        # R1 collision defense: refuse to overwrite a dir not managed by aihaus.
        if ((Test-Path $dst) -and (-not (Test-Path (Join-Path $dst ".aihaus-managed")))) {
            Write-Warning "  warn: $dst exists but is not aihaus-managed; skipping (manual cleanup required)"
            $skippedCount++
            continue
        }

        # Remove stale or prior-version junction/copy.
        if (Test-Path $dst) {
            Remove-Item -Recurse -Force -LiteralPath $dst
        }

        # Attempt junction strategies in priority order.
        $linkCreated  = $false
        $linkStrategy = ""

        if (-not $linkCreated) {
            try {
                # Strategy 1: New-Item -ItemType Junction (same-volume; no elevation)
                New-Item -ItemType Junction -Path $dst -Target $src -Force -ErrorAction Stop | Out-Null
                $linkCreated  = $true
                $linkStrategy = "junction (New-Item)"
            } catch {
                # Volume check for R7: if cross-volume, go to mklink /D next
                $srcDrive = (Split-Path $src -Qualifier).TrimEnd(':')
                $dstDrive = (Split-Path $dst -Qualifier).TrimEnd(':')
                $crossVol = ($srcDrive -ne $dstDrive)

                if (-not $linkCreated) {
                    try {
                        # Strategy 2: cmd /c mklink /J (same-volume junction via cmd.exe)
                        $result = cmd /c "mklink /J `"$dst`" `"$src`"" 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            $linkCreated  = $true
                            $linkStrategy = "junction (mklink /J)"
                        }
                    } catch { }
                }

                if (-not $linkCreated -and $crossVol) {
                    try {
                        # Strategy 3: mklink /D (directory symlink; requires Developer Mode or admin)
                        Write-Host "  warn: cross-volume detected (${srcDrive}: -> ${dstDrive}:); falling back to mklink /D for $skillName" -ForegroundColor Yellow
                        $result = cmd /c "mklink /D `"$dst`" `"$src`"" 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            $linkCreated  = $true
                            $linkStrategy = "symlink (mklink /D cross-volume fallback)"
                        } else {
                            Write-Host "  warn: mklink /D failed for $skillName ($result); falling back to copy" -ForegroundColor Yellow
                        }
                    } catch {
                        Write-Host "  warn: mklink /D threw for $skillName; falling back to copy" -ForegroundColor Yellow
                    }
                } elseif (-not $linkCreated) {
                    Write-Host "  warn: junction failed for $skillName; falling back to copy" -ForegroundColor Yellow
                }
            }
        }

        if (-not $linkCreated) {
            # Strategy 4: copy (final fallback -- works everywhere, no link)
            Copy-Item -Recurse -Force -Path $src -Destination $dst
            $linkStrategy = "copy (fallback -- no junction)"
            Write-Host "  warn: using copy strategy for $skillName ($linkStrategy)" -ForegroundColor Yellow
        }

        # Drop .aihaus-managed marker inside the skill dir (R1 defense, I-02).
        # Content: two lines — managed_by + source path (ADR-260504-A §6.3).
        $markerPath = Join-Path $dst ".aihaus-managed"
        $markerContent = "managed_by=aihaus`nsource=$src`n"
        [System.IO.File]::WriteAllText($markerPath, $markerContent, [System.Text.Encoding]::UTF8)

        Write-Host "  user-global: $dst [$linkStrategy]"
        $installedCount++
    }

    Write-Host "  user-global skills: $installedCount installed, $skippedCount skipped (collision)"
}

# ============================================================================
# V5 (M022/Z4): Dogfood mode check -- I-04, L9
# Must run BEFORE per-repo install logic. If we are inside the aihaus package
# directory, emit a one-liner and return. Never git-pull. Never self-junction.
# Per-repo overlay skipped in dogfood mode; user-global skills still installed.
# ============================================================================
if (Test-DogfoodCwd) {
    Write-Host "info: you are inside the aihaus package; run 'aihaus self-update' to refresh from origin"
    # Still install user-global skills (cwd IS the pkg clone).
    $resolvedHome = $PkgRoot
    Write-Host ""
    Write-Host "  installing user-global skills..."
    Install-UserGlobalSkills -AihausHome $resolvedHome
    # Write registry so future invocations use this clone directly (tier 3).
    $registryDir = Join-Path $env:USERPROFILE ".aihaus"
    if (-not (Test-Path $registryDir)) {
        New-Item -ItemType Directory -Path $registryDir -Force | Out-Null
    }
    $registryFile = Join-Path $registryDir ".install-source"
    Set-Content -LiteralPath $registryFile -Value $resolvedHome -Encoding UTF8 -NoNewline
    Write-Host "  registry: $env:USERPROFILE\.aihaus\.install-source -> $resolvedHome"
    Write-Host ""
    Write-Host "aihaus user-global skills installed (dogfood mode; per-repo overlay skipped)."
    exit 0
}

# ============================================================================
# Resolve AIHAUS_HOME for non-dogfood installs.
# If running from within a clone of the aihaus repo targeting another directory,
# use the resolved PkgRoot as the canonical AIHAUS_HOME.
# ============================================================================
$AihausResolved = $null
$pkgSkillsCheck = Join-Path $PkgRoot "pkg\.aihaus\skills"
if (Test-Path $pkgSkillsCheck) {
    # Running from within a clone of the aihaus repo targeting another directory.
    $AihausResolved = $PkgRoot
} else {
    $AihausResolved = Resolve-AihausHome
    if ($null -eq $AihausResolved) {
        Write-Error "error: could not locate aihaus package. Set AIHAUS_HOME or pass -Package <path>."
        exit 1
    }
}

if (-not (Test-Path $Target)) {
    Write-Error "target directory does not exist: $Target"
    exit 1
}
$Target = (Resolve-Path $Target).Path
$Mode = if ($Copy) { 'copy' } else { 'link' }

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
Write-SyncedTargetWarning -TargetPath $Target
Write-CopyModeWarning

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
        # Remove old managed contents before copying. This is copy-mode orphan
        # pruning: the shipped package tree is the manifest for managed files.
        if (Test-Path $dst) {
            Remove-Item -Recurse -Force $dst
        }
        Copy-Item -Path $src -Destination $dst -Recurse -Force
        Write-Host "  refreshed: .aihaus\$name (managed copy pruned)"
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
    # Step 3: existing .aihaus/ handling (V5: zero-prompt happy path -- I-13, L8)
    # Dead junction/dir with no content -> silent remove and continue.
    # Live .aihaus/ -> require -Force opt-in; default -> abort with stderr error.
    if (Test-Path $TargetAihaus) {
        # Check if it's a dead junction (junction target doesn't exist)
        $item = Get-Item -LiteralPath $TargetAihaus -Force -ErrorAction SilentlyContinue
        $isDeadJunction = $false
        if ($null -ne $item -and $item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            # It's a junction/symlink -- check if target resolves
            try {
                $resolved = (Resolve-Path -LiteralPath $TargetAihaus -ErrorAction Stop).Path
                $isDeadJunction = $false
            } catch {
                $isDeadJunction = $true
            }
        }

        if ($isDeadJunction) {
            # Dead junction -- silently remove and continue.
            Remove-Item -Force -LiteralPath $TargetAihaus
        } elseif ($Force) {
            # -Force opt-in: destructive overwrite.
            Remove-Item -Recurse -Force -LiteralPath $TargetAihaus
        } else {
            Write-Host "error: .aihaus\ already exists; pass -Force to overwrite" -ForegroundColor Red
            exit 1
        }
    }

    # Step 4: install only package-owned base surfaces. Project knowledge,
    # decisions, and memory are seeded below from neutral templates so fresh
    # repos do not inherit aihaus-flow's own dogfood history.
    New-Item -ItemType Directory -Path $TargetAihaus -Force | Out-Null
    foreach ($rel in @('skills', 'agents', 'hooks', 'templates')) {
        $src = Join-Path $PkgAihaus $rel
        $dst = Join-Path $TargetAihaus $rel
        if (Test-Path -LiteralPath $src) {
            if (Test-Path -LiteralPath $dst) {
                Remove-Item -LiteralPath $dst -Recurse -Force
            }
            Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
        }
    }
}

# Repo-local runtime layout. Package-owned source stays in AIHAUS_HOME; target
# repos receive only runtime/state defaults and editable workflow profiles.
foreach ($dir in @(
    (Join-Path $TargetAihaus 'bin'),
    (Join-Path $TargetAihaus 'state'),
    (Join-Path $TargetAihaus 'runtime'),
    (Join-Path $TargetAihaus 'backups'),
    (Join-Path $TargetAihaus 'workflows'),
    (Join-Path $TargetAihaus 'workflows\runs'),
    (Join-Path $TargetAihaus 'memory\workflows'),
    (Join-Path $TargetAihaus 'memory\agents'),
    (Join-Path $TargetAihaus 'memory\reviews'),
    (Join-Path $TargetAihaus 'memory\global'),
    (Join-Path $TargetAihaus 'memory\backend'),
    (Join-Path $TargetAihaus 'memory\frontend')
)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}
$workflowDefaultSrc = Join-Path $PkgAihaus 'workflows\default.md'
$workflowDefaultDst = Join-Path $TargetAihaus 'workflows\default.md'
if (-not (Test-Path $workflowDefaultDst) -and (Test-Path $workflowDefaultSrc)) {
    Copy-Item -LiteralPath $workflowDefaultSrc -Destination $workflowDefaultDst
    Write-Host "  workflow: created .aihaus\workflows\default.md"
}
$workflowAgentsSrc = Join-Path $PkgAihaus 'workflows\agents.md'
$workflowAgentsDst = Join-Path $TargetAihaus 'workflows\agents.md'
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
    $dst = Join-Path $TargetAihaus $rel
    if (-not (Test-Path -LiteralPath $dst) -and (Test-Path -LiteralPath $src)) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force | Out-Null
        Copy-Item -LiteralPath $src -Destination $dst
    }
}
$decisionSeedSrc = Join-Path $PkgTemplates 'decisions.md'
$decisionSeedDst = Join-Path $TargetAihaus 'decisions.md'
if (-not (Test-Path -LiteralPath $decisionSeedDst) -and (Test-Path -LiteralPath $decisionSeedSrc)) {
    Copy-Item -LiteralPath $decisionSeedSrc -Destination $decisionSeedDst
    Write-Host "  memory: created .aihaus\decisions.md"
}
$knowledgeSeedSrc = Join-Path $PkgTemplates 'knowledge.md'
$knowledgeSeedDst = Join-Path $TargetAihaus 'knowledge.md'
if (-not (Test-Path -LiteralPath $knowledgeSeedDst) -and (Test-Path -LiteralPath $knowledgeSeedSrc)) {
    Copy-Item -LiteralPath $knowledgeSeedSrc -Destination $knowledgeSeedDst
    Write-Host "  memory: created .aihaus\knowledge.md"
}
# Business-rules contract ledger (BRC-S7 / ADR-260531-A) — the decision-autonomy substrate.
$brSeedSrc = Join-Path $PkgTemplates 'business-rules.md'
$brSeedDst = Join-Path $TargetAihaus 'memory\workflows\business-rules.md'
if (-not (Test-Path -LiteralPath $brSeedDst) -and (Test-Path -LiteralPath $brSeedSrc)) {
    $brSeedDir = Split-Path -Parent $brSeedDst
    if (-not (Test-Path -LiteralPath $brSeedDir)) { New-Item -ItemType Directory -Force -Path $brSeedDir | Out-Null }
    Copy-Item -LiteralPath $brSeedSrc -Destination $brSeedDst
    Write-Host "  memory: created .aihaus\memory\workflows\business-rules.md (business-rules contract)"
}
# Output-style: the decision-autonomy contract framing (BRC-S6 / A1 finding). Opt-in.
$osSrcDir = Join-Path $PkgAihaus 'output-styles'
if (Test-Path -LiteralPath $osSrcDir) {
    $osDstDir = Join-Path $Target '.claude\output-styles'
    if (-not (Test-Path -LiteralPath $osDstDir)) { New-Item -ItemType Directory -Force -Path $osDstDir | Out-Null }
    Get-ChildItem -LiteralPath $osSrcDir -Filter '*.md' -File | ForEach-Object {
        $osDst = Join-Path $osDstDir $_.Name
        if (-not (Test-Path -LiteralPath $osDst)) {
            Copy-Item -LiteralPath $_.FullName -Destination $osDst
            Write-Host "  output-style: created .claude\output-styles\$($_.Name)"
        }
    }
}

function Ensure-WorkflowEnvironmentPrompts {
    param([string]$EnvironmentFile)

    if (-not (Test-Path -LiteralPath $EnvironmentFile)) { return }
    $raw = Get-Content -LiteralPath $EnvironmentFile -Raw
    if ($raw -match 'AIHAUS:WORKFLOW-ENVIRONMENT-PROMPTS-START') { return }
    if ($raw -match '## Runtime and Deployment') { return }

    Add-Content -LiteralPath $EnvironmentFile -Value @'

<!-- AIHAUS:WORKFLOW-ENVIRONMENT-PROMPTS-START -->
## Runtime and Deployment

- **Where code runs:** _local dev / container / CodeBuild / ECS / Lambda / other_
- **Default dev URL:** _fill in if browser validation uses a stable URL_
- **Deploy path:** _command, pipeline, CodeBuild project, or human-owned release path_
- **Promotion gates:** _what must pass before dev, staging, or production_

## Credentials and Test Accounts

- **Credential location:** _Secrets Manager, Parameter Store, .env vault, password manager, or other approved source_
- **Test users/roles:** _named roles only; do not store passwords or tokens_
- **Auth protocol:** _how an agent should authenticate for Playwright or API smoke checks_

## Validation Commands

- **Unit/integration:** _repo command or CI job_
- **Playwright/browser:** _repo command, dev URL, required seed data_
- **CodeBuild/CI:** _project names or commands used to check builds_
- **Smoke evidence:** _screenshots, traces, URLs, logs, or release artifacts expected_

## Source System Hints

- **External kanban:** _source system, project/view/board identifiers, or none_
- **Stage sync:** _which statuses/views mirror local aihaus stages_
- **Question protocol:** _how business-rule gaps are recorded and answered_
<!-- AIHAUS:WORKFLOW-ENVIRONMENT-PROMPTS-END -->
'@
    Write-Host "  memory: appended workflow environment prompts"
}
Ensure-WorkflowEnvironmentPrompts -EnvironmentFile (Join-Path $TargetAihaus 'memory\workflows\environment.md')

function Ensure-ClaudeContextBridge {
    param([string]$ClaudeDir)

    $contextSrc = Join-Path $PkgTemplates 'claude\CLAUDE.md'
    $contextDst = Join-Path $ClaudeDir 'CLAUDE.md'
    $ruleSrc = Join-Path $PkgTemplates 'claude\rules\aihaus-project-memory.md'
    $rulesDir = Join-Path $ClaudeDir 'rules'
    $ruleDst = Join-Path $rulesDir 'aihaus-project-memory.md'

    New-Item -ItemType Directory -Path $rulesDir -Force | Out-Null

    function Remove-LargeClaudeImports {
        param([string]$Path)
        if (-not (Test-Path -LiteralPath $Path)) { return }
        $lines = Get-Content -LiteralPath $Path
        $filtered = New-Object System.Collections.Generic.List[string]
        $changed = $false
        foreach ($line in $lines) {
            $normalized = $line.TrimEnd()
            if ($normalized -eq '@../.aihaus/decisions.md' -or $normalized -eq '@../.aihaus/knowledge.md') {
                $changed = $true
                continue
            }
            $filtered.Add($line)
        }
        if ($changed) {
            Set-Content -LiteralPath $Path -Value $filtered -Encoding UTF8
            Write-Host "  claude-context: removed large ledger startup imports"
        }
    }

    if (Test-Path -LiteralPath $contextSrc) {
        if (-not (Test-Path -LiteralPath $contextDst)) {
            Copy-Item -LiteralPath $contextSrc -Destination $contextDst
            Write-Host "  claude-context: created .claude\CLAUDE.md"
        } elseif (-not (Select-String -LiteralPath $contextDst -Pattern 'AIHAUS:CLAUDE-CONTEXT-START' -SimpleMatch -Quiet)) {
            Add-Content -LiteralPath $contextDst -Value ''
            Add-Content -LiteralPath $contextDst -Value (Get-Content -LiteralPath $contextSrc -Raw)
            Write-Host "  claude-context: appended aihaus imports to .claude\CLAUDE.md"
        }
    } else {
        Write-Host "  warn: Claude context template missing at $contextSrc" -ForegroundColor Yellow
    }
    Remove-LargeClaudeImports -Path $contextDst

    if (Test-Path -LiteralPath $ruleSrc) {
        if (-not (Test-Path -LiteralPath $ruleDst)) {
            Copy-Item -LiteralPath $ruleSrc -Destination $ruleDst
            Write-Host "  claude-context: created .claude\rules\aihaus-project-memory.md"
        } elseif (-not (Select-String -LiteralPath $ruleDst -Pattern 'AIHAUS:CLAUDE-RULES-START' -SimpleMatch -Quiet)) {
            Add-Content -LiteralPath $ruleDst -Value ''
            Add-Content -LiteralPath $ruleDst -Value (Get-Content -LiteralPath $ruleSrc -Raw)
            Write-Host "  claude-context: appended aihaus rule to .claude\rules\aihaus-project-memory.md"
        }
    } else {
        Write-Host "  warn: Claude rule template missing at $ruleSrc" -ForegroundColor Yellow
    }
}

# Step 5+6: create .claude/{skills,agents,hooks} as junctions or copies
$TargetClaude = Join-Path $Target '.claude'
New-Item -ItemType Directory -Path $TargetClaude -Force | Out-Null
Ensure-ClaudeContextBridge -ClaudeDir $TargetClaude

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
    Write-Host "  copy: .claude\$Name (managed copy pruned)"
}

# M024/S02: Skill-junction conditional (Concern C) -- ADR-260507-A #5
# Skip per-repo .claude\skills junction when user-global skills already exist
# (detected by sentinel directory $HOME\.claude\skills\aih-init, present in
# every aihaus install). Opt-out: -ForceProjectSkills switch.
# Note: dogfood mode exits before reaching this block, so the conditional only
# applies to non-dogfood -Target invocations.
function Test-HasUserGlobalSkills {
    return (Test-Path (Join-Path $env:USERPROFILE ".claude\skills\aih-init"))
}

foreach ($name in @('skills','agents','hooks')) {
    if ($name -eq 'skills') {
        if (-not (Test-HasUserGlobalSkills) -or $ForceProjectSkills) {
            Link-Or-Copy -Name 'skills'
        } else {
            Write-Host "  skip: .claude\skills -- user-global skills present (pass -ForceProjectSkills to override)"
        }
    } else {
        Link-Or-Copy -Name $name
    }
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

    # Merge-Object: deep-merge $Overlay over $Base (ADR-260514-B array-aware semantics).
    # Dual by-shape rule for arrays:
    #   Outer shape ({matcher,hooks} elements): position-paired merge with recursion.
    #   Inner shape ({command} elements): union by .command (template/overlay wins).
    #   All other arrays: replacement (overlay wins) -- preserves M014 permissions contract.
    function Merge-HooksByCommand {
        param($BaseArr, $OverlayArr)
        # Union by .command -- overlay (template) wins on collision
        $result = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $BaseArr) { $result.Add($item) | Out-Null }
        foreach ($entry in $OverlayArr) {
            $cmd = if ($entry.PSObject.Properties.Name -contains 'command') { $entry.command } else { $null }
            $exists = $result | Where-Object { $_.PSObject.Properties.Name -contains 'command' -and $_.command -eq $cmd }
            if (-not $exists) { $result.Add($entry) | Out-Null }
        }
        return $result.ToArray()
    }

    function Test-HasMatcherHooks($Arr) {
        if (-not $Arr -or $Arr.Count -eq 0) { return $false }
        foreach ($item in $Arr) {
            if (-not ($item -is [psobject])) { return $false }
            if (-not ($item.PSObject.Properties.Name -contains 'matcher')) { return $false }
            if (-not ($item.PSObject.Properties.Name -contains 'hooks')) { return $false }
        }
        return $true
    }

    function Test-HasCommand($Arr) {
        if (-not $Arr -or $Arr.Count -eq 0) { return $false }
        foreach ($item in $Arr) {
            if (-not ($item -is [psobject])) { return $false }
            if (-not ($item.PSObject.Properties.Name -contains 'command')) { return $false }
        }
        return $true
    }

    function Merge-HooksArrays {
        param($BaseArr, $OverlayArr)
        if (-not $BaseArr -or $BaseArr.Count -eq 0) { return $OverlayArr }
        if (-not $OverlayArr -or $OverlayArr.Count -eq 0) { return $BaseArr }
        if ((Test-HasMatcherHooks $BaseArr) -and (Test-HasMatcherHooks $OverlayArr)) {
            # outer shape: position-paired merge
            $minLen = [Math]::Min($BaseArr.Count, $OverlayArr.Count)
            $result = [System.Collections.Generic.List[object]]::new()
            for ($i = 0; $i -lt $minLen; $i++) {
                $bh = if ($BaseArr[$i].PSObject.Properties.Name -contains 'hooks') { $BaseArr[$i].hooks } else { @() }
                $oh = if ($OverlayArr[$i].PSObject.Properties.Name -contains 'hooks') { $OverlayArr[$i].hooks } else { @() }
                $mergedInner = Merge-HooksArrays $bh $oh
                $entry = $OverlayArr[$i].PSObject.Copy()
                $entry.hooks = $mergedInner
                $result.Add($entry) | Out-Null
            }
            # surplus template entries first, then surplus user entries
            for ($i = $minLen; $i -lt $OverlayArr.Count; $i++) { $result.Add($OverlayArr[$i]) | Out-Null }
            for ($i = $minLen; $i -lt $BaseArr.Count; $i++) { $result.Add($BaseArr[$i]) | Out-Null }
            return $result.ToArray()
        }
        if ((Test-HasCommand $BaseArr) -and (Test-HasCommand $OverlayArr)) {
            return Merge-HooksByCommand $BaseArr $OverlayArr
        }
        # default: replacement
        return $OverlayArr
    }

    function Merge-Object {
        param($Base, $Overlay)
        if ($Overlay -is [psobject] -and $Base -is [psobject]) {
            foreach ($prop in $Overlay.PSObject.Properties) {
                if ($Base.PSObject.Properties.Name -contains $prop.Name) {
                    if ($prop.Name -eq 'hooks' -and
                        $Base.hooks -is [psobject] -and $Overlay.hooks -is [psobject]) {
                        # hooks key: event-level array merge
                        $mergedHooks = $Base.hooks.PSObject.Copy()
                        foreach ($eventProp in $Overlay.hooks.PSObject.Properties) {
                            $eventName = $eventProp.Name
                            $ovArr = $eventProp.Value
                            if ($mergedHooks.PSObject.Properties.Name -contains $eventName) {
                                $baseArr = $mergedHooks.$eventName
                                $mergedHooks.$eventName = Merge-HooksArrays $baseArr $ovArr
                            } else {
                                Add-Member -InputObject $mergedHooks -NotePropertyName $eventName -NotePropertyValue $ovArr -Force
                            }
                        }
                        $Base.hooks = $mergedHooks
                    } else {
                        $Base.$($prop.Name) = Merge-Object $Base.$($prop.Name) $prop.Value
                    }
                } else {
                    Add-Member -InputObject $Base -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
                }
            }
            return $Base
        }
        # Arrays: check by-shape rules
        if ($Overlay -is [array] -and $Base -is [array]) {
            return Merge-HooksArrays $Base $Overlay
        }
        return $Overlay
    }

    $merged = Merge-Object $dstJson $srcJson
    $merged = Normalize-HooksShape $merged
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

    if (Test-Path $SettingsOut) {
        $settingsRaw = Get-Content -LiteralPath $SettingsOut -Raw
        if ($settingsRaw -match '\.claude/hooks/') {
            $settingsRaw = $settingsRaw -replace '\.claude/hooks/', '.aihaus/hooks/'
            Set-Content -LiteralPath $SettingsOut -Value $settingsRaw -Encoding UTF8 -NoNewline
            Write-Host "  settings: normalized hook paths to .aihaus\hooks"
        }
    }

    # ---- Drift-detect: prompt recompute if hook count fell behind template ----
    # ADR-260514-B Half B rollout closure (PowerShell port of update.sh drift-detect).
    # Compares template hook count vs merged settings hook count for each .hooks.<Event>[].
    # If any Event has template_count - user_count >= AIHAUS_DRIFT_THRESHOLD (default 2),
    # prompts user to recompute with AIHAUS_RECOMPUTE_MERGE=1.
    $DriftPromptEnv = $env:AIHAUS_DRIFT_PROMPT
    $DriftThreshold = if ($env:AIHAUS_DRIFT_THRESHOLD) { [int]$env:AIHAUS_DRIFT_THRESHOLD } else { 2 }
    $SentinelPath = Join-Path $TargetAihaus '.recompute-skipped-260514'
    if ($DriftPromptEnv -ne '0' -and (Test-Path $SettingsOut) -and (Test-Path $SettingsSrc)) {
        if (Test-Path $SentinelPath) {
            Write-Host "  drift-detect: recompute skipped (sentinel present)" -ForegroundColor DarkGray
        } else {
            try {
                $tmplHooks = if ($srcJson.PSObject.Properties.Name -contains 'hooks') { $srcJson.hooks } else { $null }
                $userHooks = if ($merged.PSObject.Properties.Name -contains 'hooks') { $merged.hooks } else { $null }
                $maxDelta = 0; $maxEvent = ''
                if ($tmplHooks -is [psobject]) {
                    foreach ($evProp in $tmplHooks.PSObject.Properties) {
                        $evName = $evProp.Name
                        $tmplEntries = $evProp.Value
                        $tmplCount = ($tmplEntries | ForEach-Object { if ($_.PSObject.Properties.Name -contains 'hooks') { $_.hooks.Count } else { 0 } } | Measure-Object -Sum).Sum
                        $userEntries = if ($userHooks -is [psobject] -and $userHooks.PSObject.Properties.Name -contains $evName) { $userHooks.$evName } else { @() }
                        $userCount = ($userEntries | ForEach-Object { if ($_.PSObject.Properties.Name -contains 'hooks') { $_.hooks.Count } else { 0 } } | Measure-Object -Sum).Sum
                        $delta = $tmplCount - $userCount
                        if ($delta -gt $maxDelta) { $maxDelta = $delta; $maxEvent = $evName }
                    }
                }
                if ($maxDelta -ge $DriftThreshold) {
                    $driftAnswer = Read-Host "  Detected $maxDelta missing canonical hook entries from $maxEvent. Recompute merged settings now? [Y/n]"
                    if ([string]::IsNullOrWhiteSpace($driftAnswer) -or $driftAnswer -match '^[Yy]$') {
                        Write-Host "  drift-detect: recomputing merged settings..."
                        $env:AIHAUS_RECOMPUTE_MERGE = '1'
                        $srcJsonFresh = Get-Content $SettingsSrc -Raw | ConvertFrom-Json
                        $dstJsonFresh = Get-Content $SettingsOut -Raw | ConvertFrom-Json
                        $remerged = Merge-Object $dstJsonFresh $srcJsonFresh
                        $remerged = Normalize-HooksShape $remerged
                        $remerged | ConvertTo-Json -Depth 20 | Set-Content -Path $SettingsOut -Encoding UTF8
                        $env:AIHAUS_RECOMPUTE_MERGE = $null
                        Write-Host "  settings: recomputed (drift-corrected)"
                    } else {
                        Set-Content -Path $SentinelPath -Value '' -NoNewline
                        Write-Host "  drift-detect: skipped; sentinel written to suppress future prompts" -ForegroundColor DarkGray
                    }
                }
            } catch {
                # drift-detect is best-effort; never fail install
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

# Step 10: V5 user-global skill install -- ADR-260504-A FR-01/FR-06
# Install each aih-* skill into $env:USERPROFILE\.claude\skills\ (user-global Claude Code resolution layer).
# This runs on every non-dogfood non-update invocation (idempotent per I-02).
# M024/S02 (Concern B fix): pass $AihausResolved (repo root containing pkg\) not $PkgRoot
# (which is repo-root\pkg -- would resolve to repo-root\pkg\pkg\.aihaus\skills, never exists).
if (-not $Update) {
    Write-Host ""
    Write-Host "  installing user-global skills..."
    Install-UserGlobalSkills -AihausHome $AihausResolved

    # Step 11: write $env:USERPROFILE\.aihaus\.install-source registry (FR-04, I-01)
    # Written here (after per-repo overlay + user-global skills succeed) so a partial
    # failure never pins a broken path. Using $AihausResolved as the canonical AIHAUS_HOME.
    # M024/S02 (Concern B fix): use $AihausResolved (repo root) not $PkgRoot (repo-root\pkg).
    $registryDir = Join-Path $env:USERPROFILE ".aihaus"
    if (-not (Test-Path $registryDir)) {
        New-Item -ItemType Directory -Path $registryDir -Force | Out-Null
    }
    $registryFile = Join-Path $registryDir ".install-source"
    Set-Content -LiteralPath $registryFile -Value $AihausResolved -Encoding UTF8 -NoNewline
    Write-Host "  registry: $env:USERPROFILE\.aihaus\.install-source -> $AihausResolved"
}

# Step 12: idempotent .gitignore injection (soft-fail per LD-3)
# Manual fallback: pkg\.aihaus\templates\gitignore-fragment
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

function Invoke-InjectGitignore {
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
        '/.aihaus/memory/local/',
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

    # Primary idempotency check -- guard-comment anchor already present?
    if (Test-Path -LiteralPath $gitignore) {
        $guardHit = Select-String -LiteralPath $gitignore -Pattern '^# AIHAUS:GITIGNORE-START' -Quiet
        if ($guardHit) {
            $rawContent = Read-AihUtf8Text -Path $gitignore
            $content = @(ConvertTo-AihLines -Text $rawContent)
            $missing = @($entries | Where-Object { $content -notcontains $_ })
            if ($missing.Count -eq 0) {
                Write-Host "  .gitignore: aihaus block already present (no-op)"
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
        '# AIHAUS:GITIGNORE-START -- managed by install.sh / update.sh; do not edit between markers'
    ) + $entries + @('# AIHAUS:GITIGNORE-END')

    try {
        Add-AihUtf8Lines -Path $gitignore -Lines $block
        Write-Host "  .gitignore: aihaus block injected"
    } catch {
        Write-Host "  !! WARNING: could not write .gitignore at $gitignore" -ForegroundColor Yellow
        Write-Host "  !!          Apply manually from pkg\.aihaus\templates\gitignore-fragment" -ForegroundColor Yellow
    }
}
Invoke-InjectGitignore -TargetDir $Target

# Step 13: aih-graph memory engine binary bootstrap
# Downloads the aih-graph binary to .aihaus\bin\ if not already present.
# Non-fatal: /aih-init and hooks degrade to lexical/no-memory behavior if absent.
if (-not $env:AIHAUS_SKIP_GRAPH_BINARY -and -not $Update) {
    $graphBin = Join-Path $TargetAihaus 'bin\aih-graph.exe'
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
    } else {
        Write-Host "  aih-graph: already installed at $graphBin"
    }
}

# Step 14: success message
Write-Host ""
if ($Update) {
    Write-Host "aihaus updated ($Mode mode)."
    Write-Host "Launch with: .\aihaus\auto.ps1"
} else {
    Write-Host "aihaus installed ($Mode mode)."
    Write-Host "Launch with: .\aihaus\auto.ps1"
    Write-Host "Run /aih-init inside the launched session to bootstrap project.md"
}
