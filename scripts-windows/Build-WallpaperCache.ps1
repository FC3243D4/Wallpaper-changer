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
        foreach ($rel in @(Get-WcWallpaperList -Folder $f)) {
            if ($seen.Add($rel)) { $files.Add((Join-Path (Join-Path $base $f) $rel)) }
        }
    }
    $total = $files.Count
    Say "Colors: $total wallpapers..."
    if ($total -eq 0) { return }
    $counts = @{ cache = 0; made = 0; failed = 0; fallback = 0 }
    $done = 0; $forceFlag = [bool]$Force
    $files | ForEach-Object -ThrottleLimit $Throttle -Parallel {
        Import-Module $using:colorModule -DisableNameChecking
        try { (Get-WallpaperColor -Image $_ -Force:$using:forceFlag).Source } catch { 'FAIL' }
    } | ForEach-Object {
        $done++
        if ($_ -eq 'cache') { $counts.cache++ } elseif ($_ -eq 'FAIL') { $counts.failed++ } elseif ($_ -in 'lifted', 'last', 'default') { $counts.fallback++ } else { $counts.made++ }
        if (-not $Quiet -and ($done % 25 -eq 0 -or $done -eq $total)) { Write-Host -NoNewline ("`r  [{0}/{1}] {2}%" -f $done, $total, [int](100 * $done / $total)) }
    }
    Say ''
    Say ("Colors: {0} computed, {1} already cached, {2} failed" -f $counts.made, $counts.cache, $counts.failed)
    if ($counts.fallback -gt 0) { Write-Warning ("{0} wallpaper(s) only got a fallback color (very dark and matugen missing?). They are not cached; install matugen and re-run to fix them." -f $counts.fallback) }
}

function Invoke-ListPass {
    # The random picker's wallpaper lists (self-validating, see Common.psm1). Only rebuilds what changed.
    param([string[]]$Folders)
    foreach ($f in $Folders) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $n = @(Get-WcWallpaperList -Folder $f).Count
        Say ("Wallpaper list {0}: {1} files ({2:N1}s)" -f $f, $n, $sw.Elapsed.TotalSeconds)
    }
}

function Invoke-ThumbnailPass {
    param([string[]]$Folders)
    $found = Find-Python -RequirePyQt6
    if (-not $found) { Write-Warning 'Thumbnails skipped: no Python with PyQt6 found (re-run install-Windows.ps1, it can set that up). The picker still makes them on demand.'; return }
    $py = $found.Exe
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
        Invoke-ListPass -Folders $folders
        if (-not $NoColors) { Invoke-ColorPass -Folders $folders }
        if (-not $NoThumbnails) { Invoke-ThumbnailPass -Folders $folders }
    }
    finally { $build.ReleaseMutex(); $build.Dispose() }
}

if (-not (Test-Path -LiteralPath $base)) { throw "Wallpaper folder not found: $base" }

if (-not $Watch) { Invoke-CachePass; return }

# ---- watch mode -------------------------------------------------------------------------------
# Events go into PowerShell's event queue (Register-ObjectEvent), so changes that happen WHILE a
# cache pass is running are not lost: they are still queued when the pass ends and trigger the
# next one. A burst of events (copying a folder) is debounced into a single pass. Each pass
# refreshes, in order: the picker's wallpaper lists (seconds - so a new wallpaper can be picked
# almost immediately), the accent colors, then the thumbnails.
$single = [System.Threading.Mutex]::new($false, 'Local\WallpaperChanger.CacheWatcher')
if (-not $single.WaitOne(0)) { Say 'The cache watcher is already running.'; return }
$watcher = $null
try {
    $watcher = [System.IO.FileSystemWatcher]::new($base)
    $watcher.IncludeSubdirectories = $true
    $watcher.InternalBufferSize = 65536                 # fewer overflows when thousands of files arrive at once
    $watcher.NotifyFilter = [System.IO.NotifyFilters]'FileName, DirectoryName, LastWrite'
    foreach ($ev in 'Created', 'Changed', 'Deleted', 'Renamed', 'Error') {
        $null = Register-ObjectEvent -InputObject $watcher -EventName $ev -SourceIdentifier "WallpaperChanger.Watch.$ev"
    }
    $watcher.EnableRaisingEvents = $true                # start listening BEFORE the first pass, so nothing in between is missed

    Invoke-CachePass
    Say "Watching $base for changes (Ctrl+C to stop)..."
    while ($true) {
        if (-not (Wait-Event -Timeout 60)) { continue }
        # debounce: keep draining until the folder has been quiet for 5 seconds
        do { Get-Event | Remove-Event; $more = Wait-Event -Timeout 5 } while ($more)
        Say 'Wallpaper folder changed - updating caches...'
        try { Invoke-CachePass } catch { Write-Warning $_.Exception.Message }
        # anything that changed during the pass is still queued and starts the next loop immediately
    }
}
finally {
    Get-EventSubscriber -Force | Where-Object { $_.SourceIdentifier -like 'WallpaperChanger.Watch.*' } | Unregister-Event -Force -ErrorAction SilentlyContinue
    if ($watcher) { $watcher.Dispose() }
    $single.ReleaseMutex(); $single.Dispose()
}
