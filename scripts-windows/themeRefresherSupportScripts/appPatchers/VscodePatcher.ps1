#Requires -Version 7.0
<#
.SYNOPSIS
  Patches VS Code's workbench.colorCustomizations (and the in-app logo) with the accent color.

.DESCRIPTION
  Port of VscodePatcher.sh. Prefers matugen's resolved primary color (from
  cache\matugen\vscode-colors.json, rendered earlier in the same refresh) so the
  accent matches the "Matugen Theme" extension exactly; falls back to the raw
  seed color otherwise.

  settings.json is JSONC, so only the one property is replaced in the raw text.
  The user's comments and the rest of the file are left untouched; a one-time
  settings.json.wc-bak copy is kept next to it.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Color)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\..\lib\WallpaperChanger.Common.psm1') -DisableNameChecking
$paths = Get-WcPaths

$accent = '#' + (ConvertTo-HexColor $Color)

$matugenCache = Join-Path $paths.MatugenCache 'vscode-colors.json'
if (Test-Path -LiteralPath $matugenCache) {
    try {
        $primary = (Get-Content -LiteralPath $matugenCache -Raw | ConvertFrom-Json).special.cursor
        if ($primary -and (Test-HexColor $primary)) {
            $accent = '#' + (ConvertTo-HexColor $primary)
            Write-Output "VscodePatcher: using matugen's resolved primary ($accent) instead of the raw wallpaper seed"
        }
        else { Write-Output "VscodePatcher: special.cursor missing in $matugenCache, using raw seed color" }
    }
    catch { Write-Output "VscodePatcher: could not read $matugenCache ($($_.Exception.Message)), using raw seed color" }
}
else { Write-Output "VscodePatcher: $matugenCache not found, using raw seed color" }

$userDir = Join-Path $env:APPDATA 'Code\User'
$settingsFile = Join-Path $userDir 'settings.json'
if (-not (Test-Path -LiteralPath $settingsFile)) { Write-Output 'VS Code settings not found, skipping'; return }

# --- in-app logo (media\code-icon.svg) -----------------------------------------
# User installs live in %LOCALAPPDATA%\Programs (writable); system installs in
# Program Files need admin and are skipped with a note.
$baseIcon = Join-Path $paths.Svg 'vscode_base_icon.svg'
if (Test-Path -LiteralPath $baseIcon) {
    $svg = (Get-Content -LiteralPath $baseIcon -Raw).Replace('currentColor', $accent)
    $patched = $false
    foreach ($root in @((Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code'), (Join-Path $env:ProgramFiles 'Microsoft VS Code'))) {
        foreach ($name in 'code-icon.svg', 'vscode-icon.svg') {
            $target = Join-Path $root "resources\app\out\media\$name"
            if (-not (Test-Path -LiteralPath $target)) { continue }
            if ((Get-Content -LiteralPath $target -Raw) -ceq $svg) { continue }
            try { [System.IO.File]::WriteAllText($target, $svg, [System.Text.UTF8Encoding]::new($false)); Write-Output "Patched: $target"; $patched = $true }
            catch [System.UnauthorizedAccessException] { Write-Output "Permission denied: $target (system-wide install; re-run once from an elevated shell to patch it)" }
        }
    }
    if ($patched) {
        foreach ($d in 'CachedData', 'Cache', 'GPUCache') {
            $p = Join-Path $env:APPDATA "Code\$d"
            if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue; Write-Output "Cleared: $p" }
        }
    }
}

# --- color customizations -----------------------------------------------------
$colors = [ordered]@{
    'list.activeSelectionBackground'         = "${accent}99"
    'list.hoverBackground'                   = "${accent}33"
    'list.focusBackground'                   = "${accent}99"
    'list.focusOutline'                      = "${accent}b3"
    'menu.selectionBackground'               = '#00000000'
    'menu.selectionBorder'                   = $accent
    'menu.border'                            = "${accent}33"
    'quickInputList.focusBackground'         = "${accent}99"
    'focusBorder'                            = $accent
    'activityBar.activeBorder'               = $accent
    'activityBarBadge.background'            = $accent
    'badge.background'                       = "${accent}f0"
    'button.background'                      = $accent
    'button.border'                          = $accent
    'button.hoverBackground'                 = "${accent}cc"
    'tab.activeBorderTop'                    = $accent
    'editorCursor.foreground'                = $accent
    'selection.background'                   = "${accent}55"
    'inputValidation.infoBorder'             = $accent
    'panelTitle.activeBorder'                = $accent
    'statusBar.debuggingBackground'          = $accent
    'statusBarItem.prominentBackground'      = $accent
    'editorSuggestWidget.selectedBackground' = "${accent}26"
    'editorBracketMatch.background'          = "${accent}55"
    'terminal.selectionBackground'           = "${accent}33"
    'agentsBadge.background'                 = $accent
    'agentsUnreadBadge.background'           = $accent
}
$body = ($colors.GetEnumerator() | ForEach-Object { "        $(ConvertTo-Json $_.Key -Compress): $(ConvertTo-Json $_.Value -Compress)" }) -join ",`n"
$valueJson = "{`n$body`n    }"

$text = Get-Content -LiteralPath $settingsFile -Raw
if ([string]::IsNullOrWhiteSpace($text)) { $text = '{}' }
$updated = Set-JsoncProperty -Text $text -Name 'workbench.colorCustomizations' -ValueJson $valueJson
if ($updated -ceq $text) { Write-Output "VS Code colors already up to date ($accent)"; return }
Write-WcFile -Path $settingsFile -Content $updated -Backup
Write-Output "VS Code colors updated: $accent"
