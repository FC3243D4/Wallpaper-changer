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
  --zen-hotreload       Install live theme reload support for Zen Browser
  --help                Show this help message
EOF
}

# Regenerates the wallpaper-thumbnails.path unit's PathChanged= list so it
# always matches whatever aspect-ratio folders currently exist under
# ~/Pictures/wallpapers, instead of a hardcoded "16-9". Safe to call
# repeatedly (--thumbnails, --update-wallpapers, --install) — it only
# rewrites the file and reloads/restarts the watcher if it's actually
# installed and enabled.
generate_thumbnails_path_unit() {
    local wallBaseDIR="$HOME/Pictures/wallpapers"
    local unitDir="$HOME/.config/systemd/user"
    local pathUnit="$unitDir/wallpaper-thumbnails.path"

    # Base dir first (catches new/removed ratio folders themselves),
    # then every existing ratio subfolder (catches files dropped inside).
    local watchDirs=("$wallBaseDIR")
    if [ -d "$wallBaseDIR" ]; then
        while IFS= read -r dir; do
            watchDirs+=("$dir")
        done < <(find "$wallBaseDIR" -mindepth 1 -maxdepth 1 -type d | sort)
    fi

    mkdir -p "$unitDir"
    {
        echo "[Unit]"
        echo "Description=Watch for new wallpapers"
        echo ""
        echo "[Path]"
        for dir in "${watchDirs[@]}"; do
            echo "PathChanged=$dir"
        done
        echo "Unit=wallpaper-thumbnails.service"
        echo ""
        echo "[Install]"
        echo "WantedBy=default.target"
    } > "$pathUnit"
}

cmd_thumbnails() {
    echo "Enabling automated watcher for wallpaper thumbnails..."
    mkdir -p ~/.config/systemd/user
    cp ./scripts-linux/wallpaper-thumbnails.service ~/.config/systemd/user
    generate_thumbnails_path_unit
    systemctl --user daemon-reload
    systemctl --user enable --now wallpaper-thumbnails.path
    echo "Thumbnail watcher installed successfully."
}

cmd_zen_hotreload() {
    echo "Installing Zen Browser live theme reload support..."
    source "$SUPPORT/zen_hotreload_install.sh"
}

cmd_update_wallpapers() {
    if [ ! -d "$HOME/Pictures/wallpapers" ]; then
        echo "Wallpapers directory not found at $HOME/Pictures/wallpapers."
        echo "Run --install first."
        exit 1
    fi

    # Sourcing wallpaper_install.sh only defines detect_aspect_ratios and
    # validate_wallpaper_structure here — its copy logic is gated behind
    # $CreatePicturesDir/$WallpapersDirExists/$CopyWallpapers, which are
    # never set to true in this code path, so nothing else in it runs.
    source "$SUPPORT/wallpaper_install.sh"

    WALLPAPERS_SOURCE="./wallpapers"
    if ! validate_wallpaper_structure "$WALLPAPERS_SOURCE"; then
        echo "The wallpapers folder structure in the repo is invalid or incomplete, skipping wallpaper update."
        exit 1
    fi

    # Detect aspect ratios dynamically instead of relying on a hardcoded list,
    # so new ratio folders added to the repo are picked up automatically.
    detectedRatios=()
    detect_aspect_ratios "$WALLPAPERS_SOURCE" detectedRatios

    # Check if any nsfw wallpapers are already present in the destination
    # by looking for files whose names start with "nsfw".
    syncNsfw=false
    if find "$HOME/Pictures/wallpapers" -maxdepth 2 -name "nsfw*" -print -quit 2>/dev/null | grep -q .; then
        syncNsfw=true
        echo "Detected existing nsfw wallpapers — those will be synced too."
    fi

    sourceDirs=()
    for ratio in "${detectedRatios[@]}"; do
        [ -d "$WALLPAPERS_SOURCE/sfw/$ratio" ] && sourceDirs+=("$WALLPAPERS_SOURCE/sfw/$ratio")
    done
    if [ "$syncNsfw" = true ]; then
        for ratio in "${detectedRatios[@]}"; do
            [ -d "$WALLPAPERS_SOURCE/nsfw/$ratio" ] && sourceDirs+=("$WALLPAPERS_SOURCE/nsfw/$ratio")
        done
    fi

    if (( ${#sourceDirs[@]} == 0 )); then
        echo "No wallpaper directories found in the repo."
        exit 1
    fi

    if [ "$syncNsfw" = true ]; then
        copy_with_bar "Syncing wallpapers..." "${sourceDirs[@]}" "$HOME/Pictures/wallpapers/"
    else
        copy_with_bar "Syncing wallpapers..." --exclude="nsfw*" "${sourceDirs[@]}" "$HOME/Pictures/wallpapers/"
    fi

    # Invalidate aspect ratio cache so the changer picks up new wallpapers
    [ -f "$HOME/.cache/wallpaper_ratios.cache" ] && rm "$HOME/.cache/wallpaper_ratios.cache"

    # If the thumbnail watcher is already installed, refresh which folders
    # it watches — new ratio folders synced just now won't be picked up
    # otherwise until the .path unit is regenerated.
    if [ -f "$HOME/.config/systemd/user/wallpaper-thumbnails.path" ]; then
        generate_thumbnails_path_unit
        systemctl --user daemon-reload
        systemctl --user restart wallpaper-thumbnails.path
        echo "Thumbnail watcher folder list refreshed."
    fi

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
    chmod +x "$HOME/.config/WallpaperChanger/themeRefresherSupportScripts/appPatchers"/*
    echo "Scripts updated successfully."
}

cmd_install() {
    echo "Starting installation process..."
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

    # 1 CHECK DEPENDENCIES
    if ! source "$SUPPORT/dependency_check.sh"; then
        echo "Dependency check failed. Stopping."
        exit 1
    fi

    # 2 WALLPAPER CLONE AND FALLBACK
    # If no wallpapers are cloned it will use the fallback
    if [ ! -d "./wallpapers" ] && [ -d "./wallpapersDefaultInstall" ]; then
        source "$SUPPORT/wallpaperClone.sh"
        if [ ! -d "./wallpapers" ] && [ -d "./wallpapersDefaultInstall" ]; then
            echo "No ./wallpapers folder found — using bundled wallpapersDefaultInstall instead."
            ln -s "./wallpapersDefaultInstall" "./wallpapers"
        fi
    fi

    # 3 CHECK FOR EXISTING DIRECTORIES AND FILES
    source "$SUPPORT/directory_setup.sh"

    # 4 SCRIPT INSTALLATION
    source "$SUPPORT/script_install.sh"

    # 5 WALLPAPER INSTALLATION
    source "$SUPPORT/wallpaper_install.sh"

    # 6 INSTALL THEMES
    source "$SUPPORT/install_themes.sh"

    # 7 OFFER ZEN BROWSER HOT RELOAD (only if Zen is detected)
    source "$SUPPORT/zen_hotreload_prompt.sh"

    # 8 APPLY WALLPAPER/THEME NOW
    # Nearly everything downstream (matugen, icon theming, GTK/KDE colors,
    # tray icons, etc.) depends on .current_wallpaper existing — nothing
    # sets that until a wallpaper is actually applied. Do it now instead
    # of waiting for the next Hyprland session start, so the system is
    # fully themed the moment installation finishes.
    if [ -x "$HOME/.config/WallpaperChanger/WallpaperApplicator.sh" ]; then
        read -p "wallpaperApplicator.sh random will now be run, be advised that some of your programs might be closed and open again for the theming to be applied, do you wish to procede? [Y/n]"
        echo""
        echo""
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            echo "Applying a random wallpaper to finish setting up theming..."
            "$HOME/.config/WallpaperChanger/WallpaperApplicator.sh" random
        else
            echo "It is strongly advised for you to run this script once the installation is done to theme everything"
        fi
    fi

    # 9 FINAL MESSAGE
    source "$SUPPORT/final_message.sh"
}

case "$1" in
    --install)            cmd_install ;;
    --thumbnails)         cmd_thumbnails ;;
    --update-scripts)     cmd_update_scripts ;;
    --update-wallpapers)  cmd_update_wallpapers ;;
    --zen-hotreload)      cmd_zen_hotreload ;;
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