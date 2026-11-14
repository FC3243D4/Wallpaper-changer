#Requires -Version 7.0
<#
.SYNOPSIS
  Recolors Vesktop's Discord brand/control accent via QuickCSS.

.DESCRIPTION
  Port of DiscordPatcher.sh. Skipped (and any previous patch removed) when the
  Midnight Discord theme is enabled: Midnight already defines its own accent
  palette (rendered from the matugen template), and these blanket overrides
  would fight with it.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Color)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\..\lib\WallpaperChanger.Common.psm1') -DisableNameChecking

$hex = ConvertTo-HexColor $Color
$vesktopDir = Join-Path $env:APPDATA 'vesktop'
if (-not (Test-Path -LiteralPath $vesktopDir)) { Write-Output "Vesktop not found at $vesktopDir, skipping"; return }

$quickCss = Join-Path $vesktopDir 'settings\quickCss.css'
$settings = Join-Path $vesktopDir 'settings\settings.json'
$markStart = '/* >>> ThemeRefresher accent (auto-generated, do not edit) >>> */'
$markEnd = '/* <<< ThemeRefresher accent <<< */'

# Vencord keeps enabled themes in settings\settings.json ("enabledThemes").
$midnight = $false
if (Test-Path -LiteralPath $settings) {
    $raw = Get-Content -LiteralPath $settings -Raw
    try { $midnight = @((ConvertFrom-Json $raw).enabledThemes) -contains 'midnight-discord.css' }
    catch { $midnight = $raw.Contains('"midnight-discord.css"') }
}
if ($midnight) {
    Write-Output 'Midnight Discord theme is enabled - it already sets its own accent colors; skipping accent patch.'
    if ((Test-Path -LiteralPath $quickCss) -and (Set-MarkedBlock -Path $quickCss -StartMarker $markStart -EndMarker $markEnd -Remove)) {
        Write-Output "Removed previous DiscordPatcher accent block from $quickCss."
    }
    return
}

$hover = Get-BlendedColor $hex @(255, 255, 255) 0.12
$active = Get-BlendedColor $hex @(0, 0, 0) 0.15

# Applied on * (not :root): Discord's components re-declare these custom
# properties locally, and a local declaration beats an inherited value even
# against !important, so forcing it on every element is what actually wins.
$block = @"
*, *::before, *::after {
  --background-brand: #$hex !important;
  --background-brand-hover: $hover !important;
  --background-brand-active: $active !important;
  --text-brand: #$hex !important;
  --icon-brand: #$hex !important;
  --border-brand: #$hex !important;
  --focus-brand: #$hex !important;
  --button-brand-background: #$hex !important;
  --button-brand-background-hover: $hover !important;
  --button-brand-background-active: $active !important;
  --brand-500: #$hex !important;

  --control-primary-background-default: #$hex !important;
  --control-primary-background-hover: $hover !important;
  --control-primary-background-active: $active !important;
  --control-primary-border-default: #$hex !important;
  --control-primary-border-hover: $hover !important;
  --control-primary-border-active: $active !important;
}
"@
Set-MarkedBlock -Path $quickCss -StartMarker $markStart -EndMarker $markEnd -Block $block.TrimEnd() | Out-Null
Write-Output "Discord/Vesktop accent patched -> #$hex"
