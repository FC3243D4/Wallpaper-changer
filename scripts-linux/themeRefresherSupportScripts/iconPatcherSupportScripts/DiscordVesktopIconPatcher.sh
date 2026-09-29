#!/usr/bin/env bash

# Discord/Vesktop share one base icon, and Vesktop additionally needs the
# tray-state PNGs above — too entangled for the generic engine.
patch_discord_vesktop_icons() {
    src="$iconsDir/discord_base_icon.svg"
    if [ -f "$src" ]; then
        if command -v discord >/dev/null 2>&1; then
            sed "s/currentColor/$accent/g" "$src" > "$iconThemeDir/apps/scalable/discord.svg"
            echo "Discord icon patched"
            patch_desktop_icon "discord" "discord.desktop" "com.discordapp.Discord.desktop"
        fi
        if command -v vesktop >/dev/null 2>&1; then
            sed "s/currentColor/$accent/g" "$src" > "$iconThemeDir/apps/scalable/vesktop.svg"
            echo "Vesktop icon patched"
            patch_desktop_icon "vesktop" "vesktop.desktop" "*vesktop*.desktop"
        fi
    fi
}