#!/usr/bin/env bash
# ScriptsInstall.sh
# Copies the WallpaperChanger scripts into ~/.config/WallpaperChanger.
# Meant to be SOURCED from Install-Linux.sh; relies on $configDirExists,
# $copyScripts, and $useXrandr being set by earlier modules.

source "$supportDir/Utils.sh"

if [ "$configDirExists" = false ]; then
    mkdir "$HOME/.config/WallpaperChanger"
fi

if [ "$copyScripts" = true ]; then
    if [ "$useXrandr" = true ]; then
        copy_with_bar "Copying Xrandr scripts..." \
            "./scripts-linux/Xrandr/" "$HOME/.config/WallpaperChanger/"
    else
        copy_with_bar "Copying Wayland scripts..." \
            "./scripts-linux/wayland/" "$HOME/.config/WallpaperChanger/"
    fi

    copy_with_bar "Copying support scripts..." \
        "./scripts-linux/AspectRatioChecker.sh" \
        "./scripts-linux/ThemeRefresher.sh" \
        "./scripts-linux/GenerateWallpaperThumbnails.sh" \
        "./scripts-linux/themeRefresherSupportScripts" \
        "$HOME/.config/WallpaperChanger/"

    chmod +x "$HOME/.config/WallpaperChanger"/*
    chmod +x "$HOME/.config/WallpaperChanger/themeRefresherSupportScripts"/*
    chmod +x "$HOME/.config/WallpaperChanger/themeRefresherSupportScripts/appPatchers"/*
    echo "Scripts copied successfully."
    echo ""
fi