#!/usr/bin/env bash
# VicinaeExtensionsPatcher.sh
# Replaces the icon of selected Vicinae store extensions with accent-colored
# versions of our own base SVGs (rendered to 512x512 PNG).
#
# Sourced by IconPatcher.sh, so it relies on these from the parent script:
# $accent, $iconsDir, $gameIconsDir, find_base_svg, patch_svg_color (Utils.sh).
#
# Speed:
#   - each icon is skipped entirely when nothing changed (same svg, accent
#     and converter, and the PNG on disk is still the one we wrote — an
#     extension update that restores the original PNG is detected and
#     re-patched)
#   - icons that do need work are converted in parallel
#   - rsvg-convert is preferred (renders the vector straight at 512px, far
#     faster than magick); magick/convert are only fallbacks
#
# To add another extension, add one "name:extension-id" line below.

# name:extension-id   (base svg is ${name}_base_icon.svg)
vicinaeExtensionIcons=(
    "arch:store.vicinae.arch-packages"
    "flathub:store.vicinae.flathub-search"
    "color-palette:store.vicinae.color-converter"
    "keyboard:store.vicinae.hypr-keybinds"
    "character:store.vicinae.nerdfont-search"
    "window-close:store.vicinae.process-manager"
    "systemd:store.vicinae.systemd"
)

# Color for these icons. Switch to "$symbolicAccent" to match tray/waybar.
_vicinae_icon_color() { echo "$accent"; }

_vicinae_pick_converter() {
    if command -v rsvg-convert >/dev/null 2>&1; then echo rsvg-convert
    elif command -v magick     >/dev/null 2>&1; then echo magick
    elif command -v convert    >/dev/null 2>&1; then echo convert
    else return 1; fi
}

# _vicinae_svg_to_png <converter> <src.svg> <dst.png>  -> 512x512, transparent
_vicinae_svg_to_png() {
    local conv="$1" src="$2" dst="$3"
    if [ "$conv" = rsvg-convert ]; then
        rsvg-convert -w 512 -h 512 --keep-aspect-ratio -o "$dst" "$src"
        return
    fi
    # magick/convert rasterize at a DPI, not a pixel size: derive the density
    # from the svg's viewBox width so the render is ~512px wide instead of
    # upscaling a small bitmap (blurry). Falls back to a high fixed density.
    local w density
    w=$(grep -oP -m1 'viewBox="\s*[-0-9.]+[ ,]+[-0-9.]+[ ,]+\K[0-9.]+' "$src")
    if [ -n "$w" ]; then
        density=$(awk -v w="$w" 'BEGIN { d = int(72 * 512 / w) + 1; print (d < 72 ? 72 : d) }')
    else
        density=2400
    fi
    "$conv" -background none -density "$density" "$src" -resize 512x512 \
        -gravity center -extent 512x512 "PNG32:$dst"
}

_vicinae_cksum() { cksum | cut -d' ' -f1; }

# _vicinae_patch_one <name> <extId> <conv> <color>   (runs in a background job)
_vicinae_patch_one() {
    local name="$1" extId="$2" conv="$3" accent="$4"   # local accent: read by patch_svg_color
    local extRoot="$HOME/.local/share/vicinae/extensions"
    local target="$extRoot/$extId/assets/extension_icon.png"
    local stampDir="$HOME/.cache/WallpaperChanger/vicinae-ext-icons"
    local stamp="$stampDir/$extId"

    if [ ! -d "$extRoot/$extId/assets" ]; then
        echo "not installed: $extId (skipping $name)"
        return 0
    fi

    local src
    src=$(find_base_svg "$name") || {
        echo "no ${name}_base_icon.svg (skipping $extId)" >&2
        return 0
    }

    # Fingerprint of everything that influences the output
    local inHash outHash
    inHash=$({ cat "$src"; printf '|%s|%s|%s' "$accent" "${colorTokens[$name]:-currentColor}" "$conv"; } | _vicinae_cksum)

    if [ -f "$stamp" ] && [ -f "$target" ]; then
        outHash=$(_vicinae_cksum < "$target")
        [ "$(cat "$stamp")" = "$inHash:$outHash" ] && return 0   # up to date
    fi

    local tmpSvg tmpPng
    tmpSvg=$(mktemp --suffix=.svg)
    tmpPng=$(mktemp --suffix=.png)
    patch_svg_color "$src" "$tmpSvg" "$name"

    if _vicinae_svg_to_png "$conv" "$tmpSvg" "$tmpPng" && [ -s "$tmpPng" ]; then
        mv -f "$tmpPng" "$target"
        chmod 644 "$target"
        mkdir -p "$stampDir"
        echo "$inHash:$(_vicinae_cksum < "$target")" > "$stamp"
        echo "patched $extId <- $name"
    else
        echo "conversion failed: $name -> $extId" >&2
        rm -f "$tmpPng"
    fi
    rm -f "$tmpSvg"
}

patch_vicinae_extension_icons() {
    local extRoot="$HOME/.local/share/vicinae/extensions"
    [ -d "$extRoot" ] || { echo "Vicinae extensions dir not found, skipping"; return 0; }

    local conv
    conv=$(_vicinae_pick_converter) || {
        echo "No SVG->PNG converter (rsvg-convert/magick) found, skipping Vicinae extension icons" >&2
        return 0
    }

    # patch_svg_color looks names up in colorTokens; make sure it exists
    declare -p colorTokens >/dev/null 2>&1 || declare -gA colorTokens=()

    local color entry pids=() pid
    color=$(_vicinae_icon_color)

    for entry in "${vicinaeExtensionIcons[@]}"; do
        _vicinae_patch_one "${entry%%:*}" "${entry#*:}" "$conv" "$color" &
        pids+=($!)
    done
    # Wait only on our own jobs — a bare `wait` would also block on the
    # tray/wlogout jobs IconPatcher.sh runs in the background.
    for pid in "${pids[@]}"; do wait "$pid"; done
}