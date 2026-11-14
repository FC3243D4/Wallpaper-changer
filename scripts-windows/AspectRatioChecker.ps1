#Requires -Version 7.0
<#
.SYNOPSIS
  Prints the wallpaper folder (with trailing separator) whose aspect ratio is closest to a resolution.
.EXAMPLE
  ./AspectRatioChecker.ps1 3440x1440      # -> C:\Users\me\Pictures\wallpapers\21-9\
.NOTES
  Port of AspectRatioChecker.sh; the folders are discovered on disk, so any
  "W-H" folder you add under the wallpaper directory is considered.
#>
[CmdletBinding()]
param([Parameter(Mandatory, Position = 0)][ValidatePattern('^\d+x\d+$')][string]$Resolution)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\WallpaperChanger.Common.psm1') -DisableNameChecking
$base = (Get-WcConfig).wallpaperDir
$w, $h = $Resolution -split 'x' | ForEach-Object { [int]$_ }
$folders = @(Get-ChildItem -LiteralPath $base -Directory -ErrorAction Stop | Where-Object Name -Match '^\d+-\d+' | ForEach-Object Name)
if ($folders.Count -eq 0) { throw "No aspect-ratio folders (e.g. 16-9) found in $base" }
$best = Get-AspectFolder -Width $w -Height $h -Folders $folders
Write-Output ((Join-Path $base $best) + [System.IO.Path]::DirectorySeparatorChar)
