#!/usr/bin/env bash

# Swaync icons — written to swaync's config dir, plus fixed-red error/note
patch_osd_icons() {
    local swayncIconsDir="$HOME/.config/swaync/icons"
    local notifRed="#e74c3c"  # adjust to taste — not accent-derived, always red
    if command -v swaync >/dev/null 2>&1; then
        mkdir -p "$swayncIconsDir"

        declare -A osdIcons=(
            [microphone]="microphone"
            [microphone-mute]="microphone-mute"
            [music]="music"
            [picture]="picture"
            [timer]="timer"
            [volume-high]="volume-high"
            [volume-mid]="volume-mid"
            [volume-low]="volume-low"
            [volume-mute]="volume-mute"
            [brightness-20]="brightness-20"
            [brightness-40]="brightness-40"
            [brightness-60]="brightness-60"
            [brightness-80]="brightness-80"
            [brightness-100]="brightness-100"
            [ok]="ok"
            [wallpaper_changer]="wallpaper_changer"
        )

        local patched=0
        for outName in "${!osdIcons[@]}"; do
            src="$iconsDir/${osdIcons[$outName]}_base_icon.svg"
            if [ -f "$src" ]; then
                sed -e "s/currentColor/$accent/g" "$src" > "$swayncIconsDir/${outName}.svg"
                patched=$((patched + 1))
            fi
        done

        # Error/note icons: always red, independent of the accent color
        for outName in error note; do
            src="$iconsDir/${outName}_base_icon.svg"
            if [ -f "$src" ]; then
                sed "s/currentColor/$notifRed/g" "$src" > "$swayncIconsDir/${outName}.svg"
                patched=$((patched + 1))
            fi
        done

        if [ "$patched" -gt 0 ]; then
            echo "OSD icons patched ($patched/16)"
        else
            echo "  no OSD base icons found to patch"
        fi
    fi
}