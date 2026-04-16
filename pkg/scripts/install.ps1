# aihaus install script (Windows PowerShell)
# Copies .aihaus/ into target repo and links .claude/{skills,agents,hooks}.
# Flags:
#   -Target <path>   Install into <path> instead of $PWD
#   -Copy            Copy files instead of creating junctions
#   -Update          Re-sync package dirs only; preserve local data
#   -Help            Show usage

[CmdletBinding()]
param(
    [string]$Target = (Get-Location).Path,
    [switch]$Copy,
    [switch]$Update,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

function Show-Usage {
    @'
Usage: install.ps1 [-Target <path>] [-Copy] [-Update]

Installs aihaus into a target git repository.

Options:
  -Target <path>   Target directory (default: current working directory)
  -Copy            Copy files instead of creating junctions
  -Update          Re-sync package dirs only; preserve local data
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
$Mode = if ($Copy) { 'copy' } else { 'link' }

if ($Update) {
    Write-Host "aihaus updater (via -Update)"
} else {
    Write-Host "aihaus installer"
}
Write-Host "  package: $PkgRoot"
Write-Host "  target:  $Target"
Write-Host "  mode:    $Mode"

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

    # Restore per-agent calibration from .aihaus\.calibration (schema v1).
    # Mirror of restore_calibration() in update.sh — pinned call site between
    # agents refresh and .claude\ re-link so both layers pick up restored
    # frontmatter. Schema contract:
    # pkg\.aihaus\skills\aih-calibrate\annexes\state-file.md
    $stateFile = Join-Path $TargetAihaus '.calibration'
    if (Test-Path $stateFile) {
        $schemaLine = (Select-String -Path $stateFile -Pattern '^schema=' | Select-Object -First 1)
        $schema = ''
        if ($schemaLine) {
            $schema = ($schemaLine.Line -split '=', 2)[1]
            $schema = ($schema -replace "`r", '').Trim()
        }
        if ($schema -ne '1') {
            Write-Host "  warn: unknown .calibration schema='$schema' — skipping restore"
        } else {
            $restored = 0
            $skipped = 0
            $lastPreset = ''
            foreach ($line in (Get-Content -LiteralPath $stateFile)) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                if ($line -match '^\s*#') { continue }
                if ($line -notmatch '=') { continue }
                $parts = $line -split '=', 2
                $key = ($parts[0] -replace "`r", '').Trim()
                $value = ($parts[1] -replace "`r", '').Trim()
                if ($key -eq 'schema') { continue }
                if ($key -eq 'permission_mode') { continue }
                if ($key -eq 'last_preset') { $lastPreset = $value; continue }
                if ($key -eq 'last_commit') { continue }
                if ([string]::IsNullOrWhiteSpace($value)) { continue }

                $agentFile = Join-Path (Join-Path $TargetAihaus 'agents') ("$key.md")
                if (Test-Path $agentFile) {
                    $content = Get-Content -LiteralPath $agentFile
                    $newContent = $content -replace '^effort: .*', "effort: $value"
                    # UTF8 no-BOM, no trailing newline — matches sed -i.bak byte layout.
                    Set-Content -LiteralPath $agentFile -Value $newContent -Encoding UTF8 -NoNewline
                    $restored++
                } else {
                    $skipped++
                    Write-Host "  warn: .calibration references missing agent '$key' — skipped"
                }
            }
            if ($skipped -gt 0) {
                Write-Host "  restored $restored per-agent effort override(s) from .aihaus\.calibration ($skipped skipped — missing agents)"
            } else {
                Write-Host "  restored $restored per-agent effort override(s) from .aihaus\.calibration"
            }
            if ($lastPreset -eq 'auto-mode-safe') {
                Write-Host ""
                Write-Host "  !!  Your last preset was auto-mode-safe, but side effects" -ForegroundColor Yellow
                Write-Host "  !!  (auto-approve-bash.sh SAFE_PATTERNS widening + worktree" -ForegroundColor Yellow
                Write-Host "  !!  agents' permissionMode removal) are NOT auto-restored." -ForegroundColor Yellow
                Write-Host "  !!  Classifier pauses may occur until you re-run:" -ForegroundColor Yellow
                Write-Host "  !!    /aih-calibrate --preset auto-mode-safe" -ForegroundColor Yellow
                Write-Host ""
            }
        }
    }
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
            # mklink /J is available via cmd on every modern Windows — no admin required
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
}

# Step 8: write install mode marker
Set-Content -Path (Join-Path $TargetAihaus '.install-mode') -Value $Mode -NoNewline

# Step 9: success
Write-Host ""
if ($Update) {
    Write-Host "aihaus updated ($Mode mode)."
} else {
    Write-Host "aihaus installed ($Mode mode)."
    Write-Host "Run /aih-init to bootstrap project.md"
}
