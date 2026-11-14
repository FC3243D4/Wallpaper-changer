#Requires -Version 7.0
<#
.SYNOPSIS
  Applies the accent color (saturation-boosted) to OpenRGB devices.

.DESCRIPTION
  Port of RgbApply.sh (OpenRGB part; ratbagctl has no Windows equivalent).

  OpenRGB needs administrator rights for some hardware (Corsair RAM over SMBus).
  Instead of elevating on every wallpaper change, the recommended setup is a
  scheduled task that runs `OpenRGB --server` elevated once at logon
  (Register-OpenRgbServer.ps1). This script then talks to that server as a
  normal, unelevated client - no UAC prompt, and nothing user-writable is ever
  executed with admin rights. If no server is listening it falls back to the
  old behavior: launch OpenRGB elevated (one UAC prompt) just for this call.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Color)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\lib\WallpaperChanger.Common.psm1') -DisableNameChecking

$cfg = Get-WcConfig
if (-not $cfg.rgbEnabled) { Write-Output 'RGB disabled in config.json, skipping'; return }

$hex = ConvertTo-HexColor $Color
$boost = Get-SaturationBoostedColor -Hex $hex
if ($boost.Changed) { Write-Output ("RGB: saturation {0:N2} -> 0.80 ({1} -> {2})" -f $boost.Saturation, $hex, $boost.Hex) }
else { Write-Output "RGB: keeping $hex (saturation $('{0:N2}' -f $boost.Saturation))" }
$out = $boost.Hex.ToUpperInvariant()

$exe = Get-OpenRgbExe
if (-not $exe) { Write-Output 'OpenRGB not found (set openRgbExe in config.json), skipping RGB'; return }
$port = [int]$cfg.openRgbPort

function Test-LocalPort {
    param([int]$Port, [int]$TimeoutMs = 400)
    $client = [System.Net.Sockets.TcpClient]::new()
    try { $client.ConnectAsync('127.0.0.1', $Port).Wait($TimeoutMs) -and $client.Connected }
    catch { $false }
    finally { $client.Dispose() }
}

if (Test-LocalPort -Port $port) {
    & $exe --client "127.0.0.1:$port" --color $out 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "OpenRGB client exited with $LASTEXITCODE" }
    Write-Output "RGB applied via OpenRGB server on port ${port}: $out"
}
else {
    Write-Output "No OpenRGB server on port $port - falling back to an elevated one-shot (UAC prompt). Run Register-OpenRgbServer.ps1 once to avoid this."
    Start-Process -FilePath $exe -ArgumentList @('--color', $out) -Verb RunAs | Out-Null
    Write-Output "RGB applied via elevated OpenRGB: $out"
}
