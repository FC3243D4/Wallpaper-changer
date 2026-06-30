#!/usr/bin/env bash

SUPPORT="$HOME/.config/WallpaperChanger/themeRefresherSupportScripts"

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
    "$SUPPORT/vscodePatcher.sh" "$color"
fi
if command -v zen-browser >/dev/null 2>&1; then
    "$SUPPORT/zenPatcher.sh" "$color"
fi
if command -v sourcegit >/dev/null 2>&1; then
    "$SUPPORT/sourceGitPatcher.sh" "$color"
fi
if command -v ferdium >/dev/null 2>&1; then
    "$SUPPORT/ferdiumPatcher.sh" "$color"
fi

# 7. Restart apps
declare -A APPS
APPS[dolphin]="x|dolphin|dolphin|dolphin|dolphin"
APPS[zen]="f|zen-bin|zen-bin|zen-browser|zen"
APPS[ferdium]="f|electron.*ferdium-bin|electron.*ferdium-bin|ferdium|"
APPS[sourcegit]="x|sourcegit|sourcegit|sourcegit|sourcegit"
APPS[code]="x|code|code|code|code"


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
    sleep 0.2 && "$SUPPORT/hyprMasterLayoutPreservation.sh" restore

elif [ "$XDG_CURRENT_DESKTOP" == "KDE" ]; then
    kquitapp6 plasmashell && sleep 1 && kstart plasmashell &
    disown
fi
