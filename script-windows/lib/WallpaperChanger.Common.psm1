#Requires -Version 7.0
# WallpaperChanger.Common.psm1
# Shared helpers for the Windows port of the theming pipeline: install paths,
# config, input validation, color math, atomic file writes, JSONC editing,
# Wallpaper Engine / OpenRGB discovery and the parallel patcher runner.
#
# Everything that ends up in a file, a registry value or a process argument
# goes through ConvertTo-HexColor first, so a corrupt cache entry can never
# inject anything into a patched config.

Set-StrictMode -Version Latest

# Install root = the folder that contains lib\ (e.g. %LOCALAPPDATA%\WallpaperChanger).
$script:Root = if ($env:WALLPAPERCHANGER_HOME) { $env:WALLPAPERCHANGER_HOME } else { Split-Path -Parent $PSScriptRoot }

function Get-WcPaths {
    $cache = Join-Path $script:Root 'cache'
    [ordered]@{
        Root             = $script:Root
        Support          = Join-Path $script:Root 'themeRefresherSupportScripts'
        Patchers         = Join-Path $script:Root 'themeRefresherSupportScripts\appPatchers'
        Svg              = Join-Path $script:Root 'themeRefresherSupportScripts\svg'
        Templates        = Join-Path $script:Root 'matugen\templates'
        MatugenConfig    = Join-Path $script:Root 'matugen\config.toml'
        Config           = Join-Path $script:Root 'config.json'
        Cache            = $cache
        ColorCache       = Join-Path $cache 'colors'
        MatugenCache     = Join-Path $cache 'matugen'
        Thumbnails       = Join-Path $cache 'wallpaper-thumbnails'
        CurrentWallpaper = Join-Path $script:Root 'current_wallpaper.txt'
        LastWallpaper    = Join-Path $cache 'wallpaper_last.txt'
        FileCache        = Join-Path $cache 'wallpaper_cache.json'
    }
}

# ---------------------------------------------------------------- config ---
function Get-WcConfig {
    $paths = Get-WcPaths
    $cfg = [ordered]@{
        wallpaperDir       = Join-Path $env:USERPROFILE 'Pictures\wallpapers'
        wallpaperEngineExe = $null      # null = auto-detect (any Steam library, running process, registry)
        openRgbExe         = $null      # null = auto-detect
        openRgbPort        = 6742       # OpenRGB SDK server port
        rgbEnabled         = $true
        refreshMode        = 'Full'     # run after a wallpaper change: Full | Softrun | Rgb | None
    }
    if (Test-Path -LiteralPath $paths.Config) {
        try {
            $user = Get-Content -LiteralPath $paths.Config -Raw | ConvertFrom-Json -AsHashtable
            foreach ($key in @($cfg.Keys)) {
                if ($user.ContainsKey($key) -and $null -ne $user[$key]) { $cfg[$key] = $user[$key] }
            }
        }
        catch { Write-Warning "Could not read $($paths.Config): $($_.Exception.Message). Using defaults." }
    }
    $cfg
}

function Set-WcConfigValue {
    param([Parameter(Mandatory)][string]$Name, $Value)
    $paths = Get-WcPaths
    $user = @{}
    if (Test-Path -LiteralPath $paths.Config) {
        try { $user = Get-Content -LiteralPath $paths.Config -Raw | ConvertFrom-Json -AsHashtable } catch { $user = @{} }
    }
    $user[$Name] = $Value
    Write-WcFile -Path $paths.Config -Content ($user | ConvertTo-Json -Depth 5)
}

# ------------------------------------------------------------ validation ---
function ConvertTo-HexColor {
    # Returns a lower-case 6-digit hex string without '#', or throws.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    $v = $Value.Trim().TrimStart('#').ToLowerInvariant()
    if ($v -notmatch '^[0-9a-f]{6}$') { throw "Invalid hex color '$Value' (expected 6 hex digits)" }
    $v
}

function Test-HexColor {
    param([AllowEmptyString()][string]$Value)
    $Value.Trim().TrimStart('#') -match '^[0-9a-fA-F]{6}$'
}

# ------------------------------------------------------------ color math ---
function Get-Brightness {
    # Same perceived-brightness formula as the Linux scripts (0-255).
    param([Parameter(Mandatory)][string]$Hex)
    $r = [Convert]::ToInt32($Hex.Substring(0, 2), 16)
    $g = [Convert]::ToInt32($Hex.Substring(2, 2), 16)
    $b = [Convert]::ToInt32($Hex.Substring(4, 2), 16)
    [int][Math]::Floor(($r * 299 + $g * 587 + $b * 114) / 1000)
}

function Get-SaturationBoostedColor {
    # Pastel dominant colors read as washed-out white on LED strips, so raise
    # saturation to a floor while keeping hue and value. Colors already at the
    # floor, and real grays/whites (saturation below IgnoreSaturation), are
    # left alone. Mirrors RgbApply.sh.
    param(
        [Parameter(Mandatory)][string]$Hex,
        [double]$MinSaturation = 0.80,
        [double]$IgnoreSaturation = 0.18
    )
    $Hex = ConvertTo-HexColor $Hex
    $rn = [Convert]::ToInt32($Hex.Substring(0, 2), 16) / 255.0
    $gn = [Convert]::ToInt32($Hex.Substring(2, 2), 16) / 255.0
    $bn = [Convert]::ToInt32($Hex.Substring(4, 2), 16) / 255.0

    $max = [Math]::Max($rn, [Math]::Max($gn, $bn))
    $min = [Math]::Min($rn, [Math]::Min($gn, $bn))
    $delta = $max - $min
    $v = $max
    $s = if ($max -eq 0) { 0.0 } else { $delta / $max }

    if ($delta -eq 0 -or $s -lt $IgnoreSaturation -or $s -ge $MinSaturation) {
        return [pscustomobject]@{ Hex = $Hex; Changed = $false; Saturation = $s }
    }

    if ($max -eq $rn) { $h = 60 * ((($gn - $bn) / $delta) % 6) }
    elseif ($max -eq $gn) { $h = 60 * ((($bn - $rn) / $delta) + 2) }
    else { $h = 60 * ((($rn - $gn) / $delta) + 4) }
    if ($h -lt 0) { $h += 360 }

    $c = $v * $MinSaturation
    $x = $c * (1 - [Math]::Abs((($h / 60) % 2) - 1))
    $m = $v - $c
    switch ([Math]::Floor($h / 60)) {
        0 { $rp = $c; $gp = $x; $bp = 0 }
        1 { $rp = $x; $gp = $c; $bp = 0 }
        2 { $rp = 0; $gp = $c; $bp = $x }
        3 { $rp = 0; $gp = $x; $bp = $c }
        4 { $rp = $x; $gp = 0; $bp = $c }
        default { $rp = $c; $gp = 0; $bp = $x }
    }
    $to = { param($n) [int][Math]::Min([Math]::Max([Math]::Round(($n + $m) * 255, [MidpointRounding]::AwayFromZero), 0), 255) }
    $out = '{0:x2}{1:x2}{2:x2}' -f (& $to $rp), (& $to $gp), (& $to $bp)
    [pscustomobject]@{ Hex = $out; Changed = $true; Saturation = $s }
}

function Get-BlendedColor {
    # Blend $Hex toward a target (white/black) by Amount (0-1); returns '#rrggbb'.
    param([string]$Hex, [int[]]$Target, [double]$Amount)
    $Hex = ConvertTo-HexColor $Hex
    $c = 0, 2, 4 | ForEach-Object { [Convert]::ToInt32($Hex.Substring($_, 2), 16) }
    $o = 0..2 | ForEach-Object { [int][Math]::Round($c[$_] + ($Target[$_] - $c[$_]) * $Amount, [MidpointRounding]::AwayFromZero) }
    '#{0:x2}{1:x2}{2:x2}' -f $o[0], $o[1], $o[2]
}

function Get-DominantColorFromPixels {
    # Dominant color of a pixel buffer. Own implementation: pixels are bucketed
    # to 4 bits per channel, near-black pixels are ignored, the fullest bucket
    # wins, and the result is the true mean of the pixels in that bucket.
    #   $Bgra  - raw bytes, 4 per pixel in B,G,R,A order (System.Drawing's
    #            Format32bppArgb layout on little-endian Windows)
    # Returns a 6-digit hex string, or $null when every pixel was filtered out.
    param(
        [Parameter(Mandatory)][byte[]]$Bgra,
        [int]$MinChannelSum = 60
    )
    $counts = [int[]]::new(4096)
    $sumR = [long[]]::new(4096); $sumG = [long[]]::new(4096); $sumB = [long[]]::new(4096)
    for ($i = 0; $i + 3 -lt $Bgra.Length; $i += 4) {
        if ($Bgra[$i + 3] -lt 128) { continue }                      # transparent
        $b = [int]$Bgra[$i]; $g = [int]$Bgra[$i + 1]; $r = [int]$Bgra[$i + 2]
        if (($r + $g + $b) -lt $MinChannelSum) { continue }          # near-black
        $k = (($r -shr 4) -shl 8) -bor (($g -shr 4) -shl 4) -bor ($b -shr 4)
        $counts[$k]++; $sumR[$k] += $r; $sumG[$k] += $g; $sumB[$k] += $b
    }
    $best = -1; $bestCount = 0
    for ($k = 0; $k -lt 4096; $k++) { if ($counts[$k] -gt $bestCount) { $best = $k; $bestCount = $counts[$k] } }
    if ($best -lt 0) { return $null }
    '{0:x2}{1:x2}{2:x2}' -f [int]($sumR[$best] / $bestCount), [int]($sumG[$best] / $bestCount), [int]($sumB[$best] / $bestCount)
}

# ----------------------------------------------------------- file writes ---
function Write-WcFile {
    # Atomic UTF-8 (no BOM) write: temp file in the same folder, then move over
    # the target, so a crash can never leave a half-written config behind.
    # -Backup keeps a one-time "<file>.wc-bak" copy of whatever was there first.
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
        [switch]$Backup
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $tmp = "$Path.wc-tmp"
    [System.IO.File]::WriteAllText($tmp, $Content, [System.Text.UTF8Encoding]::new($false))
    if ($Backup -and (Test-Path -LiteralPath $Path) -and -not (Test-Path -LiteralPath "$Path.wc-bak")) {
        Copy-Item -LiteralPath $Path -Destination "$Path.wc-bak"
    }
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Set-MarkedBlock {
    # Replace (or append) the block between two marker lines, leaving the rest
    # of the file untouched. -Remove deletes the block instead.
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$StartMarker,
        [Parameter(Mandatory)][string]$EndMarker,
        [string]$Block = '',
        [switch]$Remove
    )
    $text = if (Test-Path -LiteralPath $Path) { Get-Content -LiteralPath $Path -Raw } else { '' }
    if ($null -eq $text) { $text = '' }
    $pattern = '(?s)\r?\n?' + [regex]::Escape($StartMarker) + '.*?' + [regex]::Escape($EndMarker) + '\r?\n?'
    $had = $text -match $pattern
    if ($Remove) {
        if (-not $had) { return $false }
        Write-WcFile -Path $Path -Content ([regex]::Replace($text, $pattern, "`n"))
        return $true
    }
    $full = "$StartMarker`n$Block`n$EndMarker"
    if ($had) { $new = [regex]::Replace($text, $pattern, [System.Text.RegularExpressions.MatchEvaluator] { param($m) "`n$full`n" }) }
    else { $new = $text.TrimEnd() + "`n`n$full`n" }
    Write-WcFile -Path $Path -Content $new
    $true
}

# ------------------------------------------------------------------ JSONC --
# VS Code's settings.json is JSONC (comments, trailing commas). Rewriting it
# through a JSON serializer would delete the user's comments, so the property
# is replaced in the raw text instead and everything else is left byte-for-byte.
function Skip-JsoncTrivia {
    param([string]$T, [int]$I)
    while ($I -lt $T.Length) {
        $c = $T[$I]
        if ($c -eq [char]0xFEFF -or [char]::IsWhiteSpace($c)) { $I++ }
        elseif ($c -eq '/' -and $I + 1 -lt $T.Length -and $T[$I + 1] -eq '/') {
            $nl = $T.IndexOf("`n", $I); $I = if ($nl -lt 0) { $T.Length } else { $nl + 1 }
        }
        elseif ($c -eq '/' -and $I + 1 -lt $T.Length -and $T[$I + 1] -eq '*') {
            $e = $T.IndexOf('*/', $I + 2); $I = if ($e -lt 0) { $T.Length } else { $e + 2 }
        }
        else { break }
    }
    $I
}

function Skip-JsoncString {
    # $I points at the opening quote; returns the index just past the closing one.
    param([string]$T, [int]$I)
    $I++
    while ($I -lt $T.Length) {
        if ($T[$I] -eq '\') { $I += 2; continue }
        if ($T[$I] -eq '"') { return $I + 1 }
        $I++
    }
    throw 'Unterminated string in JSONC'
}

function Skip-JsoncValue {
    param([string]$T, [int]$I)
    $c = $T[$I]
    if ($c -eq '"') { return Skip-JsoncString $T $I }
    if ($c -eq '{' -or $c -eq '[') {
        $depth = 0
        while ($I -lt $T.Length) {
            $c = $T[$I]
            if ($c -eq '"') { $I = Skip-JsoncString $T $I; continue }
            if ($c -eq '/' -and $I + 1 -lt $T.Length -and ($T[$I + 1] -eq '/' -or $T[$I + 1] -eq '*')) { $I = Skip-JsoncTrivia $T $I; continue }
            if ($c -eq '{' -or $c -eq '[') { $depth++ }
            elseif ($c -eq '}' -or $c -eq ']') { $depth--; if ($depth -eq 0) { return $I + 1 } }
            $I++
        }
        throw 'Unbalanced brackets in JSONC'
    }
    while ($I -lt $T.Length -and $T[$I] -notin ',', '}', ']', "`n", "`r", '/') { $I++ }   # number / true / false / null
    $I
}

function Set-JsoncProperty {
    # Sets a top-level property of a JSONC object text. $ValueJson must already
    # be valid JSON. Replaces the existing value in place, or inserts the
    # property as the first one in the root object.
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$ValueJson
    )
    $i = Skip-JsoncTrivia $Text 0
    if ($i -ge $Text.Length -or $Text[$i] -ne '{') { throw 'Root of the JSONC document is not an object' }
    $rootOpen = $i
    $i = Skip-JsoncTrivia $Text ($i + 1)
    while ($i -lt $Text.Length -and $Text[$i] -ne '}') {
        if ($Text[$i] -ne '"') { throw "Unexpected character '$($Text[$i])' at offset $i" }
        $keyEnd = Skip-JsoncString $Text $i
        $key = $Text.Substring($i + 1, $keyEnd - $i - 2)
        $i = Skip-JsoncTrivia $Text $keyEnd
        if ($Text[$i] -ne ':') { throw "Expected ':' after key '$key'" }
        $i = Skip-JsoncTrivia $Text ($i + 1)
        $valueStart = $i
        $valueEnd = Skip-JsoncValue $Text $i
        if ($key -ceq $Name) {
            return $Text.Substring(0, $valueStart) + $ValueJson + $Text.Substring($valueEnd)
        }
        $i = Skip-JsoncTrivia $Text $valueEnd
        if ($i -lt $Text.Length -and $Text[$i] -eq ',') { $i = Skip-JsoncTrivia $Text ($i + 1) }
    }
    $hasProps = (Skip-JsoncTrivia $Text ($rootOpen + 1)) -lt $Text.Length -and $Text[(Skip-JsoncTrivia $Text ($rootOpen + 1))] -ne '}'
    $insert = if ($hasProps) { "`n    `"$Name`": $ValueJson," } else { "`n    `"$Name`": $ValueJson`n" }
    $Text.Substring(0, $rootOpen + 1) + $insert + $Text.Substring($rootOpen + 1)
}

# ------------------------------------------------------- profiles.ini ------
function Get-MozillaProfileDirs {
    # Profile folders listed in a Firefox-family profiles.ini ([Profile*] Path=
    # with IsRelative, plus [Install*] Default=). Only folders that exist.
    param([Parameter(Mandatory)][string]$Root)
    $ini = Join-Path $Root 'profiles.ini'
    if (-not (Test-Path -LiteralPath $ini)) { return @() }
    $found = [System.Collections.Generic.List[string]]::new()
    $section = ''; $path = $null; $rel = '1'
    $norm = { param($p) [System.IO.Path]::GetFullPath(($p -replace '[\\/]', [System.IO.Path]::DirectorySeparatorChar)) }
    $flush = {
        if ($section -like 'Profile*' -and $path) {
            $found.Add((& $norm $(if ($rel -eq '0') { $path } else { Join-Path $Root $path })))
        }
    }
    foreach ($line in (Get-Content -LiteralPath $ini)) {
        if ($line -match '^\[(.+)\]\s*$') {
            & $flush
            $section = $Matches[1]; $path = $null; $rel = '1'
        }
        elseif ($line -match '^Path=(.*)$') { $path = $Matches[1] }
        elseif ($line -match '^IsRelative=(.*)$') { $rel = $Matches[1] }
        elseif ($section -like 'Install*' -and $line -match '^Default=(.*)$') {
            $d = $Matches[1]; $found.Add((& $norm $(if ([System.IO.Path]::IsPathRooted($d)) { $d } else { Join-Path $Root $d })))
        }
    }
    & $flush
    $found | Select-Object -Unique | Where-Object { Test-Path -LiteralPath $_ -PathType Container }
}

# -------------------------------------------------------------- discovery --
function Get-SteamLibraryRoots {
    $roots = [System.Collections.Generic.List[string]]::new()
    $steam = @()
    if ($IsWindows) {
        foreach ($k in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
            try {
                $p = Get-ItemProperty -Path $k -ErrorAction Stop
                foreach ($n in 'SteamPath', 'InstallPath') { if ($p.PSObject.Properties[$n]) { $steam += $p.$n } }
            }
            catch { }
        }
    }
    foreach ($pf in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) { if ($pf) { $steam += (Join-Path $pf 'Steam') } }
    foreach ($s in ($steam | Where-Object { $_ } | ForEach-Object { $_ -replace '/', '\' } | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $s)) { continue }
        $roots.Add($s)
        $vdf = Join-Path $s 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) {
                $roots.Add(($m.Groups[1].Value -replace '\\\\', '\'))
            }
        }
    }
    $roots | Select-Object -Unique
}

function Get-WallpaperEngineExe {
    # Finds wallpaper64.exe no matter how Wallpaper Engine was installed: an
    # explicit override, a running instance, Steam's uninstall entry, or any
    # Steam library (other drives included). The result is cached in config.json.
    param([switch]$Refresh)
    $cfg = Get-WcConfig
    $isExe = { param($p) $p -and (Test-Path -LiteralPath $p -PathType Leaf) }

    foreach ($c in @($env:WALLPAPER_ENGINE_EXE, $(if (-not $Refresh) { $cfg.wallpaperEngineExe }))) {
        if (& $isExe $c) { return $c }
    }

    $dirs = [System.Collections.Generic.List[string]]::new()
    foreach ($proc in (Get-Process -Name 'wallpaper64', 'wallpaper32' -ErrorAction SilentlyContinue)) {
        if ($proc.Path) { $dirs.Add((Split-Path -Parent $proc.Path)) }
    }
    if ($IsWindows) {
        foreach ($k in 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 431960',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 431960',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 431960') {
            try { $d = (Get-ItemProperty -Path $k -ErrorAction Stop).InstallLocation; if ($d) { $dirs.Add($d) } } catch { }
        }
    }
    foreach ($lib in (Get-SteamLibraryRoots)) {
        $common = Join-Path $lib 'steamapps\common'
        $dirs.Add((Join-Path $common 'wallpaper_engine'))
        $manifest = Join-Path $lib 'steamapps\appmanifest_431960.acf'
        if (Test-Path -LiteralPath $manifest) {
            $m = [regex]::Match((Get-Content -LiteralPath $manifest -Raw), '"installdir"\s+"([^"]+)"')
            if ($m.Success) { $dirs.Add((Join-Path $common $m.Groups[1].Value)) }
        }
    }
    foreach ($d in ($dirs | Select-Object -Unique)) {
        foreach ($exe in 'wallpaper64.exe', 'wallpaper32.exe') {
            $p = Join-Path $d $exe
            if (& $isExe $p) { try { Set-WcConfigValue -Name wallpaperEngineExe -Value $p } catch { }; return $p }
        }
    }
    $null
}

function Get-OpenRgbExe {
    $cfg = Get-WcConfig
    $cands = @($env:OPENRGB_EXE, $cfg.openRgbExe)
    foreach ($pair in @(@($env:ProgramFiles, 'OpenRGB\OpenRGB.exe'), @(${env:ProgramFiles(x86)}, 'OpenRGB\OpenRGB.exe'),
            @($env:LOCALAPPDATA, 'Programs\OpenRGB\OpenRGB.exe'), @($env:USERPROFILE, 'scoop\apps\openrgb\current\OpenRGB.exe'))) {
        if ($pair[0]) { $cands += (Join-Path $pair[0] $pair[1]) }
    }
    $cmd = Get-Command 'OpenRGB.exe' -ErrorAction SilentlyContinue
    if ($cmd) { $cands += $cmd.Source }
    $cands | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
}

function Find-Matugen {
    $cmd = Get-Command 'matugen' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $cands = @((Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\matugen.exe'),
        (Join-Path $env:USERPROFILE 'scoop\shims\matugen.exe'),
        (Join-Path $env:USERPROFILE '.cargo\bin\matugen.exe'))
    $cands | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
}

# ------------------------------------------------ aspect-ratio folder -------
function Get-AspectFolder {
    # Name of the wallpaper folder (e.g. "21-9") whose ratio is closest to the
    # given resolution. Same result as AspectRatioChecker.sh.
    param(
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][int]$Height,
        [Parameter(Mandatory)][string[]]$Folders
    )
    $actual = $Width / $Height
    $best = $null; $bestDiff = [double]::MaxValue
    foreach ($f in $Folders) {
        if ($f -notmatch '^(\d+)-(\d+)') { continue }
        $diff = [Math]::Abs(([double]$Matches[1] / [double]$Matches[2]) - $actual)
        if ($diff -lt $bestDiff) { $best = $f; $bestDiff = $diff }
    }
    $best
}

# --------------------------------------------------------- job plumbing ----
function Start-WcPatcherJob {
    # Runs a patcher script on a thread job (cheap, no new pwsh process).
    # Output lines get a "[label] " prefix; Wait-WcPatcherJobs prints them.
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Script,
        [hashtable]$Arguments = @{}
    )
    Start-ThreadJob -Name $Label -ScriptBlock {
        param($label, $script, $splat)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $failed = $false
        try { & $script @splat *>&1 | ForEach-Object { "[$label] $_" } }
        catch { "[$label] ERROR: $($_.Exception.Message)"; $failed = $true }
        [pscustomobject]@{ __wcResult = $true; Label = $label; Failed = $failed; Seconds = $sw.Elapsed.TotalSeconds }
    } -ArgumentList $Label, $Script, $Arguments
}

function Wait-WcPatcherJobs {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Jobs)
    $failed = @()
    foreach ($job in $Jobs) {
        Wait-Job -Job $job | Out-Null
        foreach ($item in (Receive-Job -Job $job -ErrorAction Continue)) {
            if ($item -is [string]) { Write-Host $item }
            elseif ($item.PSObject.Properties['__wcResult']) {
                [Console]::Error.WriteLine(('[timing] {0}: {1:N3}s' -f $item.Label, $item.Seconds))
                if ($item.Failed) { $failed += $item.Label }
            }
        }
        if ($job.State -eq 'Failed') { $failed += $job.Name }
        Remove-Job -Job $job -Force
    }
    $failed | Select-Object -Unique
}

function Invoke-WcTimed {
    # time_step equivalent: runs the script block, prints "[timing] label: Ns" to stderr.
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][scriptblock]$Script)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try { & $Script } finally { [Console]::Error.WriteLine(('[timing] {0}: {1:N3}s' -f $Label, $sw.Elapsed.TotalSeconds)) }
}

function Remove-LegacyHotkey {
    # Cleans up the old AutoHotkey v1 hotkey (Ctrl+Alt+W): stops a running
    # instance and deletes its script copies and Startup entries. A process
    # already running the NEW script ($KeepScript) is left alone. Returns a
    # list of strings describing what was done.
    param(
        [Parameter(Mandatory)][string]$StartupDir,
        [Parameter(Mandatory)][string]$KeepScript
    )
    $done = [System.Collections.Generic.List[string]]::new()
    if ($IsWindows) {
        $procs = Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%'" -ErrorAction SilentlyContinue
        foreach ($p in $procs) {
            $cl = [string]$p.CommandLine
            if ($cl -match 'wallpaperHotkey\.ahk' -and -not $cl.Contains($KeepScript)) {
                try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop; $done.Add("stopped the old hotkey process (PID $($p.ProcessId))") } catch { }
            }
        }
    }
    $files = @(
        (Join-Path $StartupDir 'wallpaperHotkey.ahk'),                       # old hard-link startup entry
        (Join-Path $StartupDir 'WallpaperChanger Hotkey.lnk'),               # shortcut made by an earlier installer
        (Join-Path $env:USERPROFILE 'Documents\wallpaperScripts\wallpaperHotkey.ahk')   # copy in the old install folder
    )
    foreach ($f in $files) {
        if (Test-Path -LiteralPath $f) {
            try { Remove-Item -LiteralPath $f -Force -ErrorAction Stop; $done.Add("removed $f") } catch { $done.Add("could not remove ${f}: $($_.Exception.Message)") }
        }
    }
    $done
}

Export-ModuleMember -Function *-*
