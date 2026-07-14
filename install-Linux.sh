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

cmd_thumbnails() {
    echo "Enabling automated watcher for wallpaper thumbnails..."
    mkdir -p ~/.config/systemd/user
    cp ./scripts-linux/wallpaper-thumbnails.* ~/.config/systemd/user
    systemctl --user enable --now wallpaper-thumbnails.path
    echo "Thumbnail watcher installed successfully."
}

cmd_zen_hotreload() {
    echo "Installing Zen Browser live theme reload support..."
    source "$SUPPORT/zen_hotreload_install.sh"
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

    # 2 CHECK FOR EXISTING DIRECTORIES AND FILES
    source "$SUPPORT/directory_setup.sh"

    # 3 SCRIPT INSTALLATION
    source "$SUPPORT/script_install.sh"

    # 4 WALLPAPER SOURCE FALLBACK
    # Some repo checkouts don't ship the full ./wallpapers tree (e.g. to
    # keep a base clone small, or avoid nsfw content by default). If it's
    # missing, fall back to the smaller ./wallpapersDefaultInstall set via
    # a persistent symlink — every script that expects ./wallpapers
    # (including this installer's own --update-wallpapers) then keeps
    # working with no separate fallback logic needed anywhere else.
    if [ ! -d "./wallpapers" ] && [ -d "./wallpapersDefaultInstall" ]; then
        echo "No ./wallpapers folder found — using bundled wallpapersDefaultInstall instead."
        ln -s "./wallpapersDefaultInstall" "./wallpapers"
    fi

    # 5 WALLPAPER INSTALLATION
    source "$SUPPORT/wallpaper_install.sh"

    # 6 INSTALL THEMES
    source "$SUPPORT/install_themes.sh"

    # 7 SET PRIMARY DISPLAY
    # WallpaperChanger's symlink-based wallpaper application needs a
    # primary display set to work correctly. Detects whichever connected
    # output sits at position 0,0, applies it immediately (so wallpaper
    # application below works this session too, without needing a
    # Hyprland restart first), stores it as PRIMARY_DISPLAY in
    # 01-UserDefaults.lua, and uncomments the line in Startup_Apps.lua
    # that references that env var — so if the display ever changes
    # later, only UserDefaults.lua needs updating, not Startup_Apps.lua.
    USERDEFAULTS_LUA="$HOME/.config/hypr/UserConfigs/01-UserDefaults.lua"
    STARTUPAPPS_LUA="$HOME/.config/hypr/UserConfigs/Startup_Apps.lua"
    if ! command -v xrandr >/dev/null 2>&1; then
        echo "xrandr not found — skipping primary display setup."
    else
        primary_display=$(xrandr --query 2>/dev/null | awk '
            / connected/ {
                for (i = 1; i <= NF; i++) {
                    if ($i ~ /^[0-9]+x[0-9]+\+0\+0$/) {
                        print $1
                        exit
                    }
                }
            }
        ')

        if [ -z "$primary_display" ]; then
            echo "Could not detect a display at position 0,0 — skipping primary display setup."
            echo "You may need to set this manually in $USERDEFAULTS_LUA."
        else
            xrandr --output "$primary_display" --primary 2>/dev/null

            if [ -f "$USERDEFAULTS_LUA" ]; then
                if grep -q 'hl.env("PRIMARY_DISPLAY"' "$USERDEFAULTS_LUA" 2>/dev/null; then
                    echo "PRIMARY_DISPLAY already configured in 01-UserDefaults.lua — leaving it as-is."
                else
                    sed -i "s|hl.env(\"PRIMARY_DISPLAY\", \"x\")|hl.env(\"PRIMARY_DISPLAY\", \"${primary_display}\")|" "$USERDEFAULTS_LUA"
                    echo "PRIMARY_DISPLAY set to $primary_display in 01-UserDefaults.lua."
                fi
            else
                echo "$USERDEFAULTS_LUA not found — skipping."
            fi

            if [ -f "$STARTUPAPPS_LUA" ]; then
                if grep -qE '^\s*"xrandr --output \$PRIMARY_DISPLAY --primary",' "$STARTUPAPPS_LUA" 2>/dev/null; then
                    echo "Startup_Apps.lua already references \$PRIMARY_DISPLAY — leaving it as-is."
                else
                    sed -i 's|--"xrandr --output X --primary",|"xrandr --output $PRIMARY_DISPLAY --primary",|' "$STARTUPAPPS_LUA"
                    echo "Startup_Apps.lua updated to use \$PRIMARY_DISPLAY."
                fi
            else
                echo "$STARTUPAPPS_LUA not found — skipping."
            fi
        fi
    fi

    # 8 APPLY WALLPAPER/THEME NOW
    # Nearly everything downstream (matugen, icon theming, GTK/KDE colors,
    # tray icons, etc.) depends on .current_wallpaper existing — nothing
    # sets that until a wallpaper is actually applied. Do it now instead
    # of waiting for the next Hyprland session start, so the system is
    # fully themed the moment installation finishes.
    if [ -x "$HOME/.config/WallpaperChanger/WallpaperApplicator.sh" ]; then
        echo "Applying a random wallpaper to finish setting up theming..."
        "$HOME/.config/WallpaperChanger/WallpaperApplicator.sh" random
    fi

    # 9 OFFER ZEN BROWSER HOT RELOAD (only if Zen is detected)
    source "$SUPPORT/zen_hotreload_prompt.sh"

    # 10 FINAL MESSAGE
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