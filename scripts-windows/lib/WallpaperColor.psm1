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

function Get-ImageQuantizedColors {
    # The image's two main colors, most populated first, as 6-digit hex strings. Windows
    # counterpart of the "-scale 50x50 -colors 2 histogram" step of the Linux scripts: the image
    # is scaled to 50x50 and split into two clusters (2-means, seeded with the darkest and the
    # brightest pixel). Finds the usable color of images whose dominant color is too dark, e.g.
    # white line art on black. Returns nothing if the image can't be decoded.
    param([Parameter(Mandatory)][string]$Path)
    if (-not $script:CanDecodeImages) { return }
    try {
        Add-Type -AssemblyName System.Drawing
        $size = 50
        $src = [System.Drawing.Image]::FromFile($Path)
        $bmp = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppRgb)
        try {
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
                $g.DrawImage($src, 0, 0, $size, $size)
            }
            finally { $g.Dispose() }
            $rect = [System.Drawing.Rectangle]::new(0, 0, $size, $size)
            $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppRgb)
            try {
                $stride = $data.Stride
                $bytes = [byte[]]::new($stride * $size)
                [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
            }
            finally { $bmp.UnlockBits($data) }
        }
        finally { $src.Dispose(); $bmp.Dispose() }

        # pixels (memory order is B, G, R, X)
        $n = $size * $size
        $pr = [int[]]::new($n); $pg = [int[]]::new($n); $pb = [int[]]::new($n)
        $iMin = 0; $iMax = 0; $lMin = [int]::MaxValue; $lMax = -1
        for ($y = 0; $y -lt $size; $y++) {
            for ($x = 0; $x -lt $size; $x++) {
                $p = $y * $size + $x
                $o = $y * $stride + $x * 4
                $pb[$p] = $bytes[$o]; $pg[$p] = $bytes[$o + 1]; $pr[$p] = $bytes[$o + 2]
                $l = 299 * $pr[$p] + 587 * $pg[$p] + 114 * $pb[$p]
                if ($l -lt $lMin) { $lMin = $l; $iMin = $p }
                if ($l -gt $lMax) { $lMax = $l; $iMax = $p }
            }
        }

        # 2-means
        $c = @(
            @([double]$pr[$iMin], [double]$pg[$iMin], [double]$pb[$iMin]),
            @([double]$pr[$iMax], [double]$pg[$iMax], [double]$pb[$iMax])
        )
        $count = @(0, 0)
        for ($iter = 0; $iter -lt 8; $iter++) {
            $sum = @(@(0.0, 0.0, 0.0), @(0.0, 0.0, 0.0))
            $count = @(0, 0)
            for ($p = 0; $p -lt $n; $p++) {
                $d0 = [Math]::Pow($pr[$p] - $c[0][0], 2) + [Math]::Pow($pg[$p] - $c[0][1], 2) + [Math]::Pow($pb[$p] - $c[0][2], 2)
                $d1 = [Math]::Pow($pr[$p] - $c[1][0], 2) + [Math]::Pow($pg[$p] - $c[1][1], 2) + [Math]::Pow($pb[$p] - $c[1][2], 2)
                $k = if ($d1 -lt $d0) { 1 } else { 0 }
                $sum[$k][0] += $pr[$p]; $sum[$k][1] += $pg[$p]; $sum[$k][2] += $pb[$p]
                $count[$k]++
            }
            foreach ($k in 0, 1) {
                if ($count[$k] -gt 0) { $c[$k] = @($sum[$k][0] / $count[$k], $sum[$k][1] / $count[$k], $sum[$k][2] / $count[$k]) }
            }
        }

        0, 1 | Where-Object { $count[$_] -gt 0 } | Sort-Object { $count[$_] } -Descending | ForEach-Object {
            $v = $c[$_] | ForEach-Object { [int][Math]::Round($_, [MidpointRounding]::AwayFromZero) }
            '{0:x2}{1:x2}{2:x2}' -f $v[0], $v[1], $v[2]
        }
    }
    catch { Write-Verbose "Get-ImageQuantizedColors failed for ${Path}: $($_.Exception.Message)" }
}

function Get-WallpaperColor {
    # Returns [pscustomobject]@{ Color; Source; CacheFile; Fallback }
    #   Source: 'cache' | 'image' | 'quantized' | 'matugen:<index>'    (normal, cached)
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

    # dominant color too dark -> the image's other main color (white line art on black has a
    # dark dominant color but a perfectly usable light one), most populated first
    if (-not $color -and $script:CanDecodeImages) {
        foreach ($q in @(Get-ImageQuantizedColors -Path $Image)) {
            if ((Get-Brightness $q) -ge $script:MinBrightness) { $color = $q; $source = 'quantized'; break }
        }
    }

    # still nothing -> matugen's own ranked seed colors (valid indexes are 0..3)
    if (-not $color) {
        for ($i = 0; $i -le 3; $i++) {
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
