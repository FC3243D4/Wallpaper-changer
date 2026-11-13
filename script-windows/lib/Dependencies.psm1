#Requires -Version 7.0
# Dependencies.psm1
# Checks for, and (after asking) installs, the tools the Windows pipeline uses.
#
#   Install-Matugen   required for theming. Upstream publishes no Windows
#                     binaries (and I found no winget/scoop package), so it is
#                     built from source with `cargo install matugen --locked`;
#                     if Rust is missing, rustup can be installed via winget first.
#   Install-FilePilot optional third-party file manager (winget: Voidstar.FilePilot).
#
# Every function takes -Yes (answer yes to the install question) and
# -NonInteractive (never ask, never install - just report what is missing).

Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'WallpaperChanger.Common.psm1') -DisableNameChecking

function Confirm-Choice {
    # Default answer is No. -Yes forces Yes, -NonInteractive forces No.
    param([Parameter(Mandatory)][string]$Question, [switch]$Yes, [switch]$NonInteractive)
    if ($Yes) { return $true }
    if ($NonInteractive) { return $false }
    (Read-Host "$Question (y/N)") -match '^(y|yes)$'
}

function Find-Cargo {
    $cmd = Get-Command 'cargo' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $p = Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe'     # rustup's default location, not yet on PATH in this session
    if (Test-Path -LiteralPath $p -PathType Leaf) { $p }
}

function Test-WingetPackage {
    # True if winget lists the package as installed.
    param([Parameter(Mandatory)][string]$Id)
    $winget = Get-Command 'winget' -ErrorAction SilentlyContinue
    if (-not $winget) { return $false }
    & $winget.Source list --id $Id --exact --accept-source-agreements 2>&1 | Out-Null
    $LASTEXITCODE -eq 0
}

function Install-Matugen {
    # Returns the path to matugen, or $null if it is still missing afterwards.
    param([switch]$Yes, [switch]$NonInteractive)

    $existing = Find-Matugen
    if ($existing) { Write-Host "matugen: $existing" -ForegroundColor Green; return $existing }

    Write-Host 'matugen is not installed. The theming pipeline needs it.' -ForegroundColor Yellow
    Write-Host '  Upstream has no Windows download, so it is compiled from source with Rust (a few minutes, one time).'

    $cargo = Find-Cargo
    if (-not $cargo) {
        $winget = Get-Command 'winget' -ErrorAction SilentlyContinue
        if ($winget -and (Confirm-Choice 'Rust (cargo) is missing. Install it with winget (Rustlang.Rustup; its installer may offer to add the Visual Studio C++ Build Tools, which it needs)?' -Yes:$Yes -NonInteractive:$NonInteractive)) {
            & $winget.Source install --id Rustlang.Rustup --exact --accept-package-agreements --accept-source-agreements
            $cargo = Find-Cargo
            if (-not $cargo) { Write-Warning 'Rust is not available yet. Finish the rustup setup, then re-run this installer.' }
        }
    }
    if (-not $cargo) {
        Write-Host '  To install it yourself: get Rust from https://rustup.rs, then run:  cargo install matugen --locked' -ForegroundColor Yellow
        return $null
    }

    if (Confirm-Choice "Build and install matugen now with '$cargo install matugen --locked'?" -Yes:$Yes -NonInteractive:$NonInteractive) {
        & $cargo install matugen --locked
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "cargo install matugen failed (exit $LASTEXITCODE). The most common cause is a missing C++ linker: install the Visual Studio Build Tools ('Desktop development with C++') and retry."
            return $null
        }
    }
    else { Write-Host '  Skipped. Install later with:  cargo install matugen --locked' -ForegroundColor Yellow; return $null }

    $found = Find-Matugen
    if ($found) { Write-Host "matugen installed: $found" -ForegroundColor Green }
    else { Write-Warning 'cargo finished but matugen.exe was not found (expected in %USERPROFILE%\.cargo\bin).' }
    $found
}

function Install-FilePilot {
    # Optional. Returns $true if File Pilot is present afterwards.
    param([switch]$Yes, [switch]$NonInteractive)

    $configDir = Join-Path $env:APPDATA 'Voidstar\FilePilot'
    if ((Test-Path -LiteralPath $configDir) -or (Test-WingetPackage -Id 'Voidstar.FilePilot')) {
        Write-Host 'File Pilot: installed' -ForegroundColor Green
        return $true
    }

    $winget = Get-Command 'winget' -ErrorAction SilentlyContinue
    Write-Host 'Optional: File Pilot (https://filepilot.tech) is a fast third-party file manager. It is proprietary software, free during its beta and planned to become a paid license. Wallpaper-changer works without it.'
    if (-not $winget) { Write-Host '  winget is not available; download it from https://filepilot.tech/download if you want it.'; return $false }
    if (-not (Confirm-Choice 'Install File Pilot with winget (Voidstar.FilePilot)?' -Yes:$Yes -NonInteractive:$NonInteractive)) { return $false }

    & $winget.Source install --id Voidstar.FilePilot --exact --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "winget could not install File Pilot (exit $LASTEXITCODE). The official installer is at https://filepilot.tech/download."
        return $false
    }
    Write-Host 'File Pilot installed (the winget package can trail the newest release on the website).' -ForegroundColor Green
    $true
}

Export-ModuleMember -Function *-*
