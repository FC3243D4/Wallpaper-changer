#Requires -Version 7.0
<#
.SYNOPSIS
  Picks the accent seed color for the current wallpaper and prints it as 6 hex digits.

.DESCRIPTION
  Port of ColorChooser.sh:
    1. use the cached color for this wallpaper if there is one;
    2. otherwise take the dominant color of the image (own histogram-based
       extraction, see Get-DominantColorFromPixels);
    3. if that is too dark to be a usable accent, ask matugen for its own
       ranked seed colors (indices 0-4) and take the first bright enough one;
    4. cache the result.
  Logs go to the information stream; ONLY the color is written to the output
  stream, so `$c = ./ColorChooser.ps1` captures just the color.

.PARAMETER Image
  Image to analyse. Default: the path in current_wallpaper.txt.
#>
[CmdletBinding()]
param([string]$Image)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\lib\WallpaperChanger.Common.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot '..\lib\Matugen.psm1') -DisableNameChecking

$minBrightness = 20          # same threshold as the Linux script
$paths = Get-WcPaths
$cfg = Get-WcConfig

if (-not $Image) {
    if (-not (Test-Path -LiteralPath $paths.CurrentWallpaper)) { throw "No wallpaper given and $($paths.CurrentWallpaper) does not exist." }
    $Image = (Get-Content -LiteralPath $paths.CurrentWallpaper -TotalCount 1).Trim()
}
if (-not (Test-Path -LiteralPath $Image -PathType Leaf)) { throw "Wallpaper not found: $Image" }
$Image = (Resolve-Path -LiteralPath $Image).Path

# --- cache location -------------------------------------------------------
# Wallpapers inside the library are keyed by "series\file" (ratio folder
# stripped, so every aspect version shares one entry, like on Linux);
# anything else by a hash of its full path.
$base = [System.IO.Path]::GetFullPath($cfg.wallpaperDir).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
if ($Image.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) {
    $rel = $Image.Substring($base.Length)
    $parts = $rel -split '[\\/]', 2
    $key = if ($parts.Count -eq 2) { $parts[1] } else { $rel }
}
else {
    $sha = [System.Security.Cryptography.SHA1]::HashData([System.Text.Encoding]::UTF8.GetBytes($Image.ToLowerInvariant()))
    $key = '_external\' + [Convert]::ToHexString($sha).ToLowerInvariant() + '.img'
}
$cacheFile = Join-Path $paths.ColorCache ($key + '.color')

if (Test-Path -LiteralPath $cacheFile) {
    $cached = (Get-Content -LiteralPath $cacheFile -TotalCount 1).Trim()
    if (Test-HexColor $cached) {
        Write-Host "Using cached color for $key"
        Write-Output (ConvertTo-HexColor $cached)
        return
    }
    Write-Host "Ignoring corrupt cache entry $cacheFile"
}

# --- 1. dominant color of the image --------------------------------------
if ($IsWindows) { Import-Module (Join-Path $PSScriptRoot '..\lib\ImageColor.psm1') -DisableNameChecking }

$color = if ($IsWindows) { Get-ImageDominantColor -Path $Image } else { $null }
if ($color) { Write-Host "Dominant color: #$color (brightness $(Get-Brightness $color))" }

# --- 2. too dark / failed -> matugen's own seed candidates ------------------
if (-not $color -or (Get-Brightness $color) -lt $minBrightness) {
    if ($color) { Write-Host "Dominant color too dark, asking matugen for alternatives..." }
    $color = $null
    for ($i = 0; $i -le 4; $i++) {
        $candidate = Get-MatugenSourceColor -ImagePath $Image -Index $i
        if (-not $candidate) { continue }
        if ((Get-Brightness $candidate) -ge $minBrightness) {
            $color = $candidate
            Write-Host "Using matugen seed #${i}: #${color}"
            break
        }
    }
}

if (-not $color) { throw "Could not determine an accent color for $Image (is matugen installed?)" }
$color = ConvertTo-HexColor $color

Write-WcFile -Path $cacheFile -Content "$color`n"
Write-Output $color
