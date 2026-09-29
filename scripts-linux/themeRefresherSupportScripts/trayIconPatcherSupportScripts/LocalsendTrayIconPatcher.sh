#!/usr/bin/env bash

patch_localsend_tray() {
    command -v localsend >/dev/null 2>&1 || return 0

    # Confirmed via `pacman -Ql localsend`: real tray assets live in its
    # Flutter asset bundle. logo-32-black/-white are the light/dark tray
    # variants (standard cross-platform tray convention); logo-32.png is
    # the plain fallback. Recolor all three since we can't tell at rest
    # which one LocalSend's tray plugin actually selects at runtime.
    local imgDir="/usr/lib/localsend/data/flutter_assets/assets/img"
    [ -d "$imgDir" ] || {
        echo "  localsend: $imgDir not found (package layout may have changed)"
        return 1
    }

    local svg
    svg=$(resolve_themed_svg "localsend") || { echo "  localsend: no themed base icon found, skipping tray"; return 1; }

    local names=(logo-32.png logo-32-black.png logo-32-white.png)

    if [ "$listOnly" -eq 1 ]; then
        echo "localsend: would overwrite in $imgDir:"
        printf '  %s\n' "${names[@]}"
        return 0
    fi

    command -v rsvg-convert >/dev/null 2>&1 || {
        echo "  localsend: rsvg-convert not found, cannot rasterize"; return 1
    }
    fix_system_dir_permissions "$imgDir" "localsend" || return 1

    local patched=0
    for n in "${names[@]}"; do
        local f="$imgDir/$n"
        [ -f "$f" ] || continue
        local backup="${f}.orig"
        [ -f "$backup" ] || cp "$f" "$backup"
        rsvg-convert -w 32 -h 32 "$svg" -o "$f" && patched=$((patched + 1))
    done
    echo "LocalSend tray icons patched in place ($patched/${#names[@]}, $imgDir)"
}