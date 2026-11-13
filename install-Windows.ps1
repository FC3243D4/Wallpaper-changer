<#
.SYNOPSIS
  Installs the Windows side of Wallpaper-changer (Wallpaper Engine + theming pipeline).

.DESCRIPTION
  Run from the repo root:
      powershell.exe -ExecutionPolicy Bypass -File .\install-Windows.ps1
  (it re-launches itself in PowerShell 7 and offers to install it with winget if needed)

  Installs to %LOCALAPPDATA%\WallpaperChanger (scripts, matugen templates, GUI,
  config.json, caches). Re-running updates the scripts and keeps config.json
  and the caches.

.PARAMETER InstallDir          Where to install (default %LOCALAPPDATA%\WallpaperChanger).
.PARAMETER WallpaperDir        Wallpaper library (default %USERPROFILE%\Pictures\wallpapers).
.PARAMETER SkipWallpapers      Don't copy/sync the repo's bundled wallpapers.
.PARAMETER IncludeNsfw         Also sync the bundled NSFW wallpapers (files named nsfw-*).
.PARAMETER NoStartup           Don't create the Startup shortcut for the Ctrl+Alt+W hotkey.
.PARAMETER RegisterOpenRgbServer
                               Also register the elevated OpenRGB server task (one UAC prompt).
.PARAMETER Yes                 Answer yes to the dependency prompts (matugen / Rust / File Pilot installs).
.PARAMETER NonInteractive      Ask nothing and install nothing; only report what is missing.
#>
[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'WallpaperChanger'),
    [string]$WallpaperDir = (Join-Path $env:USERPROFILE 'Pictures\wallpapers'),
    [switch]$SkipWallpapers,
    [switch]$IncludeNsfw,
    [switch]$NoStartup,
    [switch]$RegisterOpenRgbServer,
    [switch]$Yes,
    [switch]$NonInteractive
)

# --- PowerShell 7 guard ----------------------------------------------------------
# This file must stay parseable by Windows PowerShell 5.1 (so `powershell.exe -File install-Windows.ps1`
# works): no #Requires line, no 7-only syntax above this point. It re-launches itself in pwsh.
if ($PSVersionTable.PSVersion.Major -lt 7) {
    $pwshExe = $null
    $found = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($found) { $pwshExe = $found.Source }
    if (-not $pwshExe) {
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        $ask = $false
        if ($winget -and -not $NonInteractive) {
            $ask = $Yes -or ((Read-Host 'PowerShell 7 is required. Install it with winget now? (y/N)') -match '^(y|yes)$')
        }
        if ($ask) {
            & $winget.Source install --id Microsoft.PowerShell --exact --accept-package-agreements --accept-source-agreements
            $candidate = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
            if (Test-Path $candidate) { $pwshExe = $candidate }
        }
    }
    if (-not $pwshExe) { Write-Host 'PowerShell 7 is required: winget install Microsoft.PowerShell' -ForegroundColor Red; exit 1 }
    $fwd = @()
    foreach ($k in $PSBoundParameters.Keys) {
        $v = $PSBoundParameters[$k]
        if ($v -is [System.Management.Automation.SwitchParameter]) { if ($v.IsPresent) { $fwd += "-$k" } }
        else { $fwd += "-$k"; $fwd += [string]$v }
    }
    & $pwshExe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @fwd
    exit $LASTEXITCODE
}

$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'This installer is for Windows. Use Install-Linux.sh on Linux.' }

$repo = $PSScriptRoot
$srcScripts = Join-Path $repo 'script-windows'
$srcSvg = Join-Path $repo 'scripts-linux\themeRefresherSupportScripts\svg'
$srcGui = Join-Path $repo 'scripts-linux\WallpaperGui.py'
foreach ($p in $srcScripts, $srcSvg, $srcGui) { if (-not (Test-Path -LiteralPath $p)) { throw "Missing in repo: $p (run this from the repo root)" } }

function Write-Step([string]$Text) { Write-Host $Text -ForegroundColor Green }
function Write-Warn([string]$Text) { Write-Host $Text -ForegroundColor Yellow }

function Invoke-Robocopy {
    # robocopy exit codes 0-7 are success variants, 8+ are failures.
    param([string]$From, [string]$To, [string[]]$Options)
    & robocopy.exe $From $To @Options /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE): $From -> $To" }
}

# --- 1. install the scripts ------------------------------------------------------
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Invoke-Robocopy $srcScripts $InstallDir @('/E')                         # no purge: keeps config.json + cache
Invoke-Robocopy $srcSvg (Join-Path $InstallDir 'themeRefresherSupportScripts\svg') @('/MIR')
Copy-Item -LiteralPath $srcGui -Destination (Join-Path $InstallDir 'WallpaperGui.py') -Force
Remove-Item -LiteralPath (Join-Path $InstallDir 'getDominantColor.ps1') -ErrorAction SilentlyContinue   # replaced by ColorChooser.ps1
Get-ChildItem -LiteralPath $InstallDir -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
Write-Step "Scripts installed to $InstallDir"

# --- 2. config ----------------------------------------------------------------------------
$env:WALLPAPERCHANGER_HOME = $InstallDir
Import-Module (Join-Path $InstallDir 'lib\WallpaperChanger.Common.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $InstallDir 'lib\Matugen.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $InstallDir 'lib\Dependencies.psm1') -Force -DisableNameChecking
$paths = Get-WcPaths
if (-not (Test-Path -LiteralPath $paths.Config)) {
    Write-WcFile -Path $paths.Config -Content ([ordered]@{ wallpaperDir = $WallpaperDir; refreshMode = 'Full' } | ConvertTo-Json)
    Write-Step "Created $($paths.Config)"
}
$cfg = Get-WcConfig
$WallpaperDir = $cfg.wallpaperDir

# --- 3. dependency report ---------------------------------------------------------------
$we = Get-WallpaperEngineExe -Refresh
if ($we) { Write-Step "Wallpaper Engine: $we" }
else { Write-Warn "Wallpaper Engine was not found (Steam libraries on every drive, uninstall entry and running processes were checked). Start it once and re-run this installer, or set 'wallpaperEngineExe' in $($paths.Config)." }

# matugen is required: offer to build it with cargo (installing Rust first if needed).
$null = Install-Matugen -Yes:$Yes -NonInteractive:$NonInteractive

$openRgb = Get-OpenRgbExe
if ($openRgb) { Write-Step "OpenRGB: $openRgb" } else { Write-Warn 'OpenRGB not found - RGB sync will be skipped (https://openrgb.org).' }

# File Pilot is optional.
$null = Install-FilePilot -Yes:$Yes -NonInteractive:$NonInteractive

$py = Get-Command python -ErrorAction SilentlyContinue
if ($py) {
    & $py.Source -c 'import PyQt6' 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Warn 'PyQt6 missing for the wallpaper picker GUI: python -m pip install PyQt6' }
}
else { Write-Warn 'Python not found - needed only for the wallpaper picker GUI (WallpaperGui.py).' }

# --- 4. wallpapers ---------------------------------------------------------------------------
# Same sync rules as `Install-Linux.sh --update-wallpapers`, scoped to the wallpaper
# folder only: SFW folders are mirrored (files named nsfw-* are never touched), NSFW
# files are only ever added.
$wallSrc = @('wallpapers', 'wallpapersDefaultInstall') | ForEach-Object { Join-Path $repo $_ } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if ($wallSrc -and -not $SkipWallpapers -and -not $NonInteractive) {
    # -Yes deliberately does not cover this one: the sync deletes files.
    $answer = Read-Host "Sync this repo's wallpapers into $WallpaperDir? Existing SFW files not in the repo are removed from those folders (y/n)"
    if ($answer -eq 'y') {
        foreach ($sfw in (Get-ChildItem -LiteralPath (Join-Path $wallSrc 'sfw') -Directory -ErrorAction SilentlyContinue)) {
            Invoke-Robocopy $sfw.FullName (Join-Path $WallpaperDir $sfw.Name) @('/MIR', '/XF', 'nsfw-*')
            Write-Step "Synced $($sfw.Name) wallpapers."
        }
        if ($IncludeNsfw) {
            foreach ($n in (Get-ChildItem -LiteralPath (Join-Path $wallSrc 'nsfw') -Directory -ErrorAction SilentlyContinue)) {
                Invoke-Robocopy $n.FullName (Join-Path $WallpaperDir $n.Name) @('/E')
                Write-Step "Added NSFW $($n.Name) wallpapers."
            }
        }
        & (Join-Path $InstallDir 'clearCache-Windows.ps1') | Out-Null          # make the changer see the new files
    }
    else { Write-Warn "Skipping wallpaper sync. Put your wallpapers in $WallpaperDir\<aspect-ratio>\ (16-9, 21-9, 32-9, 16-10 ...)." }
}

# --- 5. hotkey (Startup shortcut instead of the old hard link) ------------------------------
if (-not $NoStartup) {
    $startup = [Environment]::GetFolderPath('Startup')
    $legacy = Join-Path $startup 'wallpaperHotkey.ahk'
    if (Test-Path -LiteralPath $legacy) { Remove-Item -LiteralPath $legacy -Force; Write-Step 'Removed the old hard-link startup entry.' }
    $lnk = Join-Path $startup 'WallpaperChanger Hotkey.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $sc = $shell.CreateShortcut($lnk)
    $sc.TargetPath = Join-Path $InstallDir 'wallpaperHotkey.ahk'
    $sc.WorkingDirectory = $InstallDir
    $sc.Save()
    Write-Step 'Startup shortcut created (needs AutoHotkey v1.1: https://www.autohotkey.com). Hotkey: Ctrl+Alt+W.'
}

# --- 6. OpenRGB server --------------------------------------------------------------------------
if ($RegisterOpenRgbServer) { & (Join-Path $InstallDir 'Register-OpenRgbServer.ps1') }
elseif ($openRgb) { Write-Warn "RGB tip: run  pwsh -File `"$InstallDir\Register-OpenRgbServer.ps1`"  once to run OpenRGB elevated at logon, so wallpaper changes need no UAC prompt." }

$legacyDir = Join-Path $env:USERPROFILE 'Documents\wallpaperScripts'
if (Test-Path -LiteralPath $legacyDir) { Write-Warn "The old install in $legacyDir is no longer used - delete it when you like." }

Write-Step "`nDone. Try it:  pwsh -File `"$InstallDir\setRandomWallpaper-WE.ps1`""
