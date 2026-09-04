#!/usr/bin/env bash
# install_themes.sh
# Installs the base Breeze theme packages required by gtkPatcher.sh,
# kdePatcher.sh, and iconPatcher.sh.

set -euo pipefail

# Packages required for accent-color patching to work.
# All available in the official Arch 'extra' repo (no AUR needed).
themePackages=(
    breeze         # Base color schemes (BreezeDark.colors) + Breeze icon theme
    breeze-gtk     # GTK 3/4 Breeze-Dark theme files
    breeze-icons   # Breeze icon SVGs (folder, system-file-manager, etc.)
)

missingPackages=()

for pkg in "${themePackages[@]}"; do
    if ! pacman -Qi "$pkg" &>/dev/null; then
        missingPackages+=("$pkg")
    fi
done

if [ ${#missingPackages[@]} -eq 0 ]; then
    echo "All base theme packages already installed."
else
    echo "Installing missing theme packages: ${missingPackages[*]}"
    if command -v paru &>/dev/null; then
        paru -S --needed --noconfirm "${missingPackages[@]}"
    elif command -v yay &>/dev/null; then
        yay -S --needed --noconfirm "${missingPackages[@]}"
    else
        sudo pacman -S --needed --noconfirm "${missingPackages[@]}"
    fi
fi

# Optional: org.kde.dolphin.svg / org.cachyos.hello.svg only matter if those
# apps are present — iconPatcher.sh already gates on this with `command -v`,
# so no install step is needed for them here.