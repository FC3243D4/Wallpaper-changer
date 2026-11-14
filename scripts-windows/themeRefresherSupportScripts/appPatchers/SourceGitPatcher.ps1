#Requires -Version 7.0
<#
.SYNOPSIS
  Normalizes SourceGit's matugen theme and regenerates the static ForkDark theme.

.DESCRIPTION
  Port of SourceGitPatcher.sh. Validates the matugen-rendered theme and
  upper-cases its hex colors (SourceGit expects #RRGGBB), regenerates
  ForkDark.json from a pristine base with the accent and a hue-rotated graph
  palette, and only switches ThemeOverrides to the matugen theme when it isn't
  already pointing at one of the two managed themes (a manual choice between
  them is left alone).
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Color)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\..\lib\WallpaperChanger.Common.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot '..\..\lib\Matugen.psm1') -DisableNameChecking

$hex = ConvertTo-HexColor $Color
$accent = '#' + $hex.ToUpperInvariant()

$dir = Get-SourceGitDir
if (-not $dir) { Write-Output 'SourceGit data folder not found (%APPDATA%\SourceGit), skipping'; return }

$rendered = Join-Path $dir 'matugen-theme.json'
$prefs = Join-Path $dir 'preference.json'
$forkDark = Join-Path $dir 'ForkDark.json'
$forkDarkBase = "$forkDark.base"

if (-not (Test-Path -LiteralPath $rendered)) { throw "Rendered matugen SourceGit theme not found at $rendered (matugen has to run first)" }

# 1. validate + normalize the rendered theme
$content = Get-Content -LiteralPath $rendered -Raw
try { $null = ConvertFrom-Json $content } catch { throw "Rendered theme at $rendered is not valid JSON, aborting" }
$normalized = [regex]::Replace($content, '#[0-9a-fA-F]{6}', { param($m) $m.Value.ToUpperInvariant() })
if ($normalized -cne $content) { Write-WcFile -Path $rendered -Content $normalized }

# 2. ForkDark base (original static theme), created once
if (-not (Test-Path -LiteralPath $forkDarkBase)) {
    $base = @'
{
    "BasicColors": {
        "Window": "#1E1E1E",
        "WindowBorder": "#252526",
        "TitleBar": "#444444",
        "ToolBar": "#252526",
        "Popup": "#1E1E1E",
        "Contents": "#1E1E1E",
        "HistoryBG": "#1E1E1E",
        "Badge": "#007ACC",
        "BadgeFG": "#FFFFFF",
        "Conflict": "#D16969",
        "Conflict.Foreground": "#FFFFFF",
        "Border0": "#3C3C3C",
        "Border1": "#444444",
        "Border2": "#444444",
        "FlatButton.Background": "#333333",
        "FlatButton.BackgroundHovered": "#3C3C3C",
        "FG1": "#D4D4D4",
        "FG2": "#D4D4D4",
        "Diff.EmptyBG": "#252526",
        "Diff.AddedBG": "#144212",
        "Diff.DeletedBG": "#660000",
        "Diff.AddedHighlight": "#22A822",
        "Diff.DeletedHighlight": "#CC0000",
        "SystemAccentColor": "#007ACC",
        "Link": "#3794FF"
    },
    "GraphPenThickness": 2,
    "OpacityForNotMergedCommits": 0.5,
    "GraphColors": [
        "#ff9502", "#ff2968", "#ffcc00", "#4EC9B0", "#cb73e1", "#1cadf8", "#CE9178",
        "#C8C8C8", "#808080", "#a2845e", "#99442b", "#22A822", "#CC0000"
    ]
}
'@
    Write-WcFile -Path $forkDarkBase -Content $base
}

# 3. ForkDark.json: HSV rotation seeded from the accent (13 graph lanes)
function ConvertTo-Hsv {
    param([double]$R, [double]$G, [double]$B)
    $max = [Math]::Max($R, [Math]::Max($G, $B)); $min = [Math]::Min($R, [Math]::Min($G, $B)); $d = $max - $min
    $h = 0.0
    if ($d -ne 0) {
        if ($max -eq $R) { $h = (($G - $B) / $d) % 6 } elseif ($max -eq $G) { $h = (($B - $R) / $d) + 2 } else { $h = (($R - $G) / $d) + 4 }
        $h = $h / 6; if ($h -lt 0) { $h += 1 }
    }
    @($h, $(if ($max -eq 0) { 0.0 } else { $d / $max }), $max)
}
function ConvertFrom-Hsv {
    param([double]$H, [double]$S, [double]$V)
    $h6 = ($H % 1.0) * 6; $i = [int][Math]::Floor($h6); $f = $h6 - $i
    $p = $V * (1 - $S); $q = $V * (1 - $S * $f); $t = $V * (1 - $S * (1 - $f))
    $rgb = switch ($i % 6) { 0 { $V, $t, $p } 1 { $q, $V, $p } 2 { $p, $V, $t } 3 { $p, $q, $V } 4 { $t, $p, $V } default { $V, $p, $q } }
    '#{0:X2}{1:X2}{2:X2}' -f [int][Math]::Floor($rgb[0] * 255), [int][Math]::Floor($rgb[1] * 255), [int][Math]::Floor($rgb[2] * 255)
}
$r = [Convert]::ToInt32($hex.Substring(0, 2), 16) / 255.0
$g = [Convert]::ToInt32($hex.Substring(2, 2), 16) / 255.0
$b = [Convert]::ToInt32($hex.Substring(4, 2), 16) / 255.0
$hsv = ConvertTo-Hsv $r $g $b
$sat = [Math]::Max($hsv[1], 0.6); $val = [Math]::Max($hsv[2], 0.75)
$graph = 0..12 | ForEach-Object { ConvertFrom-Hsv (($hsv[0] + $_ / 13.0) % 1.0) $sat $val }

$theme = Get-Content -LiteralPath $forkDarkBase -Raw | ConvertFrom-Json
$theme.BasicColors.SystemAccentColor = $accent
$theme.BasicColors.Badge = $accent
$theme.GraphColors = @($graph)
Write-WcFile -Path $forkDark -Content ($theme | ConvertTo-Json -Depth 10)
Write-Output "ForkDark.json updated (accent: $accent)"

# 4. take over ThemeOverrides only if it isn't one of the managed themes already
if (Test-Path -LiteralPath $prefs) {
    $p = Get-Content -LiteralPath $prefs -Raw | ConvertFrom-Json
    $current = if ($p.PSObject.Properties['ThemeOverrides']) { [string]$p.ThemeOverrides } else { '' }
    $norm = { param($x) if ($x) { try { [System.IO.Path]::GetFullPath($x).ToLowerInvariant() } catch { $x.ToLowerInvariant() } } else { '' } }
    if ((& $norm $current) -in @((& $norm $forkDark), (& $norm $rendered))) {
        Write-Output "ThemeOverrides already set to '$current', leaving as is"
    }
    else {
        if ($p.PSObject.Properties['ThemeOverrides']) { $p.ThemeOverrides = $rendered } else { $p | Add-Member -NotePropertyName ThemeOverrides -NotePropertyValue $rendered }
        Write-WcFile -Path $prefs -Content ($p | ConvertTo-Json -Depth 20) -Backup
        Write-Output "ThemeOverrides was '$current', set to matugen theme: $rendered"
    }
}
else {
    Write-Warning "$prefs not found, ThemeOverrides was NOT set. Launch SourceGit once to generate preference.json, then re-run."
}
Write-Output "SourceGit theme files ready ($forkDark, $rendered)"
