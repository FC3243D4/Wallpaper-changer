#!/usr/bin/env bash
# dependency_check.sh
# Checks for required dependencies and installs any that are missing.
# Meant to be SOURCED from install-Linux.sh (not executed) so that
# UseXrandr / UseWayland are visible to the caller.
#
# Returns 0 on success, 1 on failure (caller should check $? and stop).

packageList=()

echo "Checking dependencies..."
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
if [ "$UseXrandr" = true ]; then
    if ! xrandr | grep primary &> /dev/null; then
        cat << EOF
xrandr is installed but no primary display is set. To ensure the script works correctly, please set a primary display with:
xrandr --output <display> --primary

Replace <display> with the name of your display — you can find it by running xrandr and looking for connected displays. If you have multiple displays, make sure to set the correct one.

EOF
    fi
fi
if ! command -v rsync &>/dev/null; then
    echo "rsync"
    packageList=("${packageList[@]}" "rsync")
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

if (( ${#packageList[@]} == 0 )); then
    echo "All dependencies are already installed."
    return 0
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
            return 1
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
            return 1
        fi

        if ! "$AUR_HELPER" -S --needed --noconfirm "${aurPackages[@]}"; then
            echo "Package installation failed. Please install the packages listed above manually and re-run this script."
            return 1
        fi
    fi

    echo "All missing packages installed successfully."
    echo ""
fi

return 0
