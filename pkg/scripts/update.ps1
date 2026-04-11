# AIhaus update script (Windows PowerShell)
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

Re-syncs package-managed files in .aihaus/ from the AIhaus package source.
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

Write-Host "AIhaus updater"
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
Write-Host "AIhaus updated ($Mode mode)."
exit 0
