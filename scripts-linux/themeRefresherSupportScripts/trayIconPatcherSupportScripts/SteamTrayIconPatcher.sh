#!/usr/bin/env bash

patch_steam_tray() {
    command -v steam >/dev/null 2>&1 || return 0

    local svg
    svg=$(resolve_themed_svg "steam") || { echo "  steam: no themed base icon found, skipping tray"; return 1; }

    local targets=(
        "$HOME/.local/share/Steam/public/steam_tray_mono.png"
        "/usr/share/pixmaps/steam_tray_mono.png"
    )

    if [ "$listOnly" -eq 1 ]; then
        echo "steam: would overwrite:"
        printf '  %s\n' "${targets[@]}"
        return 0
    fi

    command -v rsvg-convert >/dev/null 2>&1 || {
        echo "  steam: rsvg-convert not found, cannot rasterize"; return 1
    }

    local patched=0
    for f in "${targets[@]}"; do
        [ -f "$f" ] || { echo "  steam: $f not found, skipping"; continue; }

        # Only the system copy needs the chown-once treatment; the
        # self-updating client copy under $HOME is already user-owned.
        if [[ "$f" == /usr/* ]]; then
            fix_system_dir_permissions "$(dirname "$f")" "steam" || continue
        fi

        local backup="${f}.orig"
        [ -f "$backup" ] || cp "$f" "$backup"

        local dims size
        if command -v identify >/dev/null 2>&1; then
            dims=$(identify -format "%wx%h" "$backup" 2>/dev/null)
        elif command -v magick >/dev/null 2>&1; then
            dims=$(magick identify -format "%wx%h" "$backup" 2>/dev/null)
        fi
        size="${dims%x*}"
        [ -z "$size" ] && size=24

        rsvg-convert -w "$size" -h "$size" "$svg" -o "$f" && patched=$((patched + 1))
    done
    echo "Steam tray icon patched in place ($patched/${#targets[@]})"
}