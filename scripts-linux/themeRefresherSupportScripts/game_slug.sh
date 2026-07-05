#!/usr/bin/env bash
# game_slug.sh
# Prints the slug gamesIconPatcher.sh would derive for a given game, so you
# know exactly what key to use in GAME_SLUG_OVERRIDES.
#
# Usage:
#   game_slug.sh                          # scan every game .desktop file
#                                          # under ~/.local/share/applications
#   game_slug.sh <path-to-.desktop-file>  # just this one file
#   game_slug.sh --name "Forza Horizon 6" # slugify a title directly, no file needed

set -euo pipefail

APPS_DIR="$HOME/.local/share/applications"

slugify() {
    echo "$1" | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9 -]//g; s/[[:space:]]+/_/g; s/-+/_/g'
}

is_game_desktop_file() {
    local f="$1"
    grep -qE '^Exec=.*(steam://rungameid|lutris:rungame|heroic)' "$f" 2>/dev/null \
        || grep -qiE '^Categories=.*game' "$f" 2>/dev/null
}

print_slug_for_file() {
    local desktop_file="$1"
    local name
    name=$(grep -m1 '^Name=' "$desktop_file" | cut -d= -f2-)
    if [ -z "$name" ]; then
        echo "  (no Name= found in $(basename "$desktop_file") — skipping)"
        return
    fi
    printf '%-45s %s\n' "$name" "$(slugify "$name")"
}

if [ "$#" -eq 0 ]; then
    # No argument: scan every game .desktop file found
    if [ ! -d "$APPS_DIR" ]; then
        echo "Applications directory not found: $APPS_DIR" >&2
        exit 1
    fi

    printf '%-45s %s\n' "NAME" "SLUG"
    printf '%-45s %s\n' "----" "----"

    found=0
    while IFS= read -r -d '' desktop_file; do
        is_game_desktop_file "$desktop_file" || continue
        print_slug_for_file "$desktop_file"
        found=$((found + 1))
    done < <(find "$APPS_DIR" -maxdepth 3 -type f -name "*.desktop" -print0 2>/dev/null)

    echo
    echo "$found game .desktop file(s) found."

elif [ "$1" = "--name" ]; then
    if [ "$#" -lt 2 ]; then
        echo "Usage: $0 --name \"Game Title\"" >&2
        exit 1
    fi
    echo "Name:  $2"
    echo "Slug:  $(slugify "$2")"

else
    desktop_file="$1"
    if [ ! -f "$desktop_file" ]; then
        echo "File not found: $desktop_file" >&2
        exit 1
    fi
    name=$(grep -m1 '^Name=' "$desktop_file" | cut -d= -f2-)
    if [ -z "$name" ]; then
        echo "No Name= found in $desktop_file" >&2
        exit 1
    fi
    echo "Name:  $name"
    echo "Slug:  $(slugify "$name")"
fi
