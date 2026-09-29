#!/usr/bin/env bash

patch_cohesion_tray() {
    local appId="io.github.brunofin.Cohesion"
    command -v flatpak >/dev/null 2>&1 || return 0
    flatpak info "$appId" >/dev/null 2>&1 || return 0

    local overrideDir="$HOME/.local/share/cohesion-icons"
    local iconDir="$overrideDir/icons/hicolor/512x512/apps"

    # One-time sandbox grant, checked (not blindly re-applied) every run so
    # this doesn't spam `flatpak override` on every theme refresh — same
    # spirit as fix_system_dir_permissions's one-time chown above.
    if ! flatpak override --user --show "$appId" 2>/dev/null | grep -q "$overrideDir"; then
        echo "  cohesion: granting one-time sandbox access to $overrideDir"
        flatpak override --user "$appId" \
            --filesystem="$overrideDir:ro" \
            --env=XDG_DATA_DIRS="$overrideDir:/app/share:/usr/share:/var/lib/flatpak/exports/share:$HOME/.local/share/flatpak/exports/share" \
            || { echo "  cohesion: flatpak override failed, skipping tray"; return 1; }
    fi

    mkdir -p "$iconDir" || return 1

    local svg
    svg=$(resolve_themed_svg "notion") || {
        echo "  cohesion: no themed base icon found ($iconsDir/cohesion_base_icon.svg), skipping tray"
        return 1
    }
    svgUnread=$(resolve_themed_svg "notion-unread") || {
        echo "  cohesion: no themed unread base icon found ($iconsDir/cohesion_unread_base_icon.svg), skipping tray"
        return 1
    }

    local colorTargets=(
        "$iconDir/io.github.brunofin.Cohesion.png"
        "$iconDir/io.github.brunofin.Cohesion-unread.png"
    )
    local greyTargets=(
        "$iconDir/io.github.brunofin.Cohesion-greyscale.png"
        "$iconDir/io.github.brunofin.Cohesion-greyscale-unread.png"
    )

    if [ "$listOnly" -eq 1 ]; then
        echo "cohesion: would write:"
        printf '  %s\n' "${colorTargets[@]}" "${greyTargets[@]}"
        return 0
    fi

    command -v rsvg-convert >/dev/null 2>&1 || {
        echo "  cohesion: rsvg-convert not found, cannot rasterize"; return 1
    }

    # Normal and unread icons never touch each other's files at any stage
    # (each greyscale target only ever reads its OWN color counterpart, via
    # ${f/-greyscale/}), so each one's full color->greyscale chain runs as
    # its own independent background pipeline instead of doing both color
    # rasterizations, then both greyscale derivations, as one sequential
    # chain of 4 external tool calls. A background subshell can't add to
    # `patched` directly, so each pipeline reports how many of its own 2
    # files it wrote back via its exit code (0, 1, or 2).
    local greyTool="cp"
    if command -v magick >/dev/null 2>&1; then
        greyTool="magick"
    elif command -v convert >/dev/null 2>&1; then
        greyTool="convert"
    else
        echo "  cohesion: imagemagick not found, copying color icon into greyscale slots unmodified"
    fi

    _cohesion_pipeline() {
        local colorTarget="$1" greyTarget="$2" rsvg="$3" tool="$4"
        local n=0
        rsvg-convert -w 512 -h 512 "$rsvg" -o "$colorTarget" && n=$((n + 1))
        case "$tool" in
            magick)  magick "$colorTarget" -colorspace Gray "$greyTarget" && n=$((n + 1)) ;;
            convert) convert "$colorTarget" -colorspace Gray "$greyTarget" && n=$((n + 1)) ;;
            *)       cp "$colorTarget" "$greyTarget" && n=$((n + 1)) ;;
        esac
        return "$n"
    }

    _cohesion_pipeline "${colorTargets[0]}" "${greyTargets[0]}" "$svg" "$greyTool" &
    local pid1=$!
    _cohesion_pipeline "${colorTargets[1]}" "${greyTargets[1]}" "$svgUnread" "$greyTool" &
    local pid2=$!

    local patched=0
    wait "$pid1"; patched=$((patched + $?))
    wait "$pid2"; patched=$((patched + $?))

    echo "Cohesion tray icons patched ($patched/4, $iconDir)"
    echo "  (restart Cohesion for the new icons to take effect)"
}