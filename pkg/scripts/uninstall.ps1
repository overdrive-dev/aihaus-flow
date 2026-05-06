# aihaus uninstall script (Windows PowerShell)
# Removes package-installed files while preserving user data.
# Flags:
#   -Target <path>        Uninstall from <path> instead of $PWD
#   -Purge                Remove EVERYTHING under .aihaus/ (including project.md)
#   -PurgeUserGlobal      Remove user-global aih-* skills from ~\.claude\skills\
#                         Only removes entries carrying the .aihaus-managed marker AND
#                         whose junction/symlink target resolves under registered AIHAUS_HOME
#                         (R4 readlink validation — ADR-260504-A FR-06 + FR-21).

[CmdletBinding()]
param(
    [string]$Target = (Get-Location).Path,
    [switch]$Purge,
    [switch]$PurgeUserGlobal,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

function Show-Usage {
    @'
Usage: uninstall.ps1 [-Target <path>] [-Purge] [-PurgeUserGlobal]

Removes aihaus files from a target repository while preserving user data.

Options:
  -Target <path>        Target directory (default: current working directory)
  -Purge                Delete ALL .aihaus/ data including project.md (prompts)
  -PurgeUserGlobal      Remove user-global aih-* skills from ~\.claude\skills\
                        Only removes entries marked aihaus-owned AND whose junction/
                        symlink target resolves under registered AIHAUS_HOME (R4 guard).
  -Help                 Show this message
'@ | Write-Host
}

if ($Help) { Show-Usage; exit 0 }

if (-not (Test-Path $Target)) {
    Write-Error "target directory does not exist: $Target"
    exit 1
}
$Target = (Resolve-Path $Target).Path
$Claude = Join-Path $Target '.claude'
$Aihaus = Join-Path $Target '.aihaus'
$Touched = $false

function Remove-ClaudeEntry {
    param([string]$Name)
    $path = Join-Path $script:Claude $Name
    if (-not (Test-Path $path)) { return }
    $item = Get-Item $path -Force
    # Both symlinks and junctions have the ReparsePoint attribute
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        cmd /c "rmdir `"$path`"" | Out-Null
        if ($LASTEXITCODE -ne 0) { Remove-Item -Force $path -ErrorAction SilentlyContinue }
        Write-Host "  removed link: .claude\$Name"
    } else {
        Remove-Item -Recurse -Force $path
        Write-Host "  removed dir:  .claude\$Name"
    }
    $script:Touched = $true
}

function Remove-AihausSub {
    param([string]$Name)
    $path = Join-Path $script:Aihaus $Name
    if (Test-Path $path) {
        Remove-Item -Recurse -Force $path
        Write-Host "  removed:      .aihaus\$Name"
        $script:Touched = $true
    }
}

if ($Purge) {
    $anything = (Test-Path $Aihaus) -or (Test-Path (Join-Path $Claude 'skills')) `
        -or (Test-Path (Join-Path $Claude 'agents')) -or (Test-Path (Join-Path $Claude 'hooks'))
    if (-not $anything) {
        Write-Host "Nothing to uninstall"
        exit 0
    }
    Write-Host "This will delete ALL .aihaus/ data including project.md."
    $reply = Read-Host "Type 'yes' to confirm"
    if ($reply -ne 'yes') {
        Write-Host "Aborted."
        exit 0
    }
    foreach ($name in @('skills','agents','hooks')) { Remove-ClaudeEntry -Name $name }
    if (Test-Path $Aihaus) {
        Remove-Item -Recurse -Force $Aihaus
        Write-Host "  removed:      .aihaus\ (purged)"
        $Touched = $true
    }
} else {
    foreach ($name in @('skills','agents','hooks')) { Remove-ClaudeEntry -Name $name }
    foreach ($name in @('skills','agents','hooks','memory')) { Remove-AihausSub -Name $name }
    $mode = Join-Path $Aihaus '.install-mode'
    if (Test-Path $mode) {
        Remove-Item -Force $mode
        $Touched = $true
    }
}

# ---------------------------------------------------------------------------
# -PurgeUserGlobal: remove user-global aih-* skill dirs from ~\.claude\skills\
# Security boundary (ADR-260504-A FR-06 + FR-21 R4):
#   - Only removes dirs carrying a .aihaus-managed marker (aihaus-owned signal).
#   - (Get-Item).Target resolves junction/symlink target; refuses if outside AIHAUS_HOME.
#   - Removes ~\.aihaus\.install-source registry after successful purge.
#   - Removes ~\.claude\hooks\session-start.sh if aihaus-managed marker present.
# ---------------------------------------------------------------------------
function Invoke-PurgeUserGlobal {
    $userProfile = $env:USERPROFILE
    $userSkillsDir = Join-Path $userProfile '.claude\skills'
    $registry = Join-Path $userProfile '.aihaus\.install-source'
    $purgeAny = $false

    # Resolve registered AIHAUS_HOME from the install-source registry.
    if (-not (Test-Path $registry)) {
        Write-Warning "~\.aihaus\.install-source not found; no registered AIHAUS_HOME to validate against"
        Write-Warning "user-global purge aborted (cannot perform R4 readlink validation without registry)"
        return
    }
    $aihausHome = (Get-Content $registry -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($aihausHome)) {
        Write-Warning "~\.aihaus\.install-source is empty; cannot resolve AIHAUS_HOME"
        return
    }
    # Resolve to canonical absolute path (guard against relative paths in registry).
    if (-not (Test-Path $aihausHome)) {
        Write-Warning "AIHAUS_HOME '$aihausHome' from registry does not exist on disk; R4 validation skipped"
        return
    }
    $aihausHome = (Resolve-Path $aihausHome).Path
    # Normalize: no trailing backslash for prefix comparison.
    $homePrefix = $aihausHome.TrimEnd('\').TrimEnd('/')

    Write-Host "  user-global purge: AIHAUS_HOME=$aihausHome"

    # Iterate over every aih-* entry in the user-global skills dir.
    if (Test-Path $userSkillsDir) {
        $entries = Get-ChildItem -LiteralPath $userSkillsDir -Force -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -like 'aih-*' }
        foreach ($entry in $entries) {
            $entryName = $entry.Name
            $markerPath = Join-Path $entry.FullName '.aihaus-managed'

            # --- Marker check (FR-06) ---
            if (-not (Test-Path $markerPath)) {
                Write-Host "skipping ~\.claude\skills\${entryName}: no .aihaus-managed marker (not aihaus-owned)" -ForegroundColor Yellow
                continue
            }

            # --- R4 readlink validation (FR-21) ---
            # Resolve the junction/symlink target. For copied dirs, read source= line.
            $resolvedTarget = $null
            $item = Get-Item -LiteralPath $entry.FullName -Force -ErrorAction SilentlyContinue
            if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                # Junction or symlink — resolve via .Target property.
                $resolvedTarget = $item.Target
                if ($resolvedTarget) {
                    # Resolve to absolute if relative.
                    try {
                        $resolvedTarget = (Resolve-Path $resolvedTarget -ErrorAction Stop).Path
                    } catch {
                        $resolvedTarget = $null
                    }
                }
            } else {
                # Copied dir: read source= line from .aihaus-managed marker.
                $srcLine = Get-Content $markerPath -ErrorAction SilentlyContinue |
                           Where-Object { $_ -match '^source=' } |
                           Select-Object -First 1
                if ($srcLine) {
                    $resolvedTarget = ($srcLine -replace '^source=', '').Trim()
                }
            }

            if ([string]::IsNullOrWhiteSpace($resolvedTarget)) {
                Write-Host "skipping ~\.claude\skills\${entryName}: symlink target outside registered AIHAUS_HOME (R4 guard)" -ForegroundColor Yellow
                continue
            }

            # Prefix check: target must start with homePrefix (case-insensitive on Windows).
            $resolvedNorm = $resolvedTarget.TrimEnd('\').TrimEnd('/')
            if (-not ($resolvedNorm -ieq $homePrefix -or $resolvedNorm -ilike "${homePrefix}\*" -or $resolvedNorm -ilike "${homePrefix}/*")) {
                Write-Host "skipping ~\.claude\skills\${entryName}: symlink target outside registered AIHAUS_HOME (R4 guard)" -ForegroundColor Yellow
                continue
            }

            # Both checks passed — remove the entry.
            # Use cmd rmdir for junctions (avoids deleting the target contents).
            if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                cmd /c "rmdir `"$($entry.FullName)`"" | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    Remove-Item -Recurse -Force $entry.FullName -ErrorAction SilentlyContinue
                }
            } else {
                Remove-Item -Recurse -Force $entry.FullName
            }
            Write-Host "  removed user-global: ~\.claude\skills\$entryName"
            $purgeAny = $true
        }
    }

    # --- Hook fragment cleanup (Z7 outcome — gate on marker existence) ---
    # If install.sh dropped a user-global hook fragment at ~/.claude/hooks/session-start.sh
    # and that file carries a managed_by=aihaus line, remove it.
    $userHook = Join-Path $userProfile '.claude\hooks\session-start.sh'
    if (Test-Path $userHook) {
        $hookContent = Get-Content $userHook -ErrorAction SilentlyContinue
        if ($hookContent -and ($hookContent -match 'managed_by=aihaus')) {
            Remove-Item -Force $userHook
            Write-Host "  removed user-global: ~\.claude\hooks\session-start.sh"
            $purgeAny = $true
            # Also remove now-empty hooks dir if empty.
            $hooksDir = Join-Path $userProfile '.claude\hooks'
            if (Test-Path $hooksDir) {
                $remaining = Get-ChildItem $hooksDir -Force -ErrorAction SilentlyContinue
                if (-not $remaining) {
                    Remove-Item -Force $hooksDir -ErrorAction SilentlyContinue
                }
            }
        }
    }

    # --- Remove install-source registry after successful purge ---
    if (Test-Path $registry) {
        Remove-Item -Force $registry
        Write-Host "  removed: ~\.aihaus\.install-source"
        $purgeAny = $true
    }

    if (-not $purgeAny) {
        Write-Host "  user-global: nothing to remove"
    }

    $script:Touched = $true
}

# Invoke user-global purge if flag was set.
if ($PurgeUserGlobal) {
    Invoke-PurgeUserGlobal
}

# Settings cleanup: only remove keys listed in _aihaus_managed marker
$Settings = Join-Path $Claude 'settings.local.json'
if (Test-Path $Settings) {
    try {
        $json = Get-Content $Settings -Raw | ConvertFrom-Json
    } catch {
        $json = $null
    }
    if ($json -and $json.PSObject.Properties.Name -contains '_aihaus_managed') {
        $managed = @($json._aihaus_managed)
        foreach ($keyPath in $managed) {
            $parts = $keyPath -split '\.'
            $node = $json
            for ($i = 0; $i -lt $parts.Length - 1; $i++) {
                if ($node -and ($node.PSObject.Properties.Name -contains $parts[$i])) {
                    $node = $node.$($parts[$i])
                } else {
                    $node = $null; break
                }
            }
            if ($node -and $node.PSObject.Properties.Name -contains $parts[-1]) {
                $node.PSObject.Properties.Remove($parts[-1])
            }
        }
        $json.PSObject.Properties.Remove('_aihaus_managed')
        $json | ConvertTo-Json -Depth 20 | Set-Content -Path $Settings -Encoding UTF8
        Write-Host "  settings: cleaned aihaus-managed keys"
        $Touched = $true
    }
}

if (-not $Touched) {
    Write-Host "Nothing to uninstall"
    exit 0
}

if (-not $Purge) {
    Write-Host ""
    Write-Host "User data preserved at .aihaus/{milestones,features,bugfixes,plans}/"
}
