#!/usr/bin/env bash
# wallpaper_install.sh
# Creates the Pictures/wallpapers directory if needed and copies wallpapers
# from the repo, including the nsfw prompt.
# Meant to be SOURCED from install-Linux.sh; relies on $CreatePicturesDir,
# $WallpapersDirExists, and $CopyWallpapers being set by directory_setup.sh.
# Sets $CopyNsfw for use by final_message.sh.

ASPECT_RATIOS=(
    "16-9" "21-9" "32-9" "4-3"
    "16-10" "21-10" "32-10" "3-2"
    "9-16" "9-21" "9-32" "3-4"
    "10-16" "10-21" "10-32" "2-3"
)

# Draws a visual progress bar by parsing rsync's --info=progress2 output.
# --no-inc-recursive forces rsync to scan all files first so the percentage
# is accurate and never goes backwards.
copy_with_bar() {
    local label="$1"
    shift
    echo "$label"

    rsync -a --no-inc-recursive --info=progress2 "$@" 2>&1 | \
    while IFS= read -d $'\r' -r line; do
        pct=$(echo "$line" | grep -oE '[0-9]+%' | head -1 | tr -d '%')
        [ -z "$pct" ] && continue
        # xfr#N = files transferred; to-chk=REMAINING/TOTAL
        xfr=$(echo "$line" | grep -oE 'xfr#[0-9]+' | grep -oE '[0-9]+')
        total=$(echo "$line" | grep -oE 'to-chk=[0-9]+/[0-9]+' | grep -oE '/[0-9]+' | tr -d '/')
        local filled=$(( pct * 40 / 100 ))
        local empty=$(( 40 - filled ))
        local bar=""
        for ((i=0; i<filled; i++)); do bar+="█"; done
        for ((i=0; i<empty; i++)); do bar+="░"; done
        if [ -n "$xfr" ] && [ -n "$total" ]; then
            printf "\r  [%s] %3d%%  (%s/%s files)" "$bar" "$pct" "$xfr" "$total"
        else
            printf "\r  [%s] %3d%%" "$bar" "$pct"
        fi
    done
    printf "\n"
}

if [ "$CreatePicturesDir" = true ]; then
    mkdir "$HOME/Pictures"
    mkdir "$HOME/Pictures/wallpapers"
else
    if [ "$WallpapersDirExists" = false ]; then
        mkdir "$HOME/Pictures/wallpapers"
    fi
fi

if [ "$CopyWallpapers" = true ]; then
    if [ -f "$HOME/.cache/wallpaper_ratios.cache" ]; then
        rm "$HOME/.cache/wallpaper_ratios.cache"
    fi
    read -p "Do you want to copy the nsfw wallpapers? [y/N]" -n 1 -r
    echo ""
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        CopyNsfw=false
    else
        CopyNsfw=true
    fi

    # Collect all source directories to copy in a single rsync call so the
    # progress bar reflects the entire transfer rather than one folder at a time.
    sourceDirs=()
    for ratio in "${ASPECT_RATIOS[@]}"; do
        [ -d "./wallpapers/sfw/$ratio" ] && sourceDirs+=("./wallpapers/sfw/$ratio")
    done
    if [ "$CopyNsfw" = true ]; then
        for ratio in "${ASPECT_RATIOS[@]}"; do
            [ -d "./wallpapers/nsfw/$ratio" ] && sourceDirs+=("./wallpapers/nsfw/$ratio")
        done
    fi

    if (( ${#sourceDirs[@]} != 0 )); then
        copy_with_bar "Copying wallpapers..." "${sourceDirs[@]}" "$HOME/Pictures/wallpapers/"
        echo "Wallpapers copied successfully."
        echo ""
    fi
fi
