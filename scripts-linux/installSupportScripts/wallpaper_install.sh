#!/usr/bin/env bash
# wallpaper_install.sh
# Creates the Pictures/wallpapers directory if needed and copies wallpapers
# from the repo, including the nsfw prompt.
# Meant to be SOURCED from install-Linux.sh; relies on $CreatePicturesDir,
# $WallpapersDirExists, and $CopyWallpapers being set by directory_setup.sh.
# Sets $CopyNsfw for use by final_message.sh.

source "$SUPPORT/utils.sh"

VALID_EXTENSIONS=("jpg" "jpeg" "png" "pnm" "tga" "tiff" "webp" "bmp" "farbfeld" "gif")
DEFAULT_WALLPAPERS_DIR="./wallpapersDefaultInstall"
REQUIRED_RATIO="16-9"

# ---------------------------------------------------------------------------
# detect_aspect_ratios: lists the aspect-ratio subfolders found under
# <base>/sfw. Populates the array named in $2 via nameref.
# ---------------------------------------------------------------------------
detect_aspect_ratios() {
    local base="$1"
    local -n out=$2
    out=()
    for d in "$base/sfw"/*/; do
        [ -d "$d" ] || continue
        out+=("$(basename "$d")")
    done
}

# ---------------------------------------------------------------------------
# validate_wallpaper_structure: checks:
#   - the required aspect ratio ($REQUIRED_RATIO) is present, since it's
#     the base directory wallpaperApplicator relies on
#   - every ratio folder under sfw (and nsfw, if present) has the same
#     set of filenames as every other ratio folder in that same tree
#   - all files inside nsfw are prefixed with "nsfw-"
#   - all files use one of the supported extensions
# Returns 0 if valid, 1 otherwise.
# ---------------------------------------------------------------------------
validate_wallpaper_structure() {
    local base="$1"
    local sfw_dir="$base/sfw"
    local nsfw_dir="$base/nsfw"

    [ -d "$sfw_dir" ] || return 1

    local ratios=()
    detect_aspect_ratios "$base" ratios
    (( ${#ratios[@]} == 0 )) && return 1

    local has_required=false
    local ratio
    for ratio in "${ratios[@]}"; do
        [ "$ratio" = "$REQUIRED_RATIO" ] && has_required=true
    done
    $has_required || return 1

    is_valid_ext() {
        local ext="${1##*.}"
        ext="${ext,,}"
        local valid
        for valid in "${VALID_EXTENSIONS[@]}"; do
            [ "$ext" = "$valid" ] && return 0
        done
        return 1
    }

    local reference=()
    while IFS= read -r -d '' f; do
        reference+=("$(basename "$f")")
    done < <(find "$sfw_dir/$REQUIRED_RATIO" -maxdepth 1 -type f -print0)

    local files f
    for ratio in "${ratios[@]}"; do
        files=()
        while IFS= read -r -d '' f; do
            files+=("$(basename "$f")")
        done < <(find "$sfw_dir/$ratio" -maxdepth 1 -type f -print0)

        for f in "${files[@]}"; do
            is_valid_ext "$f" || return 1
        done

        if [ "$(printf '%s\n' "${files[@]}" | sort)" != "$(printf '%s\n' "${reference[@]}" | sort)" ]; then
            return 1
        fi
    done

    if [ -d "$nsfw_dir" ]; then
        for ratio in "${ratios[@]}"; do
            [ -d "$nsfw_dir/$ratio" ] || return 1
            files=()
            while IFS= read -r -d '' f; do
                files+=("$(basename "$f")")
            done < <(find "$nsfw_dir/$ratio" -maxdepth 1 -type f -print0)

            for f in "${files[@]}"; do
                is_valid_ext "$f" || return 1
                [[ "$f" == nsfw-* ]] || return 1
            done
        done
    fi

    return 0
}

if [ "$CreatePicturesDir" = true ]; then
    mkdir "$HOME/Pictures"
    mkdir "$HOME/Pictures/wallpapers"
else
    if [ "$WallpapersDirExists" = false ]; then
        mkdir "$HOME/Pictures/wallpapers"
    fi
fi

if [ "$CopyWallpapers" = true ]; then
    if [ -f "$HOME/.cache/wallpaper_ratios.cache" ]; then
        rm "$HOME/.cache/wallpaper_ratios.cache"
    fi

    WALLPAPERS_SOURCE="./wallpapers"
    if ! validate_wallpaper_structure "$WALLPAPERS_SOURCE"; then
        echo "The wallpapers folder structure is invalid, incomplete, or missing the required $REQUIRED_RATIO aspect ratio."
        echo "Falling back to the default wallpapers included with this install: $DEFAULT_WALLPAPERS_DIR"
        echo ""
        WALLPAPERS_SOURCE="$DEFAULT_WALLPAPERS_DIR"
    fi

    #Checks if nsfw wallpapers exist and in case asks the user if he wants to install them
    if [ -d "$WALLPAPERS_SOURCE/nsfw" ]; then
        read -p "Do you want to copy the nsfw wallpapers? [y/N]" -n 1 -r
        echo ""
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            CopyNsfw=false
        else
            CopyNsfw=true
        fi
    fi

    detectedRatios=()
    detect_aspect_ratios "$WALLPAPERS_SOURCE" detectedRatios

    requiredRatios=("$REQUIRED_RATIO")
    chosenRatios=()
    if (( ${#detectedRatios[@]} > 1 )); then
        echo "Multiple aspect ratios were found. Select which ones to install:"
        echo "($REQUIRED_RATIO is required and cannot be deselected; space to toggle, enter to confirm)"
        echo ""
        multiselect chosenRatios detectedRatios[@] requiredRatios[@]
    else
        chosenRatios=("${detectedRatios[@]}")
    fi

    # Safety net: guarantee the required ratio is always installed even if
    # detection/selection logic above is ever bypassed or changed later.
    if [[ ! " ${chosenRatios[*]} " == *" $REQUIRED_RATIO "* ]]; then
        chosenRatios+=("$REQUIRED_RATIO")
    fi

    # Collect all source directories to copy in a single rsync call so the
    # progress bar reflects the entire transfer rather than one folder at a time.
    sourceDirs=()
    for ratio in "${chosenRatios[@]}"; do
        [ -d "$WALLPAPERS_SOURCE/sfw/$ratio" ] && sourceDirs+=("$WALLPAPERS_SOURCE/sfw/$ratio")
    done
    if [ "$CopyNsfw" = true ]; then
        for ratio in "${chosenRatios[@]}"; do
            [ -d "$WALLPAPERS_SOURCE/nsfw/$ratio" ] && sourceDirs+=("$WALLPAPERS_SOURCE/nsfw/$ratio")
        done
    fi

    if (( ${#sourceDirs[@]} != 0 )); then
        copy_with_bar "Copying wallpapers..." "${sourceDirs[@]}" "$HOME/Pictures/wallpapers/"
        printf '%s\n' "${chosenRatios[@]}" > "$HOME/.cache/wallpaper_ratios.cache"
        echo "Wallpapers copied successfully."
        echo ""
    fi
fi