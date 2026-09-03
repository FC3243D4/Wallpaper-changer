#!/usr/bin/env bash
# sourceGitPatcher.sh
# Regenerates ForkDark.json (a static theme patched with just the accent
# color's SystemAccentColor/Badge/GraphColors), and normalizes/validates
# the matugen-rendered SourceGit theme. Only switches SourceGit's active
# ThemeOverrides to the matugen theme if it isn't already pointed at
# either of these two — leaves a manual theme choice untouched.
# Usage: sourceGitPatcher.sh <hex_color>

set -euo pipefail

color="${1,,}"

if [ -z "$color" ]; then
    echo "Usage: $0 <hex_color>" >&2
    exit 1
fi

accent="#${color^^}"

sourceGitDir="$HOME/.sourcegit"
renderedThemeFile="$sourceGitDir/matugen-theme.json"
sourceGitPrefsFile="$sourceGitDir/preference.json"
forkDarkThemeFile="$sourceGitDir/ForkDark.json"
forkDarkBaseFile="${forkDarkThemeFile}.base"

if [ ! -f "$renderedThemeFile" ]; then
    echo "Rendered matugen SourceGit theme not found at $renderedThemeFile (run matugen first)" >&2
    exit 1
fi

# Validate the rendered theme is real JSON and normalize hex case to
# uppercase (SourceGit's theme loader expects #RRGGBB; matugen renders
# lowercase). One pass does both, so the JSON is only ever parsed once.
if ! python3 - << EOF
import json, re, sys
path = '$renderedThemeFile'
with open(path, 'r') as f:
    content = f.read()
try:
    json.loads(content)
except ValueError:
    sys.exit(1)
content = re.sub(r'#[0-9a-fA-F]{6}', lambda m: m.group(0).upper(), content)
with open(path, 'w') as f:
    f.write(content)
EOF
then
    echo "Rendered theme at $renderedThemeFile is not valid JSON, aborting" >&2
    exit 1
fi

mkdir -p "$sourceGitDir"

# Create the ForkDark base reference (original static theme) if missing.
if [ ! -f "$forkDarkBaseFile" ]; then
    cat > "$forkDarkBaseFile" << 'BASE_THEME_EOF'
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

# Regenerate ForkDark.json from the base, seeding the original
# HSV-rotation logic directly from the accent color.
python3 - << EOF
import json, colorsys

def hex_to_hsv(h):
    r, g, b = int(h[0:2], 16) / 255, int(h[2:4], 16) / 255, int(h[4:6], 16) / 255
    return colorsys.rgb_to_hsv(r, g, b)

def hsv_to_hex(h, s, v):
    r, g, b = colorsys.hsv_to_rgb(h % 1.0, s, v)
    return '#{:02X}{:02X}{:02X}'.format(int(r * 255), int(g * 255), int(b * 255))

baseHue, baseSat, baseVal = hex_to_hsv('$color')
sat = max(baseSat, 0.6)
val = max(baseVal, 0.75)
graphColors = [hsv_to_hex((baseHue + i / 13.0) % 1.0, sat, val) for i in range(13)]

with open('$forkDarkBaseFile', 'r') as f:
    theme = json.load(f)
theme['BasicColors']['SystemAccentColor'] = '${accent}'.upper()
theme['BasicColors']['Badge'] = '${accent}'.upper()
theme['GraphColors'] = graphColors

with open('$forkDarkThemeFile', 'w') as f:
    json.dump(theme, f, indent=4)
print('ForkDark.json updated (accent:', '${accent}'.upper(), ')')
EOF

# Only take over ThemeOverrides if it isn't already pointed at ForkDark or
# the matugen theme — a manual choice between these two is left alone.
if [ -f "$sourceGitPrefsFile" ]; then
    python3 - << EOF
import json
with open('$sourceGitPrefsFile', 'r') as f:
    prefs = json.load(f)
current = prefs.get('ThemeOverrides', '')
managed = {'$forkDarkThemeFile', '$renderedThemeFile'}
if current in managed:
    print(f"ThemeOverrides already set to {current!r}, leaving as is")
else:
    prefs['ThemeOverrides'] = '$renderedThemeFile'
    with open('$sourceGitPrefsFile', 'w') as f:
        json.dump(prefs, f, indent=4)
    print(f"ThemeOverrides was {current!r}, set to matugen theme: $renderedThemeFile")
EOF
else
    echo "Warning: $sourceGitPrefsFile not found, ThemeOverrides was NOT set. Launch SourceGit once to generate preference.json, then re-run this script." >&2
fi

echo "SourceGit theme files ready ($forkDarkThemeFile, $renderedThemeFile)"