#!/usr/bin/env bash

# Kill all child processes (e.g. rsync) if the script is interrupted or killed.
trap 'echo ""; echo "Installation interrupted. Cleaning up..."; kill 0' SIGINT SIGTERM

SUPPORT="./scripts-linux/installSupportScripts"

usage() {
    cat << EOF
Usage: ./install-Linux.sh [OPTION]

Options:
  --install             Run the full installation process
  --thumbnails          Install the automated wallpaper thumbnail watcher
  --update-scripts      Copy only new and updated scripts to the destination
  --update-wallpapers   Copy only new and updated wallpapers to the destination
  --help                Show this help message
EOF
}

cmd_thumbnails() {
    echo "Enabling automated watcher for wallpaper thumbnails..."
    mkdir -p ~/.config/systemd/user
    cp ./scripts-linux/wallpaper-thumbnails.* ~/.config/systemd/user
    systemctl --user enable --now wallpaper-thumbnails.path
    echo "Thumbnail watcher installed successfully."
}

cmd_update_wallpapers() {
    ASPECT_RATIOS=(
        "16-9" "21-9" "32-9" "4-3"
        "16-10" "21-10" "32-10" "3-2"
        "9-16" "9-21" "9-32" "3-4"
        "10-16" "10-21" "10-32" "2-3"
    )

    if [ ! -d "$HOME/Pictures/wallpapers" ]; then
        echo "Wallpapers directory not found at $HOME/Pictures/wallpapers."
        echo "Run --install first."
        exit 1
    fi

    # Check if any nsfw wallpapers are already present in the destination
    # by looking for files whose names start with "nsfw".
    syncNsfw=false
    if find "$HOME/Pictures/wallpapers" -maxdepth 2 -name "nsfw*" -print -quit 2>/dev/null | grep -q .; then
        syncNsfw=true
        echo "Detected existing nsfw wallpapers — those will be synced too."
    fi

    sourceDirs=()
    for ratio in "${ASPECT_RATIOS[@]}"; do
        [ -d "./wallpapers/sfw/$ratio" ] && sourceDirs+=("./wallpapers/sfw/$ratio")
    done
    if [ "$syncNsfw" = true ]; then
        for ratio in "${ASPECT_RATIOS[@]}"; do
            [ -d "./wallpapers/nsfw/$ratio" ] && sourceDirs+=("./wallpapers/nsfw/$ratio")
        done
    fi

    if (( ${#sourceDirs[@]} == 0 )); then
        echo "No wallpaper directories found in the repo."
        exit 1
    fi

    source "$SUPPORT/utils.sh"

    if [ "$syncNsfw" = true ]; then
        copy_with_bar "Syncing wallpapers..." "${sourceDirs[@]}" "$HOME/Pictures/wallpapers/"
    else
        copy_with_bar "Syncing wallpapers..." --exclude="nsfw*" "${sourceDirs[@]}" "$HOME/Pictures/wallpapers/"
    fi

    # Invalidate aspect ratio cache so the changer picks up new wallpapers
    [ -f "$HOME/.cache/wallpaper_ratios.cache" ] && rm "$HOME/.cache/wallpaper_ratios.cache"

    echo "Wallpapers synced successfully."
}

cmd_update_scripts() {
    source "$SUPPORT/utils.sh"

    if [ ! -d "$HOME/.config/WallpaperChanger" ]; then
        echo "WallpaperChanger directory not found at $HOME/.config/WallpaperChanger."
        echo "Run --install first."
        exit 1
    fi

    # Detect which display utility was originally installed
    if [ -f "$HOME/.config/WallpaperChanger/WallpaperMenuXrandr.sh" ]; then
        UseXrandr=true
    else
        UseXrandr=false
    fi

    if [ "$UseXrandr" = true ]; then
        copy_with_bar "Updating Xrandr scripts..." \
            "./scripts-linux/Xrandr/" "$HOME/.config/WallpaperChanger/"
    else
        copy_with_bar "Updating Wayland scripts..." \
            "./scripts-linux/wayland/" "$HOME/.config/WallpaperChanger/"
    fi

    copy_with_bar "Updating support scripts..." \
        "./scripts-linux/AspectRatioChecker.sh" \
        "./scripts-linux/themeRefresher.sh" \
        "./scripts-linux/generateWallpaperThumbnails.sh" \
        "./scripts-linux/themeRefresherSupportScripts" \
        "$HOME/.config/WallpaperChanger/"

    chmod +x "$HOME/.config/WallpaperChanger"/*
    chmod +x "$HOME/.config/WallpaperChanger/themeRefresherSupportScripts"/*
    echo "Scripts updated successfully."
}


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
}

case "$1" in
    --install)            cmd_install ;;
    --thumbnails)         cmd_thumbnails ;;
    --update-scripts)     cmd_update_scripts ;;
    --update-wallpapers)  cmd_update_wallpapers ;;
    --help)               usage ;;
    *)
        if [ -z "$1" ]; then
            echo "No option provided."
        else
            echo "Unknown option: $1"
        fi
        echo ""
        usage
        exit 1
        ;;
esac