#!/usr/bin/env bash
# trayIconPatcher.sh
# Themes system-tray icons for apps that don't pick up breeze-dark-accent's
# regular app-icon theming — either because they draw their tray icon from
# their own bundled asset (not looked up by name through the icon theme),
# or because they expect a literal file path in their own config, the way
# Vesktop does. Split out from iconPatcher.sh since each app needs a
# different hand-rolled approach rather than the generic .desktop engine.
#
# Called automatically from iconPatcher.sh at the end of its run, so the
# accent-colored app SVGs in $iconThemeDir/apps/scalable/ already exist.
#
# Usage: trayIconPatcher.sh <hex_color> [--list]
#   --list   discover/report what would be touched for blueman and
#            onedrivegui without writing anything. Run this first on a new
#            machine to confirm the discovered icon names look right.

color="${1,,}"
listOnly=0
[ "${2:-}" = "--list" ] && listOnly=1

if [ -z "$color" ]; then
    echo "Usage: $0 <hex_color> [--list]" >&2
    exit 1
fi

accent="#$color"
supportDir="$HOME/.config/WallpaperChanger/themeRefresherSupportScripts"
iconsDir="$supportDir/svg"
gameIconsDir="$iconsDir/games"
iconThemeDir="$HOME/.local/share/icons/breeze-dark-accent"

# Match waybar's text color exactly, not just "the same seed": $color/
# $accent here is the raw hex colorChooser.sh sampled from the wallpaper,
# but waybar's @primary is matugen's *resolved* colors.primary.default —
# a tonally-adjusted derivative of that seed, not the seed itself. Icons
# colored with the raw seed and waybar text colored with the resolved
# primary are two close-but-different colors, which is exactly why the
# mismatch stands out sitting right next to each other in the tray.
# matugen already runs before iconPatcher.sh in themeRefresher.sh, so the
# rendered file already has the real value — read it back instead of
# re-deriving it. Only affects tray icons; everything else in the
# pipeline still uses the raw seed.
waybarColorsRenderedFile="$HOME/.config/waybar/colors.css"
if [ -f "$waybarColorsRenderedFile" ]; then
    waybarAccent=$(grep -m1 -oP '@define-color\s+primary\s+\K#[0-9a-fA-F]{6}' "$waybarColorsRenderedFile")
    if [ -n "$waybarAccent" ]; then
        accent="$waybarAccent"
        color="${accent#\#}"
        color="${color,,}"
        echo "  tray icons: using waybar's resolved primary ($accent) instead of the raw wallpaper seed"
    else
        echo "  tray icons: primary not found in $waybarColorsRenderedFile, falling back to raw seed color"
    fi
else
    echo "  tray icons: $waybarColorsRenderedFile not found, falling back to raw seed color"
fi

# Shared helper — always recolors fresh from the base SVG using this
# script's own (waybar-corrected) $accent. Deliberately does NOT reuse
# $iconThemeDir/apps/scalable/<name>.svg even when it exists, since that
# copy was colored by iconPatcher.sh's engine with the raw wallpaper seed
# — reusing it would silently defeat the primary correction above. Costs
# a redundant recolor, but guarantees tray icons and waybar text agree.
resolve_themed_svg() {
    local name="$1"
    local base=""
    [ -f "$gameIconsDir/${name}_base_icon.svg" ] && base="$gameIconsDir/${name}_base_icon.svg"
    [ -z "$base" ] && [ -f "$iconsDir/${name}_base_icon.svg" ] && base="$iconsDir/${name}_base_icon.svg"
    [ -z "$base" ] && return 1

    local tmp
    tmp=$(mktemp --suffix=.svg)
    sed "s/currentColor/$accent/g" "$base" > "$tmp"
    echo "$tmp"
}

# fix_system_dir_permissions <dir> <label>
# One-time chown of a package-owned directory to the current user, so
# subsequent writes need no sudo at all — until the next package update
# resets ownership back to root, at which point this just redoes it.
# Non-blocking: uses `sudo -n`, so it fails fast instead of hanging when
# there's no cached credential/interactive terminal (see: the hang bug
# from an earlier version of this pattern). Ownership is otherwise kept
# in sync by TARGETS in update-and-fix.sh, which runs after every
# topgrade and re-chowns anything a package update reset to root.
fix_system_dir_permissions() {
    local dir="$1" label="$2"
    [ -w "$dir" ] && return 0
    echo "  $label: $dir is root-owned, attempting one-time chown..."
    if sudo -n chown -R "$USER" "$dir" 2>/dev/null; then
        echo "  $label: ownership fixed — future runs won't need sudo."
        echo "  (if theming silently stops updating after a $label package"
        echo "   update, that's this directory getting reset to root again — just"
        echo "   re-run this script and it'll redo the chown.)"
        return 0
    fi
    echo "  $label: couldn't chown automatically (needs an interactive sudo prompt)."
    echo "  Run this once yourself, then re-run this script:"
    echo "    sudo chown -R \$USER $dir"
    return 1
}

#nativmix tray icon
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

#ferdium tray icon
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

#localsend tray icon
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

#streamcontroller tray icon
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

#steam tray icon
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

#blueman tray icon
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
    # "Bluetooth Manager" app icon elsewhere in iconPatcher.sh, rather than
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

#onedrivegui tray icon
oneDriveGuiImagesDir="/usr/lib/OneDriveGUI/resources/images"

declare -A oneDriveGuiSvgOverrides=(
    ["icons8-cloud-done-80.png"]="cloud-check:accent"      # ok/synced
    ["warning.png"]="cloud-exclamation:#f39c12"            # warning
    ["icons8-cloud-error-80.png"]="cloud-x:#e74c3c"        # error
    ["icons8-cloud-sync-80.png"]="cloud-cog:accent"        # syncing
)

declare -A oneDriveGuiColorizeOnly=(
    ["icons8-cloud-80.png"]="accent"        # idle
    ["icons8-cloud-stop-80.png"]="accent"   # paused (unless this is actually "warning" — see above)
)

fix_onedrive_gui_permissions() {
    fix_system_dir_permissions "$oneDriveGuiImagesDir" "onedrivegui"
}

patch_onedrive_gui_tray() {
    command -v onedrivegui >/dev/null 2>&1 || return 0
    [ -d "$oneDriveGuiImagesDir" ] || {
        echo "  onedrivegui: $oneDriveGuiImagesDir not found (package layout may have changed)"
        return 1
    }

    if [ "$listOnly" -eq 1 ]; then
        echo "onedrivegui: custom SVG replacements:"
        for name in "${!oneDriveGuiSvgOverrides[@]}"; do
            IFS=':' read -r iconName target <<< "${oneDriveGuiSvgOverrides[$name]}"
            [ "$target" = "accent" ] && target="$accent"
            printf '  %-28s -> %s_base_icon.svg (%s)\n' "$name" "$iconName" "$target"
        done
        echo "onedrivegui: plain recolor (existing vendor art):"
        for name in "${!oneDriveGuiColorizeOnly[@]}"; do
            local target="${oneDriveGuiColorizeOnly[$name]}"
            [ "$target" = "accent" ] && target="$accent"
            printf '  %-28s -> %s\n' "$name" "$target"
        done
        echo "  (left alone: icons8-green-circle-48.png, icons8-red-circle-48.png, and"
        echo "   in-window UI icons like account/folder/gear/play/pause/quit)"
        return 0
    fi

    local tool=""
    command -v magick >/dev/null 2>&1 && tool="magick"
    [ -z "$tool" ] && command -v convert >/dev/null 2>&1 && tool="convert"
    if [ -z "$tool" ]; then
        echo "  onedrivegui: ImageMagick not found, cannot recolor icons"
        return 1
    fi
    command -v rsvg-convert >/dev/null 2>&1 || {
        echo "  onedrivegui: rsvg-convert not found, cannot rasterize custom SVGs"
        return 1
    }

    fix_onedrive_gui_permissions || return 1

    local patched=0 skipped=0

    # -- custom SVG replacements --
    for name in "${!oneDriveGuiSvgOverrides[@]}"; do
        local f="$oneDriveGuiImagesDir/$name"
        [ -f "$f" ] || { echo "  onedrivegui: vendor file $name not found, skipping"; continue; }

        IFS=':' read -r iconName target <<< "${oneDriveGuiSvgOverrides[$name]}"
        [ "$target" = "accent" ] && target="$accent"

        local srcSvg="$iconsDir/${iconName}_base_icon.svg"
        if [ ! -f "$srcSvg" ]; then
            echo "  onedrivegui: $srcSvg not found — add it, or drop this override for $name"
            skipped=$((skipped + 1))
            continue
        fi

        local backup="${f}.orig"
        [ -f "$backup" ] || cp "$f" "$backup"

        # Match the vendor icon's own pixel size so it doesn't look
        # mismatched next to the icons we're leaving alone.
        local dims
        if command -v identify >/dev/null 2>&1; then
            dims=$(identify -format "%wx%h" "$backup" 2>/dev/null)
        else
            dims=$("$tool" identify -format "%wx%h" "$backup" 2>/dev/null)
        fi
        local w="${dims%x*}" h="${dims#*x}"
        [ -z "$w" ] && w=80
        [ -z "$h" ] && h=80

        local tmpSvg tmpPng
        tmpSvg=$(mktemp --suffix=.svg)
        tmpPng=$(mktemp --suffix=.png)
        sed "s/currentColor/$target/g" "$srcSvg" > "$tmpSvg"
        rsvg-convert -w "$w" -h "$h" "$tmpSvg" -o "$tmpPng"
        cp "$tmpPng" "$f"
        rm -f "$tmpSvg" "$tmpPng"
        patched=$((patched + 1))
        echo "  $name replaced with ${iconName}_base_icon.svg ($target)"
    done

    # -- plain recolor of remaining vendor art --
    for name in "${!oneDriveGuiColorizeOnly[@]}"; do
        local f="$oneDriveGuiImagesDir/$name"
        [ -f "$f" ] || { echo "  onedrivegui: vendor file $name not found, skipping"; continue; }

        local target="${oneDriveGuiColorizeOnly[$name]}"
        [ "$target" = "accent" ] && target="$accent"

        local backup="${f}.orig"
        [ -f "$backup" ] || cp "$f" "$backup"

        "$tool" "$backup" -fill "$target" -colorize 100% "$f"
        patched=$((patched + 1))
    done

    echo "OneDriveGUI tray icons patched ($patched patched, $skipped skipped)"
    echo "  (originals preserved as *.png.orig next to each file)"
}

#vesktop tray icons
patch_vesktop_tray() {
    command -v vesktop >/dev/null 2>&1 || return 0

    local userAssets="$HOME/.config/vesktop/userAssets"

    # Don't create userAssets/ ourselves if Vesktop has never initialized
    # it — writing files there before Vesktop knows about custom assets
    # at all may not be picked up. Ask once via the UI (Customize ->
    # pick any file, for both Tray and Tray Unread) so Vesktop creates
    # its own tray/trayUnread files, then this script just keeps
    # overwriting them from then on.
    [ -d "$userAssets" ] || {
        echo "  vesktop: $userAssets doesn't exist yet — open Vesktop's"
        echo "  Settings -> User Assets -> Tray/Tray Unread -> Customize"
        echo "  and pick any image once for each, then re-run this script."
        return 1
    }

    command -v rsvg-convert >/dev/null 2>&1 || {
        echo "  vesktop: rsvg-convert not found, cannot rasterize"; return 1
    }

    local patched=0

    # -- plain tray icon --
    local svg
    svg=$(resolve_themed_svg "vesktop") || svg=$(resolve_themed_svg "discord") || {
        echo "  vesktop: no themed base icon found for tray, skipping"
    }
    if [ -n "$svg" ]; then
        local target="$userAssets/tray"
        if [ "$listOnly" -eq 1 ]; then
            echo "vesktop: would overwrite $target"
        else
            rsvg-convert -w 64 -h 64 "$svg" -o "$target" \
                && { echo "Vesktop tray icon patched in place ($target)"; patched=$((patched + 1)); }
        fi
    fi

    # -- unread-badge variant — separate base icon, since the badge is
    # baked into the artwork itself rather than composited by Vesktop
    # (unlike Ferdium/OneDriveGUI, there's no separate dot overlay step
    # here — whatever discord-unread_base_icon.svg draws is exactly what
    # shows in the tray). --
    local svgUnread
    svgUnread=$(resolve_themed_svg "discord-unread") || {
        echo "  vesktop: discord-unread_base_icon.svg not found, skipping trayUnread"
    }
    if [ -n "$svgUnread" ]; then
        local targetUnread="$userAssets/trayUnread"
        if [ "$listOnly" -eq 1 ]; then
            echo "vesktop: would overwrite $targetUnread"
        else
            rsvg-convert -w 64 -h 64 "$svgUnread" -o "$targetUnread" \
                && { echo "Vesktop trayUnread icon patched in place ($targetUnread)"; patched=$((patched + 1)); }
        fi
    fi

    [ "$listOnly" -eq 1 ] && return 0
    [ "$patched" -gt 0 ]
}

#ytmdesktop tray icons
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

#betterbird tray icons
patch_betterbird_tray() {
    local betterbirdTarget isFlatpak=0

    if [ -d "$HOME/.var/app/eu.betterbird.Betterbird" ]; then
        isFlatpak=1
        betterbirdTarget="$HOME/.var/app/eu.betterbird.Betterbird/data/icons/hicolor/scalable/status"
    elif command -v betterbird >/dev/null 2>&1; then
        betterbirdTarget="/opt/betterbird"
    else
        echo "  betterbird: not installed, skipping tray"
        return 0
    fi

    defaultsvg=$(resolve_themed_svg "mail") || { echo "  betterbird: no themed base icon found, skipping tray"; return 1; }
    newmailsvg=$(resolve_themed_svg "new-mail") || { echo "  betterbird: no themed new-mail icon found, skipping tray"; return 1; }

    if [ "$isFlatpak" -eq 1 ]; then
        if [ "$listOnly" -eq 1 ]; then
            echo "betterbird: would overwrite:"
            echo "  $betterbirdTarget/eu.betterbird.Betterbird-default.svg"
            echo "  $betterbirdTarget/eu.betterbird.Betterbird-newmail.svg"
            return 0
        fi
        mkdir -p "$betterbirdTarget" || return 1
        cp "$defaultsvg" "$betterbirdTarget/eu.betterbird.Betterbird-default.svg"
        cp "$newmailsvg" "$betterbirdTarget/eu.betterbird.Betterbird-newmail.svg"
        echo "Betterbird tray icon patched (flatpak)"
        return 0
    fi

    cp "$defaultsvg" "$betterbirdTarget/chrome/icons/default/default.svg"
    cp "$newmailsvg" "$betterbirdTarget/chrome/icons/default/newmail.svg"

    local svg
    svg=$(resolve_themed_svg "mail") || { echo "  betterbird: no themed base icon found, skipping tray"; return 1; }

    local targets=(
        "$betterbirdTarget/chrome/icons/default/default16.png"
        "$betterbirdTarget/chrome/icons/default/default22.png"
        "$betterbirdTarget/chrome/icons/default/default24.png"
        "$betterbirdTarget/chrome/icons/default/default32.png"
        "$betterbirdTarget/chrome/icons/default/default48.png"
        "$betterbirdTarget/chrome/icons/default/default64.png"
        "$betterbirdTarget/chrome/icons/default/default128.png"
        "$betterbirdTarget/chrome/icons/default/default256.png"
    )

    local resolutions=(
        16 22 24 32 48 64 128 256
    )

    if [ "$listOnly" -eq 1 ]; then
        echo "betterbird: would overwrite:"
        printf '  %s\n' "${targets[@]}"
        return 0
    fi

    command -v rsvg-convert >/dev/null 2>&1 || {
        echo "  betterbird: rsvg-convert not found, cannot rasterize"; return 1
    }
    fix_system_dir_permissions "$betterbirdTarget/chrome/icons/default" "default.svg" || return 1

    local patched=0
    for r in "${resolutions[@]}"; do
        local f="$betterbirdTarget/chrome/icons/default/default${r}.png"
        [ -f "$f" ] || { echo "  betterbird: $f not found, skipping"; continue; }
        local backup="${f}.orig"
        [ -f "$backup" ] || cp "$f" "$backup"
        rsvg-convert -w $r -h $r "$svg" -o "$f" && patched=$((patched + 1))
    done
    echo "Betterbird tray icon patched in place ($patched/${#targets[@]})"
}

#cohesion tray icons
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

    local patched=0
    local f
    for f in "${colorTargets[@]}"; do
        if [[ "$f" == *-unread.png ]]; then
            rsvg="$svgUnread"
        else
            rsvg="$svg"
        fi
        rsvg-convert -w 512 -h 512 "$rsvg" -o "$f" && patched=$((patched + 1))
    done

    # Greyscale slots are Cohesion's own monochrome tray-style toggle —
    # desaturate the accent render rather than reusing it verbatim, so the
    # toggle still does something. ${f/-greyscale/} maps each greyscale
    # target back to the color file it should be derived from (...
    # -greyscale.png -> ...png, ...-greyscale-unread.png -> ...-unread.png).
    if command -v magick >/dev/null 2>&1; then
        for f in "${greyTargets[@]}"; do
            magick "${f/-greyscale/}" -colorspace Gray "$f" && patched=$((patched + 1))
        done
    elif command -v convert >/dev/null 2>&1; then
        for f in "${greyTargets[@]}"; do
            convert "${f/-greyscale/}" -colorspace Gray "$f" && patched=$((patched + 1))
        done
    else
        echo "  cohesion: imagemagick not found, copying color icon into greyscale slots unmodified"
        for f in "${greyTargets[@]}"; do
            cp "${f/-greyscale/}" "$f" && patched=$((patched + 1))
        done
    fi

    echo "Cohesion tray icons patched ($patched/4, $iconDir)"
    echo "  (restart Cohesion for the new icons to take effect)"
}


# time_step_bg <label> <function> — same contract as time_step, but
# backgrounds the function and prefixes every line it prints (stdout+
# stderr merged) with "[label] " so concurrent jobs' output stays
# attributable (same technique themeRefresher.sh's time_step_bg uses).
#
# Output is captured to a temp file, not piped live through sed: if any
# function here backgrounds+disowns work of its own without redirecting
# that work's output first (e.g. force_ytm_desktop_reload's 12s delayed
# revert — already safely redirected, but exactly the risky shape), a
# live pipe would let that orphaned writer hold the pipe open
# indefinitely, turning a fast step into a stuck one. A regular file has
# no such blocking semantics — confirmed by reproducing the failure
# against rgbApply.sh's disowned ratbagctl loop elsewhere in this pipeline.
#
# Every function below writes to a different app's own disjoint asset
# directory (blueman is the only one touching $iconThemeDir), and the
# shared helpers they call (resolve_themed_svg, fix_system_dir_permissions)
# are safe under concurrency too — so running them all in parallel is fine.
#
# Never wrap this in $(...) to grab the PID — that runs in its own
# subshell, and a job backgrounded inside it gets reparented away (not a
# waitable child of this script) once the subshell exits. Call directly,
# then read $! right after.
time_step_bg() {
    local label="$1"; shift
    local outfile
    outfile=$(mktemp)
    (
        local start end rc
        start=$(date +%s.%N)
        "$@" > "$outfile" 2>&1
        rc=$?
        end=$(date +%s.%N)
        sed "s/^/[$label] /" "$outfile"
        rm -f "$outfile"
        awk -v s="$start" -v e="$end" -v l="$label" \
            'BEGIN { printf "  [%7.3fs] %s\n", e - s, l }' >&2
        exit $rc
    ) &
}

# ---- Run everything ----
declare -a trayPids=()
time_step_bg "nativmix"         patch_nativmix_tray;         trayPids+=("$!")
time_step_bg "ferdium"          patch_ferdium_tray;          trayPids+=("$!")
time_step_bg "localsend"        patch_localsend_tray;        trayPids+=("$!")
time_step_bg "streamcontroller" patch_streamcontroller_tray; trayPids+=("$!")
time_step_bg "steam"            patch_steam_tray;            trayPids+=("$!")
time_step_bg "blueman"          patch_blueman_tray;          trayPids+=("$!")
time_step_bg "onedrivegui"      patch_onedrive_gui_tray;      trayPids+=("$!")
time_step_bg "vesktop"          patch_vesktop_tray;          trayPids+=("$!")
time_step_bg "ytmdesktop"       patch_ytm_desktop_tray;       trayPids+=("$!")
time_step_bg "betterbird"       patch_betterbird_tray;       trayPids+=("$!")
time_step_bg "cohesion"         patch_cohesion_tray;         trayPids+=("$!")

for pid in "${trayPids[@]}"; do
    wait "$pid"
done

[ "$listOnly" -eq 0 ] && echo "Tray icons patched with $accent"