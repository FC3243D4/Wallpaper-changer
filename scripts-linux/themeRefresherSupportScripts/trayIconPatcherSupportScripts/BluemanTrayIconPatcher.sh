#!/usr/bin/env bash

patch_blueman_tray() {
    command -v blueman-applet >/dev/null 2>&1 || return 0

    local searchDirs=(
        "/usr/share/icons/hicolor"
        "/usr/share/pixmaps"
        "/usr/share/blueman/icons"
    )
    local found=()
    for dir in "${searchDirs[@]}"; do
        [ -d "$dir" ] || continue
        while IFS= read -r f; do
            found+=("$f")
        done < <(find "$dir" -iname "*blueman-tray*" -type f 2>/dev/null)
    done

    if [ "${#found[@]}" -eq 0 ]; then
        echo "  blueman: no blueman-tray-* icon files found under ${searchDirs[*]}"
        echo "  (run 'find / -iname \"*blueman-tray*\" 2>/dev/null' once to locate them,"
        echo "   then adjust searchDirs in patch_blueman_tray)"
        return 1
    fi

    # Full substitution with the same bluetooth icon already used for the
    # "Bluetooth Manager" app icon elsewhere in IconPatcher.sh, rather than
    # tinting blueman's own vendor art — vendor blueman-tray icons are a
    # filled badge shape, so a plain -colorize just turns into a flat blob
    # instead of a recognizable glyph.
    local srcSvg
    srcSvg=$(resolve_themed_svg "bluetooth") || {
        echo "  blueman: $iconsDir/bluetooth_base_icon.svg not found, can't substitute — falling back to plain recolor"
        srcSvg=""
    }

    if [ "$listOnly" -eq 1 ]; then
        echo "blueman: would replace ${#found[@]} file(s) with bluetooth_base_icon.svg:"
        printf '  %s\n' "${found[@]}"
        return 0
    fi

    local tool=""
    command -v magick >/dev/null 2>&1 && tool="magick"
    [ -z "$tool" ] && command -v convert >/dev/null 2>&1 && tool="convert"

    local tmpSvg=""
    if [ -n "$srcSvg" ]; then
        # resolve_themed_svg already returns accent-colored content (either
        # the engine's already-generated app icon, or a freshly recolored
        # temp copy of the base SVG) — just use it directly.
        tmpSvg="$srcSvg"
    fi

    local patched=0
    local jobDir
    jobDir=$(mktemp -d)
    local i=0
    for f in "${found[@]}"; do
        i=$((i + 1))
        (
            case "$f" in
                *hicolor*)
                    rel="${f#/usr/share/icons/hicolor/}"
                    dst="$iconThemeDir/$rel"
                    ;;
                *)
                    # pixmaps/blueman's own dir — no theme-relative path, so
                    # just mirror basename under a flat "blueman" subfolder.
                    dst="$iconThemeDir/blueman/$(basename "$f")"
                    ;;
            esac
            mkdir -p "$(dirname "$dst")"

            if [ -n "$tmpSvg" ]; then
                if [[ "$f" == *.svg ]]; then
                    cp "$tmpSvg" "$dst"
                elif command -v rsvg-convert >/dev/null 2>&1; then
                    # Size comes from the hicolor directory name (e.g. 24x24);
                    # default to 48 for anything outside that layout (pixmaps).
                    size=48
                    if [[ "$f" == *hicolor/*x*/status* ]]; then
                        sizedir="${f#/usr/share/icons/hicolor/}"
                        size="${sizedir%%x*}"
                    fi
                    rsvg-convert -w "$size" -h "$size" "$tmpSvg" -o "$dst"
                else
                    echo "  blueman: rsvg-convert not found, skipping raster icon $f"
                    exit 1
                fi
            elif [[ "$f" == *.svg ]]; then
                sed "s/currentColor/$accent/g" "$f" > "$dst" 2>/dev/null \
                    || cp "$f" "$dst"
            elif [ -n "$tool" ]; then
                "$tool" "$f" -fill "$accent" -colorize 100% "$dst"
            else
                echo "  blueman: no ImageMagick found, skipping raster icon $f"
                exit 1
            fi
            touch "$jobDir/$i"
        ) &
    done
    wait
    patched=$(find "$jobDir" -mindepth 1 | wc -l)
    rm -rf "$jobDir"
    # resolve_themed_svg now always returns a throwaway temp file (never a
    # path under $iconThemeDir), but keep this guard as cheap insurance rather
    # than assume that never changes again.
    case "$tmpSvg" in
        "$iconThemeDir"/*) : ;;   # would be permanent — leave it alone
        "") : ;;
        *) rm -f "$tmpSvg" ;;
    esac
    echo "Blueman tray icons patched ($patched/${#found[@]})"
}
