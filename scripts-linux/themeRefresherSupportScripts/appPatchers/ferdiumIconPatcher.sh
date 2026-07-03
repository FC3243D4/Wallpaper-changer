#!/usr/bin/env bash
# ferdiumIconPatcher.sh
# Patches Ferdium service recipe icons with the accent color by rewriting
# each recipe's package.json "defaultIcon" field to a local file:// URI.
#
# NOTE: Ferdium only re-reads recipe package.json on process start. A window
# reload is not enough if Ferdium runs in the tray/background — you must
# fully kill and relaunch the process (see reminder at the end of this script).
#
# Usage: ferdiumIconPatcher.sh <hex_color>

color="${1,,}"

if [ -z "$color" ]; then
    echo "Usage: $0 <hex_color>" >&2
    exit 1
fi

accent="#$color"
SUPPORT="$HOME/.config/WallpaperChanger/themeRefresherSupportScripts"
ICONS="$SUPPORT/svg"
FERDIUM_RECIPES="$HOME/.config/Ferdium/recipes"
FERDIUM_ICON_OUT="$SUPPORT/ferdium-icons"

mkdir -p "$FERDIUM_ICON_OUT"

if [ ! -d "$FERDIUM_RECIPES" ]; then
    echo "Ferdium recipes directory not found: $FERDIUM_RECIPES" >&2
    exit 1
fi

restarted_needed=0

# Some downloaded icon filenames don't match their Ferdium recipe folder name
# 1:1. Map recipe_id -> actual filename in $ICONS here as needed.
declare -A ICON_FILE_OVERRIDES=(
    ["instagram-direct-messages"]="instagram_base_icon.svg"
    ["android-messages"]="messages_base_icon.svg"
    ["home-assistant"]="home_assistant_base_icon.svg"
    ["franz-custom-website"]="3d_printer_base_icon.svg"
)

# Recipes that are SHARED across multiple configured services rather than
# dedicated to one app (e.g. Ferdium's generic "Custom Website" recipe).
# Ferdium doesn't expose a per-instance icon override at the recipe-file
# level, so patching these affects every service built on that recipe —
# there is no reliable way to target just one instance by name from here.
SHARED_RECIPES=("franz-custom-website")

is_shared_recipe() {
    local id="$1"
    for shared in "${SHARED_RECIPES[@]}"; do
        [ "$id" = "$shared" ] && return 0
    done
    return 1
}

for recipe_dir in "$FERDIUM_RECIPES"/*/; do
    recipe_id="$(basename "$recipe_dir")"
    [ "$recipe_id" = "temp" ] && continue

    pkg="$recipe_dir/package.json"
    if [ ! -f "$pkg" ]; then
        echo "Recipe '$recipe_id' has no package.json — skipping"
        continue
    fi
    echo "Recipe '$recipe_id' found"

    icon_file="${ICON_FILE_OVERRIDES[$recipe_id]:-${recipe_id}_base_icon.svg}"
    src="$ICONS/$icon_file"

    if [ ! -f "$src" ]; then
        echo "  no base icon (expected $src) — skipping"
        continue
    fi

    if is_shared_recipe "$recipe_id"; then
        echo "  WARNING: '$recipe_id' is a shared recipe — this icon will apply"
        echo "  to ALL services using it, not just one. Ferdium has no per-instance"
        echo "  icon override at the recipe-file level, so per-service targeting"
        echo "  by name isn't possible from this script."
    fi

    dst="$FERDIUM_ICON_OUT/$recipe_id.svg"

    # Strip any DOCTYPE declaration referencing an external DTD — Electron's
    # sandboxed webview can fail to render the whole SVG if it can't resolve
    # that reference over file://. Harmless to remove; doesn't affect the icon.
    # Then patch flat-hex, near-black gray, and currentColor conventions —
    # whichever the source icon actually uses, this covers it.
    python3 - "$src" "$dst" "$accent" << 'EOF'
import re
import sys

src, dst, accent = sys.argv[1], sys.argv[2], sys.argv[3]
with open(src, "r") as f:
    content = f.read()

content = re.sub(r"<!DOCTYPE[^>]*>", "", content, flags=re.DOTALL)
content = re.sub(r"#000000", accent, content, flags=re.IGNORECASE)
content = re.sub(r"#0f0f0f", accent, content, flags=re.IGNORECASE)
content = content.replace('fill="currentColor"', f'fill="{accent}"')

with open(dst, "w") as f:
    f.write(content)
EOF

    new_uri="file://$dst"
    current_uri=$(grep -m1 '"defaultIcon"' "$pkg" | sed -E 's/.*"defaultIcon"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')

    if [ "$current_uri" != "$new_uri" ]; then
        sed -i -E "s|\"defaultIcon\"[[:space:]]*:[[:space:]]*\"[^\"]*\"|\"defaultIcon\": \"$new_uri\"|" "$pkg"
        echo "  patched"
        restarted_needed=1
    else
        echo "  already up to date"
    fi
done

echo "Ferdium icons patched with $accent"

if [ "$restarted_needed" -eq 1 ]; then
    echo
    echo "NOTE: Ferdium caches recipe metadata in memory. If it's running in the"
    echo "background/tray, a window reload will NOT pick up these changes."
    echo "Fully restart it to see the new icons:"
    echo "    pkill -f ferdium && ferdium &"
fi