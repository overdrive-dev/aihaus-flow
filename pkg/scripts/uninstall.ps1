# AIhaus uninstall script (Windows PowerShell)
# Removes package-installed files while preserving user data.
# Flags:
#   -Target <path>   Uninstall from <path> instead of $PWD
#   -Purge           Remove EVERYTHING under .aihaus/ (including project.md)

[CmdletBinding()]
param(
    [string]$Target = (Get-Location).Path,
    [switch]$Purge,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

function Show-Usage {
    @'
Usage: uninstall.ps1 [-Target <path>] [-Purge]

Removes AIhaus files from a target repository while preserving user data.

Options:
  -Target <path>   Target directory (default: current working directory)
  -Purge           Delete ALL .aihaus/ data including project.md (prompts)
  -Help            Show this message
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
        Write-Host "  settings: cleaned AIhaus-managed keys"
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
