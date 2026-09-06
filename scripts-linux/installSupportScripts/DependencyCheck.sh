#!/usr/bin/env bash
# DependencyCheck.sh
# Checks for required dependencies and installs any that are missing.
# Meant to be SOURCED from Install-Linux.sh (not executed) so that
# useXrandr / useWayland are visible to the caller.
#
# Returns 0 on success, 1 on failure (caller should check $? and stop).

source "$supportDir/PkgManager.sh" || return 1

packageList=()

echo "Checking dependencies..."

if [ "$XDG_SESSION_TYPE" != "wayland" ]; then
    useWayland=false
    if ! xrandr -v foo &> /dev/null; then
        echo "You are not using Wayland, but xrandr is not installed."
        echo ""
        packageList+=("xrandr")
    else
        echo "You are not using Wayland. The script will use xrandr instead."
        echo ""
        useXrandr=true
    fi
fi
if [ "$useXrandr" = true ]; then
    if ! xrandr | grep primary &> /dev/null; then
        cat << EOF2
xrandr is installed but no primary display is set. To ensure the script works correctly, please set a primary display with:
xrandr --output <display> --primary

Replace <display> with the name of your display — you can find it by running xrandr and looking for connected displays. If you have multiple displays, make sure to set the correct one.

EOF2
    fi
fi
if ! command -v rsync &>/dev/null; then
    echo "rsync"
    packageList+=("rsync")
fi
if ! magick --version &> /dev/null; then
    echo "imagemagick"
    packageList+=("imagemagick")
fi
if ! matugen --version &> /dev/null; then
    echo "matugen"
    packageList+=("matugen")
fi
if ! awww --version &> /dev/null; then
    echo "awww"
    packageList+=("awww")
fi
if ! command -v bc &>/dev/null; then
    echo "bc"
    packageList+=("bc")
fi
if ! python3 -c "import PIL" &>/dev/null; then
    echo "python-pillow"
    packageList+=("python-pillow")
fi
if ! openrgb --version &> /dev/null; then
    echo "openrgb is not installed. You will not have the wallpaper's dominant color applied to your devices. Please install openrgb if you want this feature."
    echo ""
fi

if (( ${#packageList[@]} == 0 )); then
    echo "All dependencies are already installed."
    return 0
fi

echo "The following packages are missing and will be installed:"
printf '  %s\n' "${packageList[@]}"
echo ""

sync_repos
if ! install_pkgs "${packageList[@]}"; then
    echo "Package installation failed. Please install the packages listed above manually and re-run this script."
    return 1
fi

echo "All missing packages installed successfully."
echo ""
return 0