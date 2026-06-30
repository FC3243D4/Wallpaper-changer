#!/usr/bin/env bash
# install_themes.sh
# Installs the base Breeze theme packages required by gtkPatcher.sh,
# kdePatcher.sh, and iconPatcher.sh.

set -euo pipefail

# Packages required for accent-color patching to work.
# All available in the official Arch 'extra' repo (no AUR needed).
THEME_PACKAGES=(
    breeze         # Base color schemes (BreezeDark.colors) + Breeze icon theme
    breeze-gtk     # GTK 3/4 Breeze-Dark theme files
    breeze-icons   # Breeze icon SVGs (folder, system-file-manager, etc.)
)

missing_packages=()

for pkg in "${THEME_PACKAGES[@]}"; do
    if ! pacman -Qi "$pkg" &>/dev/null; then
        missing_packages+=("$pkg")
    fi
done

if [ ${#missing_packages[@]} -eq 0 ]; then
    echo "All base theme packages already installed."
else
    echo "Installing missing theme packages: ${missing_packages[*]}"
    if command -v paru &>/dev/null; then
        paru -S --needed --noconfirm "${missing_packages[@]}"
    elif command -v yay &>/dev/null; then
        yay -S --needed --noconfirm "${missing_packages[@]}"
    else
        sudo pacman -S --needed --noconfirm "${missing_packages[@]}"
    fi
fi

# Optional: org.kde.dolphin.svg / org.cachyos.hello.svg only matter if those
# apps are present — iconPatcher.sh already gates on this with `command -v`,
# so no install step is needed for them here.
