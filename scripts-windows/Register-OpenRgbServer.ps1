#Requires -Version 7.0
<#
.SYNOPSIS
  One-time setup: runs `OpenRGB --server` elevated at every logon via a scheduled task.

.DESCRIPTION
  Some hardware (Corsair RAM over SMBus, for example) needs OpenRGB to run as
  administrator. Rather than elevating a user-writable script on every
  wallpaper change, this registers ONE task that starts the OpenRGB executable
  itself with highest privileges at logon. The wallpaper scripts then talk to
  that server as a normal user (RgbApply.ps1): no UAC prompt per change, and no
  admin-run code lives anywhere a non-admin process can modify.

  Shows a UAC prompt once. -Unregister removes the task again.
  The task refuses an OpenRGB.exe outside Program Files (a user-writable binary
  run as admin would be a privilege-escalation hole) unless
  -AllowUserWritablePath is given.
#>
[CmdletBinding()]
param(
    [switch]$Unregister,
    [switch]$AllowUserWritablePath,
    [string]$OpenRgbExe,     # filled in automatically when the script re-launches itself elevated
    [int]$Port,
    [string]$ForUser
)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Windows only.' }
Import-Module (Join-Path $PSScriptRoot 'lib\WallpaperChanger.Common.psm1') -DisableNameChecking

$taskName = 'WallpaperChanger OpenRGB Server'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    # Resolve everything that depends on *this* user's profile first, then go elevated.
    $argList = @('-NoProfile', '-ExecutionPolicy', 'RemoteSigned', '-File', "`"$PSCommandPath`"", '-ForUser', "`"$env:USERDOMAIN\$env:USERNAME`"")
    if ($Unregister) { $argList += '-Unregister' }
    else {
        $exe = if ($OpenRgbExe) { $OpenRgbExe } else { Get-OpenRgbExe }
        if (-not $exe) { throw 'OpenRGB.exe not found. Install OpenRGB or set "openRgbExe" in config.json first.' }
        $argList += @('-OpenRgbExe', "`"$exe`"", '-Port', [int](Get-WcConfig).openRgbPort)
    }
    if ($AllowUserWritablePath) { $argList += '-AllowUserWritablePath' }
    Write-Host 'Requesting administrator rights (one-time)...'
    Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $argList -Verb RunAs -Wait
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($Unregister) { Write-Host $(if ($task) { 'Task is still registered.' } else { 'Task removed.' }) }
    else { Write-Host $(if ($task) { "Task '$taskName' is registered; OpenRGB server will start at every logon." } else { 'Task was not registered.' }) }
    return
}

# ---- elevated from here on --------------------------------------------------------
$user = if ($ForUser) { $ForUser } else { "$env:USERDOMAIN\$env:USERNAME" }

if ($Unregister) {
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "Removed scheduled task '$taskName'."
    }
    else { Write-Host "Task '$taskName' does not exist." }
    return
}

if (-not $OpenRgbExe -or -not (Test-Path -LiteralPath $OpenRgbExe -PathType Leaf)) { throw "OpenRGB.exe not found: '$OpenRgbExe'" }
$exe = (Resolve-Path -LiteralPath $OpenRgbExe).Path
$protected = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
if (-not $AllowUserWritablePath -and -not ($protected | Where-Object { $exe.StartsWith($_.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) })) {
    throw "Refusing to run '$exe' as administrator: it is outside Program Files, so a non-admin process could replace it and gain admin rights. Install OpenRGB system-wide, or pass -AllowUserWritablePath if you accept that risk."
}
if (-not $Port) { $Port = 6742 }

$action = New-ScheduledTaskAction -Execute $exe -Argument "--server --startminimized --server-port $Port" -WorkingDirectory (Split-Path -Parent $exe)
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Host "Registered '$taskName' for $user (runs: $exe --server on port $Port)."
if (-not (Get-Process -Name 'OpenRGB' -ErrorAction SilentlyContinue)) { Start-ScheduledTask -TaskName $taskName; Write-Host 'Started it now.' }
else { Write-Host 'OpenRGB is already running; close it and sign out/in (or start the task) so the elevated server takes over.' }
