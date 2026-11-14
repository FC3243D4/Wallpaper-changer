#Requires -Version 7.0
<#
.SYNOPSIS
  Clears the wallpaper list cache so newly added wallpapers are picked up.
.PARAMETER All
  Also clear the per-wallpaper accent color cache and thumbnails.
#>
[CmdletBinding()]
param([switch]$All)
Import-Module (Join-Path $PSScriptRoot 'lib\WallpaperChanger.Common.psm1') -DisableNameChecking
$p = Get-WcPaths
$targets = @($p.FileCache, $p.LastWallpaper)
if ($All) { $targets += $p.ColorCache, $p.Thumbnails }
foreach ($t in $targets) {
    if (Test-Path -LiteralPath $t) { Remove-Item -LiteralPath $t -Recurse -Force; Write-Host "Cleared: $t" }
}
Write-Host 'Done.'
