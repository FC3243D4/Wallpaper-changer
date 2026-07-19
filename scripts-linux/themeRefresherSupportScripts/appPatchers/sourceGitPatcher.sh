#!/usr/bin/env bash
# sourceGitPatcher.sh
# Applies the matugen-rendered SourceGit theme (produced from matugen-theme.json)
# to SourceGit by pointing preference.json at it.
# Usage: sourceGitPatcher.sh [path_to_rendered_theme_json]

set -euo pipefail

SOURCEGIT_DIR="$HOME/.sourcegit"
RENDERED="${1:-$SOURCEGIT_DIR/matugen-theme.json}"
SOURCEGIT_PREFS="$SOURCEGIT_DIR/preference.json"

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

if [ -f "$SOURCEGIT_PREFS" ]; then
    python3 - << EOF
import json
with open('$SOURCEGIT_PREFS', 'r') as f:
    p = json.load(f)
p['ThemeOverrides'] = '$RENDERED'
with open('$SOURCEGIT_PREFS', 'w') as f:
    json.dump(p, f, indent=4)
EOF
    echo "preference.json ThemeOverrides -> $RENDERED"
else
    echo "Warning: $SOURCEGIT_PREFS not found, ThemeOverrides was NOT set. Launch SourceGit once to generate preference.json, then re-run this script." >&2
fi

echo "SourceGit theme applied from $RENDERED"