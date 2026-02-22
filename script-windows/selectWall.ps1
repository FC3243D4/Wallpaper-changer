param(
    [string]$BasePath = "C:\something",
    [string]$ReferenceRatio = "16-9",
    [string]$SetScript = "C:\WallpaperScripts\setwall.ps1",
    [string]$CacheFile = "$env:LOCALAPPDATA\wallpaper_cache.json",
    [string]$LastFile  = "$env:LOCALAPPDATA\wallpaper_last.txt"
)

$dw = New-Object -ComObject Microsoft.Windows.DesktopWallpaper
$referenceFolder = Join-Path $BasePath $ReferenceRatio

# -------------------------
# 1️⃣ CACHE SYSTEM
# -------------------------
if (Test-Path $CacheFile) {
    $files = Get-Content $CacheFile | ConvertFrom-Json
}
else {
    $files = Get-ChildItem -Path $referenceFolder -Recurse -File -Include *.jpg,*.png,*.jpeg,*.bmp |
        ForEach-Object { $_.FullName.Substring($referenceFolder.Length + 1) }

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
# 3️⃣ ASYNC PARALLEL APPLY
# -------------------------
$monitorCount = $dw.GetMonitorDevicePathCount()

$jobs = @()
for ($i = 0; $i -lt $monitorCount; $i++) {
    $jobs += Start-Job -ScriptBlock {
        param($script,$index,$rel)
        powershell -ExecutionPolicy Bypass -File $script $index $rel
    } -ArgumentList $SetScript,$i,$relativePath
}

$jobs | Wait-Job | Remove-Job