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
$destScripts = "$env:USERPROFILE\wallpaperScripts"

if (Test-Path $sourceScripts) {
    Copy-Item -Path $sourceScripts -Destination $destScripts -Recurse -Force
    Write-Host "Scripts copied to $destScripts" -ForegroundColor Green
} else {
    New-Item -ItemType Directory -Force -Path $destScripts
    Write-Host "Directory created at $destScripts and copied scripts there." -ForegroundColor Green

}

# Check and create Pictures folder
$picturesPath = "$env:USERPROFILE\Pictures"
$wallpapersPath = "$picturesPath\wallpapers"

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

# Ask about NSFW wallpapers
$includeNSFW = Read-Host "Include NSFW wallpapers? (y/n)"

# Copy wallpaper folders
$aspectRatios = @("16-9", "32-9", "16-10")
foreach ($ratio in $aspectRatios) {
    $source = ".\$ratio"
    if (Test-Path $source) {
        Copy-Item -Path $source -Destination "$wallpapersPath\$ratio" -Recurse -Force
        Write-Host "Copied $ratio wallpapers." -ForegroundColor Green
    }
}

# Copy NSFW if requested
if ($includeNSFW -eq 'y') {
    $nsfwSource = ".\nsfw"
    if (Test-Path $nsfwSource) {
        Copy-Item -Path $nsfwSource -Destination "$wallpapersPath\" -Recurse -Force
        Write-Host "Copied NSFW wallpapers." -ForegroundColor Green
    }
}

Write-Host "Installation complete!" -ForegroundColor Green