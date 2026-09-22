#!/usr/bin/env bash

patch_nativmix_tray() {
    command -v nativmix >/dev/null 2>&1 || return 0

    # Confirmed via nativmix's own source (utils/paths.py get_icon_path()):
    # the tray icon always reads this exact file directly, and only falls
    # back to QIcon.fromTheme("nativmix") if it's missing — so as long as
    # this file exists (it does, via the AUR package), theming the icon
    # theme entry alone is never enough; this file has to be overwritten.
    local target="/usr/share/nativmix/assets/icon.png"
    [ -f "$target" ] || {
        echo "  nativmix: $target not found (package layout may have changed)"
        return 1
    }

    local svg
    svg=$(resolve_themed_svg "nativmix-alt") || svg=$(resolve_themed_svg "nativmix") || {
        echo "  nativmix: no themed base icon found, skipping tray"; return 1
    }

    if [ "$listOnly" -eq 1 ]; then
        echo "nativmix: would overwrite $target with themed nativmix-alt/nativmix icon"
        return 0
    fi

    command -v rsvg-convert >/dev/null 2>&1 || {
        echo "  nativmix: rsvg-convert not found, cannot rasterize"; return 1
    }

    fix_system_dir_permissions "$(dirname "$target")" "nativmix" || return 1

    local backup="${target}.orig"
    [ -f "$backup" ] || cp "$target" "$backup"

    rsvg-convert -w 256 -h 256 "$svg" -o "$target" \
        && echo "NativMix tray icon patched in place ($target)"
}