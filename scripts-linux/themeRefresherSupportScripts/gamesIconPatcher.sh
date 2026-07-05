#!/usr/bin/env bash
# gamesIconPatcher.sh
# Gives every installed game a themed icon in its .desktop entry — a custom
# per-game icon if you've downloaded one, or the generic "gaming" icon as a
# fallback otherwise. Covers Steam, Lutris, and Heroic.
#
# NOTE: this patches .desktop files, it doesn't create them. Steam itself
# doesn't generate one .desktop entry per installed game — you need a
# separate tool for that (e.g. "steam-desktop-shortcuts" on the AUR) if you
# don't already have per-game entries showing up in rofi. Lutris and Heroic
# both have a "create desktop shortcut" option that generates these for you.
#
# Usage: gamesIconPatcher.sh <hex_color>

color="${1,,}"

if [ -z "$color" ]; then
    echo "Usage: $0 <hex_color>" >&2
    exit 1
fi

accent="#$color"
SUPPORT="$HOME/.config/WallpaperChanger/themeRefresherSupportScripts"
ICONS="$SUPPORT/svg"
GAME_ICONS="$ICONS/games"                 # drop per-game custom icons here
FALLBACK_ICON="$ICONS/gaming_base_icon.svg"
OUT_DIR="$SUPPORT/game-icons"
APPS_DIR="$HOME/.local/share/applications"

mkdir -p "$OUT_DIR" "$GAME_ICONS"

if [ ! -f "$FALLBACK_ICON" ]; then
    echo "Fallback icon not found: $FALLBACK_ICON" >&2
    exit 1
fi

# Manual overrides for game titles whose normalized slug doesn't match the
# filename you downloaded (punctuation, subtitles, roman numerals, etc).
# Key = slug derived from the .desktop file's Name=, value = the icon
# filename (without _base_icon.svg) to use instead.
declare -A GAME_SLUG_OVERRIDES=(
    ["forza_horizon_6"]="forza"
    ["elden_ring"]="elden_ring"
    ["elden_ring_nightreign"]="elden_ring"
    ["nierautomata"]="nier_automata"
    ["clair_obscur_expedition_33"]="expedition_33"
)

slugify() {
    echo "$1" | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9 -]//g; s/[[:space:]]+/_/g; s/-+/_/g'
}

is_game_desktop_file() {
    local f="$1"
    grep -qE '^Exec=.*(steam://rungameid|lutris:rungame|heroic)' "$f" 2>/dev/null \
        || grep -qiE '^Categories=.*game' "$f" 2>/dev/null
}

patch_svg_color() {
    # $1 = source svg, $2 = dest svg
    # All game icons are authored fresh using currentColor (on either fill
    # or stroke, whichever the icon uses) — a single bare token replace
    # covers both without needing attribute-specific patterns.
    python3 - "$1" "$2" "$accent" << 'PYEOF'
import sys

src, dst, accent = sys.argv[1], sys.argv[2], sys.argv[3]
with open(src, "r") as f:
    content = f.read()

content = content.replace("currentColor", accent)

with open(dst, "w") as f:
    f.write(content)
PYEOF
}

if [ ! -d "$APPS_DIR" ]; then
    echo "Applications directory not found: $APPS_DIR" >&2
    exit 1
fi

patched=0
fallback_used=0
skipped=0

while IFS= read -r -d '' desktop_file; do
    is_game_desktop_file "$desktop_file" || { skipped=$((skipped + 1)); continue; }

    name=$(grep -m1 '^Name=' "$desktop_file" | cut -d= -f2-)
    if [ -z "$name" ]; then
        echo "  no Name= found in $(basename "$desktop_file") — skipping"
        continue
    fi

    slug=$(slugify "$name")
    slug="${GAME_SLUG_OVERRIDES[$slug]:-$slug}"

    src_icon="$GAME_ICONS/${slug}_base_icon.svg"
    if [ -f "$src_icon" ]; then
        echo "Game '$name' -> custom icon ($slug)"
    else
        src_icon="$FALLBACK_ICON"
        fallback_used=$((fallback_used + 1))
        echo "Game '$name' -> no custom icon for '$slug', using fallback"
    fi

    dst_icon="$OUT_DIR/${slug}.svg"
    patch_svg_color "$src_icon" "$dst_icon"

    if grep -q '^Icon=' "$desktop_file"; then
        sed -i "s|^Icon=.*|Icon=$dst_icon|" "$desktop_file"
    else
        echo "Icon=$dst_icon" >> "$desktop_file"
    fi

    patched=$((patched + 1))
done < <(find "$APPS_DIR" -maxdepth 3 -type f -name "*.desktop" -print0 2>/dev/null)

echo
echo "Done. Patched $patched game(s) with $accent — $fallback_used used the generic gaming icon."

if [ "$patched" -gt 0 ]; then
    update-desktop-database "$APPS_DIR" 2>/dev/null
fi
