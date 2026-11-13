#Requires -Version 7.0
<#
.SYNOPSIS
  Recolors Ferdium service recipe icons by rewriting each recipe's package.json "defaultIcon".

.DESCRIPTION
  Port of FerdiumPatcher.sh / FerdiumIconPatcher.sh (identical logic, one script
  here). Ferdium only re-reads recipe metadata on process start, so a running
  Ferdium needs a full restart to show new icons (the Full refresh already does
  that).
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Color)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\..\lib\WallpaperChanger.Common.psm1') -DisableNameChecking
$paths = Get-WcPaths

$accent = '#' + (ConvertTo-HexColor $Color)
$recipesDir = Join-Path $env:APPDATA 'Ferdium\recipes'
$outDir = Join-Path $env:APPDATA 'Ferdium\themed-icons'
if (-not (Test-Path -LiteralPath $recipesDir)) { Write-Output "Ferdium recipes folder not found: $recipesDir, skipping"; return }
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

# recipe id -> icon file name, for icons whose name doesn't match the recipe folder
$overrides = @{
    'instagram-direct-messages' = 'instagram_base_icon.svg'
    'android-messages'          = 'messages_base_icon.svg'
    'home-assistant'            = 'home_assistant_base_icon.svg'
    'franz-custom-website'      = '3d_printer_base_icon.svg'
    'office365-owa'             = 'outlook_base_icon.svg'
}
# Recipes shared by several configured services: the icon applies to all of them.
$shared = @('franz-custom-website')

$changed = 0
foreach ($recipe in (Get-ChildItem -LiteralPath $recipesDir -Directory | Where-Object Name -ne 'temp')) {
    $id = $recipe.Name
    $pkg = Join-Path $recipe.FullName 'package.json'
    if (-not (Test-Path -LiteralPath $pkg)) { continue }

    $iconFile = if ($overrides.ContainsKey($id)) { $overrides[$id] } else { "${id}_base_icon.svg" }
    $src = Join-Path $paths.Svg $iconFile
    if (-not (Test-Path -LiteralPath $src)) { continue }      # no base icon for this recipe

    if ($id -in $shared) { Write-Output "[$id] WARNING: shared recipe - this icon applies to ALL services using it" }

    # Strip any external-DTD DOCTYPE (can stop Electron's sandboxed webview from
    # rendering the SVG) and recolor flat black / near-black / currentColor.
    # currentColor must be resolved here: it is loaded via a file URI with no
    # page color context and would fall back to black.
    $svg = Get-Content -LiteralPath $src -Raw
    $svg = [regex]::Replace($svg, '(?s)<!DOCTYPE[^>]*>', '')
    $svg = [regex]::Replace($svg, '#000000', $accent, 'IgnoreCase')
    $svg = [regex]::Replace($svg, '#0f0f0f', $accent, 'IgnoreCase')
    $svg = $svg.Replace('fill="currentColor"', "fill=`"$accent`"").Replace('stroke="currentColor"', "stroke=`"$accent`"")
    $dst = Join-Path $outDir "$id.svg"
    Write-WcFile -Path $dst -Content $svg

    $newUri = [System.Uri]::new($dst).AbsoluteUri                    # file:///C:/Users/.../id.svg
    $text = Get-Content -LiteralPath $pkg -Raw
    $m = [regex]::Match($text, '"defaultIcon"\s*:\s*"([^"]*)"')
    if (-not $m.Success) { Write-Output "[$id] no defaultIcon field - skipping"; continue }
    if ($m.Groups[1].Value -ceq $newUri) { continue }
    $updated = $text.Substring(0, $m.Index) + "`"defaultIcon`": `"$newUri`"" + $text.Substring($m.Index + $m.Length)
    Write-WcFile -Path $pkg -Content $updated
    Write-Output "[$id] patched"
    $changed++
}
Write-Output "Ferdium icons patched with $accent ($changed changed)"
if ($changed -gt 0 -and (Get-Process -Name 'Ferdium' -ErrorAction SilentlyContinue)) {
    Write-Output 'NOTE: Ferdium caches recipe metadata in memory - restart it fully (quit from the tray) to see the new icons.'
}
