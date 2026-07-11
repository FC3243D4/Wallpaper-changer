# zen_hotreload_prompt.sh
# Sourced from cmd_install. Detects a Zen Browser install and, if found,
# offers to set up live theme reload (zen_hotreload_install.sh) — which
# needs sudo and a network fetch, so it's opt-in rather than automatic.
# Silently does nothing if Zen isn't installed.
#
# Skip the prompt outright with:
#   ZEN_HOTRELOAD_AUTO=yes ./install-Linux.sh --install
#   ZEN_HOTRELOAD_AUTO=no  ./install-Linux.sh --install

zen_hotreload_prompt_detect() {
    local candidate
    for candidate in /opt/zen-browser-bin /opt/zen-browser /usr/lib/zen-browser /usr/lib64/zen-browser; do
        [ -d "$candidate" ] && { echo "$candidate"; return 0; }
    done
    return 1
}

_zen_dir="${ZEN_INSTALL_DIR:-}"
if [ -z "$_zen_dir" ]; then
    _zen_dir="$(zen_hotreload_prompt_detect)" || _zen_dir=""
fi

if [ -n "$_zen_dir" ]; then
    echo ""
    echo "Zen Browser detected at $_zen_dir."

    case "${ZEN_HOTRELOAD_AUTO:-}" in
        yes|y|Y) reply="y" ;;
        no|n|N)  reply="n" ;;
        *)
            if [ -t 0 ]; then
                read -r -p "Install live theme reload support for it (needs sudo, fetches fx-autoconfig)? [y/N] " reply
            else
                reply="n"
                echo "Non-interactive shell detected, skipping by default."
            fi
            ;;
    esac

    case "$reply" in
        [yY]|[yY][eE][sS])
            export ZEN_INSTALL_DIR="$_zen_dir"
            source "$SUPPORT/zen_hotreload_install.sh"
            ;;
        *)
            echo "Skipping Zen hot reload setup. Run './install-Linux.sh --zen-hotreload' anytime to add it later."
            ;;
    esac
fi

unset _zen_dir
