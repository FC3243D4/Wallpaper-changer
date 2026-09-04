#!/usr/bin/env bash
# directory_setup.sh
# Checks for existing config/wallpaper directories and the rofi config,
# prompting the user for overwrite/copy decisions.
# Meant to be SOURCED from install-Linux.sh so that configDirExists,
# copyScripts, wallpapersDirExists, copyWallpapers, and createPicturesDir
# are visible to later modules.

if [ -d "$HOME/.config/WallpaperChanger" ]; then
    read -p "Directory $HOME/.config/WallpaperChanger exists. Do you want to delete it and all its content? [y/N]" -n 1 -r
    echo ""
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        configDirExists=true
        read -p "Do you still want to copy the current wallpapers folder's scripts to the directory? [y/N]" -n 1 -r
        echo ""
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            copyScripts=false
        else
            copyScripts=true
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
            wallpapersDirExists=true
            if [ -d ./wallpapers ]; then
                read -p "Do you still want to copy the current wallpapers folder's wallpapers to the directory? [y/N]" -n 1 -r
                echo ""
                echo ""
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    copyWallpapers=false
                else
                    copyWallpapers=true
                fi
            else
                copyWallpapers=false
            fi
        else
            rm -r "$HOME/Pictures/wallpapers"
            if [ -d ./wallpapers ]; then
                read -p "Do you want to copy the current wallpapers folder's wallpapers to the directory? [y/N]" -n 1 -r
                echo ""
                echo ""
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    copyWallpapers=false
                else
                    copyWallpapers=true
                fi
            else
                copyWallpapers=false
            fi
        fi
    fi
else
    read -p "Pictures directory does not exist. This can be because of your system language or because you deleted it. Do you want to create it? [y/N]" -n 1 -r
    echo ""
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        copyWallpapers=false
        wallpapersDirExists=false
    else
        createPicturesDir=true
        if [ -d ./wallpapers ]; then
            read -p "Do you want to copy the current wallpapers folder's wallpapers to the directory? [y/N]" -n 1 -r
            echo ""
            echo ""
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                copyWallpapers=false
            else
                copyWallpapers=true
            fi
        else
            copyWallpapers=false
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
        cp ./rofi/config-wallpaper.rasi "$HOME/.config/rofi/"
    fi
else
    cp ./rofi/config-wallpaper.rasi "$HOME/.config/rofi/"
fi