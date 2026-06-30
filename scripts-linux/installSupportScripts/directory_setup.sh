#!/usr/bin/env bash
# directory_setup.sh
# Checks for existing config/wallpaper directories and the rofi config,
# prompting the user for overwrite/copy decisions.
# Meant to be SOURCED from install-Linux.sh so that ConfigDirExists,
# CopyScripts, WallpapersDirExists, CopyWallpapers, CreatePicturesDir,
# and wallpapersRepo are visible to later modules.

if [ -d "$HOME/.config/WallpaperChanger" ]; then
    read -p "Directory $HOME/.config/WallpaperChanger exists. Do you want to delete it and all its content? [y/N]" -n 1 -r
    echo ""
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        ConfigDirExists=true
        read -p "Do you still want to copy this repo's scripts to the directory? [y/N]" -n 1 -r
        echo ""
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            CopyScripts=false
        else
            CopyScripts=true
        fi
    else
        rm -r "$HOME/.config/WallpaperChanger"
    fi
fi

if [ -d "$HOME/Pictures" ]; then
    if [ -d "$HOME/Pictures/wallpapers" ]; then
        read -p "Directory $HOME/Pictures/wallpapers exists. Do you want to delete it and all its content? [y/N]" -n 1 -r
        echo ""
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            WallpapersDirExists=true
            read -p "Do you still want to copy this repo's wallpapers to the directory? [y/N]" -n 1 -r
            echo ""
            echo ""
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                CopyWallpapers=false
            else
                CopyWallpapers=true
            fi
        else
            rm -r "$HOME/Pictures/wallpapers"
        fi
    fi
else
    read -p "Pictures directory does not exist. This can be because of your system language or because you deleted it. Do you want to create it? [y/N]" -n 1 -r
    echo ""
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        CopyWallpapers=false
        WallpapersDirExists=false
    else
        CreatePicturesDir=true
        if [ -d ./wallpapers ]; then
            wallpapersRepo=true
            read -p "Do you want to copy this repo's wallpapers to the directory? [y/N]" -n 1 -r
            echo ""
            echo ""
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                CopyWallpapers=false
            else
                CopyWallpapers=true
            fi
        fi
    fi
fi

if [ ! -d "$HOME/.config/rofi" ]; then
    mkdir -p "$HOME/.config/rofi"
fi
if [ -f "$HOME/.config/rofi/config-wallpaper.rasi" ]; then
    read -p "Rofi config for the wallpaper menu already exists. Would you like to overwrite it with the one from the repo? [y/N]" -n 1 -r
    echo ""
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cp ./scripts-linux/config-wallpaper.rasi "$HOME/.config/rofi/"
    fi
else
    cp ./scripts-linux/config-wallpaper.rasi "$HOME/.config/rofi/"
fi
