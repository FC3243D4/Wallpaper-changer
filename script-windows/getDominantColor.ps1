param(
    [string]$imagePath,
    [string]$openrgbExe = "C:\Program Files\OpenRGB\OpenRGB.exe",
    [double]$minSaturation = 0.80,    # 0.0 - 1.0, target floor for boosted colors
    [double]$ignoreSaturation = 0.15  # 0.0 - 1.0, colors below this are treated as
                                      # intentional white/near-white and left untouched
)

Add-Type -AssemblyName System.Drawing

# -------------------------
# Near-white / low-saturation correction
# -------------------------
# Pastel dominant colors (low saturation) read as washed-out/white on cheap
# LED strips no matter which channels are numerically high. Convert to HSV
# and, if saturation is between $ignoreSaturation and $minSaturation, raise
# it to $minSaturation while keeping hue and value (brightness) unchanged.
# Colors already at or above the floor, and true grays/whites/blacks
# (saturation below $ignoreSaturation), are left untouched.
function Get-SaturationBoostedColor {
    param(
        [int]$R,
        [int]$G,
        [int]$B,
        [double]$MinSaturation,
        [double]$IgnoreSaturation
    )

    $rn = $R / 255.0
    $gn = $G / 255.0
    $bn = $B / 255.0

    $max = [Math]::Max($rn, [Math]::Max($gn, $bn))
    $min = [Math]::Min($rn, [Math]::Min($gn, $bn))
    $delta = $max - $min
    $v = $max
    $s = if ($max -eq 0) { 0 } else { $delta / $max }

    if ($delta -eq 0) {
        return [PSCustomObject]@{ R = $R; G = $G; B = $B; Changed = $false }
    }

    if ($max -eq $rn) {
        $h = 60 * ((($gn - $bn) / $delta) % 6)
    } elseif ($max -eq $gn) {
        $h = 60 * ((($bn - $rn) / $delta) + 2)
    } else {
        $h = 60 * ((($rn - $gn) / $delta) + 4)
    }
    if ($h -lt 0) { $h += 360 }

    if ($s -lt $IgnoreSaturation -or $s -ge $MinSaturation) {
        # already saturated enough, or too close to gray/white to touch
        return [PSCustomObject]@{ R = $R; G = $G; B = $B; Changed = $false }
    }

    $s = $MinSaturation
    $c = $v * $s
    $hh = $h / 60
    $k = $hh % 2
    $x = $c * (1 - [Math]::Abs($k - 1))
    $m = $v - $c

    if ($h -lt 60)        { $rp = $c; $gp = $x; $bp = 0 }
    elseif ($h -lt 120)   { $rp = $x; $gp = $c; $bp = 0 }
    elseif ($h -lt 180)   { $rp = 0;  $gp = $c; $bp = $x }
    elseif ($h -lt 240)   { $rp = 0;  $gp = $x; $bp = $c }
    elseif ($h -lt 300)   { $rp = $x; $gp = 0;  $bp = $c }
    else                  { $rp = $c; $gp = 0;  $bp = $x }

    $rr = [Math]::Round(($rp + $m) * 255)
    $gg = [Math]::Round(($gp + $m) * 255)
    $bb = [Math]::Round(($bp + $m) * 255)

    $rr = [Math]::Min([Math]::Max($rr, 0), 255)
    $gg = [Math]::Min([Math]::Max($gg, 0), 255)
    $bb = [Math]::Min([Math]::Max($bb, 0), 255)

    return [PSCustomObject]@{ R = [int]$rr; G = [int]$gg; B = [int]$bb; Changed = $true }
}


# load image
$img = [System.Drawing.Bitmap]::FromFile($imagePath)

# downscale for speed
$small = New-Object System.Drawing.Bitmap 80,80
$g = [System.Drawing.Graphics]::FromImage($small)
$g.DrawImage($img,0,0,80,80)

$colorCounts = @{}

for($x=0;$x -lt $small.Width;$x++){
    for($y=0;$y -lt $small.Height;$y++){

        $c = $small.GetPixel($x,$y)

        # ignore near-black pixels
        if(($c.R + $c.G + $c.B) -lt 60){ continue }

        $key = "$($c.R),$($c.G),$($c.B)"

        if($colorCounts.ContainsKey($key)){
            $colorCounts[$key]++
        }else{
            $colorCounts[$key]=1
        }
    }
}

# get dominant
$dominant = $colorCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1

if(!$dominant){ exit }

$rgb = $dominant.Key.Split(",")

$r=$rgb[0]; $g=$rgb[1]; $b=$rgb[2]

$boosted = Get-SaturationBoostedColor -R ([int]$r) -G ([int]$g) -B ([int]$b) -MinSaturation $minSaturation -IgnoreSaturation $ignoreSaturation
$r = $boosted.R; $g = $boosted.G; $b = $boosted.B

if ($boosted.Changed) {
    Write-Host "Color too desaturated for LEDs, boosted saturation"
}

$hex = "{0:X2}{1:X2}{2:X2}" -f [int]$r,[int]$g,[int]$b

Write-Host "Dominant color: $hex"

# send to OpenRGB
Start-Process $openrgbExe -ArgumentList "--color $hex" -Verb RunAs