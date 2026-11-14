#Requires -Version 7.0
<#
.SYNOPSIS
  Pre-generates the accent-color cache and the picker thumbnails for the whole wallpaper
  library (Windows counterpart of GenerateWallpaperThumbnails.sh + its systemd path watcher).

.DESCRIPTION
  Both caches fill themselves lazily anyway (the picker makes thumbnails as you scroll,
  ThemeRefresher computes a color on first use). This does it ahead of time, in parallel
  and incrementally: anything already up to date is skipped, so re-running is cheap.

    -Watch   stay running: do a pass now, then another a few seconds after the wallpaper
             folder stops changing (new, replaced or removed files). Meant for the login
             shortcut the installer can create.

.PARAMETER Ratios        Aspect folders to process, e.g. 16-9,21-9. Default: the ratios chosen at
                         install time (config.json "aspectRatios"), else every ratio folder found.
.PARAMETER NoColors      Skip the accent colors.
.PARAMETER NoThumbnails  Skip the thumbnails.
.PARAMETER Force         Recompute colors even if cached (thumbnails are always checked by timestamp).
.PARAMETER Throttle      Parallel workers for colors (default: all cores but one).
.PARAMETER Quiet         No progress output.
#>
[CmdletBinding()]
param(
    [string[]]$Ratios,
    [switch]$NoColors,
    [switch]$NoThumbnails,
    [switch]$Force,
    [switch]$Watch,
    [switch]$Quiet,
    [int]$Throttle = [Math]::Max(1, [Environment]::ProcessorCount - 1)
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\WallpaperChanger.Common.psm1') -DisableNameChecking
$colorModule = Join-Path $PSScriptRoot 'lib\WallpaperColor.psm1'

# Be a good background citizen.
try { [System.Diagnostics.Process]::GetCurrentProcess().PriorityClass = 'BelowNormal' } catch { }

$cfg = Get-WcConfig
$base = $cfg.wallpaperDir
$extensions = '.jpg', '.jpeg', '.png', '.bmp', '.webp'
function Say([string]$t) { if (-not $Quiet) { Write-Host $t } }

function Get-RatioFolders {
    $all = @(Get-ChildItem -LiteralPath $base -Directory -ErrorAction Stop | Where-Object Name -Match '^\d+-\d+$' | ForEach-Object Name)
    $wanted = @($Ratios | ForEach-Object { $_ -split '[,\s]+' } | Where-Object { $_ })
    if ($wanted.Count -eq 0) { $wanted = @($cfg.aspectRatios | Where-Object { $_ }) }
    $picked = if ($wanted.Count -gt 0) { @($all | Where-Object { $_ -in $wanted }) } else { @() }
    if ($picked.Count -eq 0) { $picked = $all }
    @($picked | Sort-Object { if ($_ -eq '16-9') { '' } else { $_ } })       # 16-9 first, like Linux
}

function Invoke-ColorPass {
    param([string[]]$Folders)
    # One entry per wallpaper regardless of aspect folder (the color cache ignores the ratio).
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $files = [System.Collections.Generic.List[string]]::new()
    foreach ($f in $Folders) {
        $root = Join-Path $base $f
        foreach ($item in (Get-ChildItem -LiteralPath $root -Recurse -File)) {
            if ($item.Extension.ToLowerInvariant() -notin $extensions) { continue }
            if ($seen.Add($item.FullName.Substring($root.Length))) { $files.Add($item.FullName) }
        }
    }
    $total = $files.Count
    Say "Colors: $total wallpapers..."
    if ($total -eq 0) { return }
    $counts = @{ cache = 0; made = 0; failed = 0 }
    $done = 0; $forceFlag = [bool]$Force
    $files | ForEach-Object -ThrottleLimit $Throttle -Parallel {
        Import-Module $using:colorModule -DisableNameChecking
        try { (Get-WallpaperColor -Image $_ -Force:$using:forceFlag).Source } catch { 'FAIL' }
    } | ForEach-Object {
        $done++
        if ($_ -eq 'cache') { $counts.cache++ } elseif ($_ -eq 'FAIL') { $counts.failed++ } else { $counts.made++ }
        if (-not $Quiet -and ($done % 25 -eq 0 -or $done -eq $total)) { Write-Host -NoNewline ("`r  [{0}/{1}] {2}%" -f $done, $total, [int](100 * $done / $total)) }
    }
    Say ''
    Say ("Colors: {0} computed, {1} already cached, {2} failed" -f $counts.made, $counts.cache, $counts.failed)
}

function Invoke-ThumbnailPass {
    param([string[]]$Folders)
    $py = $null
    foreach ($name in 'python', 'python3') {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) {
            & $cmd.Source -c 'import PyQt6.QtGui' 2>$null
            if ($LASTEXITCODE -eq 0) { $py = $cmd.Source; break }
        }
    }
    if (-not $py) { Write-Warning 'Thumbnails skipped: need Python with PyQt6 (python -m pip install PyQt6). The picker still makes them on demand.'; return }
    $script = Join-Path $PSScriptRoot 'GenerateWallpaperThumbnails.py'
    $pyArgs = @($script, '--wallpapers', $base, '--ratios', ($Folders -join ','))
    if ($Quiet) { $pyArgs += '--quiet' }
    & $py @pyArgs
    if ($LASTEXITCODE -ne 0) { Write-Warning "Thumbnail generator exited with $LASTEXITCODE" }
}

function Invoke-CachePass {
    $build = [System.Threading.Mutex]::new($false, 'Local\WallpaperChanger.CacheBuild')
    if (-not $build.WaitOne(0)) { Say 'A cache build is already running.'; return }
    try {
        $folders = Get-RatioFolders
        Say "Aspect folders: $($folders -join ', ')"
        if (-not $NoColors) { Invoke-ColorPass -Folders $folders }
        if (-not $NoThumbnails) { Invoke-ThumbnailPass -Folders $folders }
    }
    finally { $build.ReleaseMutex(); $build.Dispose() }
}

if (-not (Test-Path -LiteralPath $base)) { throw "Wallpaper folder not found: $base" }

if (-not $Watch) { Invoke-CachePass; return }

# ---- watch mode -------------------------------------------------------------------------------
$single = [System.Threading.Mutex]::new($false, 'Local\WallpaperChanger.CacheWatcher')
if (-not $single.WaitOne(0)) { Say 'The cache watcher is already running.'; return }
try {
    Invoke-CachePass
    $watcher = [System.IO.FileSystemWatcher]::new($base)
    $watcher.IncludeSubdirectories = $true
    $watcher.NotifyFilter = [System.IO.NotifyFilters]'FileName, DirectoryName, LastWrite'
    Say "Watching $base for changes (Ctrl+C to stop)..."
    while ($true) {
        $r = $watcher.WaitForChanged([System.IO.WatcherChangeTypes]::All, 60000)
        if ($r.TimedOut) { continue }
        # debounce: copying a batch of files fires many events; wait until it goes quiet
        do { $r = $watcher.WaitForChanged([System.IO.WatcherChangeTypes]::All, 5000) } until ($r.TimedOut)
        Say 'Wallpaper folder changed - updating caches...'
        try { Invoke-CachePass } catch { Write-Warning $_.Exception.Message }
    }
}
finally { $single.ReleaseMutex(); $single.Dispose() }
