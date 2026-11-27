#!/usr/bin/env bash
# WallpaperInstall.sh
# Creates the Pictures/wallpapers directory if needed and copies wallpapers
# from the repo, including the nsfw prompt.
# Meant to be SOURCED from Install-Linux.sh; relies on $createPicturesDir,
# $wallpapersDirExists, and $copyWallpapers being set by DirectorySetup.sh.
# Sets $copyNsfw for use by FinalMessage.sh.

source "$supportDir/Utils.sh"

validExtensions=("jpg" "jpeg" "png" "pnm" "tga" "tiff" "webp" "bmp" "farbfeld" "gif")
defaultWallpapersDir="./wallpapersDefaultInstall"

# detect_aspect_ratios: lists the aspect-ratio subfolders found under
# <base>/sfw. Populates the array named in $2 via nameref.
detect_aspect_ratios() {
    local base="$1"
    local -n out=$2
    out=()
    for d in "$base/sfw"/*/; do
        [ -d "$d" ] || continue
        out+=("$(basename "$d")")
    done
}

# detect_display_resolutions: prints the resolution (WIDTHxHEIGHT) of every
# connected display, one per line. Uses the same sources as the wallpaper
# applicators: wayland-info on Wayland (wayland/WallpaperApplicator.sh), xrandr
# otherwise (Xrandr/WallpaperApplicatorXrandr.sh), which also works under
# XWayland when wayland-info is not installed. Prints nothing if neither is available.
detect_display_resolutions() {
    local resList=""
    if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wayland-info &>/dev/null; then
        resList=$(wayland-info 2>/dev/null | awk '
            /interface: .wl_output./ { in_output=1; next }
            /^interface:/            { in_output=0 }
            in_output && /^[[:space:]]*width:.*height:.*refresh:/ { width=$2; height=$5 }
            in_output && /flags:.*current/ { print width"x"height }
        ')
    fi
    if [ -z "$resList" ] && command -v xrandr &>/dev/null; then
        resList=$(xrandr --current 2>/dev/null | grep -F '*' | uniq | awk '{print $1}')
    fi
    [ -n "$resList" ] && printf '%s\n' "$resList"
    return 0
}

# suggest_aspect_ratios SFW_DIR RESULT_ARRAY
# Fills RESULT_ARRAY (by name) with the ratio folders of SFW_DIR that the
# connected displays map to, using AspectRatioChecker.sh, the same script the
# changer uses at runtime, so these are exactly the folders it will look for.
# Prints what was detected. Leaves the array empty if no display is found.
suggest_aspect_ratios() {
    local sfwDir="$1"
    local -n _sar_out=$2
    _sar_out=()
    local res folder f dup shown=false
    while read -r res; do
        [ -n "$res" ] || continue
        folder=$(bash ./scripts-linux/AspectRatioChecker.sh "$res" "$sfwDir" 2>/dev/null)
        folder=$(basename "$folder")
        [ -n "$folder" ] && [ -d "$sfwDir/$folder" ] || continue
        $shown || { echo "Connected displays:"; shown=true; }
        printf '  %-11s -> %s\n' "$res" "$folder"
        dup=false
        for f in "${_sar_out[@]}"; do [ "$f" = "$folder" ] && dup=true; done
        $dup || _sar_out+=("$folder")
    done < <(detect_display_resolutions)
    if $shown; then echo ""; else echo "Could not detect the connected displays, so nothing is pre-selected."; fi
    return 0
}

# validate_wallpaper_structure: checks:
#   - at least one aspect ratio folder is present under sfw
#   - every ratio folder under sfw (and nsfw, if present) has the same
#     set of filenames as every other ratio folder in that same tree
#   - all files inside nsfw are prefixed with "nsfw-"
#   - all files use one of the supported extensions
# Returns 0 if valid, 1 otherwise.
validate_wallpaper_structure() {
    local base="$1"
    local sfwDir="$base/sfw"
    local nsfwDir="$base/nsfw"

    [ -d "$sfwDir" ] || return 1

    local ratios=()
    detect_aspect_ratios "$base" ratios
    (( ${#ratios[@]} == 0 )) && return 1

    local ratio
    is_valid_ext() {
        local ext="${1##*.}"
        ext="${ext,,}"
        local valid
        for valid in "${validExtensions[@]}"; do
            [ "$ext" = "$valid" ] && return 0
        done
        return 1
    }

    local reference=()
    while IFS= read -r -d '' f; do
        reference+=("$(basename "$f")")
    done < <(find "$sfwDir/${ratios[0]}" -maxdepth 1 -type f -print0)

    local files f
    for ratio in "${ratios[@]}"; do
        files=()
        while IFS= read -r -d '' f; do
            files+=("$(basename "$f")")
        done < <(find "$sfwDir/$ratio" -maxdepth 1 -type f -print0)

        for f in "${files[@]}"; do
            is_valid_ext "$f" || return 1
        done

        if [ "$(printf '%s\n' "${files[@]}" | sort)" != "$(printf '%s\n' "${reference[@]}" | sort)" ]; then
            return 1
        fi
    done

    if [ -d "$nsfwDir" ]; then
        for ratio in "${ratios[@]}"; do
            [ -d "$nsfwDir/$ratio" ] || return 1
            files=()
            while IFS= read -r -d '' f; do
                files+=("$(basename "$f")")
            done < <(find "$nsfwDir/$ratio" -maxdepth 1 -type f -print0)

            for f in "${files[@]}"; do
                is_valid_ext "$f" || return 1
                [[ "$f" == nsfw-* ]] || return 1
            done
        done
    fi

    return 0
}

if [ "$createPicturesDir" = true ]; then
    mkdir "$HOME/Pictures"
    mkdir "$HOME/Pictures/wallpapers"
else
    if [ "$wallpapersDirExists" = false ]; then
        mkdir "$HOME/Pictures/wallpapers"
    fi
fi

if [ "$copyWallpapers" = true ]; then
    if [ -f "$HOME/.cache/wallpaper_ratios.cache" ]; then
        echo "removing wallpaper_ratios.cache"
        rm "$HOME/.cache/wallpaper_ratios.cache"
        echo "removing wallpaper's thumbnail cache"
        rm -r "$HOME/.cache/wallpaper-thumbnails"
    fi

    wallpapersSource="./wallpapers"
    if ! validate_wallpaper_structure "$wallpapersSource"; then
        echo "The wallpapers folder structure is invalid or incomplete (no aspect ratio folders found, or filenames/extensions are inconsistent across them)."
        echo "Falling back to the default wallpapers included with this install: $defaultWallpapersDir"
        echo ""
        wallpapersSource="$defaultWallpapersDir"
    fi

    #Checks if nsfw wallpapers exist and in case asks the user if he wants to install them
    if [ -d "$wallpapersSource/nsfw" ]; then
        ask_read NSFW -p "Do you want to copy the nsfw wallpapers? [y/N]" -n 1 -r
        echo ""
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            copyNsfw=false
        else
            copyNsfw=true
        fi
    fi

    detectedRatios=()
    detect_aspect_ratios "$wallpapersSource" detectedRatios

    noneLocked=()
    chosenRatios=()
    if (( ${#detectedRatios[@]} > 1 )) && [ -n "${WC_ANSWER_RATIOS+x}" ]; then
        # Preset by a front-end (WC_ANSWER_RATIOS="16-9 21-9"): no menu. Names that
        # are not available are ignored; an empty result falls back to all below.
        for ratio in ${WC_ANSWER_RATIOS//,/ }; do
            for avail in "${detectedRatios[@]}"; do
                [ "$ratio" = "$avail" ] && chosenRatios+=("$ratio")
            done
        done
        echo "Aspect ratios (preset): ${chosenRatios[*]}"
    elif (( ${#detectedRatios[@]} > 1 )); then
        # Pre-tick the ratios that match the connected displays.
        suggestedRatios=()
        suggest_aspect_ratios "$wallpapersSource/sfw" suggestedRatios
        echo "Multiple aspect ratios were found. Select which ones to install:"
        echo "(space to toggle, enter to confirm)"
        echo ""
        multiselect chosenRatios detectedRatios[@] noneLocked[@] suggestedRatios[@]
    else
        chosenRatios=("${detectedRatios[@]}")
    fi

    # Safety net: if nothing ended up selected, install every detected ratio
    # instead of silently leaving the wallpapers folder empty.
    if (( ${#chosenRatios[@]} == 0 )); then
        echo "No aspect ratios selected — installing all detected ratios instead."
        chosenRatios=("${detectedRatios[@]}")
    fi

    # Collect all source directories to copy in a single rsync call so the
    # progress bar reflects the entire transfer rather than one folder at a time.
    sourceDirs=()
    for ratio in "${chosenRatios[@]}"; do
        [ -d "$wallpapersSource/sfw/$ratio" ] && sourceDirs+=("$wallpapersSource/sfw/$ratio")
    done
    if [ "$copyNsfw" = true ]; then
        for ratio in "${chosenRatios[@]}"; do
            [ -d "$wallpapersSource/nsfw/$ratio" ] && sourceDirs+=("$wallpapersSource/nsfw/$ratio")
        done
    fi

    if (( ${#sourceDirs[@]} != 0 )); then
        copy_with_bar "Copying wallpapers..." "${sourceDirs[@]}" "$HOME/Pictures/wallpapers/"
        printf '%s\n' "${chosenRatios[@]}" > "$HOME/.cache/wallpaper_ratios.cache"
        echo "Wallpapers copied successfully."
        echo ""
    fi
fi