#!/usr/bin/env bash

patch_streamcontroller_tray() {
    command -v streamcontroller >/dev/null 2>&1 || return 0

    # Confirmed via src/tray.py: it sets its own DBus StatusNotifierItem
    # IconThemePath to /usr/lib/streamcontroller/Assets/icons (bypassing
    # the active icon theme entirely) and requests icon name
    # "com.core447.StreamController" — which resolves to exactly these two
    # files, per the standard hicolor apps/<size> layout.
    local iconBase="/usr/lib/streamcontroller/Assets/icons/hicolor"
    local targets=(
        "$iconBase/48x48/apps/com.core447.StreamController.png"
        "$iconBase/512x512/apps/com.core447.StreamController.png"
    )

    local svg
    svg=$(resolve_themed_svg "elgato") || { echo "  streamcontroller: no themed base icon found, skipping tray"; return 1; }

    if [ "$listOnly" -eq 1 ]; then
        echo "streamcontroller: would overwrite:"
        printf '  %s\n' "${targets[@]}"
        return 0
    fi

    command -v rsvg-convert >/dev/null 2>&1 || {
        echo "  streamcontroller: rsvg-convert not found, cannot rasterize"; return 1
    }
    fix_system_dir_permissions "$iconBase" "streamcontroller" || return 1

    local patched=0
    for f in "${targets[@]}"; do
        [ -f "$f" ] || { echo "  streamcontroller: $f not found, skipping"; continue; }
        local backup="${f}.orig"
        [ -f "$backup" ] || cp "$f" "$backup"
        # Size comes from the directory name (48x48 / 512x512).
        local size
        size=$(basename "$(dirname "$(dirname "$f")")")
        size="${size%%x*}"
        rsvg-convert -w "$size" -h "$size" "$svg" -o "$f" && patched=$((patched + 1))
    done
    echo "StreamController tray icon patched in place ($patched/${#targets[@]})"
}