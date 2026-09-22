#!/usr/bin/env bash

#onedrivegui tray icon
oneDriveGuiImagesDir="/usr/lib/OneDriveGUI/resources/images"

declare -A oneDriveGuiSvgOverrides=(
    ["icons8-cloud-done-80.png"]="cloud-check:accent"      # ok/synced
    ["warning.png"]="cloud-exclamation:#f39c12"            # warning
    ["icons8-cloud-error-80.png"]="cloud-x:#e74c3c"        # error
    ["icons8-cloud-sync-80.png"]="cloud-cog:accent"        # syncing
)

declare -A oneDriveGuiColorizeOnly=(
    ["icons8-cloud-80.png"]="accent"        # idle
    ["icons8-cloud-stop-80.png"]="accent"   # paused (unless this is actually "warning" — see above)
)

fix_onedrive_gui_permissions() {
    fix_system_dir_permissions "$oneDriveGuiImagesDir" "onedrivegui"
}

patch_onedrive_gui_tray() {
    command -v onedrivegui >/dev/null 2>&1 || return 0
    [ -d "$oneDriveGuiImagesDir" ] || {
        echo "  onedrivegui: $oneDriveGuiImagesDir not found (package layout may have changed)"
        return 1
    }

    if [ "$listOnly" -eq 1 ]; then
        echo "onedrivegui: custom SVG replacements:"
        for name in "${!oneDriveGuiSvgOverrides[@]}"; do
            IFS=':' read -r iconName target <<< "${oneDriveGuiSvgOverrides[$name]}"
            [ "$target" = "accent" ] && target="$accent"
            printf '  %-28s -> %s_base_icon.svg (%s)\n' "$name" "$iconName" "$target"
        done
        echo "onedrivegui: plain recolor (existing vendor art):"
        for name in "${!oneDriveGuiColorizeOnly[@]}"; do
            local target="${oneDriveGuiColorizeOnly[$name]}"
            [ "$target" = "accent" ] && target="$accent"
            printf '  %-28s -> %s\n' "$name" "$target"
        done
        echo "  (left alone: icons8-green-circle-48.png, icons8-red-circle-48.png, and"
        echo "   in-window UI icons like account/folder/gear/play/pause/quit)"
        return 0
    fi

    local tool=""
    command -v magick >/dev/null 2>&1 && tool="magick"
    [ -z "$tool" ] && command -v convert >/dev/null 2>&1 && tool="convert"
    if [ -z "$tool" ]; then
        echo "  onedrivegui: ImageMagick not found, cannot recolor icons"
        return 1
    fi
    command -v rsvg-convert >/dev/null 2>&1 || {
        echo "  onedrivegui: rsvg-convert not found, cannot rasterize custom SVGs"
        return 1
    }

    fix_onedrive_gui_permissions || return 1

    local patched=0 skipped=0

    # -- custom SVG replacements --
    for name in "${!oneDriveGuiSvgOverrides[@]}"; do
        local f="$oneDriveGuiImagesDir/$name"
        [ -f "$f" ] || { echo "  onedrivegui: vendor file $name not found, skipping"; continue; }

        IFS=':' read -r iconName target <<< "${oneDriveGuiSvgOverrides[$name]}"
        [ "$target" = "accent" ] && target="$accent"

        local srcSvg="$iconsDir/${iconName}_base_icon.svg"
        if [ ! -f "$srcSvg" ]; then
            echo "  onedrivegui: $srcSvg not found — add it, or drop this override for $name"
            skipped=$((skipped + 1))
            continue
        fi

        local backup="${f}.orig"
        [ -f "$backup" ] || cp "$f" "$backup"

        # Match the vendor icon's own pixel size so it doesn't look
        # mismatched next to the icons we're leaving alone.
        local dims
        if command -v identify >/dev/null 2>&1; then
            dims=$(identify -format "%wx%h" "$backup" 2>/dev/null)
        else
            dims=$("$tool" identify -format "%wx%h" "$backup" 2>/dev/null)
        fi
        local w="${dims%x*}" h="${dims#*x}"
        [ -z "$w" ] && w=80
        [ -z "$h" ] && h=80

        local tmpSvg tmpPng
        tmpSvg=$(mktemp --suffix=.svg)
        tmpPng=$(mktemp --suffix=.png)
        sed "s/currentColor/$target/g" "$srcSvg" > "$tmpSvg"
        rsvg-convert -w "$w" -h "$h" "$tmpSvg" -o "$tmpPng"
        cp "$tmpPng" "$f"
        rm -f "$tmpSvg" "$tmpPng"
        patched=$((patched + 1))
        echo "  $name replaced with ${iconName}_base_icon.svg ($target)"
    done

    # -- plain recolor of remaining vendor art --
    for name in "${!oneDriveGuiColorizeOnly[@]}"; do
        local f="$oneDriveGuiImagesDir/$name"
        [ -f "$f" ] || { echo "  onedrivegui: vendor file $name not found, skipping"; continue; }

        local target="${oneDriveGuiColorizeOnly[$name]}"
        [ "$target" = "accent" ] && target="$accent"

        local backup="${f}.orig"
        [ -f "$backup" ] || cp "$f" "$backup"

        "$tool" "$backup" -fill "$target" -colorize 100% "$f"
        patched=$((patched + 1))
    done

    echo "OneDriveGUI tray icons patched ($patched patched, $skipped skipped)"
    echo "  (originals preserved as *.png.orig next to each file)"
}