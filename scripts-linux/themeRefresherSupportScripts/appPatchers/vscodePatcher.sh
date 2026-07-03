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
import colorsys

def hex_to_hsv(h):
    h = h.lstrip('#')
    r, g, b = int(h[0:2],16)/255, int(h[2:4],16)/255, int(h[4:6],16)/255
    return colorsys.rgb_to_hsv(r, g, b)

def hsv_to_hex(h, s, v):
    r, g, b = colorsys.hsv_to_rgb(h % 1.0, min(1,s), min(1,v))
    return '#{:02X}{:02X}{:02X}'.format(int(r*255), int(g*255), int(b*255))

base_h, base_s, base_v = hex_to_hsv("$color")
dark  = hsv_to_hex(base_h, base_s, max(0, base_v - 0.15))
mid   = hsv_to_hex(base_h, base_s, base_v)
light = hsv_to_hex(base_h, max(0, base_s - 0.2), min(1, base_v + 0.15))

with open("$VSCODE_BASE_ICON", "r") as f:
    svg = f.read()
svg = svg.replace("#0065A9", dark)
svg = svg.replace("#007ACC", mid)
svg = svg.replace("#1F9CF0", light)

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