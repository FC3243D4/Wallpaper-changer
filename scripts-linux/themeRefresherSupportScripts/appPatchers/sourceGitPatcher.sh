#!/usr/bin/env bash
# sourceGitPatcher.sh
# Ensures both the static ForkDark theme and the matugen-rendered theme exist
# in SourceGit's config dir, then applies the matugen theme ONLY if SourceGit
# isn't already pointed at one of these two (i.e. leaves a manual choice of
# either ForkDark or the matugen theme untouched).
# Usage: sourceGitPatcher.sh [path_to_rendered_theme_json]

set -euo pipefail

SOURCEGIT_DIR="$HOME/.sourcegit"
RENDERED="${1:-$SOURCEGIT_DIR/matugen-theme.json}"
SOURCEGIT_PREFS="$SOURCEGIT_DIR/preference.json"
FORKDARK_THEME="$SOURCEGIT_DIR/ForkDark.json"

if [ ! -f "$RENDERED" ]; then
    echo "Rendered matugen SourceGit theme not found at $RENDERED (run matugen first)" >&2
    exit 1
fi

if ! python3 -c "import json; json.load(open('$RENDERED'))" 2>/dev/null; then
    echo "Rendered theme at $RENDERED is not valid JSON, aborting" >&2
    exit 1
fi

# SourceGit's theme loader expects uppercase hex (#RRGGBB); matugen renders
# lowercase, so normalize in place rather than depending on a to_upper
# filter (not available in every matugen version).
python3 - << EOF
import re
with open('$RENDERED', 'r') as f:
    content = f.read()
content = re.sub(r'#[0-9a-fA-F]{6}', lambda m: m.group(0).upper(), content)
with open('$RENDERED', 'w') as f:
    f.write(content)
EOF

mkdir -p "$SOURCEGIT_DIR"

# Always keep the static ForkDark theme available as a selectable option.
cat > "$FORKDARK_THEME" << 'FORKDARK_EOF'
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
FORKDARK_EOF

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