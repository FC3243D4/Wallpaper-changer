#!/usr/bin/env bash

SUPPORT="$HOME/.config/WallpaperChanger/themeRefresherSupportScripts"

# Runs "$@" and prints how long it took, e.g. "[timing] iconPatcher: 0.842s".
# The timing line goes to stderr, so `color=$(timed colorChooser ...)` still
# only captures the wrapped command's real stdout.
timed() {
    local label="$1"; shift
    local t0 t1 elapsed rc
    t0=$(date +%s%N)
    "$@"
    rc=$?
    t1=$(date +%s%N)
    elapsed=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.3f", (b-a)/1000000000}')
    echo "[timing] ${label}: ${elapsed}s" >&2
    return $rc
}

usage() {
    cat << EOF
Usage: ./install-Linux.sh [OPTION]

Options:
  --full             Run the full theme refresh process (including restarting apps)
  --rgb              Apply the accent color to RGB devices only
  --softrun          Apply the accent color to RGB devices, patch themes and icons, but do not restart any apps
  --tray             Run the tray icon updater only
  --help             Show this help message
EOF
}

cmd_full() {
    # Save Hyprland layout state before any restarts
    if [ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]; then
        "$SUPPORT/hyprLayoutPreservation.sh" save
    fi

    # 1. Choose accent color from wallpaper
    color=$(timed "colorChooser" "$SUPPORT/colorChooser.sh")
    if [ $? -ne 0 ] || [ -z "$color" ]; then
        echo "ERROR: colorChooser failed, aborting"
        exit 1
    fi

    color="${color,,}"
    accent="#$color"
    echo "Final color: $accent"

    # Run matugen once with the final chosen color
    timed "matugen" matugen color hex "$accent" --quiet

    # 2. Apply to RGB devices (backgrounded — fire and forget)
    timed "rgbApply" "$SUPPORT/rgbApply.sh" "$color"

    # 3. Patch KDE color schemes
    timed "kdePatcher" "$SUPPORT/kdePatcher.sh" "$color"

    # 4. Patch GTK themes
    timed "gtkPatcher" "$SUPPORT/gtkPatcher.sh" "$color"

    # 5. Patch icons
    timed "iconPatcher" "$SUPPORT/iconPatcher.sh" "$color"

    # 6. Patch app-specific themes
    if command -v code >/dev/null 2>&1; then
        timed "vscodePatcher" "$SUPPORT/appPatchers/vscodePatcher.sh" "$color"
    fi
    if command -v sourcegit >/dev/null 2>&1; then
        timed "sourceGitPatcher" "$SUPPORT/appPatchers/sourceGitPatcher.sh" "$color"
    fi
    if command -v ferdium >/dev/null 2>&1; then
        timed "ferdiumPatcher" "$SUPPORT/appPatchers/ferdiumPatcher.sh" "$color"
        timed "ferdiumIconPatcher" "$SUPPORT/appPatchers/ferdiumIconPatcher.sh" "$color"
    fi
    if command -v vesktop >/dev/null 2>&1; then
        timed "discordPatcher" "$SUPPORT/appPatchers/discordPatcher.sh" "$color"
    fi
    #browser patchers
    if command -v zen-browser >/dev/null 2>&1; then
        timed "zenPatcher" "$SUPPORT/appPatchers/zenPatcher.sh" "$color"
    fi
    if command -v firefox >/dev/null 2>&1; then
        timed "firefoxPatcher" "$SUPPORT/appPatchers/firefoxPatcher.sh" "$color"
    fi
    #betterbird patcher
    if command -v betterbird >/dev/null 2>&1 || command -v thunderbird >/dev/null 2>&1; then
        timed "thunderbirdPatcher" "$SUPPORT/appPatchers/thunderbirdPatcher.sh" "$color"
    fi

    # 7. Restart apps
    declare -A APPS
    APPS[dolphin]="x|dolphin|dolphin|dolphin|dolphin"
    APPS[ferdium]="f|electron.*ferdium-bin|electron.*ferdium-bin|ferdium|ferdium"
    APPS[sourcegit]="x|sourcegit|sourcegit|sourcegit|sourcegit"
    APPS[code]="x|code|code|code|code"
    APPS[vesktop]="x|vesktop|vesktop|vesktop -m|vesktop"
    APPS[nativmix]="x|nativmix|nativmix|nativmix --hidden --restart|"
    APPS[localsend]="x|localsend|localsend|localsend --hidden|"
    APPS[betterbird]="f|betterbird|betterbird|betterbird|eu.betterbird.Betterbird"
    APPS[thunderbird]="f|thunderbird|thunderbird|thunderbird|org.mozilla.Thunderbird"
    APPS[swaync]="x|swaync|swaync|swaync"

    # Sourced directly (not via timed()) because it must set $running in
    # THIS shell for the wait_for_hypr_class loop below to see it.
    _t0=$(date +%s%N)
    source "$SUPPORT/appRestarter.sh"
    _t1=$(date +%s%N)
    echo "[timing] appRestarter: $(awk -v a="$_t0" -v b="$_t1" 'BEGIN{printf "%.3f", (b-a)/1000000000}')s" >&2

    # Blocks until a window of the given Hyprland class appears (or times
    # out). Used so hyprLayoutPreservation.sh restore only runs once every
    # relaunched window actually exists — otherwise a late-appearing window
    # (e.g. Spotify) grabs focus after restore already set it.
    wait_for_hypr_class() {
        local wclass="$1"
        local deadline=$(( $(date +%s) + 5 ))
        while [ $(date +%s) -lt $deadline ]; do
            hyprctl clients -j | python3 -c "
import json,sys
clients=json.load(sys.stdin)
exit(0 if any('$wclass' in c.get('class','').lower() for c in clients) else 1)
" 2>/dev/null && return 0
            sleep 0.1
        done
        return 1
    }

    if [ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]; then
        # Wait for each windowed app individually
        for app in "${running[@]}"; do
            echo "Waiting for $app to appear..."
            IFS='|' read -r _ _ _ _ wclass <<< "${APPS[$app]}"
            [ -z "$wclass" ] && continue
            timed "wait_for_hypr_class($app)" wait_for_hypr_class "$wclass"
        done
    fi

    #Desktop Environment specific actions
    if [ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]; then
        # Restore Hyprland layout state after all restarts (Spotify included)
        timed "hyprLayoutPreservation restore" "$SUPPORT/hyprLayoutPreservation.sh" restore

        timed "waybar restart" systemctl --user restart waybar.service

    elif [ "$XDG_CURRENT_DESKTOP" == "KDE" ]; then
        kquitapp6 plasmashell && sleep 1 && kstart plasmashell &
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
    color=$(timed "colorChooser" "$SUPPORT/colorChooser.sh")
    if [ $? -ne 0 ] || [ -z "$color" ]; then
        echo "ERROR: colorChooser failed, aborting"
        exit 1
    fi

    color="${color,,}"
    accent="#$color"
    echo "Final color: $accent"

    # Run matugen once with the final chosen color
    timed "matugen" matugen color hex "$accent" --quiet

    # 2. Apply to RGB devices (backgrounded — fire and forget)
    timed "rgbApply" "$SUPPORT/rgbApply.sh" "$color"

    # 3. Patch KDE color schemes
    timed "kdePatcher" "$SUPPORT/kdePatcher.sh" "$color"

    # 4. Patch GTK themes
    timed "gtkPatcher" "$SUPPORT/gtkPatcher.sh" "$color"

    # 5. Patch icons
    timed "iconPatcher" "$SUPPORT/iconPatcher.sh" "$color"

    # 6. Patch app-specific themes
    if command -v code >/dev/null 2>&1; then
        timed "vscodePatcher" "$SUPPORT/appPatchers/vscodePatcher.sh" "$color"
    fi
    if command -v sourcegit >/dev/null 2>&1; then
        timed "sourceGitPatcher" "$SUPPORT/appPatchers/sourceGitPatcher.sh" "$color"
    fi
    if command -v ferdium >/dev/null 2>&1; then
        timed "ferdiumPatcher" "$SUPPORT/appPatchers/ferdiumPatcher.sh" "$color"
        timed "ferdiumIconPatcher" "$SUPPORT/appPatchers/ferdiumIconPatcher.sh" "$color"
    fi
    if command -v vesktop >/dev/null 2>&1; then
        timed "discordPatcher" "$SUPPORT/appPatchers/discordPatcher.sh" "$color"
    fi
    #browser patchers
    if command -v zen-browser >/dev/null 2>&1; then
        timed "zenPatcher" "$SUPPORT/appPatchers/zenPatcher.sh" "$color"
    fi
    if command -v firefox >/dev/null 2>&1; then
        timed "firefoxPatcher" "$SUPPORT/appPatchers/firefoxPatcher.sh" "$color"
    fi
    #betterbird patcher
    if command -v betterbird >/dev/null 2>&1 || command -v thunderbird >/dev/null 2>&1; then
        timed "thunderbirdPatcher" "$SUPPORT/appPatchers/thunderbirdPatcher.sh" "$color"
    fi

    if [ "$XDG_CURRENT_DESKTOP" == "KDE" ]; then
        kquitapp6 plasmashell && sleep 1 && kstart plasmashell &
        disown
    elif [ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]; then
        timed "waybar restart" systemctl --user restart waybar.service
    fi
}

cmd_tray() {
    # 1. Choose accent color from wallpaper
    color=$(timed "colorChooser" "$SUPPORT/colorChooser.sh")
    if [ $? -ne 0 ] || [ -z "$color" ]; then
        echo "ERROR: colorChooser failed, aborting"
        exit 1
    fi

    color="${color,,}"
    accent="#$color"
    echo "Final color: $accent"

    # Run the tray icon updater script
    timed "trayIconPatcher.sh" "$SUPPORT/trayIconPatcher.sh" "$color"

    # Reload shell/waybar to reflect tray icon changes
    if [ "$XDG_CURRENT_DESKTOP" == "KDE" ]; then
        kquitapp6 plasmashell && sleep 1 && kstart plasmashell &
        disown
    elif [ "$XDG_CURRENT_DESKTOP" == "Hyprland" ]; then
        timed "waybar restart" systemctl --user restart waybar.service
    fi
}

case "$1" in
    --full)        cmd_full ;;
    --rgb)         cmd_rgb ;;
    --softrun)     cmd_softrun ;;
    --tray)        cmd_tray ;;
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