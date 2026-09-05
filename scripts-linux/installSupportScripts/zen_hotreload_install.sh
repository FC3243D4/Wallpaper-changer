#!/usr/bin/env bash
# zen_hotreload_install.sh
# Installs MrOtherGuy/fx-autoconfig into a zen-browser-bin (AUR) install and
# drops zenThemeReloader.uc.js into every Zen profile ZenPatcher.sh targets,
# so edits to userChrome.css/userContent.css apply live without a restart.
#
# Intended to be sourced from install-Linux.sh (expects $supportDir to be
# set). Override the detected install dir with:
#   ZEN_INSTALL_DIR=/opt/zen-browser-bin ./install-Linux.sh --zen-hotreload
# Override which profiles get patched (colon-separated absolute paths) with:
#   ZEN_PROFILE_DIRS="/home/you/.zen/xxxx.default:/home/you/.zen/yyyy.work" ./install-Linux.sh --zen-hotreload

ZEN_INSTALL_DIR="${ZEN_INSTALL_DIR:-}"
ZEN_HOME="${ZEN_HOME:-$HOME/.zen}"
ZEN_PROFILE_DIRS="${ZEN_PROFILE_DIRS:-}"
zenReloadScript="$supportDir/zenThemeReloader.uc.js"

zen_hotreload_detect_install_dir() {
    local candidate
    for candidate in /opt/zen-browser-bin /opt/zen-browser /usr/lib/zen-browser /usr/lib64/zen-browser; do
        [ -d "$candidate" ] && { echo "$candidate"; return 0; }
    done
    return 1
}

if [ -z "$ZEN_INSTALL_DIR" ]; then
    ZEN_INSTALL_DIR="$(zen_hotreload_detect_install_dir)" || {
        echo "Could not auto-detect the Zen install directory."
        echo "Re-run with: ZEN_INSTALL_DIR=/your/path ./install-Linux.sh --zen-hotreload"
        exit 1
    }
fi

if [ ! -f "$zenReloadScript" ]; then
    echo "zenThemeReloader.uc.js not found at $zenReloadScript."
    exit 1
fi

# Reads $ZEN_HOME/profiles.ini (standard Firefox-style profile registry that
# Zen also uses) and prints one absolute profile dir per line. This is what
# lets the script find profiles regardless of the random salt in their names
# (e.g. "8ma66p8a.Default (release)") instead of hardcoding them.
zen_hotreload_find_profiles() {
    local ini="$ZEN_HOME/profiles.ini"
    [ -f "$ini" ] || return 1

    local path="" isRelative="1" inProfileSection=false found=false
    local line

    _emit() {
        [ "$inProfileSection" = true ] || return 0
        [ -n "$path" ] || return 0
        if [ "$isRelative" = "1" ]; then
            echo "$ZEN_HOME/$path"
        else
            echo "$path"
        fi
        found=true
    }

    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            \[Profile*\])
                _emit
                inProfileSection=true
                path=""
                isRelative="1"
                ;;
            \[*\])
                _emit
                inProfileSection=false
                path=""
                isRelative="1"
                ;;
            Path=*)
                path="${line#Path=}"
                ;;
            IsRelative=*)
                isRelative="${line#IsRelative=}"
                ;;
        esac
    done < "$ini"
    _emit

    [ "$found" = true ]
}

echo "Zen install dir: $ZEN_INSTALL_DIR"

workDir=$(mktemp -d)
trap 'rm -rf "$workDir"' EXIT

echo "Downloading fx-autoconfig..."
if ! curl -sL https://github.com/MrOtherGuy/fx-autoconfig/archive/refs/heads/master.tar.gz -o "$workDir/fxac.tar.gz"; then
    echo "Download failed. Check your network connection."
    exit 1
fi
tar -xzf "$workDir/fxac.tar.gz" -C "$workDir"
fxacSrc="$workDir/fx-autoconfig-master"

echo "Installing loader into $ZEN_INSTALL_DIR (requires sudo)..."
sudo cp -r "$fxacSrc/program/"* "$ZEN_INSTALL_DIR/"

zenProfiles=()
if [ -n "$ZEN_PROFILE_DIRS" ]; then
    IFS=':' read -ra zenProfiles <<< "$ZEN_PROFILE_DIRS"
else
    while IFS= read -r profileDir; do
        zenProfiles+=("$profileDir")
    done < <(zen_hotreload_find_profiles) || {
        echo "Could not find $ZEN_HOME/profiles.ini, so no profiles were auto-detected."
        echo "Re-run with: ZEN_PROFILE_DIRS=\"/path/to/profile1:/path/to/profile2\" ./install-Linux.sh --zen-hotreload"
        exit 1
    }
fi

patchedAny=false
for zenProfile in "${zenProfiles[@]}"; do
    [ ! -d "$zenProfile" ] && continue
    echo "Setting up profile: $zenProfile"
    mkdir -p "$zenProfile/chrome"
    # Merge fx-autoconfig's JS/resources/utils folders without touching
    # the userChrome.css / userContent.css / prefs.js ZenPatcher.sh manages.
    cp -rn "$fxacSrc/profile/chrome/"* "$zenProfile/chrome/" 2>/dev/null || true
    mkdir -p "$zenProfile/chrome/JS"
    cp "$zenReloadScript" "$zenProfile/chrome/JS/zenThemeReloader.uc.js"
    echo "    -> loader files + reload script in place"
    patchedAny=true
done

if [ "$patchedAny" = false ]; then
    echo "No matching Zen profiles found under $ZEN_HOME. Nothing was patched."
    exit 1
fi

echo ""
echo "Zen hot reload installed. Next steps:"
echo "  1. Fully quit Zen (all windows)."
echo "  2. Relaunch it, open about:support, and click 'Clear startup cache' (top-right button)."
echo "  3. Rerun ThemeRefresher.sh (or ZenPatcher.sh directly) and watch the theme apply live."
echo "  4. If it doesn't seem to work, check the Browser Console (Ctrl+Shift+J) for [ZenThemeReloader] log lines."