#!/usr/bin/env bash
# VscodePatcher.sh
# Patches VS Code color customizations and the activity-bar icon with the
# accent color.
#
# Prefers matugen's resolved primary color (from vscode-colors.json,
# written by ThemeRefresher.sh's earlier `matugen color hex` call) over
# the raw wallpaper-sampled seed, to match the Matugen Theme VS Code
# extension's own accent exactly. Falls back to the raw seed if that
# cache/jq isn't available.
# Usage: VscodePatcher.sh <hex_color>

color="${1,,}"

if [ -z "$color" ]; then
    echo "Usage: $0 <hex_color>" >&2
    exit 1
fi

accent="#$color"

vscodeMatugenCacheFile="$HOME/.cache/matugen/vscode-colors.json"
if [ -f "$vscodeMatugenCacheFile" ] && command -v jq &>/dev/null; then
    resolvedPrimary=$(jq -r '.special.cursor // empty' "$vscodeMatugenCacheFile" 2>/dev/null)
    if [ -n "$resolvedPrimary" ]; then
        accent="$resolvedPrimary"
        color="${accent#\#}"
        color="${color,,}"
        echo "VscodePatcher: using matugen's resolved primary ($accent) instead of the raw wallpaper seed"
    else
        echo "VscodePatcher: special.cursor not found in $vscodeMatugenCacheFile, falling back to raw seed color"
    fi
else
    echo "VscodePatcher: $vscodeMatugenCacheFile not found (or jq missing), falling back to raw seed color"
fi

vscodeSettingsFile="$HOME/.config/Code/User/settings.json"
vscodeBaseIconFile="$HOME/.config/WallpaperChanger/themeRefresherSupportScripts/svg/vscode_base_icon.svg"

if [ ! -f "$vscodeSettingsFile" ]; then
    echo "VS Code settings not found, skipping"
    exit 0
fi

# Patch VS Code's source SVG (requires ownership of /usr/share/code)
if [ -f "$vscodeBaseIconFile" ]; then
    python3 - << EOF

with open("$vscodeBaseIconFile", "r") as f:
    svg = f.read()
svg = svg.replace("currentColor", "$accent")

targets = [
    "/usr/share/code/resources/app/out/media/code-icon.svg",
    "/usr/share/code/resources/app/out/media/vscode-icon.svg",
]
for path in targets:
    try:
        with open(path, "w") as f:
            f.write(svg)
        print(f"Patched: {path}")
    except PermissionError:
        print(f"Permission denied: {path} (run: sudo chown -R \$USER /usr/share/code)")

# Clear cache so new icon is picked up
import shutil, os
for cache_dir in [
    os.path.expanduser("~/.config/Code/CachedData"),
    os.path.expanduser("~/.config/Code/Cache"),
    os.path.expanduser("~/.config/Code/GPUCache"),
]:
    if os.path.exists(cache_dir):
        shutil.rmtree(cache_dir)
        print(f"Cleared: {cache_dir}")
EOF
fi

# Patch color customizations
python3 - << EOF
import json

with open("$vscodeSettingsFile", "r") as f:
    s = json.load(f)

s["workbench.colorCustomizations"] = {
    "list.activeSelectionBackground":         "${accent}99",
    "list.hoverBackground":                   "${accent}33",
    "list.focusBackground":                   "${accent}99",
    "list.focusOutline":                      "${accent}b3",
    "menu.selectionBackground":               "#00000000",
    "menu.selectionBorder":                   "$accent",
    "menu.border":                            "${accent}33",
    "quickInputList.focusBackground":         "${accent}99",
    "focusBorder":                            "$accent",
    "activityBar.activeBorder":               "$accent",
    "activityBarBadge.background":            "$accent",
    "badge.background":                       "${accent}f0",
    "button.background":                      "$accent",
    "button.border":                          "$accent",
    "button.hoverBackground":                 "${accent}cc",
    "tab.activeBorderTop":                    "$accent",
    "editorCursor.foreground":                "$accent",
    "selection.background":                   "${accent}55",
    "inputValidation.infoBorder":             "$accent",
    "panelTitle.activeBorder":                "$accent",
    "statusBar.debuggingBackground":          "$accent",
    "statusBarItem.prominentBackground":      "$accent",
    "editorSuggestWidget.selectedBackground": "${accent}26",
    "editorBracketMatch.background":          "${accent}55",
    "terminal.selectionBackground":           "${accent}33",
    "agentsBadge.background":                 "$accent",
    "agentsUnreadBadge.background":           "$accent",
}

with open("$vscodeSettingsFile", "w") as f:
    json.dump(s, f, indent=4)
print("VS Code colors updated:", "$accent")
EOF