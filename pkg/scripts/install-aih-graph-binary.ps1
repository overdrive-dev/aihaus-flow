# Downloads the pre-built Windows aih-graph binary from GitHub Releases.
# Native PowerShell path handling avoids Git Bash/MSYS path conversion issues.

[CmdletBinding()]
param(
    [string]$Version = "",
    [string]$Bin = "",
    [string]$Repo = ""
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = if ($env:AIH_GRAPH_VERSION) { $env:AIH_GRAPH_VERSION } else { 'latest' }
}
if ([string]::IsNullOrWhiteSpace($Repo)) {
    $Repo = if ($env:AIH_GRAPH_REPO) { $env:AIH_GRAPH_REPO } else { 'overdrive-dev/aihaus-flow' }
}
if ([string]::IsNullOrWhiteSpace($Bin)) {
    $Bin = if ($env:AIH_GRAPH_BIN) {
        $env:AIH_GRAPH_BIN
    } else {
        Join-Path $HOME '.aihaus\bin\aih-graph.exe'
    }
}

$arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
switch ($arch) {
    'X64' { $goarch = 'amd64' }
    default {
        Write-Error "install-aih-graph-binary: unsupported Windows architecture '$arch'"
        exit 1
    }
}

$asset = "aih-graph-windows-$goarch.exe"
if ($Version -eq 'latest') {
    $downloadUrl = "https://github.com/$Repo/releases/latest/download/$asset"
} else {
    $tag = $Version
    if (-not $tag.StartsWith('aih-graph-v')) {
        $tag = "aih-graph-$tag"
    }
    $downloadUrl = "https://github.com/$Repo/releases/download/$tag/$asset"
}

$binDir = Split-Path -Parent $Bin
if (-not (Test-Path $binDir)) {
    New-Item -ItemType Directory -Force -Path $binDir | Out-Null
}

$binName = Split-Path -Leaf $Bin
Get-ChildItem -LiteralPath $binDir -Filter "$binName.tmp.*" -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue

$tmp = "$Bin.tmp.$PID"
$checksumTmp = "$tmp.sha256"

function Invoke-Download {
    param(
        [string]$Url,
        [string]$OutFile,
        [switch]$Optional
    )

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        & $curl.Source -fL -o $OutFile $Url
        if ($LASTEXITCODE -eq 0) { return $true }
        if ($Optional) { return $false }
        throw "curl.exe failed with exit code $LASTEXITCODE"
    }

    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
        return $true
    } catch {
        if ($Optional) { return $false }
        throw
    }
}

try {
    Write-Host "install-aih-graph-binary: $Version -> $Bin"
    Invoke-Download -Url $downloadUrl -OutFile $tmp | Out-Null

    if (Invoke-Download -Url "$downloadUrl.sha256" -OutFile $checksumTmp -Optional) {
        $expected = ((Get-Content -Raw $checksumTmp).Trim() -split '\s+')[0].ToLowerInvariant()
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $tmp).Hash.ToLowerInvariant()
        if ($expected -and $actual -and $expected -ne $actual) {
            throw "SHA-256 mismatch (expected $expected, got $actual)"
        }
    }

    Move-Item -LiteralPath $tmp -Destination $Bin -Force
    Write-Host "install-aih-graph-binary: installed to $Bin"
    try {
        & $Bin version 2>$null | Out-Host
    } catch {
        # Non-fatal: older Windows policies may block immediate execution of a
        # freshly downloaded .exe even though the install itself succeeded.
    }
} catch {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $checksumTmp -Force -ErrorAction SilentlyContinue
    Write-Error "install-aih-graph-binary: $($_.Exception.Message)"
    exit 1
} finally {
    Remove-Item -LiteralPath $checksumTmp -Force -ErrorAction SilentlyContinue
}
