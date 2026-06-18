# Windows Wallpaper Engine Installation Script

# Check if Wallpaper Engine is installed
$wallpaperEnginePath = "C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine"

if (-not (Test-Path $wallpaperEnginePath)) {
    Write-Host "ERROR: Wallpaper Engine is not installed." -ForegroundColor Red
    Write-Host "Please install Wallpaper Engine from Steam before running this script."
    exit 1
}

Write-Host "Wallpaper Engine found. Proceeding with installation..." -ForegroundColor Green

# Copy script-windows to wallpaperScripts
$sourceScripts = ".\script-windows"
$destScripts = "$env:USERPROFILE\Documents\wallpaperScripts"

if (-not (Test-Path $destScripts)) {
    New-Item -ItemType Directory -Path $destScripts -Force | Out-Null
    Write-Host "Directory created at $destScripts" -ForegroundColor Green
}

Copy-Item -Path "$sourceScripts\clearCache-Windows.ps1" -Destination $destScripts -Recurse -Force
Copy-Item -Path "$sourceScripts\getDominantColor.ps1" -Destination $destScripts -Recurse -Force
Copy-Item -Path "$sourceScripts\setRandomWallpaper-WE.ps1" -Destination $destScripts -Recurse -Force
Copy-Item -Path "$sourceScripts\wallpaperHotkey.ahk" -Destination $destScripts -Recurse -Force
Write-Host "Contents of script-windows copied to $destScripts" -ForegroundColor Green

#cretes shortcut to run hotkey listener from login
$startup = [Environment]::GetFolderPath("Startup")

$source = "$destScripts\wallpaperHotkey.ahk"
$dest   = Join-Path $startup "wallpaperHotkey.ahk"

cmd /c mklink /H "$dest" "$source"

# Check and create Pictures folder
$picturesPath = "$env:USERPROFILE\Pictures"
$wallpapersPath = "$picturesPath\wallpapers"
$cachePath = "$env:LOCALAPPDATA\wallpaper_cache.json"

if ((Test-Path ".\wallpapers")) {

    $copyWallpapers = Read-Host "Do you want to copy this repo's wallpapers? (y/n)"

    if ($copyWallpapers -ne 'y') {
    Write-Host "Skipping wallpaper copy. Please ensure you have wallpapers in $wallpapersPath for the script to work." -ForegroundColor Yellow
    } else {
        Write-Host "Preparing to copy wallpapers..." -ForegroundColor Green

        if (-not (Test-Path $picturesPath)) {
            New-Item -ItemType Directory -Path $picturesPath -Force | Out-Null
            Write-Host "Pictures folder created." -ForegroundColor Green
        } else {
            $picturesCont = @(Get-ChildItem -Path $picturesPath -ErrorAction SilentlyContinue)
            if ($picturesCont.Count -gt 0) {
                $confirm = Read-Host "Pictures folder is not empty. Delete contents? (y/n)"
                if ($confirm -eq 'y') {
                    Remove-Item -Path "$picturesPath\*" -Recurse -Force
                    Write-Host "Pictures folder cleared." -ForegroundColor Green
                } else {
                    Write-Host "Operation cancelled by user." -ForegroundColor Yellow
                    exit 0
                }
            }
        }
    }

    # Ask about NSFW wallpapers
    $includeNSFW = Read-Host "Include NSFW wallpapers? (y/n)"

    # Copy wallpaper folders
    $aspectRatios = @("16-9", "32-9", "16-10", "21-9")
    foreach ($ratio in $aspectRatios) {
        $source = ".\sfw\$ratio"
        if (Test-Path $source) {
            Copy-Item -Path $source -Destination "$wallpapersPath\$ratio" -Recurse -Force
            Write-Host "Copied $ratio wallpapers." -ForegroundColor Green
        }
        if($includeNSFW -eq 'y') {
            $nsfwSource = ".\nsfw\$ratio"
            if (Test-Path $nsfwSource) {
                Copy-Item -Path $nsfwSource -Destination "$wallpapersPath\$ratio\" -Recurse -Force
                Copy-Item -Path "$sourceScripts\setRandomWallpaper-WE-NSFW.ps1" -Destination $destScripts -Recurse -Force
                Copy-Item -Path "$sourceScripts\setRandomWallpaper-WE-SFW.ps1" -Destination $destScripts -Recurse -Force
                Write-Host "Copied NSFW $ratio wallpapers. and extra scripts." -ForegroundColor Green
            }
        }
    }
    Write-Host "Wallpapers copied to $wallpapersPath, on the script's first run they will be cached in $cachePath, if you ever want to regenerate the cache, delete $cachePath manually or using the script in $destScripts and run the script again." -ForegroundColor Green
    if($includeNSFW -eq 'y') {
        Write-Host "If you want to only use sfw or nsfw wallpapers, you can use the dedicated scripts in $destScripts to do so." -ForegroundColor Green
    }
}
Write-Host "Installation complete! Now add your wallpapers to $wallpapersPath in folders named after their aspect ratios for example: 16-9, 21-9, etc." -ForegroundColor Green