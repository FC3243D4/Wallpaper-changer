#!/usr/bin/env bash

packageList=()
UseXrandr=false

if [ "$XDG_SESSION_TYPE" != "wayland" ]; then
    UseWayland=false
    if ! xrandr -v foo &> /dev/null; then
        echo "You are not using wayland, but you do not have xrandr installed"
        echo ""
        packageList=("${packageList[@]}" "xrandr")
    else
        echo "You are not using wayland. The script will need to use xrandr instead."
        echo ""
        UseXrandr=true
    fi
fi
if xrandr -v foo &> /dev/null; then
    if ! xrandr | grep primary &> /dev/null; then
        echo "xrandr is installed but no primary display is set. to ensure the script works correctly, please set a primary display with"
        echo ""
        echo "xrandr --output <display> --primary"
        echo ""
        echo "replacing <display> with the name of your display. You can find the name of your display by running"
        echo "xrandr"
        echo ""
        echo "and looking for the connected displays. If you have multiple displays, make sure to set the correct display to ensure the script works correctly."
        echo ""
    fi
fi
if ! magick --version &> /dev/null; then
    echo "magick"
    packageList=("${packageList[@]}" "imagemagick")
fi
if ! matugen --version &> /dev/null; then
    echo "matugen"
    packageList=("${packageList[@]}" "matugen")
fi
if ! awww --version &> /dev/null; then
    echo "awww"
    packageList=("${packageList[@]}" "awww")
fi
# Check if package bc exists
if ! command -v bc &>/dev/null; then
    echo "bc"
    packageList=("${packageList[@]}" "bc")
fi
if ! openrgb --version &> /dev/null ; then
    echo "openrgb is not installed. You will not have the wallpapers dominant color applied to your devices. Please install openrgb if you want this feature."
    echo ""
fi

if (( ${#packageList[@]} != 0 )); then
    echo "The following packages are missing and will be installed:"
    printf '%s\n' "${packageList[@]}"
    echo ""

    echo "Syncing package databases..."
    sudo pacman -Sy

    repoPackages=()
    aurPackages=()
    for pkg in "${packageList[@]}"; do
        if pacman -Si "$pkg" &>/dev/null; then
            repoPackages+=("$pkg")
        else
            aurPackages+=("$pkg")
        fi
    done

    # Install official-repo packages directly with pacman, no AUR helper needed.
    if (( ${#repoPackages[@]} != 0 )); then
        echo "Installing from official repos: ${repoPackages[*]}"
        if ! sudo pacman -S --needed --noconfirm "${repoPackages[@]}"; then
            echo "Package installation failed. Please install the packages listed above manually and re-run this script."
            exit 1
        fi
    fi

    # Anything not found in official repos must come from the AUR.
    if (( ${#aurPackages[@]} != 0 )); then
        echo "Installing from AUR: ${aurPackages[*]}"

        if command -v paru &>/dev/null; then
            AUR_HELPER="paru"
        elif command -v yay &>/dev/null; then
            AUR_HELPER="yay"
        else
            AUR_HELPER=""
        fi

        if [ -z "$AUR_HELPER" ]; then
            echo "No AUR helper (paru/yay) found. The following packages are AUR-only"
            echo "and cannot be installed with pacman alone:"
            printf '%s\n' "${aurPackages[@]}"
            echo "Please install paru or yay first, then re-run this script."
            echo ""
            exit 1
        fi

        if ! "$AUR_HELPER" -S --needed --noconfirm "${aurPackages[@]}"; then
            echo "Package installation failed. Please install the packages listed above manually and re-run this script."
            exit 1
        fi
    fi

    echo "All missing packages installed successfully."
    echo ""
fi
