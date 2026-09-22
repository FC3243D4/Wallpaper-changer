#!/usr/bin/env bash

patch_betterbird_tray() {
    local betterbirdTarget isFlatpak=0

    if [ -d "$HOME/.var/app/eu.betterbird.Betterbird" ]; then
        isFlatpak=1
        betterbirdTarget="$HOME/.var/app/eu.betterbird.Betterbird/data/icons/hicolor/scalable/status"
    elif command -v betterbird >/dev/null 2>&1; then
        betterbirdTarget="/opt/betterbird"
    else
        echo "  betterbird: not installed, skipping tray"
        return 0
    fi

    defaultsvg=$(resolve_themed_svg "mail") || { echo "  betterbird: no themed base icon found, skipping tray"; return 1; }
    newmailsvg=$(resolve_themed_svg "new-mail") || { echo "  betterbird: no themed new-mail icon found, skipping tray"; return 1; }

    if [ "$isFlatpak" -eq 1 ]; then
        if [ "$listOnly" -eq 1 ]; then
            echo "betterbird: would overwrite:"
            echo "  $betterbirdTarget/eu.betterbird.Betterbird-default.svg"
            echo "  $betterbirdTarget/eu.betterbird.Betterbird-newmail.svg"
            return 0
        fi
        mkdir -p "$betterbirdTarget" || return 1
        cp "$defaultsvg" "$betterbirdTarget/eu.betterbird.Betterbird-default.svg"
        cp "$newmailsvg" "$betterbirdTarget/eu.betterbird.Betterbird-newmail.svg"
        echo "Betterbird tray icon patched (flatpak)"
        return 0
    fi

    cp "$defaultsvg" "$betterbirdTarget/chrome/icons/default/default.svg"
    cp "$newmailsvg" "$betterbirdTarget/chrome/icons/default/newmail.svg"

    local svg
    svg=$(resolve_themed_svg "mail") || { echo "  betterbird: no themed base icon found, skipping tray"; return 1; }

    local targets=(
        "$betterbirdTarget/chrome/icons/default/default16.png"
        "$betterbirdTarget/chrome/icons/default/default22.png"
        "$betterbirdTarget/chrome/icons/default/default24.png"
        "$betterbirdTarget/chrome/icons/default/default32.png"
        "$betterbirdTarget/chrome/icons/default/default48.png"
        "$betterbirdTarget/chrome/icons/default/default64.png"
        "$betterbirdTarget/chrome/icons/default/default128.png"
        "$betterbirdTarget/chrome/icons/default/default256.png"
    )

    local resolutions=(
        16 22 24 32 48 64 128 256
    )

    if [ "$listOnly" -eq 1 ]; then
        echo "betterbird: would overwrite:"
        printf '  %s\n' "${targets[@]}"
        return 0
    fi

    command -v rsvg-convert >/dev/null 2>&1 || {
        echo "  betterbird: rsvg-convert not found, cannot rasterize"; return 1
    }
    fix_system_dir_permissions "$betterbirdTarget/chrome/icons/default" "default.svg" || return 1

    local patched=0
    for r in "${resolutions[@]}"; do
        local f="$betterbirdTarget/chrome/icons/default/default${r}.png"
        [ -f "$f" ] || { echo "  betterbird: $f not found, skipping"; continue; }
        local backup="${f}.orig"
        [ -f "$backup" ] || cp "$f" "$backup"
        rsvg-convert -w $r -h $r "$svg" -o "$f" && patched=$((patched + 1))
    done
    echo "Betterbird tray icon patched in place ($patched/${#targets[@]})"
}