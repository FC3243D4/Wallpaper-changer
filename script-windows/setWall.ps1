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

$ratio = $width / $height

# Available ratio folders
$ratioFolders = Get-ChildItem $BasePath -Directory | Select-Object -Expand Name

function Parse-Ratio($r){
    $p = $r -split "-"
    return [double]$p[0] / [double]$p[1]
}

# Find closest ratio
$closest = $ratioFolders |
    Sort-Object { [math]::Abs((Parse-Ratio $_) - $ratio) } |
    Select-Object -First 1

$ratioFolder = $closest
$finalPath = Join-Path $BasePath (Join-Path $ratioFolder $RelativeWallpaper)

# monitor rect already computed
$fadeScript = "C:\scripts\fadeOverlay.ps1"

Start-Process powershell -ArgumentList @(
    "-ExecutionPolicy Bypass",
    "-File `"$fadeScript`"",
    "`"$finalPath`"",
    $rect.left,
    $rect.top,
    $width,
    $height,
    600
)

Start-Sleep -Milliseconds 120

# Apply wallpaper
if (Test-Path $finalPath) {
    $dw.SetWallpaper($monitorId, $finalPath)
    Write-Host "Wallpaper applied: $finalPath"
}
else {
    Write-Host "Wallpaper not found: $finalPath"
}