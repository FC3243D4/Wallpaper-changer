param(
    [int]$MonitorIndex,
    [string]$RelativeWallpaper
)

# Base wallpaper root
$BasePath = "C:\something"

# Create DesktopWallpaper COM object
$dw = New-Object -ComObject Microsoft.Windows.DesktopWallpaper

# Get monitor device path
$monitorId = $dw.GetMonitorDevicePathAt($MonitorIndex)

# Get monitor resolution
$rect = $dw.GetMonitorRECT($monitorId)
$width  = $rect.right - $rect.left
$height = $rect.bottom - $rect.top

# Function to simplify ratio
function Get-GCD($a, $b) {
    while ($b -ne 0) {
        $temp = $b
        $b = $a % $b
        $a = $temp
    }
    return $a
}

$gcd = Get-GCD $width $height
$ratioW = [int]($width / $gcd)
$ratioH = [int]($height / $gcd)

# Folder naming like 16-9
$ratioFolder = "$ratioW-$ratioH"

# Build final path
$finalPath = Join-Path $BasePath (Join-Path $ratioFolder $RelativeWallpaper)

# Apply wallpaper
if (Test-Path $finalPath) {
    $dw.SetWallpaper($monitorId, $finalPath)
    Write-Host "Wallpaper applied: $finalPath"
}
else {
    Write-Host "Wallpaper not found: $finalPath"
}