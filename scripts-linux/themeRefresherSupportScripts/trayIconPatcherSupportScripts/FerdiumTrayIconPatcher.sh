#!/usr/bin/env bash

patch_ferdium_tray() {
    command -v ferdium >/dev/null 2>&1 || return 0

    # Confirmed via `pacman -Ql ferdium-bin`: real Linux tray assets bundled
    # at this path, root-owned (AUR package installs to /opt). No per-user
    # config indirection like Vesktop's trayIconPath — these files are what
    # Ferdium actually loads.
    local trayDir="/opt/ferdium-bin/assets/images/tray/linux"
    [ -d "$trayDir" ] || {
        echo "  ferdium: $trayDir not found (package layout may have changed)"
        return 1
    }

    local svg
    svg=$(resolve_themed_svg "ferdium") || { echo "  ferdium: no themed base icon found, skipping tray"; return 1; }

    # tray/tray-indirect/tray-unread all get the same plain accent icon —
    # Ferdium doesn't expose a separate unread-badge asset to composite
    # onto here the way Vesktop's settings.json flow does. Say the word if
    # you'd like a red-dot badge burned into tray-unread.png specifically.
    local names=(tray tray-indirect tray-unread)

    if [ "$listOnly" -eq 1 ]; then
        echo "ferdium: would overwrite in $trayDir:"
        for n in "${names[@]}"; do
            printf '  %s.png / %s@2x.png\n' "$n" "$n"
        done
        return 0
    fi

    command -v rsvg-convert >/dev/null 2>&1 || {
        echo "  ferdium: rsvg-convert not found, cannot rasterize"; return 1
    }
    fix_system_dir_permissions "$trayDir" "ferdium" || return 1

    local patched=0
    local jobDir
    jobDir=$(mktemp -d)
    local i=0
    for n in "${names[@]}"; do
        for variant in "$n.png" "$n@2x.png"; do
            local f="$trayDir/$variant"
            [ -f "$f" ] || continue
            i=$((i + 1))
            (
                backup="${f}.orig"
                [ -f "$backup" ] || cp "$f" "$backup"

                if command -v identify >/dev/null 2>&1; then
                    dims=$(identify -format "%wx%h" "$backup" 2>/dev/null)
                elif command -v magick >/dev/null 2>&1; then
                    dims=$(magick identify -format "%wx%h" "$backup" 2>/dev/null)
                fi
                size="${dims%x*}"
                [ -z "$size" ] && size=22

                rsvg-convert -w "$size" -h "$size" "$svg" -o "$f" && touch "$jobDir/$i"
            ) &
        done
    done
    wait
    patched=$(find "$jobDir" -mindepth 1 | wc -l)
    rm -rf "$jobDir"
    echo "Ferdium tray icons patched in place ($patched files, $trayDir)"
}