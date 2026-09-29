patch_vesktop_tray() {
    command -v vesktop >/dev/null 2>&1 || return 0

    local userAssets="$HOME/.config/vesktop/userAssets"

    # Don't create userAssets/ ourselves if Vesktop has never initialized
    # it — writing files there before Vesktop knows about custom assets
    # at all may not be picked up. Ask once via the UI (Customize ->
    # pick any file, for both Tray and Tray Unread) so Vesktop creates
    # its own tray/trayUnread files, then this script just keeps
    # overwriting them from then on.
    [ -d "$userAssets" ] || {
        echo "  vesktop: $userAssets doesn't exist yet — open Vesktop's"
        echo "  Settings -> User Assets -> Tray/Tray Unread -> Customize"
        echo "  and pick any image once for each, then re-run this script."
        return 1
    }

    command -v rsvg-convert >/dev/null 2>&1 || {
        echo "  vesktop: rsvg-convert not found, cannot rasterize"; return 1
    }

    local patched=0

    # -- plain tray icon --
    local svg
    svg=$(resolve_themed_svg "vesktop") || svg=$(resolve_themed_svg "discord") || {
        echo "  vesktop: no themed base icon found for tray, skipping"
    }
    if [ -n "$svg" ]; then
        local target="$userAssets/tray"
        if [ "$listOnly" -eq 1 ]; then
            echo "vesktop: would overwrite $target"
        else
            rsvg-convert -w 64 -h 64 "$svg" -o "$target" \
                && { echo "Vesktop tray icon patched in place ($target)"; patched=$((patched + 1)); }
        fi
    fi

    # -- unread-badge variant — separate base icon, since the badge is
    # baked into the artwork itself rather than composited by Vesktop
    # (unlike Ferdium/OneDriveGUI, there's no separate dot overlay step
    # here — whatever discord-unread_base_icon.svg draws is exactly what
    # shows in the tray). --
    local svgUnread
    svgUnread=$(resolve_themed_svg "discord-unread") || {
        echo "  vesktop: discord-unread_base_icon.svg not found, skipping trayUnread"
    }
    if [ -n "$svgUnread" ]; then
        local targetUnread="$userAssets/trayUnread"
        if [ "$listOnly" -eq 1 ]; then
            echo "vesktop: would overwrite $targetUnread"
        else
            rsvg-convert -w 64 -h 64 "$svgUnread" -o "$targetUnread" \
                && { echo "Vesktop trayUnread icon patched in place ($targetUnread)"; patched=$((patched + 1)); }
        fi
    fi

    [ "$listOnly" -eq 1 ] && return 0
    [ "$patched" -gt 0 ]
}