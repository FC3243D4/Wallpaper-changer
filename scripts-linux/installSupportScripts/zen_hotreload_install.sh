# zen_hotreload_install.sh
# Installs MrOtherGuy/fx-autoconfig into a zen-browser-bin (AUR) install and
# drops zenThemeReloader.uc.js into every Zen profile zenPatcher.sh targets,
# so edits to userChrome.css/userContent.css apply live without a restart.
#
# Intended to be sourced from install-Linux.sh (expects $SUPPORT to be set).
# Override the detected install dir with:
#   ZEN_INSTALL_DIR=/opt/zen-browser-bin ./install-Linux.sh --zen-hotreload

ZEN_INSTALL_DIR="${ZEN_INSTALL_DIR:-}"
ZEN_RELOAD_SCRIPT="$SUPPORT/zenThemeReloader.uc.js"

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

if [ ! -f "$ZEN_RELOAD_SCRIPT" ]; then
    echo "zenThemeReloader.uc.js not found at $ZEN_RELOAD_SCRIPT."
    exit 1
fi

echo "Zen install dir: $ZEN_INSTALL_DIR"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "Downloading fx-autoconfig..."
if ! curl -sL https://github.com/MrOtherGuy/fx-autoconfig/archive/refs/heads/master.tar.gz -o "$WORK/fxac.tar.gz"; then
    echo "Download failed. Check your network connection."
    exit 1
fi
tar -xzf "$WORK/fxac.tar.gz" -C "$WORK"
FXAC_SRC="$WORK/fx-autoconfig-master"

echo "Installing loader into $ZEN_INSTALL_DIR (requires sudo)..."
sudo cp -r "$FXAC_SRC/program/"* "$ZEN_INSTALL_DIR/"

ZEN_PROFILES=(
    "$HOME/.zen/8ma66p8a.Default (release)"
    "$HOME/.zen/k71gdxvw.Default Profile"
)

patchedAny=false
for ZEN_PROFILE in "${ZEN_PROFILES[@]}"; do
    [ ! -d "$ZEN_PROFILE" ] && continue
    echo "Setting up profile: $ZEN_PROFILE"
    mkdir -p "$ZEN_PROFILE/chrome"
    # Merge fx-autoconfig's JS/resources/utils folders without touching
    # the userChrome.css / userContent.css / prefs.js zenPatcher.sh manages.
    cp -rn "$FXAC_SRC/profile/chrome/"* "$ZEN_PROFILE/chrome/" 2>/dev/null || true
    mkdir -p "$ZEN_PROFILE/chrome/JS"
    cp "$ZEN_RELOAD_SCRIPT" "$ZEN_PROFILE/chrome/JS/zenThemeReloader.uc.js"
    echo "    -> loader files + reload script in place"
    patchedAny=true
done

if [ "$patchedAny" = false ]; then
    echo "No matching Zen profiles found under ~/.zen. Nothing was patched."
    exit 1
fi

echo ""
echo "Zen hot reload installed. Next steps:"
echo "  1. Fully quit Zen (all windows)."
echo "  2. Relaunch it, open about:support, and click 'Clear startup cache' (top-right button)."
echo "  3. Rerun themeRefresher.sh (or zenPatcher.sh directly) and watch the theme apply live."
echo "  4. If it doesn't seem to work, check the Browser Console (Ctrl+Shift+J) for [ZenThemeReloader] log lines."
