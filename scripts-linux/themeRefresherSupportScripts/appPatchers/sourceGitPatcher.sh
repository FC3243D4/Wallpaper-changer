#!/usr/bin/env bash
# sourceGitPatcher.sh
# Patches SourceGit ForkDark theme with the accent color and generated graph colors.
# Usage: sourceGitPatcher.sh <hex_color>

color="${1,,}"

if [ -z "$color" ]; then
    echo "Usage: $0 <hex_color>" >&2
    exit 1
fi

accent="#$color"
SOURCEGIT_THEME="$HOME/.sourcegit/ForkDark.json"
SOURCEGIT_BASE="${SOURCEGIT_THEME}.base"
SOURCEGIT_PREFS="$HOME/.sourcegit/preference.json"

mkdir -p "$HOME/.sourcegit"

if [ ! -f "$SOURCEGIT_BASE" ]; then
    echo "SourceGit base theme not found at $SOURCEGIT_BASE, creating default"
    cat > "$SOURCEGIT_BASE" << 'BASE_THEME_EOF'
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
        "#ff9502",
        "#ff2968",
        "#ffcc00",
        "#4EC9B0",
        "#cb73e1",
        "#1cadf8",
        "#CE9178",
        "#C8C8C8",
        "#808080",
        "#a2845e",
        "#99442b",
        "#22A822",
        "#CC0000"
    ]
}
BASE_THEME_EOF
fi

[ -f "$SOURCEGIT_PREFS" ] && python3 - << EOF
import json
with open('$SOURCEGIT_PREFS', 'r') as f:
    p = json.load(f)
p['ThemeOverrides'] = '$SOURCEGIT_THEME'
with open('$SOURCEGIT_PREFS', 'w') as f:
    json.dump(p, f, indent=4)
EOF

python3 - << EOF
import json, colorsys

def hex_to_hsv(h):
    r, g, b = int(h[0:2],16)/255, int(h[2:4],16)/255, int(h[4:6],16)/255
    return colorsys.rgb_to_hsv(r, g, b)

def hsv_to_hex(h, s, v):
    r, g, b = colorsys.hsv_to_rgb(h % 1.0, s, v)
    return '#{:02X}{:02X}{:02X}'.format(int(r*255), int(g*255), int(b*255))

base_h, base_s, base_v = hex_to_hsv('$color')
s = max(base_s, 0.6)
v = max(base_v, 0.75)
graph_colors = [hsv_to_hex((base_h + i/13.0) % 1.0, s, v) for i in range(13)]

with open('$SOURCEGIT_BASE', 'r') as f:
    theme = json.load(f)
theme['BasicColors']['SystemAccentColor'] = '${accent}'.upper()
theme['BasicColors']['Badge'] = '${accent}'.upper()
theme['GraphColors'] = graph_colors
with open('$SOURCEGIT_THEME', 'w') as f:
    json.dump(theme, f, indent=4)
print('SourceGit theme updated')
EOF