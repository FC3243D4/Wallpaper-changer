#!/usr/bin/env bash
# script_install.sh
# Copies the WallpaperChanger scripts into ~/.config/WallpaperChanger.
# Meant to be SOURCED from install-Linux.sh; relies on $ConfigDirExists,
# $CopyScripts, and $UseXrandr being set by earlier modules.

# Draws a visual progress bar by parsing rsync's --info=progress2 output.
copy_with_bar() {
    local label="$1"
    shift
    echo "$label"

    rsync -a --no-inc-recursive --info=progress2 "$@" 2>&1 | \
    while IFS= read -d $'\r' -r line; do
        pct=$(echo "$line" | grep -oE '[0-9]+%' | head -1 | tr -d '%')
        [ -z "$pct" ] && continue
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

if [ "$ConfigDirExists" = false ]; then
    mkdir "$HOME/.config/WallpaperChanger"
fi

if [ "$CopyScripts" = true ]; then
    if [ "$UseXrandr" = true ]; then
        copy_with_bar "Copying Xrandr scripts..." \
            "./scripts-linux/Xrandr/" "$HOME/.config/WallpaperChanger/"
    else
        copy_with_bar "Copying Wayland scripts..." \
            "./scripts-linux/wayland/" "$HOME/.config/WallpaperChanger/"
    fi

    copy_with_bar "Copying support scripts..." \
        "./scripts-linux/AspectRatioChecker.sh" \
        "./scripts-linux/themeRefresher.sh" \
        "./scripts-linux/generateWallpaperThumbnails.sh" \
        "./scripts-linux/themeRefresherSupportScripts" \
        "$HOME/.config/WallpaperChanger/"

    chmod +x "$HOME/.config/WallpaperChanger"/*
    chmod +x "$HOME/.config/WallpaperChanger/themeRefresherSupportScripts"/*
    echo "Scripts copied successfully."
    echo ""
fi
