#!/usr/bin/env bash

patch_sonora_tray() {
    command -v sonora >/dev/null 2>&1 || return 0

    # Sonora's tray (crates/sonora/src/tray/sni.rs, ksni) registers a
    # StatusNotifierItem with IconName "sonora" and also an embedded
    # 32x32 pixmap (include_bytes!, so it can't be patched on disk). Hosts
    # resolve IconName through the icon theme first and only fall back to
    # the pixmap when it doesn't resolve, so a themed "sonora" entry in
    # the active theme is enough. Same "music" base as the app-menu icon
    # and ytmdesktop, recolored with waybar's resolved primary like every
    # other tray icon.
    local dst="$iconThemeDir/apps/scalable/sonora.svg"

    local svg
    svg=$(resolve_themed_svg "music") || {
        echo "  sonora: music_base_icon.svg not found, skipping tray"; return 1
    }

    if [ "$listOnly" -eq 1 ]; then
        echo "sonora: would write $dst from music_base_icon.svg"
        rm -f "$svg"
        return 0
    fi

    mkdir -p "$(dirname "$dst")"
    if cp "$svg" "$dst"; then
        echo "Sonora tray icon patched ($dst)"
    fi
    rm -f "$svg"
}