#!/usr/bin/env bash
# ferdiumPatcher.sh
# NOTE: functionally identical to ferdiumIconPatcher.sh (same recipe-icon
# patching logic) — kept as a separate entry point since themeRefresher.sh
# calls both. Only difference is how each recipe's output is line-prefixed
# below (a live `sed -u` pipe here vs. a temp-file capture there).
#
# Patches Ferdium service recipe icons with the accent color by rewriting
# each recipe's package.json "defaultIcon" field to a local file:// URI.
#
# NOTE: Ferdium only re-reads recipe package.json on process start — a
# window reload isn't enough if it's running in the tray/background. If
# any icon changed, this prints a reminder to fully restart it.
#
# Usage: ferdiumPatcher.sh <hex_color>

color="${1,,}"

if [ -z "$color" ]; then
    echo "Usage: $0 <hex_color>" >&2
    exit 1
fi

accent="#$color"
supportDir="$HOME/.config/WallpaperChanger/themeRefresherSupportScripts"
iconsDir="$supportDir/svg"
ferdiumRecipesDir="$HOME/.config/Ferdium/recipes"
ferdiumIconOutDir="$HOME/.config/Ferdium/themed-icons"

mkdir -p "$ferdiumIconOutDir"

if [ ! -d "$ferdiumRecipesDir" ]; then
    echo "Ferdium recipes directory not found: $ferdiumRecipesDir" >&2
    exit 1
fi

restartNeeded=0

# Some downloaded icon filenames don't match their Ferdium recipe folder
# name 1:1 — map recipeId -> actual filename in $iconsDir here as needed.
declare -A iconFileOverrides=(
    ["instagram-direct-messages"]="instagram_base_icon.svg"
    ["android-messages"]="messages_base_icon.svg"
    ["home-assistant"]="home_assistant_base_icon.svg"
    ["franz-custom-website"]="3d_printer_base_icon.svg"
    ["office365-owa"]="outlook_base_icon.svg"
)

# Recipes shared across multiple configured services (e.g. Ferdium's
# generic "Custom Website" recipe) rather than dedicated to one app.
# Ferdium has no per-instance icon override at the recipe-file level, so
# patching these affects every service built on that recipe.
sharedRecipes=("franz-custom-website")

is_shared_recipe() {
    local recipeId="$1"
    for shared in "${sharedRecipes[@]}"; do
        [ "$recipeId" = "$shared" ] && return 0
    done
    return 1
}

# Processes one recipe in its own backgrounded subshell (see the loop
# below) — safe since each recipe writes only its own output SVG/
# package.json. Returns 2 specifically to signal "icon changed, Ferdium
# needs a restart" — a background subshell can't set a parent-shell
# variable directly, so the exit code carries that signal back out.
process_recipe() {
    local recipeDir="$1"
    local recipeId
    recipeId="$(basename "$recipeDir")"

    local pkgFile="$recipeDir/package.json"
    if [ ! -f "$pkgFile" ]; then
        echo "Recipe '$recipeId' has no package.json — skipping"
        return 0
    fi
    echo "Recipe '$recipeId' found"

    local iconFile="${iconFileOverrides[$recipeId]:-${recipeId}_base_icon.svg}"
    local srcSvg="$iconsDir/$iconFile"

    if [ ! -f "$srcSvg" ]; then
        echo "  no base icon (expected $srcSvg) — skipping"
        return 0
    fi

    if is_shared_recipe "$recipeId"; then
        echo "  WARNING: '$recipeId' is a shared recipe — this icon will apply"
        echo "  to ALL services using it, not just one. Ferdium has no per-instance"
        echo "  icon override at the recipe-file level, so per-service targeting"
        echo "  by name isn't possible from this script."
    fi

    local dstSvg="$ferdiumIconOutDir/$recipeId.svg"

    # Strip any external-DTD DOCTYPE (Electron's sandboxed webview can
    # fail to render the whole SVG otherwise) and recolor whichever
    # convention the source icon uses: flat hex, near-black gray, or
    # currentColor (fill and/or Tabler-style stroke). currentColor must be
    # resolved here — Ferdium loads these via a file:// defaultIcon URI
    # with no page color context, so it would otherwise fall back to black.
    python3 - "$srcSvg" "$dstSvg" "$accent" << 'EOF'
import re
import sys

src, dst, accent = sys.argv[1], sys.argv[2], sys.argv[3]
with open(src, "r") as f:
    content = f.read()

content = re.sub(r"<!DOCTYPE[^>]*>", "", content, flags=re.DOTALL)
content = re.sub(r"#000000", accent, content, flags=re.IGNORECASE)
content = re.sub(r"#0f0f0f", accent, content, flags=re.IGNORECASE)
content = content.replace('fill="currentColor"', f'fill="{accent}"')
content = content.replace('stroke="currentColor"', f'stroke="{accent}"')

with open(dst, "w") as f:
    f.write(content)
EOF

    local newUri="file://$dstSvg"
    local currentUri
    currentUri=$(grep -m1 '"defaultIcon"' "$pkgFile" | sed -E 's/.*"defaultIcon"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')

    if [ "$currentUri" != "$newUri" ]; then
        sed -i -E "s|\"defaultIcon\"[[:space:]]*:[[:space:]]*\"[^\"]*\"|\"defaultIcon\": \"$newUri\"|" "$pkgFile"
        echo "  patched"
        return 2
    else
        echo "  already up to date"
        return 0
    fi
}

declare -a recipePids=()

for recipeDir in "$ferdiumRecipesDir"/*/; do
    recipeId="$(basename "$recipeDir")"
    [ "$recipeId" = "temp" ] && continue

    (
        process_recipe "$recipeDir" 2>&1 | sed -u "s/^/[$recipeId] /"
        exit "${PIPESTATUS[0]}"
    ) &
    recipePids+=("$!")
done

for pid in "${recipePids[@]}"; do
    wait "$pid"
    rc=$?
    [ "$rc" -eq 2 ] && restartNeeded=1
done

echo "Ferdium icons patched with $accent"

if [ "$restartNeeded" -eq 1 ]; then
    echo
    echo "NOTE: Ferdium caches recipe metadata in memory. If it's running in the"
    echo "background/tray, a window reload will NOT pick up these changes."
    echo "Fully restart it to see the new icons:"
    echo "    pkill -f ferdium && ferdium &"
fi