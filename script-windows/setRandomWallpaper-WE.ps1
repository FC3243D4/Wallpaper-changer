param(
    [string]$BasePath = "$env:USERPROFILE\Pictures\wallpapers",
    [string]$WallpaperEngineExe = "C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine\wallpaper64.exe",
    [string]$CacheFile = "$env:LOCALAPPDATA\wallpaper_cache.json",
    [string]$LastFile = "$env:LOCALAPPDATA\wallpaper_last.txt"
    [string]$DominantColorScript = "$env:USERPROFILE\wallpaperScripts\getDominantColor.ps1"
)

# -------------------------
# ASPECTRATIO DETECTION
# -------------------------
function Get-GCD($a,$b){
    while ($b -ne 0){
        $t=$b
        $b=$a%$b
        $a=$t
    }
    return $a
}

function Get-AspectFolder($width,$height,$availableFolders){

    $gcd = Get-GCD $width $height
    $rw = [int]($width/$gcd)
    $rh = [int]($height/$gcd)

    $exact = "$rw-$rh"
    if ($availableFolders -contains $exact){
        return $exact
    }

    # fallback → closest ratio
    $ratio = $width/$height
    $closest = $availableFolders |
        Sort-Object {
            $p=$_ -split "-"
            [math]::Abs(($p[0]/$p[1])-$ratio)
        } | Select-Object -First 1

    return $closest
}


# -------------------------
# 1️⃣ CACHE SYSTEM
# -------------------------
$referenceFolder = $BasePath

if (Test-Path $CacheFile) {
    $files = Get-Content $CacheFile | ConvertFrom-Json
} else {
    $files = Get-ChildItem -Path $referenceFolder -Recurse -File -Include *.jpg,*.png,*.jpeg,*.bmp | 
             ForEach-Object { $_.FullName.Substring($BasePath.Length + 1) }
    $files | ConvertTo-Json | Set-Content $CacheFile
}

if ($files.Count -eq 0) { exit }

# -------------------------
# 2️⃣ AVOID LAST WALLPAPER
# -------------------------
$last = ""
if (Test-Path $LastFile) { $last = Get-Content $LastFile }

$filtered = $files | Where-Object { $_ -ne $last }
if ($filtered.Count -eq 0) { $filtered = $files }

$relativePath = Get-Random $filtered
$relativePath | Set-Content $LastFile

Write-Host "Selected wallpaper: $relativePath"

# -------------------------
# 3️⃣ MONITOR DETECTION
# -------------------------
Add-Type -AssemblyName System.Windows.Forms
$monitors = [System.Windows.Forms.Screen]::AllScreens
$monitorCount = $monitors.Count

Write-Host "$monitorCount monitors"

# -------------------------
# 4️⃣ APPLY WALLPAPER PER MONITOR
# -------------------------
$availableFolders = Get-ChildItem $BasePath -Directory | Select-Object -Expand Name

for ($i=0;$i -lt $monitors.Count;$i++){

    $screen=$monitors[$i]
    $width=$screen.Bounds.Width
    $height=$screen.Bounds.Height

    $ratioFolder = Get-AspectFolder $width $height $availableFolders

    Start-Process $WallpaperEngineExe -ArgumentList @(
        '-control openWallpaper',
        "-file `"$BasePath\$ratioFolder\$relativePath`"",
        "-monitor $i"
    )
}

# -------------------------
# 5️⃣ PRIMARY MONITOR WALLFILE AND DOMINANT COLOR FOR RGB
# -------------------------
$openrgbExe = "C:\Program Files\OpenRGB\OpenRGB.exe"

if (-not (Test-Path $openrgbExe)) {
    Write-Host "OpenRGB not found at $openrgbExe. Skipping RGB color sync." -ForegroundColor Yellow
    exit 0
}
else {
    Write-Host "OpenRGB found. Proceeding with RGB color sync..." -ForegroundColor Green
    $primaryMonitor = $monitors | Where-Object { $_.Primary }

    $width  = $primaryMonitor.Bounds.Width
    $height = $primaryMonitor.Bounds.Height

    $availableFolders = Get-ChildItem $BasePath -Directory | Select-Object -Expand Name
    $ratioFolder = Get-AspectFolder $width $height $availableFolders

    $primaryWallFile = "$BasePath\$ratioFolder\$relativePath"

    powershell.exe -ExecutionPolicy Bypass -File $DominantColorScript "$primaryWallFile"
}