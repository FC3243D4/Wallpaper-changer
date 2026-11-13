#Requires -Version 7.0
# ImageColor.psm1 (Windows only)
# Decodes an image with System.Drawing and hands a small BGRA buffer to
# Get-DominantColorFromPixels. Kept in its own module so the rest of the
# pipeline doesn't touch System.Drawing (and can be unit-tested on any OS).

Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'WallpaperChanger.Common.psm1') -DisableNameChecking

function Get-ImageDominantColor {
    # Returns a 6-digit hex string, or $null if the image can't be decoded
    # (System.Drawing has no WebP support, for instance) or has no usable pixels.
    param([Parameter(Mandatory)][string]$Path, [int]$MaxSide = 96)
    try {
        Add-Type -AssemblyName System.Drawing
        $img = [System.Drawing.Image]::FromFile($Path)
        try {
            $scale = [Math]::Min(1.0, $MaxSide / [Math]::Max($img.Width, $img.Height))
            $w = [Math]::Max(1, [int]($img.Width * $scale))
            $h = [Math]::Max(1, [int]($img.Height * $scale))
            $bmp = [System.Drawing.Bitmap]::new($w, $h, 'Format32bppArgb')
            try {
                $g = [System.Drawing.Graphics]::FromImage($bmp)
                $g.InterpolationMode = 'HighQualityBilinear'
                $g.DrawImage($img, 0, 0, $w, $h)
                $g.Dispose()
                $rect = [System.Drawing.Rectangle]::new(0, 0, $w, $h)
                $data = $bmp.LockBits($rect, 'ReadOnly', 'Format32bppArgb')
                $bytes = [byte[]]::new([Math]::Abs($data.Stride) * $h)
                [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
                $bmp.UnlockBits($data)
                return Get-DominantColorFromPixels -Bgra $bytes
            }
            finally { $bmp.Dispose() }
        }
        finally { $img.Dispose() }
    }
    catch {
        Write-Host "Could not decode image directly ($($_.Exception.Message))."
        return $null
    }
}

Export-ModuleMember -Function *-*
