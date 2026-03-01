$cachePath = "$env:LOCALAPPDATA\wallpaper_cache.json"

if (Test-Path $cachePath) {
    Remove-Item -Path $cachePath -Force
    Write-Host "Cache file at $cachePath deleted successfully." -ForegroundColor Green
} else {
    Write-Host "No cache file found at $cachePath. Nothing to delete." -ForegroundColor Yellow
}