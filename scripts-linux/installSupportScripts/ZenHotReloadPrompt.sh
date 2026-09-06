#!/usr/bin/env bash
# ZenHotReloadPrompt.sh
# Sourced from cmd_install. Detects a Zen Browser install and, if found,
# offers to set up live theme reload (ZenHotReloadInstall.sh) — which
# needs sudo and a network fetch, so it's opt-in rather than automatic.
# Silently does nothing if Zen isn't installed.
#
# Skip the prompt outright with:
#   ZEN_HOTRELOAD_AUTO=yes ./Install-Linux.sh --install
#   ZEN_HOTRELOAD_AUTO=no  ./Install-Linux.sh --install

zen_hotreload_prompt_detect() {
    local candidate
    for candidate in /opt/zen-browser-bin /opt/zen-browser /usr/lib/zen-browser /usr/lib64/zen-browser; do
        [ -d "$candidate" ] && { echo "$candidate"; return 0; }
    done
    return 1
}

zenDir="${ZEN_INSTALL_DIR:-}"
if [ -z "$zenDir" ]; then
    zenDir="$(zen_hotreload_prompt_detect)" || zenDir=""
fi

if [ -n "$zenDir" ]; then
    echo ""
    echo "Zen Browser detected at $zenDir."

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
            export ZEN_INSTALL_DIR="$zenDir"
            source "$supportDir/ZenHotReloadInstall.sh"
            ;;
        *)
            echo "Skipping Zen hot reload setup. Run './Install-Linux.sh --zen-hotreload' anytime to add it later."
            ;;
    esac
fi

unset zenDir