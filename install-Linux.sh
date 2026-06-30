#!/usr/bin/env bash

# Kill all child processes (e.g. rsync) if the script is interrupted or killed.
trap 'echo ""; echo "Installation interrupted. Cleaning up..."; kill 0' SIGINT SIGTERM

if [ "$1" == "thumbnails" ]; then
    echo "enabling automated watcher for wallpaper thumbnails..."
    mkdir -p ~/.config/systemd/user
    cp ./scripts-linux/wallpaper-thumbnails.* ~/.config/systemd/user
    systemctl --user enable --now wallpaper-thumbnails.path
    exit 0
fi

SUPPORT="./scripts-linux/installSupportScripts"
chmod +x "$SUPPORT"/*

packageList=()
UseWayland=true
UseXrandr=false
CreatePicturesDir=false
ConfigDirExists=false
CopyScripts=true
WallpapersDirExists=false
CopyWallpapers=true
CopyNsfw=false
wallpapersRepo=false

# 1️⃣ CHECK DEPENDENCIES
if ! source "$SUPPORT/dependency_check.sh"; then
    echo "Dependency check failed. Stopping."
    exit 1
fi

# 2️⃣ CHECK FOR EXISTING DIRECTORIES AND FILES
source "$SUPPORT/directory_setup.sh"

# 3️⃣ SCRIPT INSTALLATION
source "$SUPPORT/script_install.sh"

# 4️⃣ WALLPAPER INSTALLATION
source "$SUPPORT/wallpaper_install.sh"

# 5️⃣ INSTALL THEMES
source "$SUPPORT/install_themes.sh"

# 6️⃣ FINAL MESSAGE
source "$SUPPORT/final_message.sh"
