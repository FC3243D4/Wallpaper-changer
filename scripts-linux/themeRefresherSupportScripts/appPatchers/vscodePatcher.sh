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