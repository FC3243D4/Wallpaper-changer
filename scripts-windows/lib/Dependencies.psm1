#Requires -Version 7.0
# Dependencies.psm1
# Checks for, and (after asking) installs, the tools the Windows pipeline uses.
#
#   Install-Matugen   required for theming. Upstream publishes no Windows
#                     binaries (and I found no winget/scoop package), so it is
#                     built from source with `cargo install matugen --locked`;
#                     if Rust is missing, rustup can be installed via winget first.
#   Install-FilePilot optional third-party file manager (winget: Voidstar.FilePilot).
#   Install-AutoHotkey optional, for the keyboard shortcuts (winget: AutoHotkey.AutoHotkey, v2).
#   Install-PythonEnv  Python + PyQt6 for the picker GUI and thumbnails: finds a working interpreter
#                      (skipping the Microsoft Store stub), offers to install Python (winget:
#                      Python.Python.3.13) and to create a private venv with PyQt6 in it.
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

function Find-AutoHotkey {
    # Path to the AutoHotkey v2 interpreter, or $null.
    $cands = @()
    foreach ($base in @($env:ProgramFiles, (Join-Path $env:LOCALAPPDATA 'Programs'))) {
        if ($base) { $cands += (Join-Path $base 'AutoHotkey\v2\AutoHotkey64.exe'), (Join-Path $base 'AutoHotkey\v2\AutoHotkey32.exe') }
    }
    $cmd = Get-Command 'AutoHotkey64.exe', 'AutoHotkey.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { $cands = @($cmd.Source) + $cands }
    $cands | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
}

function Install-AutoHotkey {
    # Optional. Returns the interpreter path, or $null if it is still missing.
    param([switch]$Yes, [switch]$NonInteractive)

    $existing = Find-AutoHotkey
    if ($existing) { Write-Host "AutoHotkey v2: $existing" -ForegroundColor Green; return $existing }

    $winget = Get-Command 'winget' -ErrorAction SilentlyContinue
    Write-Host 'Optional: AutoHotkey v2 provides the keyboard shortcuts (Win+Shift+W, Win+W, ...).'
    if (-not $winget) { Write-Host '  winget is not available; get AutoHotkey v2 from https://www.autohotkey.com/download/'; return $null }
    if (-not (Confirm-Choice 'Install AutoHotkey v2 with winget (AutoHotkey.AutoHotkey)?' -Yes:$Yes -NonInteractive:$NonInteractive)) { return $null }

    & $winget.Source install --id AutoHotkey.AutoHotkey --exact --accept-package-agreements --accept-source-agreements
    $found = Find-AutoHotkey
    if ($found) { Write-Host "AutoHotkey v2 installed: $found" -ForegroundColor Green }
    else { Write-Warning 'winget finished but AutoHotkey v2 was not found; re-run this installer after it appears.' }
    $found
}

function Install-PythonEnv {
    # Makes sure there is a Python that can import PyQt6, and records it in config.json
    # (pythonExe / pythonwExe) for the hotkey, the cache builder and the installer.
    # Returns the Find-Python result, or $null if it could not be completed.
    param([switch]$Yes, [switch]$NonInteractive)

    $save = {
        param($found)
        Set-WcConfigValue -Name pythonExe -Value $found.Exe
        Set-WcConfigValue -Name pythonwExe -Value $found.Pythonw
    }

    $ready = Find-Python -RequirePyQt6
    if ($ready) {
        Write-Host "Python $($ready.Version) with PyQt6: $($ready.Exe)" -ForegroundColor Green
        & $save $ready
        return $ready
    }

    # Is there a Python at all (any, without PyQt6)?
    $base = Find-Python
    if (-not $base) {
        Write-Host 'No usable Python 3.9+ was found (the Microsoft Store python.exe stub does not count). It is needed for the wallpaper picker and thumbnails.' -ForegroundColor Yellow
        $winget = Get-Command 'winget' -ErrorAction SilentlyContinue
        if ($winget -and (Confirm-Choice 'Install Python 3.13 with winget (Python.Python.3.13, per-user, added to PATH)?' -Yes:$Yes -NonInteractive:$NonInteractive)) {
            & $winget.Source install --id Python.Python.3.13 --exact --scope user --accept-package-agreements --accept-source-agreements
            $base = Find-Python          # also looks in %LOCALAPPDATA%\Programs\Python, so a fresh install is found before PATH refreshes
            if (-not $base) { Write-Warning 'Python was installed but could not be located yet. Open a new terminal and re-run this installer.' }
        }
        if (-not $base) {
            Write-Host '  Install Python from https://www.python.org/downloads/ (tick "Add python.exe to PATH") and re-run this installer.' -ForegroundColor Yellow
            return $null
        }
    }

    $venv = Join-Path (Get-WcPaths).Root 'venv'
    if (-not (Confirm-Choice "Create a private Python environment in $venv and install PyQt6 into it (a download of roughly 100 MB; nothing is changed in your system Python)?" -Yes:$Yes -NonInteractive:$NonInteractive)) {
        Write-Host '  Skipped. The picker (Win+W) and thumbnails need it: python -m pip install PyQt6' -ForegroundColor Yellow
        return $null
    }
    & $base.Exe -m venv $venv
    $venvPy = if ($IsWindows) { Join-Path $venv 'Scripts\python.exe' } else { Join-Path $venv 'bin/python' }
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $venvPy)) { Write-Warning "Could not create the virtual environment in $venv"; return $null }
    & $venvPy -m pip install --disable-pip-version-check PyQt6
    if ($LASTEXITCODE -ne 0) { Write-Warning "pip could not install PyQt6 (exit $LASTEXITCODE). Check your internet connection and re-run this installer."; return $null }

    $done = Find-Python -RequirePyQt6
    if ($done) { Write-Host "Python $($done.Version) with PyQt6: $($done.Exe)" -ForegroundColor Green; & $save $done }
    else { Write-Warning 'PyQt6 was installed but cannot be imported. Run: python -c "import PyQt6.QtGui" to see why.' }
    $done
}

Export-ModuleMember -Function *-*
