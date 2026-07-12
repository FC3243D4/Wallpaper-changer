#!/usr/bin/env bash

SUPPORT="$HOME/.config/WallpaperChanger/themeRefresherSupportScripts"

usage() {
    cat << EOF
Usage: ./install-Linux.sh [OPTION]

Options:
  --full             Run the full theme refresh process (including restarting apps)
  --rgb              Apply the accent color to RGB devices only
  --softrun          Apply the accent color to RGB devices, patch themes and icons, but do not restart any apps
  --help             Show this help message
EOF
}

cmd_full() {
    # Save Hyprland layout state before any restarts
    if [ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]; then
        "$SUPPORT/hyprMasterLayoutPreservation.sh" save
    fi

    # 1. Choose accent color from wallpaper
    color=$("$SUPPORT/colorChooser.sh")
    if [ $? -ne 0 ] || [ -z "$color" ]; then
        echo "ERROR: colorChooser failed, aborting"
        exit 1
    fi

    color="${color,,}"
    accent="#$color"
    echo "Final color: $accent"

    # Run matugen once with the final chosen color
    matugen color hex "$accent" --quiet

    # 2. Apply to RGB devices (backgrounded — fire and forget)
    "$SUPPORT/rgbApply.sh" "$color"

    # 3. Patch KDE color schemes
    "$SUPPORT/kdePatcher.sh" "$color"

    # 4. Patch GTK themes
    "$SUPPORT/gtkPatcher.sh" "$color"

    # 5. Patch icons
    "$SUPPORT/iconPatcher.sh" "$color"

    # 6. Patch app-specific themes
    if command -v code >/dev/null 2>&1; then
        "$SUPPORT/appPatchers/vscodePatcher.sh" "$color"
    fi
    if command -v sourcegit >/dev/null 2>&1; then
        "$SUPPORT/appPatchers/sourceGitPatcher.sh" "$color"
    fi
    if command -v ferdium >/dev/null 2>&1; then
        "$SUPPORT/appPatchers/ferdiumPatcher.sh" "$color"
        "$SUPPORT/appPatchers/ferdiumIconPatcher.sh" "$color"
    fi
    if command -v vesktop >/dev/null 2>&1; then
    "$SUPPORT/appPatchers/discordPatcher.sh" "$color"
    fi
    #browser patchers
    if command -v zen-browser >/dev/null 2>&1; then
        "$SUPPORT/appPatchers/zenPatcher.sh" "$color"
    fi
    if command -v firefox >/dev/null 2>&1; then
        "$SUPPORT/appPatchers/firefoxPatcher.sh" "$color"
    fi

    # 7. Restart apps
    declare -A APPS
    APPS[dolphin]="x|dolphin|dolphin|dolphin|dolphin"
    #APPS[zen]="f|zen-bin|zen-bin|zen-browser|zen" # removed since adding hot reloading for zen
    APPS[ferdium]="f|electron.*ferdium-bin|electron.*ferdium-bin|ferdium|"
    APPS[sourcegit]="x|sourcegit|sourcegit|sourcegit|sourcegit"
    APPS[code]="x|code|code|code|code"
    APPS[vesktop]="x|vesktop|vesktop|vesktop|vesktop"
    APPS[nativmix]="x|nativmix|nativmix|nativmix --hidden --restart|"


    source "$SUPPORT/appRestarter.sh"

    #Desktop Environment specific actions
    if [ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]; then
        # Wait for each windowed app individually
        for app in "${running[@]}"; do
            IFS='|' read -r _ _ _ _ wclass <<< "${APPS[$app]}"
            [ -z "$wclass" ] && continue
            app_deadline=$(( $(date +%s) + 5 ))
            while [ $(date +%s) -lt $app_deadline ]; do
                hyprctl clients -j | python3 -c "
import json,sys
clients=json.load(sys.stdin)
exit(0 if any('$wclass' in c.get('class','').lower() for c in clients) else 1)
" 2>/dev/null && break
                sleep 0.1
            done
        done

        # Restore Hyprland layout state after all restarts
        sleep 1 && "$SUPPORT/hyprMasterLayoutPreservation.sh" restore

        systemctl --user restart waybar.service

    elif [ "$XDG_CURRENT_DESKTOP" == "KDE" ]; then
        kquitapp6 plasmashell && sleep 1 && kstart plasmashell &
        disown
    fi

    # OneDriveGUI — special-cased instead of going through appRestarter.sh.
    # It spawns a separate `onedrive --confdir=... --monitor` child process to
    # actually do the syncing. A generic kill+relaunch only kills the GUI
    # wrapper, leaving that child orphaned and still holding the account's
    # lock file — the freshly relaunched GUI then tries to start a *new* sync
    # process against the same locked confdir and fails with "already running".
    if command -v onedrivegui >/dev/null 2>&1 && pgrep -f "onedrivegui" >/dev/null 2>&1; then
        pkill -f "onedrivegui"
        pkill -f "onedrive .*--monitor"
        deadline=$(( $(date +%s) + 5 ))
        while pgrep -f "onedrivegui|onedrive .*--monitor" >/dev/null 2>&1 && [ "$(date +%s)" -lt "$deadline" ]; do
            sleep 0.1
        done
        onedrivegui >/dev/null 2>&1 &
        disown
    fi
}

cmd_rgb() {
    # 1. Choose accent color from wallpaper
    color=$("$SUPPORT/colorChooser.sh")
    if [ $? -ne 0 ] || [ -z "$color" ]; then
        echo "ERROR: colorChooser failed, aborting"
        exit 1
    fi

    color="${color,,}"
    accent="#$color"
    echo "Final color: $accent"

    # 2. Apply to RGB devices (backgrounded — fire and forget)
    "$SUPPORT/rgbApply.sh" "$color"
}

cmd_softrun() {
    # 1. Choose accent color from wallpaper
    color=$("$SUPPORT/colorChooser.sh")
    if [ $? -ne 0 ] || [ -z "$color" ]; then
        echo "ERROR: colorChooser failed, aborting"
        exit 1
    fi

    color="${color,,}"
    accent="#$color"
    echo "Final color: $accent"

    # Run matugen once with the final chosen color
    matugen color hex "$accent" --quiet

    # 2. Apply to RGB devices (backgrounded — fire and forget)
    "$SUPPORT/rgbApply.sh" "$color"

    # 3. Patch KDE color schemes
    "$SUPPORT/kdePatcher.sh" "$color"

    # 4. Patch GTK themes
    "$SUPPORT/gtkPatcher.sh" "$color"

    # 5. Patch icons
    "$SUPPORT/iconPatcher.sh" "$color"

    # 6. Patch app-specific themes
    if command -v code >/dev/null 2>&1; then
        "$SUPPORT/appPatchers/vscodePatcher.sh" "$color"
    fi
    if command -v sourcegit >/dev/null 2>&1; then
        "$SUPPORT/appPatchers/sourceGitPatcher.sh" "$color"
    fi
    if command -v ferdium >/dev/null 2>&1; then
        "$SUPPORT/appPatchers/ferdiumPatcher.sh" "$color"
        "$SUPPORT/appPatchers/ferdiumIconPatcher.sh" "$color"
    fi
    if command -v vesktop >/dev/null 2>&1; then
    "$SUPPORT/appPatchers/discordPatcher.sh" "$color"
    fi
    #browser patchers
    if command -v zen-browser >/dev/null 2>&1; then
        "$SUPPORT/appPatchers/zenPatcher.sh" "$color"
    fi
    if command -v firefox >/dev/null 2>&1; then
        "$SUPPORT/appPatchers/firefoxPatcher.sh" "$color"
    fi

    if [ "$XDG_CURRENT_DESKTOP" == "KDE" ]; then
        kquitapp6 plasmashell && sleep 1 && kstart plasmashell &
        disown
    elif [ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]; then
        systemctl --user restart waybar.service
    fi
}

case "$1" in
    --full)        cmd_full ;;
    --rgb)         cmd_rgb ;;
    --softrun)     cmd_softrun ;;
    --help)        usage ;;
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