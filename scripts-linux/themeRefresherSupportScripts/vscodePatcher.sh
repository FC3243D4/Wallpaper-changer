#!/usr/bin/env bash
# vscodePatcher.sh
# Patches VS Code color customizations with the accent color.
# Usage: vscodePatcher.sh <hex_color>

color="${1,,}"

if [ -z "$color" ]; then
    echo "Usage: $0 <hex_color>" >&2
    exit 1
fi

accent="#$color"
VSCODE_SETTINGS="$HOME/.config/Code/User/settings.json"

if [ ! -f "$VSCODE_SETTINGS" ]; then
    echo "VS Code settings not found, skipping"
    exit 0
fi

python3 - << EOF
import json
with open('$VSCODE_SETTINGS', 'r') as f:
    s = json.load(f)
s['workbench.colorCustomizations'] = {
    "list.activeSelectionBackground": "${accent}99",
    "list.hoverBackground":           "${accent}33",
    "list.focusBackground":           "${accent}99",
    "menu.selectionBackground":       "#00000000",
    "menu.selectionBorder":           "$accent",
    "menu.border":                    "${accent}33",
    "quickInputList.focusBackground": "${accent}99",
    "focusBorder":                    "$accent",
    "activityBar.activeBorder":       "$accent",
    "tab.activeBorderTop":            "$accent",
    "editorCursor.foreground":        "$accent",
    "selection.background":           "${accent}55"
}
with open('$VSCODE_SETTINGS', 'w') as f:
    json.dump(s, f, indent=4)
print('VS Code colors updated')
EOF
