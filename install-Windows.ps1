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
.PARAMETER IncludeNsfw         Also sync the bundled NSFW wallpapers (files named nsfw-*). Without it you are asked.
.PARAMETER AspectRatios        Only install these aspect-ratio folders, e.g. -AspectRatios 16-9,21-9 (skips the checklist).
.PARAMETER AllAspectRatios     Install every aspect ratio the repo has (skips the checklist).
.PARAMETER NoStartup           Don't set up the keyboard shortcuts (AutoHotkey Startup shortcut).
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
    [string[]]$AspectRatios,
    [switch]$AllAspectRatios,
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
        elseif ($v -is [array]) { $fwd += "-$k"; $fwd += ($v -join ',') }
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
Import-Module (Join-Path $InstallDir 'lib\InstallerUi.psm1') -Force -DisableNameChecking
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

# File Pilot and AutoHotkey (keyboard shortcuts) are optional.
$null = Install-FilePilot -Yes:$Yes -NonInteractive:$NonInteractive
$ahk = Install-AutoHotkey -Yes:$Yes -NonInteractive:$NonInteractive

$py = Get-Command python -ErrorAction SilentlyContinue
if ($py) {
    & $py.Source -c 'import PyQt6' 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Warn 'PyQt6 missing for the wallpaper picker GUI: python -m pip install PyQt6' }
}
else { Write-Warn 'Python not found - needed only for the wallpaper picker GUI (WallpaperGui.py).' }

# --- 4. wallpapers ---------------------------------------------------------------------------
# Same sync rules as `Install-Linux.sh --update-wallpapers`, scoped to the wallpaper folder
# only: SFW folders are mirrored (files named nsfw-* are never touched), NSFW files are only
# ever added. Like the Linux installer you pick which aspect ratios to install; the ratios of
# your connected monitors (and your previous choice) are pre-ticked.
$wallSrc = @('wallpapers', 'wallpapersDefaultInstall') | ForEach-Object { Join-Path $repo $_ } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if ($wallSrc -and -not $SkipWallpapers -and -not $NonInteractive) {
    # -Yes deliberately does not cover this one: the sync deletes files.
    $answer = Read-Host "Sync this repo's wallpapers into ${WallpaperDir}? Existing SFW files not in the repo are removed from the ratio folders you pick (y/n)"
    if ($answer -eq 'y') {
        $sfwRoot = Join-Path $wallSrc 'sfw'
        $nsfwRoot = Join-Path $wallSrc 'nsfw'
        $available = @(Get-ChildItem -LiteralPath $sfwRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
        if ($available.Count -eq 0) { Write-Warn "No aspect-ratio folders found in $sfwRoot." }
        else {
            $withNsfw = [bool]$IncludeNsfw
            if (-not $withNsfw -and (Test-Path -LiteralPath $nsfwRoot)) { $withNsfw = (Read-Host 'Also copy the NSFW wallpapers? (y/N)') -match '^(y|yes)$' }

            $suggested = @($cfg.aspectRatios | Where-Object { $_ })              # previous choice
            try {
                Import-Module (Join-Path $InstallDir 'lib\Monitors.psm1') -Force -DisableNameChecking
                foreach ($m in (Get-WcMonitors)) {
                    $r = Get-AspectFolder -Width $m.Width -Height $m.Height -Folders $available
                    if ($r) { $suggested += $r }
                }
            }
            catch { }                                                          # no monitor info: fall back to the previous choice / all
            $requested = @($AspectRatios | ForEach-Object { $_ -split '[,\s]+' } | Where-Object { $_ })
            $chosen = @(Select-AspectRatios -Available $available -Requested $requested -All:$AllAspectRatios -Suggested @($suggested | Select-Object -Unique))
            Set-WcConfigValue -Name aspectRatios -Value $chosen

            foreach ($ratio in $chosen) {
                Invoke-Robocopy (Join-Path $sfwRoot $ratio) (Join-Path $WallpaperDir $ratio) @('/MIR', '/XF', 'nsfw-*')
                Write-Step "Synced $ratio wallpapers."
                if ($withNsfw -and (Test-Path -LiteralPath (Join-Path $nsfwRoot $ratio))) {
                    Invoke-Robocopy (Join-Path $nsfwRoot $ratio) (Join-Path $WallpaperDir $ratio) @('/E')
                    Write-Step "Added NSFW $ratio wallpapers."
                }
            }
            $skipped = @($available | Where-Object { $_ -notin $chosen })
            if ($skipped.Count -gt 0) { Write-Host "Not installed: $($skipped -join ', '). Re-run the installer to add them later (folders already on disk are never deleted)." }
            & (Join-Path $InstallDir 'clearCache-Windows.ps1') | Out-Null      # make the changer see the new files
        }
    }
    else { Write-Warn "Skipping wallpaper sync. Put your wallpapers in $WallpaperDir\<aspect-ratio>\ (16-9, 21-9, 32-9, 16-10 ...)." }
}

# --- 5. hotkeys -----------------------------------------------------------------------------------
# AutoHotkey v2 script + a Startup shortcut that launches it with the v2 interpreter at every login.
$startup = [Environment]::GetFolderPath('Startup')
$hotkeyScript = Join-Path $InstallDir 'wallpaperHotkey.ahk'
foreach ($line in (Remove-LegacyHotkey -StartupDir $startup -KeepScript $hotkeyScript)) { Write-Step "Old Ctrl+Alt+W hotkey: $line" }

if (-not $NoStartup) {
    if ($ahk) {
        $lnk = Join-Path $startup 'WallpaperChanger Hotkeys.lnk'
        $sc = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
        $sc.TargetPath = $ahk                                  # explicit v2 interpreter: no dependence on .ahk file association
        $sc.Arguments = '"' + $hotkeyScript + '"'
        $sc.WorkingDirectory = $InstallDir
        $sc.Save()
        Start-Process -FilePath $ahk -ArgumentList ('"' + $hotkeyScript + '"') -WorkingDirectory $InstallDir
        Write-Step 'Hotkeys are active now and start at every login: Win+Shift+W random, Win+Ctrl+Shift+W SFW, Win+Shift+Alt+W NSFW, Win+W picker.'
    }
    else { Write-Warn 'AutoHotkey v2 is not installed, so no keyboard shortcuts were set up. Re-run this installer and accept the AutoHotkey prompt (or use -Yes).' }
}

# --- 6. OpenRGB server --------------------------------------------------------------------------
if ($RegisterOpenRgbServer) { & (Join-Path $InstallDir 'Register-OpenRgbServer.ps1') }
elseif ($openRgb) { Write-Warn "RGB tip: run  pwsh -File `"$InstallDir\Register-OpenRgbServer.ps1`"  once to run OpenRGB elevated at logon, so wallpaper changes need no UAC prompt." }

$legacyDir = Join-Path $env:USERPROFILE 'Documents\wallpaperScripts'
if (Test-Path -LiteralPath $legacyDir) { Write-Warn "The old install in $legacyDir is no longer used - delete it when you like." }

Write-Step "`nDone. Try it:  pwsh -File `"$InstallDir\setRandomWallpaper-WE.ps1`""
