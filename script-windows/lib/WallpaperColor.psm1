#Requires -Version 7.0
# WallpaperColor.psm1 - accent color of a wallpaper, with the on-disk cache.
# Shared by ColorChooser.ps1 (one image, on demand) and Build-WallpaperCache.ps1
# (the whole library, ahead of time).

Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'WallpaperChanger.Common.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'Matugen.psm1') -DisableNameChecking
if ($IsWindows) { Import-Module (Join-Path $PSScriptRoot 'ImageColor.psm1') -DisableNameChecking }

$script:MinBrightness = 20          # same threshold as the Linux scripts

function Get-WallpaperColorCachePath {
    # Wallpapers inside the library are keyed by "series\file" (ratio folder stripped, so
    # every aspect version shares one entry, like on Linux); anything else by a hash of
    # its full path.
    param([Parameter(Mandatory)][string]$Image)
    $paths = Get-WcPaths
    $cfg = Get-WcConfig
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
    Join-Path $paths.ColorCache ($key + '.color')
}

function Get-WallpaperColor {
    # Returns [pscustomobject]@{ Color; Source; CacheFile }
    #   Source: 'cache' | 'image' | 'matugen:<index>'
    # A cache entry is only trusted if it is at least as new as the image, so a replaced
    # wallpaper gets a fresh color. Throws if no color could be determined.
    param([Parameter(Mandatory)][string]$Image, [switch]$Force)

    if (-not (Test-Path -LiteralPath $Image -PathType Leaf)) { throw "Wallpaper not found: $Image" }
    $Image = (Resolve-Path -LiteralPath $Image).Path
    $cacheFile = Get-WallpaperColorCachePath -Image $Image

    if (-not $Force -and (Test-Path -LiteralPath $cacheFile)) {
        $fresh = (Get-Item -LiteralPath $cacheFile).LastWriteTimeUtc -ge (Get-Item -LiteralPath $Image).LastWriteTimeUtc
        $cached = (Get-Content -LiteralPath $cacheFile -TotalCount 1)
        if ($fresh -and $cached -and (Test-HexColor $cached)) {
            return [pscustomobject]@{ Color = (ConvertTo-HexColor $cached); Source = 'cache'; CacheFile = $cacheFile }
        }
    }

    $color = $null; $source = $null
    if ($IsWindows) { $color = Get-ImageDominantColor -Path $Image; if ($color) { $source = 'image' } }

    # too dark (or undecodable) -> matugen's own ranked seed colors
    if (-not $color -or (Get-Brightness $color) -lt $script:MinBrightness) {
        $color = $null
        for ($i = 0; $i -le 4; $i++) {
            $candidate = Get-MatugenSourceColor -ImagePath $Image -Index $i
            if ($candidate -and (Get-Brightness $candidate) -ge $script:MinBrightness) { $color = $candidate; $source = "matugen:$i"; break }
        }
    }
    if (-not $color) { throw "Could not determine an accent color for $Image (is matugen installed?)" }
    $color = ConvertTo-HexColor $color
    Write-WcFile -Path $cacheFile -Content "$color`n"
    [pscustomobject]@{ Color = $color; Source = $source; CacheFile = $cacheFile }
}

Export-ModuleMember -Function *-*
