#Requires -Version 7.0
<#
.SYNOPSIS
  Picks the accent seed color for the current wallpaper and prints it as 6 hex digits.

.DESCRIPTION
  Port of ColorChooser.sh: cached color if there is one, otherwise the dominant color of
  the image, otherwise (too dark) matugen's own seed candidates; the result is cached.
  The logic lives in lib\WallpaperColor.psm1 so Build-WallpaperCache.ps1 can fill the
  cache for the whole library ahead of time.
  Logs go to the information stream; ONLY the color is written to the output stream, so
  `$c = ./ColorChooser.ps1` captures just the color.

.PARAMETER Image
  Image to analyse. Default: the path in current_wallpaper.txt.
#>
[CmdletBinding()]
param([string]$Image)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\lib\WallpaperChanger.Common.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot '..\lib\WallpaperColor.psm1') -DisableNameChecking

if (-not $Image) {
    $current = (Get-WcPaths).CurrentWallpaper
    if (-not (Test-Path -LiteralPath $current)) { throw "No wallpaper given and $current does not exist." }
    $Image = (Get-Content -LiteralPath $current -TotalCount 1).Trim()
}

$result = Get-WallpaperColor -Image $Image
switch -Wildcard ($result.Source) {
    'cache' { Write-Host "Using cached color for $(Split-Path -Leaf $Image)" }
    'image' { Write-Host "Dominant color: #$($result.Color)" }
    'matugen:*' { Write-Host "Using matugen seed #$($result.Source.Split(':')[1]): #$($result.Color)" }
}
Write-Output $result.Color
