#Requires -Version 7.0
<#
.SYNOPSIS
  Re-themes the desktop apps from the current wallpaper's accent color.

.DESCRIPTION
  Port of ThemeRefresher.sh for Windows.
    Full     pick color -> close running apps -> RGB + patchers + matugen in
             parallel -> relaunch the apps that were closed -> Spicetify
    Softrun  same, but never closes or relaunches anything
    Rgb      only recolor the RGB devices

.PARAMETER Color   Use this hex color instead of choosing one from the wallpaper.
.PARAMETER Image   Image to take the color from (default: current_wallpaper.txt).
#>
[CmdletBinding()]
param(
    [ValidateSet('Full', 'Softrun', 'Rgb')][string]$Mode = 'Full',
    [string]$Color,
    [string]$Image
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Import-Module (Join-Path $root 'lib\WallpaperChanger.Common.psm1') -DisableNameChecking
Import-Module (Join-Path $root 'lib\Matugen.psm1') -DisableNameChecking
. (Join-Path $root 'themeRefresherSupportScripts\AppRestarter.ps1')

$support = Join-Path $root 'themeRefresherSupportScripts'
$patchers = Join-Path $support 'appPatchers'

# One refresh at a time: rapid hotkey presses must not interleave app restarts.
$mutex = [System.Threading.Mutex]::new($false, 'Local\WallpaperChanger.ThemeRefresher')
if (-not $mutex.WaitOne(0)) { Write-Host 'Another theme refresh is already running, skipping this one.'; return }

try {
    if ($IsWindows -and ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning 'Running elevated: apps relaunched by this script would start with admin rights. Run it from a normal (non-admin) shell.'
    }
    $total = [System.Diagnostics.Stopwatch]::StartNew()
    $hadRestart = $false

    # --- 1. color -----------------------------------------------------------
    if ($Color) { $hex = ConvertTo-HexColor $Color }
    else {
        $chooserArgs = @{}
        if ($Image) { $chooserArgs.Image = $Image }
        $out = Invoke-WcTimed 'color_chooser' { & (Join-Path $support 'ColorChooser.ps1') @chooserArgs }
        $hex = ConvertTo-HexColor (@($out)[-1])
    }
    Write-Host "Accent color: #$hex"

    if ($Mode -eq 'Rgb') {
        Invoke-WcTimed 'rgb_apply' { & (Join-Path $support 'RgbApply.ps1') -Color $hex } | Write-Host
        return
    }

    # --- 2-5. close apps, patch, relaunch ---------------------------------------
    # Once the apps are closed they MUST come back, whatever happens in between (a throwing
    # patcher, Ctrl+C, a missing module...), so everything between stop and relaunch is in a
    # try/finally whose finally block always waits for the stops and relaunches.
    $failed = @()
    $jobs = [System.Collections.Generic.List[object]]::new()
    $matugenJob = $null
    try {
        # close apps that cache their theme
        if ($Mode -eq 'Full') { $hadRestart = $true; Invoke-WcTimed 'app_stop_begin' { Start-AppStopPhase } }

        # group A: independent of matugen
        $a = @{ Color = $hex }
        $jobs.Add((Start-WcPatcherJob -Label 'rgb' -Script (Join-Path $support 'RgbApply.ps1') -Arguments $a))
        $matugenJob = Start-WcPatcherJob -Label 'matugen' -Script (Join-Path $support 'MatugenRun.ps1') -Arguments $a
        $appData = $env:APPDATA
        if (Test-Path -LiteralPath (Join-Path $appData 'Ferdium\recipes')) { $jobs.Add((Start-WcPatcherJob -Label 'ferdium' -Script (Join-Path $patchers 'FerdiumPatcher.ps1') -Arguments $a)) }
        if (Test-Path -LiteralPath (Join-Path $appData 'vesktop')) { $jobs.Add((Start-WcPatcherJob -Label 'vesktop' -Script (Join-Path $patchers 'DiscordPatcher.ps1') -Arguments $a)) }
        $moz = @{ Firefox = 'Mozilla\Firefox\profiles.ini'; Zen = 'zen\profiles.ini'; Thunderbird = 'Thunderbird\profiles.ini' }
        foreach ($app in $moz.Keys) {
            $present = Test-Path -LiteralPath (Join-Path $appData $moz[$app])
            if ($app -eq 'Thunderbird' -and -not $present) { $present = Test-Path -LiteralPath (Join-Path $appData 'Betterbird\profiles.ini') }
            if ($present) { $jobs.Add((Start-WcPatcherJob -Label $app.ToLower() -Script (Join-Path $patchers 'MozillaPatcher.ps1') -Arguments @{ Color = $hex; App = $app })) }
        }

        # group B: needs the files matugen renders
        $failed = @(Wait-WcPatcherJobs @($matugenJob))
        $matugenJob = $null
        if ($failed.Count -gt 0) { Write-Warning 'matugen failed; patchers that read its output may fall back or fail.' }
        if (Test-Path -LiteralPath (Join-Path $appData 'Code\User\settings.json')) { $jobs.Add((Start-WcPatcherJob -Label 'vscode' -Script (Join-Path $patchers 'VscodePatcher.ps1') -Arguments $a)) }
        if (Get-SourceGitDir) { $jobs.Add((Start-WcPatcherJob -Label 'sourcegit' -Script (Join-Path $patchers 'SourceGitPatcher.ps1') -Arguments $a)) }

        $failed += @(Wait-WcPatcherJobs $jobs.ToArray())
        $jobs.Clear()
    }
    finally {
        # jobs still alive after an error must not keep writing while the apps start again
        foreach ($j in @($matugenJob) + $jobs.ToArray()) {
            if ($j -and $j.State -in 'Running', 'NotStarted') { Stop-Job -Job $j -ErrorAction SilentlyContinue; Remove-Job -Job $j -Force -ErrorAction SilentlyContinue }
        }
        if ($hadRestart) {
            try { Invoke-WcTimed 'app_stop_wait' { Wait-AppStopPhase } }
            catch { Write-Warning "Waiting for the apps to close failed: $($_.Exception.Message)" }
            try { Invoke-WcTimed 'app_restart' { Start-AppRestartPhase } }
            catch { Write-Warning "Relaunching the apps failed: $($_.Exception.Message)" }
        }
    }

    if ($hadRestart) {
        Invoke-WcTimed 'spicetify' { & (Join-Path $patchers 'SpicetifyRestarter.ps1') | ForEach-Object { Write-Host "[spicetify] $_" } }
    }

    [Console]::Error.WriteLine(('[timing] total: {0:N3}s' -f $total.Elapsed.TotalSeconds))
    if ($failed.Count -gt 0) { Write-Warning ("Finished with errors in: " + (($failed | Select-Object -Unique) -join ', ')) }
}
finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
