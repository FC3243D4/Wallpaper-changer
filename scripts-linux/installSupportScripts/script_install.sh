#!/usr/bin/env bash
# script_install.sh
# Copies the WallpaperChanger scripts into ~/.config/WallpaperChanger.
# Meant to be SOURCED from install-Linux.sh; relies on $ConfigDirExists,
# $CopyScripts, and $UseXrandr being set by earlier modules.

source "$SUPPORT/utils.sh"

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
    chmod +x "$HOME/.config/WallpaperChanger/themeRefresherSupportScripts/appPatchers"/*
    echo "Scripts copied successfully."
    echo ""
fi