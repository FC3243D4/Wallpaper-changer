#!/usr/bin/env bash
# PkgManager.sh
# Detects the package manager and provides install/sync abstractions.
# Meant to be SOURCED by DependencyCheck.sh and InstallThemes.sh.
#
# Exports:
#   pkgManager    — detected package manager (pacman, apt, dnf, zypper)
#   sync_repos    — refresh package database
#   install_pkgs  — install a list of logical package names

# ─── Detect package manager ──────────────────────────────────────────────────

if command -v pacman &>/dev/null;  then pkgManager="pacman"
elif command -v apt &>/dev/null;   then pkgManager="apt"
elif command -v dnf &>/dev/null;   then pkgManager="dnf"
elif command -v zypper &>/dev/null; then pkgManager="zypper"
else
    echo "Unsupported package manager. Please install dependencies manually."
    return 1
fi

# ─── Package name map ────────────────────────────────────────────────────────
# Maps logical names used in DependencyCheck.sh / InstallThemes.sh to the
# distro-specific package name. Add entries here when names differ.

_resolve_pkg() {
    local logical="$1"
    case "$pkgManager" in
        pacman)
            case "$logical" in
                imagemagick)    echo "imagemagick" ;;
                rsync)          echo "rsync" ;;
                bc)             echo "bc" ;;
                xrandr)         echo "xorg-xrandr" ;;
                breeze)         echo "breeze" ;;
                breeze-gtk)     echo "breeze-gtk" ;;
                breeze-icons)   echo "breeze-icons" ;;
                python-pillow)  echo "python-pillow" ;;
                *)              echo "$logical" ;;
            esac ;;
        apt)
            case "$logical" in
                imagemagick)    echo "imagemagick" ;;
                rsync)          echo "rsync" ;;
                bc)             echo "bc" ;;
                xrandr)         echo "x11-xserver-utils" ;;
                breeze)         echo "breeze" ;;
                breeze-gtk)     echo "breeze-gtk-theme" ;;
                breeze-icons)   echo "breeze-icon-theme" ;;
                python-pillow)  echo "python3-pil" ;;
                *)              echo "$logical" ;;
            esac ;;
        dnf)
            case "$logical" in
                imagemagick)    echo "ImageMagick" ;;
                rsync)          echo "rsync" ;;
                bc)             echo "bc" ;;
                xrandr)         echo "xrandr" ;;
                breeze)         echo "breeze-cursor-theme" ;;
                breeze-gtk)     echo "breeze-gtk" ;;
                breeze-icons)   echo "breeze-icon-theme" ;;
                python-pillow)  echo "python3-pillow" ;;
                *)              echo "$logical" ;;
            esac ;;
        zypper)
            case "$logical" in
                imagemagick)    echo "ImageMagick" ;;
                rsync)          echo "rsync" ;;
                bc)             echo "bc" ;;
                xrandr)         echo "xrandr" ;;
                breeze)         echo "breeze5" ;;
                breeze-gtk)     echo "breeze5-gtk" ;;
                breeze-icons)   echo "breeze5-icons" ;;
                python-pillow)  echo "python3-Pillow" ;;   # UNVERIFIED — check manually
                *)              echo "$logical" ;;
            esac ;;
    esac
}

# ─── Sync repos ──────────────────────────────────────────────────────────────

sync_repos() {
    echo "Syncing package databases..."
    case "$pkgManager" in
        pacman) sudo pacman -Sy ;;
        apt)    sudo apt-get update ;;
        dnf)    sudo dnf check-update || true ;;  # dnf returns 100 when updates are available, not an error
        zypper) sudo zypper refresh ;;
    esac
}

# ─── Install packages ─────────────────────────────────────────────────────────
# Usage: install_pkgs <logical_name> [<logical_name> ...]
# Handles repo vs AUR split on Arch; on other distros installs everything
# via the system package manager, with a cargo-build fallback for
# AUR-only tools.

# Packages that must be built with cargo when not found in official repos
# and no AUR helper is available.
_cargoBuildable=("matugen" "awww")

_is_cargo_buildable() {
    local pkg="$1"
    for p in "${_cargoBuildable[@]}"; do
        [ "$p" = "$pkg" ] && return 0
    done
    return 1
}

# Cross-distro "is this resolved package already installed" check, so
# install_pkgs can skip repo queries and sudo prompts entirely when
# there's nothing to do (e.g. re-running the installer).
_is_pkg_installed() {
    local resolved="$1"
    case "$pkgManager" in
        pacman) pacman -Qi "$resolved" &>/dev/null ;;
        apt)    dpkg -s "$resolved" &>/dev/null ;;
        dnf)    rpm -q "$resolved" &>/dev/null ;;
        zypper) rpm -q "$resolved" &>/dev/null ;;
    esac
}

_install_with_cargo() {
    local pkgs=("$@")

    if ! command -v cargo &>/dev/null; then
        echo "cargo is required to build ${pkgs[*]} but is not installed. Installing Rust toolchain..."
        case "$pkgManager" in
            apt)    sudo apt-get install -y cargo ;;
            dnf)    sudo dnf install -y cargo ;;
            zypper) sudo zypper install -y cargo ;;
            *)      echo "Please install cargo manually and re-run this script."; return 1 ;;
        esac
    fi

    for pkg in "${pkgs[@]}"; do
        case "$pkg" in
            matugen)
                echo "Building matugen from source (cargo install matugen)..."
                if ! cargo install matugen; then
                    echo "Failed to build matugen. Please install it manually and re-run this script."
                    return 1
                fi
                ;;
            awww)
                # awww is not on crates.io — must be cloned and built from source.
                # Both the awww and awww-daemon binaries are required.
                echo "Building awww from source (codeberg.org/LGFae/awww)..."
                if ! command -v git &>/dev/null; then
                    echo "git is required to build awww but is not installed."
                    return 1
                fi
                local tmpDir
                tmpDir="$(mktemp -d)"
                git clone https://codeberg.org/LGFae/awww "$tmpDir/awww" || { echo "Failed to clone awww."; rm -rf "$tmpDir"; return 1; }
                (cd "$tmpDir/awww" && cargo build --release) || { echo "Failed to build awww."; rm -rf "$tmpDir"; return 1; }
                sudo install -m755 "$tmpDir/awww/target/release/awww" /usr/local/bin/awww
                sudo install -m755 "$tmpDir/awww/target/release/awww-daemon" /usr/local/bin/awww-daemon
                rm -rf "$tmpDir"
                echo "awww installed successfully."
                ;;
            *)
                echo "No cargo build method available for $pkg. Please install it manually."
                return 1
                ;;
        esac
    done
}

install_pkgs() {
    local logicalPkgs=("$@")
    local repoPkgs=()
    local aurPkgs=()
    local cargoPkgs=()
    local alreadyInstalled=()

    for pkg in "${logicalPkgs[@]}"; do
        local resolved
        resolved="$(_resolve_pkg "$pkg")"

        if _is_pkg_installed "$resolved"; then
            alreadyInstalled+=("$pkg")
            continue
        fi

        # Check if the package exists in official repos
        local inRepo=false
        case "$pkgManager" in
            pacman) pacman -Si "$resolved" &>/dev/null && inRepo=true ;;
            apt)    apt-cache show "$resolved" &>/dev/null && inRepo=true ;;
            dnf)    dnf info "$resolved" &>/dev/null && inRepo=true ;;
            zypper) zypper info "$resolved" &>/dev/null && inRepo=true ;;
        esac

        if [ "$inRepo" = true ]; then
            repoPkgs+=("$resolved")
        elif [ "$pkgManager" = "pacman" ]; then
            # Not in official repos on Arch — try AUR
            aurPkgs+=("$pkg")
        elif _is_cargo_buildable "$pkg"; then
            # Not in official repos on non-Arch — build with cargo
            cargoPkgs+=("$pkg")
        else
            echo "Package '$pkg' not found in official repos and no fallback is available. Please install it manually."
            return 1
        fi
    done

    if (( ${#alreadyInstalled[@]} != 0 )); then
        echo "Already installed: ${alreadyInstalled[*]}"
    fi

    # Install repo packages
    if (( ${#repoPkgs[@]} != 0 )); then
        echo "Installing from official repos: ${repoPkgs[*]}"
        case "$pkgManager" in
            pacman) sudo pacman -S --needed --noconfirm "${repoPkgs[@]}" ;;
            apt)    sudo apt-get install -y "${repoPkgs[@]}" ;;
            dnf)    sudo dnf install -y "${repoPkgs[@]}" ;;
            zypper) sudo zypper install -y "${repoPkgs[@]}" ;;
        esac
    fi

    # Install AUR packages (Arch only)
    if (( ${#aurPkgs[@]} != 0 )); then
        echo "Installing from AUR: ${aurPkgs[*]}"
        if command -v paru &>/dev/null; then
            paru -S --needed --noconfirm "${aurPkgs[@]}"
        elif command -v yay &>/dev/null; then
            yay -S --needed --noconfirm "${aurPkgs[@]}"
        else
            echo "No AUR helper (paru/yay) found. The following packages were not found in the official repos:"
            printf '  %s\n' "${aurPkgs[@]}"
            echo "Please install paru or yay first, then re-run this script."
            return 1
        fi
    fi

    # Build with cargo as last resort (non-Arch only)
    if (( ${#cargoPkgs[@]} != 0 )); then
        _install_with_cargo "${cargoPkgs[@]}" || return 1
    fi
}