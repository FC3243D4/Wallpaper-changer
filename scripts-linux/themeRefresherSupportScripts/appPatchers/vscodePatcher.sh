#!/usr/bin/env bash
# vscodePatcher.sh
# Patches VS Code color customizations and activity bar icon with the accent color.
# Usage: vscodePatcher.sh <hex_color>

color="${1,,}"

if [ -z "$color" ]; then
    echo "Usage: $0 <hex_color>" >&2
    exit 1
fi

accent="#$color"

# Match the Matugen Theme VS Code extension's actual accent instead of just
# "the same seed". $color here is the raw wallpaper-sampled seed from
# colorChooser.sh, but the extension reads matugen's *resolved* colors from
# ~/.cache/matugen/vscode-colors.json (special.cursor = colors.primary,
# tonally processed, not the raw seed). Since themeRefresher.sh already runs
# `matugen color hex` before calling this script, that cache file reflects
# this exact wallpaper change — read it back rather than re-deriving it here.
# Falls back to the raw seed if the cache file/jq aren't available, so this
# degrades to the previous behavior rather than failing.
VSCODE_MATUGEN_CACHE="$HOME/.cache/matugen/vscode-colors.json"
if [ -f "$VSCODE_MATUGEN_CACHE" ] && command -v jq &>/dev/null; then
    resolved_primary=$(jq -r '.special.cursor // empty' "$VSCODE_MATUGEN_CACHE" 2>/dev/null)
    if [ -n "$resolved_primary" ]; then
        accent="$resolved_primary"
        color="${accent#\#}"
        color="${color,,}"
        echo "vscodePatcher: using matugen's resolved primary ($accent) instead of the raw wallpaper seed"
    else
        echo "vscodePatcher: special.cursor not found in $VSCODE_MATUGEN_CACHE, falling back to raw seed color"
    fi
else
    echo "vscodePatcher: $VSCODE_MATUGEN_CACHE not found (or jq missing), falling back to raw seed color"
fi

VSCODE_SETTINGS="$HOME/.config/Code/User/settings.json"
VSCODE_BASE_ICON="$HOME/.config/WallpaperChanger/themeRefresherSupportScripts/svg/vscode_base_icon.svg"

if [ ! -f "$VSCODE_SETTINGS" ]; then
    echo "VS Code settings not found, skipping"
    exit 0
fi

# Patch VSCode source SVG (requires ownership of /usr/share/code)
if [ -f "$VSCODE_BASE_ICON" ]; then
    python3 - << EOF

with open("$VSCODE_BASE_ICON", "r") as f:
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

with open("$VSCODE_SETTINGS", "r") as f:
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

with open("$VSCODE_SETTINGS", "w") as f:
    json.dump(s, f, indent=4)
print("VS Code colors updated:", "$accent")
EOF