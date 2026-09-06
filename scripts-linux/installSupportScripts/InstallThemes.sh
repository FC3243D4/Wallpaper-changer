#!/usr/bin/env bash
# InstallThemes.sh
# Installs the base Breeze theme packages required by GtkPatcher.sh,
# KdePatcher.sh, and IconPatcher.sh, via PkgManager.sh's logical-name
# abstraction — so this works on pacman/apt/dnf/zypper alike, not just Arch.
# Meant to be SOURCED from Install-Linux.sh (expects $supportDir to be set).
#
# Returns 0 on success, 1 on failure (caller should check $? and stop).

source "$supportDir/PkgManager.sh" || return 1

echo "Checking base theme packages..."
if ! install_pkgs breeze breeze-gtk breeze-icons; then
    echo "Theme package installation failed. Please install the Breeze color"
    echo "scheme, GTK theme, and icon theme packages manually and re-run this script."
    return 1
fi

# Optional: org.kde.dolphin.svg / org.cachyos.hello.svg only matter if those
# apps are present — IconPatcher.sh already gates on this with `command -v`,
# so no install step is needed for them here.

return 0