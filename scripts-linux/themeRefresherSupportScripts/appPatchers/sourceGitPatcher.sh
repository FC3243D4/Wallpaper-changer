#!/usr/bin/env bash
# sourceGitPatcher.sh
# Ensures both ForkDark.json and the matugen-rendered theme exist in
# SourceGit's config dir, then applies the matugen theme ONLY if SourceGit
# isn't already pointed at one of these two (leaves a manual choice of
# either theme untouched).
#
# ForkDark.json is regenerated the original way: a static base theme
# patched with just SystemAccentColor / Badge / GraphColors, derived via
# HSV rotation from the accent color.
# Usage: sourceGitPatcher.sh <hex_color>

set -euo pipefail

color="${1,,}"

if [ -z "$color" ]; then
    echo "Usage: $0 <hex_color>" >&2
    exit 1
fi

accent="#${color^^}"

SOURCEGIT_DIR="$HOME/.sourcegit"
RENDERED="$SOURCEGIT_DIR/matugen-theme.json"
SOURCEGIT_PREFS="$SOURCEGIT_DIR/preference.json"
FORKDARK_THEME="$SOURCEGIT_DIR/ForkDark.json"
FORKDARK_BASE="${FORKDARK_THEME}.base"

if [ ! -f "$RENDERED" ]; then
    echo "Rendered matugen SourceGit theme not found at $RENDERED (run matugen first)" >&2
    exit 1
fi

# Validates the file is real JSON and normalizes hex case in one pass —
# SourceGit's theme loader expects uppercase hex (#RRGGBB); matugen renders
# lowercase, so normalize in place rather than depending on a to_upper
# filter (not available in every matugen version). Previously two separate
# python3 invocations each opened this same file; merged since the second
# one has nothing to do until the first has already proven the file parses.
if ! python3 - << EOF
import json, re, sys
path = '$RENDERED'
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
    echo "Rendered theme at $RENDERED is not valid JSON, aborting" >&2
    exit 1
fi

mkdir -p "$SOURCEGIT_DIR"

# Create the ForkDark base reference (original static theme) if missing.
if [ ! -f "$FORKDARK_BASE" ]; then
    cat > "$FORKDARK_BASE" << 'BASE_THEME_EOF'
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

# Regenerate ForkDark.json from the base using the original HSV-rotation
# logic, seeded directly by the accent color passed on the command line.
python3 - << EOF
import json, colorsys

def hex_to_hsv(h):
    r, g, b = int(h[0:2], 16) / 255, int(h[2:4], 16) / 255, int(h[4:6], 16) / 255
    return colorsys.rgb_to_hsv(r, g, b)

def hsv_to_hex(h, s, v):
    r, g, b = colorsys.hsv_to_rgb(h % 1.0, s, v)
    return '#{:02X}{:02X}{:02X}'.format(int(r * 255), int(g * 255), int(b * 255))

base_h, base_s, base_v = hex_to_hsv('$color')
s = max(base_s, 0.6)
v = max(base_v, 0.75)
graph_colors = [hsv_to_hex((base_h + i / 13.0) % 1.0, s, v) for i in range(13)]

with open('$FORKDARK_BASE', 'r') as f:
    theme = json.load(f)
theme['BasicColors']['SystemAccentColor'] = '${accent}'.upper()
theme['BasicColors']['Badge'] = '${accent}'.upper()
theme['GraphColors'] = graph_colors

with open('$FORKDARK_THEME', 'w') as f:
    json.dump(theme, f, indent=4)
print('ForkDark.json updated (accent:', '${accent}'.upper(), ')')
EOF

# Only take over ThemeOverrides if it isn't already pointed at ForkDark or
# the matugen theme — a manual choice between these two is left alone.
if [ -f "$SOURCEGIT_PREFS" ]; then
    python3 - << EOF
import json
with open('$SOURCEGIT_PREFS', 'r') as f:
    p = json.load(f)
current = p.get('ThemeOverrides', '')
managed = {'$FORKDARK_THEME', '$RENDERED'}
if current in managed:
    print(f"ThemeOverrides already set to {current!r}, leaving as is")
else:
    p['ThemeOverrides'] = '$RENDERED'
    with open('$SOURCEGIT_PREFS', 'w') as f:
        json.dump(p, f, indent=4)
    print(f"ThemeOverrides was {current!r}, set to matugen theme: $RENDERED")
EOF
else
    echo "Warning: $SOURCEGIT_PREFS not found, ThemeOverrides was NOT set. Launch SourceGit once to generate preference.json, then re-run this script." >&2
fi

echo "SourceGit theme files ready ($FORKDARK_THEME, $RENDERED)"