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
        read -p "Do you want to copy the nsfw wallpapers? [y/N]" -n 1 -r
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
    if (( ${#detectedRatios[@]} > 1 )); then
        echo "Multiple aspect ratios were found. Select which ones to install:"
        echo "(space to toggle, enter to confirm)"
        echo ""
        multiselect chosenRatios detectedRatios[@] noneLocked[@]
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