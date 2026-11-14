#Requires -Version 7.0
<#
.SYNOPSIS
  Sets a (random) wallpaper through Wallpaper Engine on every monitor, then re-themes.

.PARAMETER Filter
  All (default), Sfw or Nsfw - restrict the random pick by file name ("nsfw" in the path).

.PARAMETER Wallpaper
  Apply this specific wallpaper instead of a random one, as a path relative to an
  aspect-ratio folder, e.g. "series\image.png". Each monitor gets the copy from the
  folder matching its own aspect ratio (nearest folder that has the file).

.PARAMETER NoTheme
  Skip the theme refresh afterwards.

.NOTES
  Wallpaper Engine is located automatically (running process, Steam uninstall
  entry, any Steam library on any drive); override with "wallpaperEngineExe" in
  config.json or the WALLPAPER_ENGINE_EXE environment variable.
#>
[CmdletBinding()]
param(
    [ValidateSet('All', 'Sfw', 'Nsfw')][string]$Filter = 'All',
    [string]$Wallpaper,
    [switch]$NoTheme
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\WallpaperChanger.Common.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'lib\Monitors.psm1') -DisableNameChecking

$paths = Get-WcPaths
$cfg = Get-WcConfig
$base = $cfg.wallpaperDir
$extensions = '.jpg', '.jpeg', '.png', '.bmp', '.webp'

if (-not (Test-Path -LiteralPath $base)) { throw "Wallpaper folder not found: $base (set wallpaperDir in $($paths.Config))" }
$we = Get-WallpaperEngineExe
if (-not $we) {
    throw "Wallpaper Engine not found. Start it once, or set 'wallpaperEngineExe' in $($paths.Config) (or the WALLPAPER_ENGINE_EXE environment variable)."
}

$folders = @(Get-ChildItem -LiteralPath $base -Directory | Where-Object Name -Match '^\d+-\d+' | ForEach-Object Name)
if ($folders.Count -eq 0) { throw "No aspect-ratio folders (16-9, 21-9, ...) found in $base" }

$monitors = @(Get-WcMonitors)
$primary = @($monitors | Where-Object Primary | Select-Object -First 1) + @($monitors) | Select-Object -First 1

function Get-WallpaperList {
    # Relative paths ("series\file.png") inside one aspect folder, cached on disk.
    param([string]$Folder)
    $cache = @{}
    if (Test-Path -LiteralPath $paths.FileCache) {
        try { $cache = Get-Content -LiteralPath $paths.FileCache -Raw | ConvertFrom-Json -AsHashtable } catch { $cache = @{} }
        if ($cache -isnot [hashtable]) { $cache = @{} }
    }
    if (-not $cache.ContainsKey($Folder)) {
        $root = Join-Path $base $Folder
        $cache[$Folder] = @(Get-ChildItem -LiteralPath $root -Recurse -File |
                Where-Object { $_.Extension.ToLowerInvariant() -in $extensions } |
                ForEach-Object { $_.FullName.Substring($root.Length).TrimStart('\', '/') })
        Write-WcFile -Path $paths.FileCache -Content ($cache | ConvertTo-Json -Depth 4 -Compress)
    }
    $cache[$Folder]
}

# --- pick -------------------------------------------------------------------------
if ($Wallpaper) {
    $rel = $Wallpaper -replace '/', '\'
    if ([System.IO.Path]::IsPathRooted($rel) -or $rel -match '(^|\\)\.\.(\\|$)') { throw "Wallpaper must be a relative path inside an aspect folder: $Wallpaper" }
}
else {
    $primaryFolder = Get-AspectFolder -Width $primary.Width -Height $primary.Height -Folders $folders
    $candidates = @(Get-WallpaperList -Folder $primaryFolder)
    switch ($Filter) {
        'Sfw' { $candidates = @($candidates | Where-Object { $_ -notmatch 'nsfw' }) }
        'Nsfw' { $candidates = @($candidates | Where-Object { $_ -match 'nsfw' }) }
    }
    if ($candidates.Count -eq 0) { throw "No wallpapers found in $(Join-Path $base $primaryFolder) for filter '$Filter'." }
    $last = if (Test-Path -LiteralPath $paths.LastWallpaper) { (Get-Content -LiteralPath $paths.LastWallpaper -TotalCount 1) } else { '' }
    $pool = @($candidates | Where-Object { $_ -ne $last })
    if ($pool.Count -eq 0) { $pool = $candidates }          # only one wallpaper available
    $rel = Get-Random -InputObject $pool
}

# --- apply to every monitor ---------------------------------------------------------
$primaryFile = $null
foreach ($m in $monitors) {
    # nearest aspect folder that actually has this file
    $ratio = $m.Width / $m.Height
    $ordered = $folders | Sort-Object { if ($_ -match '^(\d+)-(\d+)') { [Math]::Abs([double]$Matches[1] / [double]$Matches[2] - $ratio) } else { 1e9 } }
    $file = $null
    foreach ($f in $ordered) {
        $candidate = Join-Path (Join-Path $base $f) $rel
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $file = $candidate; break }
    }
    if (-not $file) { Write-Warning "Monitor $($m.Index): '$rel' does not exist in any aspect folder, skipping."; continue }
    Write-Host "Monitor $($m.Index) ($($m.Width)x$($m.Height)): $file"
    $proc = @{ FilePath = $we; ArgumentList = @('-control', 'openWallpaper', '-file', "`"$file`"", '-monitor', $m.Index) }
    if ($IsWindows) { $proc.WindowStyle = 'Hidden' }
    Start-Process @proc
    if ($m.Index -eq $primary.Index) { $primaryFile = $file }
}
if (-not $primaryFile) { throw "Could not apply '$rel' to the primary monitor." }

Write-WcFile -Path $paths.CurrentWallpaper -Content $primaryFile
Write-WcFile -Path $paths.LastWallpaper -Content $rel

if (-not $NoTheme -and $cfg.refreshMode -ne 'None') {
    & (Join-Path $PSScriptRoot 'ThemeRefresher.ps1') -Mode $cfg.refreshMode
}
