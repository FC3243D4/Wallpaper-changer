param(
    [string]$imagePath,
    [string]$openrgbExe = "C:\Program Files\OpenRGB\OpenRGB.exe"
)

Add-Type -AssemblyName System.Drawing

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
$hex = "{0:X2}{1:X2}{2:X2}" -f [int]$r,[int]$g,[int]$b

Write-Host "Dominant color: $hex"

# send to OpenRGB
Start-Process $openrgbExe -ArgumentList "--color $hex" -Verb RunAs