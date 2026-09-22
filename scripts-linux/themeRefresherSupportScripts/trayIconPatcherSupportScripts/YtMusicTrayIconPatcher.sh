patch_ytm_desktop_tray() {
    local resourceDir=""
    local candidates=(
        "/opt/ytmdesktop/resources"
        "/opt/YouTube Music Desktop App/resources"
        "/usr/lib/ytmdesktop/resources"
    )
    local d
    for d in "${candidates[@]}"; do
        if [ -f "$d/ytmd_white.png" ] && [ -f "$d/ytmd_black.png" ]; then
            resourceDir="$d"
            break
        fi
    done
    [ -n "$resourceDir" ] || {
        echo "  ytmdesktop: ytmd_white.png/ytmd_black.png not found under any of:"
        printf '    %s\n' "${candidates[@]}"
        echo "  (package layout may differ — find them with:"
        echo "   find / -name 'ytmd_white.png' 2>/dev/null)"
        return 1
    }

    local svg
    svg=$(resolve_themed_svg "music") || { echo "  ytmdesktop: music_base_icon.svg not found, skipping tray"; return 1; }

    local targets=("$resourceDir/ytmd_white.png" "$resourceDir/ytmd_black.png")

    if [ "$listOnly" -eq 1 ]; then
        echo "ytmdesktop: would overwrite:"
        printf '  %s\n' "${targets[@]}"
        return 0
    fi

    command -v rsvg-convert >/dev/null 2>&1 || {
        echo "  ytmdesktop: rsvg-convert not found, cannot rasterize"; return 1
    }
    fix_system_dir_permissions "$resourceDir" "ytmdesktop" || return 1

    local patched=0
    local f
    for f in "${targets[@]}"; do
        local backup="${f}.orig"
        [ -f "$backup" ] || cp "$f" "$backup"
        # Match the original 512x512 canvas so the tray-side downscale
        # behaves the same as upstream's own icon.
        rsvg-convert -w 512 -h 512 "$svg" -o "$f" && patched=$((patched + 1))
    done
    echo "YTMDesktop tray icons patched in place ($patched/${#targets[@]}, $resourceDir)"

    [ "$patched" -gt 0 ] && force_ytm_desktop_reload
}

# Makes one durable change to trayIconStyle in YTMDesktop's own config.json
# so its `conf` store (polls via fs.watchFile on Linux) notices it and
# calls setTrayIcon() itself, re-reading the PNGs just overwritten above.
# Values: Auto=0, White=1, Black=2 (src/shared/store/schema.ts). Schedules
# a delayed, detached revert to the real setting afterward — cosmetic
# only, since ytmd_white.png and ytmd_black.png are now identical, so
# which one gets selected doesn't change what's drawn in the tray.
force_ytm_desktop_reload() {
    { pgrep -x youtube-music-desktop-app >/dev/null 2>&1 || pgrep -f ytmdesktop >/dev/null 2>&1; } || {
        echo "  ytmdesktop: not currently running, nothing to notify"
        return 0
    }
    command -v jq >/dev/null 2>&1 || {
        echo "  ytmdesktop: jq not found, can't trigger a live tray refresh"
        echo "  (new icons will show next time YTMDesktop starts)"
        return 1
    }

    local cfg="$HOME/.config/YouTube Music Desktop App/config.json"
    [ -f "$cfg" ] || {
        echo "  ytmdesktop: config.json not found at $cfg, can't trigger a live refresh"
        return 1
    }

    local current other tmp
    current=$(jq -r '.appearance.trayIconStyle // 0' "$cfg")
    other=$(( (current + 1) % 3 ))

    tmp=$(mktemp)
    jq ".appearance.trayIconStyle = $other" "$cfg" > "$tmp" && mv "$tmp" "$cfg"
    echo "  ytmdesktop: set trayIconStyle $current -> $other to force a live repaint"
    echo "  (conf polls the file on Linux — can take up to ~10s to actually redraw)"

    # Detached: this script's own run finishes long before the revert
    # fires, no need to make the theme refresh wait ~10+ more seconds on
    # a cosmetic settings-value cleanup.
    (
        sleep 12
        tmp2=$(mktemp)
        jq ".appearance.trayIconStyle = $current" "$cfg" > "$tmp2" 2>/dev/null && mv "$tmp2" "$cfg"
    ) >/dev/null 2>&1 &
    disown
}