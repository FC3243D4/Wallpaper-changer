#Requires -Version 7.0
# WallpaperColor.psm1 - accent color of a wallpaper, with the on-disk cache.
# Shared by ColorChooser.ps1 (one image, on demand) and Build-WallpaperCache.ps1
# (the whole library, ahead of time).

Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'WallpaperChanger.Common.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'Matugen.psm1') -DisableNameChecking
if ($IsWindows) { Import-Module (Join-Path $PSScriptRoot 'ImageColor.psm1') -DisableNameChecking }

$script:MinBrightness = 20          # same threshold as the Linux scripts
$script:CanDecodeImages = [bool]$IsWindows      # System.Drawing decoding (tests switch this)
$script:DefaultAccent = '4285f4'                # Material blue: last resort when nothing else works

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

function Get-LiftedColor {
    # Brings a too-dark color up to a usable accent: every channel is scaled so the brightest one
    # reaches MinValue (0-1), which keeps hue and saturation. Colors that are bright enough are
    # returned unchanged.
    param([Parameter(Mandatory)][string]$Hex, [double]$MinValue = 0.6)
    $Hex = ConvertTo-HexColor $Hex
    $c = 0, 2, 4 | ForEach-Object { [Convert]::ToInt32($Hex.Substring($_, 2), 16) / 255.0 }
    $max = ($c | Measure-Object -Maximum).Maximum
    if ($max -ge $MinValue) { return $Hex }
    if ($max -le 0) { $v = [int][Math]::Round($MinValue * 255); return ('{0:x2}{0:x2}{0:x2}' -f $v) }
    $f = $MinValue / $max
    $o = $c | ForEach-Object { [int][Math]::Min(255, [Math]::Round($_ * $f * 255, [MidpointRounding]::AwayFromZero)) }
    '{0:x2}{1:x2}{2:x2}' -f $o[0], $o[1], $o[2]
}

function Get-WallpaperColor {
    # Returns [pscustomobject]@{ Color; Source; CacheFile; Fallback }
    #   Source: 'cache' | 'image' | 'matugen:<index>'                  (normal, cached)
    #           'lifted' | 'last' | 'default'                           (fallbacks, Fallback = $true)
    # A cache entry is only trusted if it is at least as new as the image, so a replaced
    # wallpaper gets a fresh color. When no good color can be found (very dark image and no
    # matugen, undecodable image...) it degrades instead of failing: the dark dominant color is
    # lifted to a usable brightness, else the last accent that was used, else Material blue.
    # Fallback colors are never cached, so the real color is computed once the cause is fixed.
    param([Parameter(Mandatory)][string]$Image, [switch]$Force)

    if (-not (Test-Path -LiteralPath $Image -PathType Leaf)) { throw "Wallpaper not found: $Image" }
    $Image = (Resolve-Path -LiteralPath $Image).Path
    $cacheFile = Get-WallpaperColorCachePath -Image $Image

    if (-not $Force -and (Test-Path -LiteralPath $cacheFile)) {
        $fresh = (Get-Item -LiteralPath $cacheFile).LastWriteTimeUtc -ge (Get-Item -LiteralPath $Image).LastWriteTimeUtc
        $cached = (Get-Content -LiteralPath $cacheFile -TotalCount 1)
        if ($fresh -and $cached -and (Test-HexColor $cached)) {
            return [pscustomobject]@{ Color = (ConvertTo-HexColor $cached); Source = 'cache'; CacheFile = $cacheFile; Fallback = $false }
        }
    }

    $color = $null; $source = $null
    $dominant = $null
    if ($script:CanDecodeImages) { $dominant = Get-ImageDominantColor -Path $Image }
    if ($dominant -and (Get-Brightness $dominant) -ge $script:MinBrightness) { $color = $dominant; $source = 'image' }

    # too dark (or undecodable) -> matugen's own ranked seed colors
    if (-not $color) {
        for ($i = 0; $i -le 4; $i++) {
            $candidate = Get-MatugenSourceColor -ImagePath $Image -Index $i
            if ($candidate -and (Get-Brightness $candidate) -ge $script:MinBrightness) { $color = $candidate; $source = "matugen:$i"; break }
        }
    }
    if ($color) {
        $color = ConvertTo-HexColor $color
        Write-WcFile -Path $cacheFile -Content "$color`n"
        return [pscustomobject]@{ Color = $color; Source = $source; CacheFile = $cacheFile; Fallback = $false }
    }

    # ---- fallbacks (never cached) ----
    if ($dominant) { return [pscustomobject]@{ Color = (Get-LiftedColor -Hex $dominant); Source = 'lifted'; CacheFile = $null; Fallback = $true } }
    $lastFile = (Get-WcPaths).LastAccent
    if (Test-Path -LiteralPath $lastFile) {
        $last = (Get-Content -LiteralPath $lastFile -TotalCount 1)
        if ($last -and (Test-HexColor $last)) { return [pscustomobject]@{ Color = (ConvertTo-HexColor $last); Source = 'last'; CacheFile = $null; Fallback = $true } }
    }
    [pscustomobject]@{ Color = $script:DefaultAccent; Source = 'default'; CacheFile = $null; Fallback = $true }
}

Export-ModuleMember -Function *-*
